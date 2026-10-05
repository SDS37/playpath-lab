#!/usr/bin/env bash
# Phase 5. Write a clear pre-roll of about 5 seconds for the SSAI stitcher.
# The creative is not the film and it is not encrypted. Apps do not encode it.
# https://ffmpeg.org/ffmpeg-formats.html#hls-2

set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo "Usage: ./pipeline/preroll.sh" >&2
  exit 1
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
out="${root}/pipeline/preroll/playpath-bars"

if ! command -v ffmpeg >/dev/null; then
  echo "ffmpeg must be on PATH (libx264 and the native AAC encoder)." >&2
  exit 1
fi

rm -rf "${out}"
mkdir -p "${out}/subtitles"

encode_video() {
  local name="$1"
  local size="$2"
  local rate="$3"
  local dir="${out}/${name}"
  mkdir -p "${dir}"
  ffmpeg -y -hide_banner \
    -f lavfi -i "color=c=0x00cc66:s=${size}:r=30:d=5" \
    -an \
    -c:v libx264 -pix_fmt yuv420p -profile:v high \
    -g 60 -keyint_min 60 \
    -x264-params "open-gop=0:keyint=60:min-keyint=60:scenecut=0" \
    -b:v "${rate}" \
    -t 5 \
    -f hls \
    -hls_time 10 \
    -hls_playlist_type vod \
    -hls_segment_type fmp4 \
    -hls_segment_options movflags=+cmaf \
    -hls_flags independent_segments \
    -hls_fmp4_init_filename init.mp4 \
    -hls_segment_filename "${dir}/seg_%d.m4s" \
    "${dir}/media.m3u8"
  if [[ "${name}" == "720p" ]]; then
    video_dur="$(playlist_duration "${dir}/media.m3u8")"
  fi
  rm -f "${dir}/media.m3u8"
}

playlist_duration() {
  awk '/^#EXTINF:/ { sub(/^#EXTINF:/, ""); sub(/,.*/, ""); print; exit }' "$1"
}

encode_audio() {
  local dir="${out}/audio"
  mkdir -p "${dir}"
  ffmpeg -y -hide_banner \
    -f lavfi -i "sine=frequency=880:sample_rate=48000:duration=5" \
    -vn \
    -c:a aac -profile:a aac_low -ac 2 -ar 48000 -b:a 128k \
    -t 5 \
    -f hls \
    -hls_time 10 \
    -hls_playlist_type vod \
    -hls_segment_type fmp4 \
    -hls_segment_options movflags=+cmaf \
    -hls_fmp4_init_filename init.mp4 \
    -hls_segment_filename "${dir}/seg_%d.m4s" \
    "${dir}/media.m3u8"
  audio_dur="$(playlist_duration "${dir}/media.m3u8")"
  rm -f "${dir}/media.m3u8"
}

encode_video 720p 1280x720 500k
encode_video 1080p 1920x1080 800k
encode_audio

one_segment() {
  local dir="$1"
  local count
  count="$(find "${dir}" -name 'seg_*.m4s' | wc -l | tr -d ' ')"
  if [[ "${count}" != "1" ]]; then
    echo "Expected one pre-roll segment in ${dir}, found ${count}." >&2
    exit 1
  fi
}

one_segment "${out}/720p"
one_segment "${out}/1080p"
one_segment "${out}/audio"

printf 'video=%s\naudio=%s\n' "${video_dur}" "${audio_dur}" >"${out}/duration.txt"

cat >"${out}/subtitles/preroll.vtt" <<'EOF'
WEBVTT
X-TIMESTAMP-MAP=LOCAL:00:00:00.000,MPEGTS:0

00:00:00.000 --> 00:00:05.000
Advertisement
EOF

awk -v dur="${video_dur}" 'BEGIN { exit !((dur + 0) >= 4.5 && (dur + 0) <= 5.5) }' || {
  echo "Pre-roll video duration ${video_dur} is not about 5 seconds." >&2
  exit 1
}
awk -v a="${video_dur}" -v b="${audio_dur}" \
  'BEGIN { d = a - b; if (d < 0) d = -d; if (d > 0.04) exit 1 }' || {
  echo "Audio duration ${audio_dur} does not match video duration ${video_dur}." >&2
  exit 1
}

echo "Pre-roll: ${out}"
echo "Video duration: ${video_dur}"
echo "Audio duration: ${audio_dur}"
