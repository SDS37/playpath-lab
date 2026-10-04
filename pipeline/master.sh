#!/usr/bin/env bash
# Phase 1. Write the playpath-bars mezzanine and a WebVTT sidecar.
# The master directory is an input. It is not a playlist, and nothing here
# runs at play time.

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
master="${root}/pipeline/master"
title="playpath-bars"
duration="60"
video="${master}/${title}.mp4"
captions="${master}/${title}.vtt"
caption_src="${1:-}"

if ! command -v ffmpeg >/dev/null || ! command -v ffprobe >/dev/null; then
  echo "ffmpeg and ffprobe must be on PATH (libx264 and the native AAC encoder)." >&2
  exit 1
fi

mkdir -p "${master}"

if [[ -n "${caption_src}" ]]; then
  case "${caption_src}" in
    *.m3u8 | *.mpd | *.m4s | *.ts)
      echo "The caption input must be a WebVTT file, not a playlist or a segment." >&2
      exit 1
      ;;
  esac
  if [[ ! -f "${caption_src}" ]]; then
    echo "Caption file not found: ${caption_src}" >&2
    exit 1
  fi
  # WebVTT header: optional UTF-8 BOM, then WEBVTT, then end of line or a
  # space/tab and more header text. https://www.w3.org/TR/webvtt1/#file-structure
  first="$(head -n 1 "${caption_src}")"
  first="${first#$'\xef\xbb\xbf'}"
  first="${first%$'\r'}"
  if [[ ! "${first}" =~ ^WEBVTT($|[[:blank:]].*)$ ]]; then
    echo "Caption file must be WebVTT (a WEBVTT header)." >&2
    exit 1
  fi
  if [[ ! "${caption_src}" -ef "${captions}" ]]; then
    cp "${caption_src}" "${captions}"
  fi
else
  cat >"${captions}" <<'EOF'
WEBVTT

00:00:00.000 --> 00:00:04.000
playpath-bars

00:00:10.000 --> 00:00:14.000
Cue at ten seconds.

00:00:56.000 --> 00:01:00.000
End of the master.
EOF
fi

# One progressive H.264 ladder source, closed GOP every 2 seconds, stereo AAC-LC.
ffmpeg -y -hide_banner \
  -f lavfi -i "testsrc2=size=1920x1080:rate=30:duration=${duration}" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=${duration}" \
  -map 0:v:0 -map 1:a:0 \
  -c:v libx264 -pix_fmt yuv420p -profile:v high \
  -g 60 -keyint_min 60 \
  -x264-params "open-gop=0:keyint=60:min-keyint=60:scenecut=0" \
  -c:a aac -profile:a aac_low -ac 2 -ar 48000 -b:a 160k \
  -t "${duration}" \
  -movflags +faststart \
  "${video}"

shopt -s nullglob
playlists=("${master}"/*.m3u8 "${master}"/*.mpd "${master}"/*.m4s "${master}"/*.ts)
if ((${#playlists[@]} > 0)); then
  echo "The master directory contains a playlist or a segment." >&2
  printf '%s\n' "${playlists[@]}" >&2
  exit 1
fi

field() {
  ffprobe -v error -select_streams "$1" -show_entries "$2" -of csv=p=0 "${video}"
}

v_codec="$(field v:0 stream=codec_name)"
v_pix="$(field v:0 stream=pix_fmt)"
v_field="$(field v:0 stream=field_order)"
v_size="$(field v:0 stream=width,height)"
a_codec="$(field a:0 stream=codec_name)"
a_profile="$(field a:0 stream=profile)"
a_channels="$(field a:0 stream=channels)"
seconds="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "${video}")"

[[ "${v_codec}" == "h264" && "${v_pix}" == "yuv420p" && "${v_field}" == "progressive" && "${v_size}" == "1920,1080" ]] || {
  echo "Unexpected video: ${v_codec} ${v_pix} ${v_field} ${v_size}" >&2
  exit 1
}
[[ "${a_codec}" == "aac" && "${a_profile}" == "LC" && "${a_channels}" == "2" ]] || {
  echo "Unexpected audio: ${a_codec} ${a_profile} ${a_channels}" >&2
  exit 1
}

awk -v seconds="${seconds}" 'BEGIN { if (seconds < 59.5 || seconds > 60.5) exit 1 }' || {
  echo "Unexpected duration: ${seconds}" >&2
  exit 1
}

# I-frames land every 60 frames. x264 reports open_gop=0 for this command,
# which is a closed GOP. x264 also clamps min-keyint to keyint/2+1; scenecut=0
# keeps the interval on the keyint above.
ffprobe -v error -select_streams v:0 -show_entries frame=pict_type -of csv=p=0 "${video}" |
  awk '
    { n++; if ($1 ~ /^I/) { if (prev && (n - prev) != 60) bad = 1; prev = n; keys++ } }
    END { if (bad || keys != 30 || n != 1800) exit 1 }
  ' || {
  echo "Video GOP is not a closed 60-frame interval across 1800 frames." >&2
  exit 1
}

echo "Wrote ${video}"
echo "Wrote ${captions}"
echo "Title id: ${title}"
