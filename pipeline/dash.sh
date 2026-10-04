#!/usr/bin/env bash
# Phase 2. Write the DASH menu for the playpath-bars CMAF ladder.
# The segments already exist. This command does not encode.
# https://dashif.org/guidelines/

set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo "Usage: ./pipeline/dash.sh" >&2
  exit 1
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=timeline
source "${root}/pipeline/timeline"

title="playpath-bars"
master_dir="${root}/pipeline/master"
out="${root}/pipeline/package/${title}"

if ! command -v python3 >/dev/null; then
  echo "python3 must be on PATH to write the DASH menu." >&2
  exit 1
fi

if [[ ! -f "${out}/master.m3u8" ]]; then
  echo "Run ./pipeline/hls.sh before writing the DASH menu." >&2
  exit 1
fi

before="$(find "${out}" -type f \( -name '*.m4s' -o -name '*.mp4' -o -name '*.vtt' \) | sort)"

python3 - "${out}" "${segment_duration}" <<'PY'
import re
import struct
import sys
from pathlib import Path

out = Path(sys.argv[1])
segment_duration = float(sys.argv[2])


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)


def parse_sidx(data):
    index = data.find(b"sidx")
    if index < 4:
        fail("A media segment has no sidx box.")
    size = struct.unpack(">I", data[index - 4 : index])[0]
    body = data[index + 4 : index - 4 + size]
    version = body[0]
    timescale = struct.unpack(">I", body[8:12])[0]
    if version == 0:
        earliest, _first = struct.unpack(">II", body[12:20])
        offset = 20
    else:
        earliest, _first = struct.unpack(">QQ", body[12:28])
        offset = 28
    count = struct.unpack(">H", body[offset + 2 : offset + 4])[0]
    offset += 4
    durations = []
    for _ in range(count):
        durations.append(struct.unpack(">I", body[offset + 4 : offset + 8])[0])
        offset += 12
    if timescale <= 0 or not durations:
        fail("A media segment sidx has no duration.")
    return timescale, earliest, durations


def parse_media(path):
    init = None
    segments = []
    durations = []
    lines = path.read_text().splitlines()
    index = 0
    while index < len(lines):
        line = lines[index]
        if line.startswith("#EXT-X-MAP:"):
            match = re.search(r'URI="([^"]+)"', line)
            if not match:
                fail(f"Missing init URI in {path}.")
            init = match.group(1)
        elif line.startswith("#EXTINF:"):
            durations.append(float(line.split(":", 1)[1].split(",", 1)[0]))
            segments.append(lines[index + 1].strip())
            index += 1
        index += 1
    if not init or not segments:
        fail(f"{path} has no init segment or no media segments.")
    return init, segments, durations


def attr(line, name):
    match = re.search(rf'{name}="([^"]+)"', line)
    if match:
        return match.group(1)
    match = re.search(rf"{name}=([^,]*)", line)
    if not match:
        fail(f"Missing {name} in {line}.")
    return match.group(1)


variants = []
audio_uri = None
text_uri = None
master_lines = (out / "master.m3u8").read_text().splitlines()
for index, line in enumerate(master_lines):
    if line.startswith("#EXT-X-MEDIA:") and "TYPE=AUDIO" in line:
        audio_uri = attr(line, "URI")
    elif line.startswith("#EXT-X-MEDIA:") and "TYPE=SUBTITLES" in line:
        text_uri = attr(line, "URI")
    elif line.startswith("#EXT-X-STREAM-INF:"):
        codecs = attr(line, "CODECS").split(",")
        video_codec = next((item for item in codecs if item.startswith("avc1.")), None)
        audio_codec = next((item for item in codecs if item.startswith("mp4a.")), None)
        if not video_codec or not audio_codec:
            fail(f"HLS CODECS is not video plus audio: {codecs}")
        variants.append(
            {
                "resolution": attr(line, "RESOLUTION"),
                "video_codec": video_codec,
                "audio_codec": audio_codec,
                "frame_rate": attr(line, "FRAME-RATE"),
                "uri": master_lines[index + 1].strip(),
            }
        )

if len(variants) != 2:
    fail(f"Expected two HLS video variants, found {len(variants)}.")
if audio_uri is None or text_uri is None:
    fail("The HLS master has no audio rendition or no subtitle rendition.")
if len({item["audio_codec"] for item in variants}) != 1:
    fail("The HLS variants do not share one audio codec.")

def load_track(uri):
    playlist = out / uri
    init, names, extinf = parse_media(playlist)
    directory = playlist.parent
    pieces = []
    for name, hls_duration in zip(names, extinf):
        path = directory / name
        if not path.is_file():
            fail(f"Missing segment {path}.")
        timescale, earliest, durations = parse_sidx(path.read_bytes())
        if len(durations) != 1:
            fail(f"{path} does not contain one CMAF subsegment.")
        pieces.append(
            {
                "name": name,
                "init": init,
                "timescale": timescale,
                "earliest": earliest,
                "duration": durations[0],
                "hls_duration": hls_duration,
                "bytes": path.stat().st_size,
            }
        )
    return pieces

video_tracks = []
for variant in variants:
    pieces = load_track(variant["uri"])
    video_tracks.append((variant, pieces))

audio_pieces = load_track(audio_uri)
text_playlist = out / text_uri
text_name = next(
    line.strip()
    for line in text_playlist.read_text().splitlines()
    if line and not line.startswith("#")
)
text_path = text_playlist.parent / text_name
if not text_path.is_file():
    fail(f"Missing subtitle file {text_path}.")

first_video = video_tracks[0][1]
second_video = video_tracks[1][1]
if [(item["earliest"], item["duration"]) for item in first_video] != [
    (item["earliest"], item["duration"]) for item in second_video
]:
    fail("The two video rungs do not share segment times.")

video_seconds = sum(item["duration"] for item in first_video) / first_video[0]["timescale"]
hls_video_seconds = sum(item["hls_duration"] for item in first_video)
if abs(video_seconds - hls_video_seconds) > 0.001:
    fail("DASH video timeline does not match the HLS media playlist.")
if abs(video_seconds - 60) > 0.5:
    fail(f"Presentation duration is {video_seconds}, expected about 60 seconds.")
for item in first_video:
    actual = item["duration"] / item["timescale"]
    if abs(actual - segment_duration) > 0.001:
        fail(f"A video segment is {actual} seconds, expected {segment_duration}.")

audio_seconds = sum(item["duration"] for item in audio_pieces) / audio_pieces[0]["timescale"]
hls_audio_seconds = sum(item["hls_duration"] for item in audio_pieces)
if abs(audio_seconds - hls_audio_seconds) > 0.001:
    fail("DASH audio timeline does not match the HLS media playlist.")
if abs(audio_seconds - video_seconds) > 0.04:
    fail("Audio and video presentations do not cover the same duration.")

def peak_bandwidth(pieces):
    peak = 0
    for item in pieces:
        seconds = item["duration"] / item["timescale"]
        rate = item["bytes"] * 8 / seconds
        if rate > peak:
            peak = rate
    return int(peak + 0.5)


def timeline(pieces):
    lines = []
    for item in pieces:
        lines.append(f'            <S t="{item["earliest"]}" d="{item["duration"]}"/>')
    return "\n".join(lines)


def seconds_attr(value):
    return f"PT{value:.3f}S"


period = seconds_attr(video_seconds)
buffer = f"PT{int(segment_duration)}S" if segment_duration == int(segment_duration) else seconds_attr(segment_duration)
audio_codec = variants[0]["audio_codec"]
text_bandwidth = max(1, int(text_path.stat().st_size * 8 / video_seconds + 0.5))
text_href = f"{text_playlist.parent.name}/{text_name}"

representations = []
for variant, pieces in video_tracks:
    width, height = variant["resolution"].split("x")
    directory = (out / variant["uri"]).parent.name
    init = pieces[0]["init"]
    offset = pieces[0]["earliest"]
    timescale = pieces[0]["timescale"]
    representations.append(
        f"""        <Representation id="{directory}" bandwidth="{peak_bandwidth(pieces)}" width="{width}" height="{height}" frameRate="{variant["frame_rate"]}" codecs="{variant["video_codec"]}">
          <SegmentTemplate timescale="{timescale}" presentationTimeOffset="{offset}" startNumber="0" initialization="{directory}/{init}" media="{directory}/seg_$Number$.m4s">
            <SegmentTimeline>
{timeline(pieces)}
            </SegmentTimeline>
          </SegmentTemplate>
        </Representation>"""
    )

audio_directory = (out / audio_uri).parent.name
audio_init = audio_pieces[0]["init"]
audio_offset = audio_pieces[0]["earliest"]
audio_timescale = audio_pieces[0]["timescale"]
mpd = f"""<?xml version="1.0" encoding="UTF-8"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static" profiles="urn:mpeg:dash:profile:isoff-live:2011" minBufferTime="{buffer}" mediaPresentationDuration="{period}">
  <Period id="playpath-bars" duration="{period}">
    <AdaptationSet contentType="video" mimeType="video/mp4" segmentAlignment="true" startWithSAP="1">
{chr(10).join(representations)}
    </AdaptationSet>
    <AdaptationSet contentType="audio" mimeType="audio/mp4" lang="en" segmentAlignment="true" startWithSAP="1">
      <Representation id="audio" bandwidth="{peak_bandwidth(audio_pieces)}" audioSamplingRate="48000" codecs="{audio_codec}">
        <AudioChannelConfiguration schemeIdUri="urn:mpeg:dash:23003:3:audio_channel_configuration:2011" value="2"/>
        <SegmentTemplate timescale="{audio_timescale}" presentationTimeOffset="{audio_offset}" startNumber="0" initialization="{audio_directory}/{audio_init}" media="{audio_directory}/seg_$Number$.m4s">
          <SegmentTimeline>
{timeline(audio_pieces)}
          </SegmentTimeline>
        </SegmentTemplate>
      </Representation>
    </AdaptationSet>
    <AdaptationSet contentType="text" mimeType="text/vtt" lang="en">
      <Role schemeIdUri="urn:mpeg:dash:role:2011" value="subtitle"/>
      <Representation id="subs" bandwidth="{text_bandwidth}">
        <BaseURL>{text_href}</BaseURL>
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>
"""
(out / "manifest.mpd").write_text(mpd)
print(f"Wrote {out / 'manifest.mpd'}")
print(f"Period duration: {video_seconds:.3f}")
PY

after="$(find "${out}" -type f \( -name '*.m4s' -o -name '*.mp4' -o -name '*.vtt' \) | sort)"
if [[ "${before}" != "${after}" ]]; then
  echo "DASH packaging changed the CMAF ladder." >&2
  exit 1
fi

shopt -s nullglob
playlists=("${master_dir}"/*.m3u8 "${master_dir}"/*.mpd "${master_dir}"/*.m4s "${master_dir}"/*.ts)
if ((${#playlists[@]} > 0)); then
  echo "DASH packaging wrote a playlist or a segment into the master directory." >&2
  printf '%s\n' "${playlists[@]}" >&2
  exit 1
fi

"${root}/pipeline/timelines.sh"

echo "Title id: ${title}"
