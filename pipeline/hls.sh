#!/usr/bin/env bash
# Phase 2. Cut the playpath-bars mezzanine into one CMAF ladder and an HLS menu.
# ffmpeg's HLS muxer writes the fMP4 segments. Apps do not slice the file.
# https://ffmpeg.org/ffmpeg-formats.html#hls-2
# DASH is a later story. It reads pipeline/timeline and these same segment files.

set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo "Usage: ./pipeline/hls.sh" >&2
  exit 1
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=timeline
source "${root}/pipeline/timeline"

title="playpath-bars"
master="${root}/pipeline/master"
video="${master}/${title}.mp4"
captions="${master}/${title}.vtt"
out="${root}/pipeline/package/${title}"
frame_rate="30"

if ! command -v ffmpeg >/dev/null || ! command -v ffprobe >/dev/null; then
  echo "ffmpeg and ffprobe must be on PATH (libx264 and the native AAC encoder)." >&2
  exit 1
fi

if [[ ! -f "${video}" || ! -f "${captions}" ]]; then
  echo "Run ./pipeline/master.sh before packaging." >&2
  exit 1
fi

fps="$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 "${video}")"
if [[ "${fps}" != "30/1" ]]; then
  echo "Expected a 30 fps mezzanine, got ${fps}." >&2
  exit 1
fi

rm -rf "${out}"
mkdir -p "${out}"

keyint="$((idr_interval * frame_rate))"

# Two video rungs and one AAC-LC rendition. The ~2000 kbit/s rung is first
# (HLS authoring specification, item 1.32). IDR every idr_interval seconds,
# and a segment cut every segment_duration seconds so each segment starts
# on an IDR (items 1.13, 7.4, 7.5, 7.6). movflags=+cmaf asks the MP4 muxer
# for CMAF fragments. https://ffmpeg.org/ffmpeg-formats.html#mov_002c-mp4_002c-ismv
ffmpeg -y -hide_banner \
  -i "${video}" \
  -filter_complex "[0:v]split=2[v1080][v720];[v720]scale=1280:720:flags=bicubic[v720s]" \
  -map "[v720s]" -map "[v1080]" -map 0:a:0 \
  -c:v libx264 -pix_fmt yuv420p -profile:v high \
  -g "${keyint}" -keyint_min "${keyint}" \
  -x264-params "open-gop=0:keyint=${keyint}:min-keyint=${keyint}:scenecut=0" \
  -force_key_frames "expr:gte(t,n_forced*${idr_interval})" \
  -b:v:0 2000k -maxrate:v:0 2500k -bufsize:v:0 4000k \
  -b:v:1 4500k -maxrate:v:1 5000k -bufsize:v:1 9000k \
  -c:a aac -profile:a aac_low -ac 2 -ar 48000 -b:a 128k \
  -var_stream_map "v:0,agroup:aac,name:720p v:1,agroup:aac,name:1080p a:0,agroup:aac,name:audio,language:en,default:yes" \
  -f hls \
  -hls_time "${segment_duration}" \
  -hls_playlist_type vod \
  -hls_segment_type fmp4 \
  -hls_segment_options movflags=+cmaf \
  -hls_flags independent_segments \
  -hls_fmp4_init_filename init.mp4 \
  -hls_segment_filename "${out}/%v/seg_%d.m4s" \
  -master_pl_name master.m3u8 \
  "${out}/%v/media.m3u8"

# AAC frames are 1024 samples, so the last audio fragment can be a few
# milliseconds. Drop that tail when it is not a real segment. Video and audio
# then cover the same timeline (items 8.2 and 8.3).
audio_playlist="${out}/audio/media.m3u8"
tail_info="$(awk '
  /^#EXTINF:/ { dur = $0; sub(/^#EXTINF:/, "", dur); sub(/,.*/, "", dur); getline file; last_dur = dur; last_file = file }
  END { printf "%s %s\n", last_dur, last_file }
' "${audio_playlist}")"
tail_dur="${tail_info%% *}"
tail_file="${tail_info#* }"
awk -v dur="${tail_dur}" 'BEGIN { exit !(dur + 0 < 0.5) }' && {
  rm -f "${out}/audio/${tail_file}"
  awk -v drop="${tail_file}" '
    /^#EXTINF:/ { dur = $0; getline file; if (file == drop) next; print dur; print file; next }
    { print }
  ' "${audio_playlist}" >"${audio_playlist}.tmp"
  mv "${audio_playlist}.tmp" "${audio_playlist}"
}

playlist_stats() {
  local playlist="$1"
  local dir
  dir="$(dirname "${playlist}")"
  awk -v dir="${dir}" '
    /^#EXTINF:/ {
      dur = $0
      sub(/^#EXTINF:/, "", dur)
      sub(/,.*/, "", dur)
      getline file
      cmd = "wc -c < \"" dir "/" file "\""
      cmd | getline bytes
      close(cmd)
      bytes += 0
      dur += 0
      rate = bytes * 8 / dur
      if (rate > peak) peak = rate
      bytes_sum += bytes
      dur_sum += dur
    }
    END {
      if (dur_sum <= 0) exit 1
      printf "%d %d %.6f\n", int(peak + 0.5), int(bytes_sum * 8 / dur_sum + 0.5), dur_sum
    }
  ' "${playlist}"
}

video_duration="$(playlist_stats "${out}/720p/media.m3u8" | awk '{ print $3 }')"
audio_stats="$(playlist_stats "${audio_playlist}")"
audio_peak="${audio_stats%% *}"
audio_rest="${audio_stats#* }"
audio_avg="${audio_rest%% *}"

mkdir -p "${out}/subtitles"
awk 'NR == 1 {
  sub(/^\xef\xbb\xbf/, "")
  sub(/\r$/, "")
  print
  print "X-TIMESTAMP-MAP=LOCAL:00:00:00.000,MPEGTS:0"
  next
}
{ sub(/\r$/, ""); print }
' "${captions}" >"${out}/subtitles/${title}.vtt"

subtitle_target="$(awk -v d="${video_duration}" 'BEGIN { if (d == int(d)) print int(d); else print int(d) + 1 }')"
cat >"${out}/subtitles/media.m3u8" <<EOF
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:${subtitle_target}
#EXT-X-PLAYLIST-TYPE:VOD
#EXTINF:${video_duration},
${title}.vtt
#EXT-X-ENDLIST
EOF

# BANDWIDTH is the peak of the video rendition plus the peak of the audio
# rendition a player can combine with it (item 9.13). AVERAGE-BANDWIDTH is
# required (item 9.14). FRAME-RATE is required on every video variant (item 9.15).
{
  echo "#EXTM3U"
  echo "#EXT-X-VERSION:7"
  echo "#EXT-X-INDEPENDENT-SEGMENTS"
  echo '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="English",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE="en",CHANNELS="2",URI="audio/media.m3u8"'
  # A WEBVTT header does not prove the cues transcribe speech or describe sound.
  echo '#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="English",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE="en",URI="subtitles/media.m3u8"'
  while IFS= read -r line; do
    if [[ "${line}" == \#EXT-X-STREAM-INF:* ]]; then
      [[ "${line}" =~ RESOLUTION=([^,]+) ]] || { echo "Missing RESOLUTION in ${line}" >&2; exit 1; }
      resolution="${BASH_REMATCH[1]}"
      [[ "${line}" =~ CODECS=\"([^\"]+)\" ]] || { echo "Missing CODECS in ${line}" >&2; exit 1; }
      codecs="${BASH_REMATCH[1]}"
      IFS= read -r uri
      stats="$(playlist_stats "${out}/${uri}")"
      peak="${stats%% *}"
      rest="${stats#* }"
      avg="${rest%% *}"
      bandwidth="$((peak + audio_peak))"
      average="$((avg + audio_avg))"
      echo "#EXT-X-STREAM-INF:BANDWIDTH=${bandwidth},AVERAGE-BANDWIDTH=${average},RESOLUTION=${resolution},CODECS=\"${codecs}\",FRAME-RATE=${frame_rate},AUDIO=\"audio\",SUBTITLES=\"subs\""
      echo "${uri}"
      echo
    fi
  done <"${out}/master.m3u8"
} >"${out}/master.m3u8.tmp"
mv "${out}/master.m3u8.tmp" "${out}/master.m3u8"

printf '%s\n' "${segment_duration}" >"${out}/segment-duration.txt"

fail() {
  echo "$1" >&2
  exit 1
}

master_playlist="${out}/master.m3u8"
variants="$(grep -c '^#EXT-X-STREAM-INF:' "${master_playlist}")"
[[ "${variants}" -eq 2 ]] || fail "Expected two video variants, found ${variants}."
grep -q 'BANDWIDTH=' "${master_playlist}" || fail "Master playlist has no BANDWIDTH."
grep -q 'AVERAGE-BANDWIDTH=' "${master_playlist}" || fail "Master playlist has no AVERAGE-BANDWIDTH."
grep -q 'RESOLUTION=1280x720' "${master_playlist}" || fail "Master playlist has no 1280x720 rung."
grep -q 'RESOLUTION=1920x1080' "${master_playlist}" || fail "Master playlist has no 1920x1080 rung."
grep -q 'CODECS="avc1\.' "${master_playlist}" || fail "Master playlist CODECS is not avc1."
grep -q 'mp4a\.40\.2' "${master_playlist}" || fail "Master playlist CODECS is not AAC-LC."
grep -q "FRAME-RATE=${frame_rate}" "${master_playlist}" || fail "Master playlist has no FRAME-RATE."
grep -q 'TYPE=AUDIO' "${master_playlist}" || fail "Master playlist has no audio rendition."
grep -q 'TYPE=SUBTITLES' "${master_playlist}" || fail "Master playlist has no subtitle rendition."
grep -q 'AUDIO="audio"' "${master_playlist}" || fail "Video variants are not tied to the audio group."
grep -q 'SUBTITLES="subs"' "${master_playlist}" || fail "Video variants are not tied to the subtitle group."
first_resolution="$(awk -F'RESOLUTION=' '/^#EXT-X-STREAM-INF:/ { split($2, a, ","); print a[1]; exit }' "${master_playlist}")"
[[ "${first_resolution}" == "1280x720" ]] || fail "The first variant should be the 2000 kbit/s 720p rung."

check_media() {
  local playlist="$1"
  local kind="$2"
  grep -q '#EXT-X-PLAYLIST-TYPE:VOD' "${playlist}" || fail "${kind} playlist is not VOD."
  grep -q "#EXT-X-TARGETDURATION:${segment_duration}" "${playlist}" || fail "${kind} target duration is not ${segment_duration}."
  grep -q '#EXT-X-MAP:' "${playlist}" || fail "${kind} playlist has no fMP4 init map."
  local map_uri
  map_uri="$(sed -n 's/.*EXT-X-MAP:URI="\([^"]*\)".*/\1/p' "${playlist}")"
  [[ -n "${map_uri}" && -f "$(dirname "${playlist}")/${map_uri}" ]] || fail "${kind} init segment is missing."
  grep -a -q ftyp "$(dirname "${playlist}")/${map_uri}" || fail "${kind} init segment is not fMP4."
  grep -a -q cmfc "$(dirname "${playlist}")/${map_uri}" || fail "${kind} init segment is not CMAF (missing cmfc)."
  local seg count=0
  while IFS= read -r seg; do
    [[ -f "$(dirname "${playlist}")/${seg}" ]] || fail "${kind} segment ${seg} is missing."
    grep -a -q moof "$(dirname "${playlist}")/${seg}" || fail "${kind} segment ${seg} is not an fMP4 fragment."
    count=$((count + 1))
  done < <(awk 'prev ~ /^#EXTINF:/ { print } { prev = $0 }' "${playlist}")
  [[ "${count}" -eq 10 ]] || fail "${kind} has ${count} segments, expected 10."
}

check_media "${out}/720p/media.m3u8" "720p"
check_media "${out}/1080p/media.m3u8" "1080p"
check_media "${audio_playlist}" "audio"
grep -q '#EXT-X-INDEPENDENT-SEGMENTS' "${out}/720p/media.m3u8" || fail "720p playlist is missing EXT-X-INDEPENDENT-SEGMENTS."
grep -q '#EXT-X-INDEPENDENT-SEGMENTS' "${out}/1080p/media.m3u8" || fail "1080p playlist is missing EXT-X-INDEPENDENT-SEGMENTS."

awk -v a="${video_duration}" -v b="$(playlist_stats "${out}/1080p/media.m3u8" | awk '{ print $3 }')" \
  'BEGIN { d = a - b; if (d < 0) d = -d; if (d > 0.001) exit 1 }' \
  || fail "The two video rungs do not cover the same duration."
audio_duration="$(playlist_stats "${audio_playlist}" | awk '{ print $3 }')"
awk -v a="${video_duration}" -v b="${audio_duration}" \
  'BEGIN { d = a - b; if (d < 0) d = -d; if (d > 0.04) exit 1 }' \
  || fail "Audio duration ${audio_duration} does not match video duration ${video_duration}."
awk -v a="${video_duration}" 'BEGIN { if (a < 59.5 || a > 60.5) exit 1 }' \
  || fail "Packaged duration is ${video_duration}, expected about 60 seconds."

grep -q 'X-TIMESTAMP-MAP=LOCAL:00:00:00.000,MPEGTS:0' "${out}/subtitles/${title}.vtt" \
  || fail "Packaged WebVTT is missing X-TIMESTAMP-MAP."
grep -q "#EXTINF:${video_duration}," "${out}/subtitles/media.m3u8" \
  || fail "Subtitle playlist does not cover the video duration."

# Each video segment starts on an IDR. pict_type I with open_gop=0 is that frame.
while IFS= read -r playlist; do
  dir="$(dirname "${playlist}")"
  map_uri="$(sed -n 's/.*EXT-X-MAP:URI="\([^"]*\)".*/\1/p' "${playlist}")"
  while IFS= read -r seg; do
    joined="$(mktemp "${TMPDIR:-/tmp}/playpath-seg.XXXX.mp4")"
    cat "${dir}/${map_uri}" "${dir}/${seg}" >"${joined}"
    pict="$(ffprobe -v error -select_streams v:0 -show_entries frame=pict_type -read_intervals "%+#1" -of csv=p=0 "${joined}")"
    rm -f "${joined}"
    [[ "${pict}" == I* ]] || fail "${seg} does not start with an IDR (got ${pict})."
  done < <(awk 'prev ~ /^#EXTINF:/ { print } { prev = $0 }' "${playlist}")
done < <(printf '%s\n' "${out}/720p/media.m3u8" "${out}/1080p/media.m3u8")

shopt -s nullglob
playlists=("${master}"/*.m3u8 "${master}"/*.mpd "${master}"/*.m4s "${master}"/*.ts)
if ((${#playlists[@]} > 0)); then
  echo "Packaging wrote a playlist or a segment into the master directory." >&2
  printf '%s\n' "${playlists[@]}" >&2
  exit 1
fi

echo "Wrote ${master_playlist}"
echo "Segment duration: ${segment_duration}"
echo "Title id: ${title}"
