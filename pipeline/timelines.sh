#!/usr/bin/env bash
# Phase 2. Compare the HLS media playlists with the DASH MPD.
# The command fails when segment times or the presentation duration diverge.
# https://dashif.org/guidelines/

set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo "Usage: ./pipeline/timelines.sh" >&2
  exit 1
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
out="${root}/pipeline/package/playpath-bars"

if [[ ! -f "${out}/master.m3u8" || ! -f "${out}/manifest.mpd" ]]; then
  echo "Run ./pipeline/hls.sh and ./pipeline/dash.sh before checking timelines." >&2
  exit 1
fi

python3 - "${out}" <<'PY'
import re
import sys
from pathlib import Path

out = Path(sys.argv[1])
tolerance = 0.001


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)


def hls_points(path):
    durations = []
    for line in path.read_text().splitlines():
        if line.startswith("#EXTINF:"):
            durations.append(float(line.split(":", 1)[1].split(",", 1)[0]))
    if not durations:
        fail(f"{path} has no segment durations.")
    points = []
    start = 0.0
    for duration in durations:
        points.append((start, duration))
        start += duration
    return points


def clock(value):
    match = re.fullmatch(r"PT(\d+(?:\.\d+)?)S", value)
    if not match:
        fail(f"Unsupported duration {value}.")
    return float(match.group(1))


def attrs(text):
    return dict(re.findall(r'([\w:]+)="([^"]*)"', text))


def dash_points(block):
    template = re.search(r"<SegmentTemplate\b([^>]*)>", block)
    if not template:
        fail("A DASH representation has no SegmentTemplate.")
    values = attrs(template.group(1))
    timescale = int(values["timescale"])
    offset = int(values.get("presentationTimeOffset", "0"))
    timeline = re.search(r"<SegmentTimeline>(.*?)</SegmentTimeline>", block, re.S)
    if not timeline:
        fail("A DASH representation has no SegmentTimeline.")
    points = []
    cursor = None
    for tag in re.findall(r"<S\b([^>]*)/>", timeline.group(1)):
        values = attrs(tag)
        duration = int(values["d"])
        repeat = int(values.get("r", "0"))
        if "t" in values:
            tick = int(values["t"])
        elif cursor is None:
            fail("A DASH segment has no start time.")
        else:
            tick = cursor
        for _ in range(repeat + 1):
            points.append(((tick - offset) / timescale, duration / timescale))
            tick += duration
        cursor = tick
    if not points:
        fail("A DASH representation has no segments.")
    return points


def near(left, right):
    return abs(left - right) <= tolerance


def compare(name, hls, dash):
    if len(hls) != len(dash):
        fail(f"{name} has {len(hls)} HLS segments and {len(dash)} DASH segments.")
    for index, ((hls_start, hls_duration), (dash_start, dash_duration)) in enumerate(zip(hls, dash)):
        if not near(hls_start, dash_start) or not near(hls_duration, dash_duration):
            fail(
                f"{name} segment {index} diverges: "
                f"HLS {hls_start:.6f}+{hls_duration:.6f}, "
                f"DASH {dash_start:.6f}+{dash_duration:.6f}."
            )


master = (out / "master.m3u8").read_text().splitlines()
video_uris = []
audio_uri = None
text_uri = None
for index, line in enumerate(master):
    if line.startswith("#EXT-X-MEDIA:") and "TYPE=AUDIO" in line:
        audio_uri = re.search(r'URI="([^"]+)"', line).group(1)
    elif line.startswith("#EXT-X-MEDIA:") and "TYPE=SUBTITLES" in line:
        text_uri = re.search(r'URI="([^"]+)"', line).group(1)
    elif line.startswith("#EXT-X-STREAM-INF:"):
        video_uris.append(master[index + 1].strip())

if len(video_uris) != 2 or not audio_uri or not text_uri:
    fail("The HLS master does not list two video rungs, audio, and subtitles.")

mpd = (out / "manifest.mpd").read_text()
period = clock(re.search(r'<Period\b[^>]*\bduration="([^"]+)"', mpd).group(1))
presentation = clock(re.search(r'mediaPresentationDuration="([^"]+)"', mpd).group(1))

by_folder = {}
for block in re.findall(r"<Representation\b.*?</Representation>", mpd, re.S):
    media = re.search(r'media="([^"]+)"', block)
    if not media:
        continue
    folder = media.group(1).split("/", 1)[0]
    by_folder[folder] = dash_points(block)

video_points = []
for uri in video_uris:
    folder = uri.split("/", 1)[0]
    if folder not in by_folder:
        fail(f"DASH has no representation for {folder}.")
    points = hls_points(out / uri)
    compare(folder, points, by_folder[folder])
    video_points.append(points)

compare("video rungs", video_points[0], video_points[1])
video_duration = video_points[0][-1][0] + video_points[0][-1][1]
if not near(period, video_duration) or not near(presentation, video_duration):
    fail(
        f"Presentation duration diverges: HLS {video_duration:.3f}, "
        f"DASH period {period:.3f}, media presentation {presentation:.3f}."
    )

audio_folder = audio_uri.split("/", 1)[0]
if audio_folder not in by_folder:
    fail("DASH has no audio representation.")
compare("audio", hls_points(out / audio_uri), by_folder[audio_folder])

text_points = hls_points(out / text_uri)
text_duration = text_points[-1][0] + text_points[-1][1]
if not near(text_duration, video_duration):
    fail(f"Subtitle playlist duration {text_duration:.3f} does not match the presentation.")

print(f"Timelines match. Presentation duration: {video_duration:.3f}")
PY
