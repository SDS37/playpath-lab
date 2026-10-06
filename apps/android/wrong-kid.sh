#!/bin/sh
# Write a DASH menu whose key id is not the one the license service holds.
# The segments stay encrypted with the lab key. Media3 asks for the other id,
# the license answer is a non-success status, and the picture stays black.
# The content key is not read or written.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
package="$root/pipeline/protected/playpath-bars"
manifest="$package/manifest.mpd"
out="$package/manifest-wrong-kid.mpd"

if [ ! -f "$manifest" ]; then
  echo "missing $manifest" >&2
  exit 1
fi

python3 - "$package" "$manifest" "$out" <<'PY'
import pathlib
import sys

package = pathlib.Path(sys.argv[1])
manifest = pathlib.Path(sys.argv[2]).read_text()
out = pathlib.Path(sys.argv[3])
wrong = bytes.fromhex("0123456789abcdeffedcba9876543210")
marker = 'cenc:default_KID="'
start = manifest.index(marker) + len(marker)
end = manifest.index('"', start)
dashed = manifest[start:end]
kid = bytes.fromhex(dashed.replace("-", ""))
if len(kid) != 16 or kid == wrong:
    raise SystemExit("lab key id was not found")

copies = {
    "720p/init_0.mp4": "720p/init_wrong.mp4",
    "1080p/init_1.mp4": "1080p/init_wrong.mp4",
    "audio/init_2.mp4": "audio/init_wrong.mp4",
}
text = manifest.replace(dashed, "01234567-89ab-cdef-fedc-ba9876543210")
for source, target in copies.items():
    data = (package / source).read_bytes()
    count = data.count(kid)
    if count == 0:
        raise SystemExit(f"{source} has no lab key id")
    (package / target).write_bytes(data.replace(kid, wrong))
    text = text.replace(f'initialization="{source}"', f'initialization="{target}"')
out.write_text(text)
print(out)
PY
