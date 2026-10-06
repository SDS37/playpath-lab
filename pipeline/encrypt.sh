#!/usr/bin/env bash
# Phase 3. Write a CENC copy of the playpath-bars ladder.
# The clear package stays, so iOS and hls.js still have clear HLS.
# ISO/IEC 23001-7 (CENC). Clear Key: https://www.w3.org/TR/encrypted-media/

set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo "Usage: ./pipeline/encrypt.sh" >&2
  exit 1
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
title="playpath-bars"
clear="${root}/pipeline/package/${title}"
out="${root}/pipeline/protected/${title}"
master_dir="${root}/pipeline/master"
key_file="${root}/services/license/lab-key.json"

if ! command -v python3 >/dev/null; then
  echo "python3 must be on PATH to encrypt the ladder." >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null; then
  echo "ffmpeg must be on PATH. The encrypt step uses it as the player that has no key." >&2
  exit 1
fi

if [[ ! -f "${clear}/master.m3u8" || ! -f "${clear}/manifest.mpd" ]]; then
  echo "Run ./pipeline/hls.sh and ./pipeline/dash.sh before encrypting." >&2
  exit 1
fi

if [[ ! -f "${key_file}" ]]; then
  echo "The lab key is missing: services/license/lab-key.json" >&2
  exit 1
fi

# Publish only after encryption and the checks below succeed. A failed run
# must not replace the protected package.
work="${out}.tmp"
rm -rf "${work}"
mkdir -p "${work}"
cp -R "${clear}/." "${work}/"

if ! python3 - "${clear}" "${work}" "${key_file}" <<'PY'
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

clear = Path(sys.argv[1])
out = Path(sys.argv[2])
key_file = Path(sys.argv[3])

CLEAR_KEY_SYSTEM = "urn:uuid:e2719d58-a985-b3c9-781a-b030af78d30e"
LICENSE_URL = "http://127.0.0.1:8082/"
CONTAINERS = {
    b"moov",
    b"trak",
    b"mdia",
    b"minf",
    b"stbl",
    b"edts",
    b"mvex",
    b"moof",
    b"traf",
    b"udta",
}


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)


def require_init(directory):
    # A variant stream map makes ffmpeg write init_<index>.mp4 even when
    # hls.sh asks for init.mp4. The media playlist records the real name.
    playlist = directory / "media.m3u8"
    name = ""
    if playlist.is_file():
        for line in playlist.read_text().splitlines():
            if line.startswith("#EXT-X-MAP:") and 'URI="' in line:
                name = line.split('URI="', 1)[1].split('"', 1)[0]
                break
    if not name or "/" in name or "\\" in name or name.startswith("."):
        fail(f"{directory.name} has no init segment.")
    path = directory / name
    if not path.is_file():
        fail(f"{directory.name} has no init segment.")
    return path


def box_size(data, at):
    size = int.from_bytes(data[at : at + 4], "big")
    if size < 8:
        fail("A media box has a size this step cannot rewrite.")
    return size


def set_box_size(data, at, size):
    data[at : at + 4] = size.to_bytes(4, "big")


def grow(data, at, delta):
    set_box_size(data, at, box_size(data, at) + delta)


def find_box(data, start, end, target, path):
    index = start
    while index + 8 <= end:
        size = box_size(data, index)
        if index + size > end:
            fail("A media box runs past its parent.")
        kind = bytes(data[index + 4 : index + 8])
        if kind == target:
            return path + [index]
        if kind in CONTAINERS:
            found = find_box(data, index + 8, index + size, target, path + [index])
            if found:
                return found
        index += size
    return None


def require_box(data, target):
    found = find_box(data, 0, len(data), target, [])
    if not found:
        fail(f"A media file has no {target.decode()} box.")
    return found[-1]


def build_tenc(kid):
    payload = b"\x00\x00\x00\x00" + b"\x00\x00\x01\x08" + kid
    return (8 + len(payload)).to_bytes(4, "big") + b"tenc" + payload


def build_sinf(original, kid):
    frma = (12).to_bytes(4, "big") + b"frma" + original
    schm_payload = b"\x00\x00\x00\x00" + b"cenc" + (0x00010000).to_bytes(4, "big")
    schm = (8 + len(schm_payload)).to_bytes(4, "big") + b"schm" + schm_payload
    tenc = build_tenc(kid)
    schi = (8 + len(tenc)).to_bytes(4, "big") + b"schi" + tenc
    inner = frma + schm + schi
    return (8 + len(inner)).to_bytes(4, "big") + b"sinf" + inner


def build_pssh(kid):
    system = bytes.fromhex("e2719d58a985b3c9781ab030af78d30e")
    payload = b"\x01\x00\x00\x00" + system + (1).to_bytes(4, "big") + kid + (0).to_bytes(4, "big")
    return (8 + len(payload)).to_bytes(4, "big") + b"pssh" + payload


def aes_ctr(key, iv8, data):
    if not data:
        return b""
    iv = iv8 + b"\x00" * 8
    return AES_CTR(key, iv, data)


def aes_ctr_commoncrypto(key, iv, data):
    import ctypes
    from ctypes import POINTER, byref, c_int, c_size_t, c_uint32, c_void_p

    lib = ctypes.CDLL("/usr/lib/system/libcommonCrypto.dylib")
    lib.CCCryptorCreateWithMode.argtypes = [
        c_uint32,
        c_uint32,
        c_uint32,
        c_uint32,
        c_void_p,
        c_void_p,
        c_size_t,
        c_void_p,
        c_size_t,
        c_int,
        c_uint32,
        POINTER(c_void_p),
    ]
    lib.CCCryptorCreateWithMode.restype = c_int
    lib.CCCryptorUpdate.argtypes = [
        c_void_p,
        c_void_p,
        c_size_t,
        c_void_p,
        c_size_t,
        POINTER(c_size_t),
    ]
    lib.CCCryptorUpdate.restype = c_int
    lib.CCCryptorRelease.argtypes = [c_void_p]
    cryptor = c_void_p()
    status = lib.CCCryptorCreateWithMode(
        0, 4, 0, 0, iv, key, len(key), None, 0, 0, 0x0002, byref(cryptor)
    )
    if status != 0:
        raise OSError("CommonCrypto rejected the lab key.")
    out = ctypes.create_string_buffer(len(data))
    moved = c_size_t()
    status = lib.CCCryptorUpdate(cryptor, data, len(data), out, len(data), byref(moved))
    lib.CCCryptorRelease(cryptor)
    if status != 0 or moved.value != len(data):
        raise OSError("CommonCrypto did not encrypt the sample.")
    return out.raw


def aes_ctr_openssl(key, iv, data):
    if shutil.which("openssl") is None:
        fail("openssl must be on PATH when CommonCrypto is not available.")
    try:
        result = subprocess.run(
            [
                "openssl",
                "enc",
                "-aes-128-ctr",
                "-K",
                key.hex(),
                "-iv",
                iv.hex(),
                "-nosalt",
                "-nopad",
            ],
            input=data,
            capture_output=True,
            check=False,
        )
    except FileNotFoundError:
        fail("openssl must be on PATH when CommonCrypto is not available.")
    if result.returncode != 0 or len(result.stdout) != len(data):
        fail("openssl could not apply AES-CTR.")
    return result.stdout


def select_aes_ctr():
    try:
        aes_ctr_commoncrypto(b"\x00" * 16, b"\x00" * 16, b"\x00" * 16)
    except OSError:
        if shutil.which("openssl") is None:
            fail("openssl must be on PATH when CommonCrypto is not available.")
        return aes_ctr_openssl
    return aes_ctr_commoncrypto


AES_CTR = select_aes_ctr()


def sample_entry_header(kind):
    if kind in {b"avc1", b"encv"}:
        return 86
    if kind in {b"mp4a", b"enca"}:
        return 36
    fail(f"Unsupported sample entry {kind.decode()}.")


def nal_length_size(entry):
    header = sample_entry_header(b"avc1")
    index = header
    while index + 8 <= len(entry):
        size = int.from_bytes(entry[index : index + 4], "big")
        if size < 8 or index + size > len(entry):
            break
        if entry[index + 4 : index + 8] == b"avcC":
            avcc = entry[index + 8 : index + size]
            if len(avcc) < 5:
                fail("avcC is too short to name the NAL length.")
            return (avcc[4] & 3) + 1
        index += size
    fail("Video sample entry has no avcC.")


def encrypt_init(path, kid):
    data = bytearray(path.read_bytes())
    if b"encv" in data or b"enca" in data or b"tenc" in data:
        fail(f"{path.name} is already encrypted.")
    path_to_stsd = find_box(data, 0, len(data), b"stsd", [])
    if not path_to_stsd:
        fail(f"{path.name} has no sample description.")
    stsd = path_to_stsd[-1]
    entry_count = int.from_bytes(data[stsd + 12 : stsd + 16], "big")
    if entry_count != 1:
        fail(f"{path.name} has {entry_count} sample entries.")
    entry_at = stsd + 16
    entry_size = box_size(data, entry_at)
    original = bytes(data[entry_at + 4 : entry_at + 8])
    if original not in {b"avc1", b"mp4a"}:
        fail(f"{path.name} sample entry {original.decode()} cannot take CENC.")
    encrypted_type = b"encv" if original == b"avc1" else b"enca"
    data[entry_at + 4 : entry_at + 8] = encrypted_type
    sinf = build_sinf(original, kid)
    insert_at = entry_at + entry_size
    data[insert_at:insert_at] = sinf
    grow(data, entry_at, len(sinf))
    for at in path_to_stsd:
        grow(data, at, len(sinf))
    moov = path_to_stsd[0]
    pssh = build_pssh(kid)
    data[moov + box_size(data, moov) : moov + box_size(data, moov)] = pssh
    grow(data, moov, len(pssh))
    path.write_bytes(data)
    return original


def parse_tfhd_default_size(box):
    flags = int.from_bytes(box[9:12], "big")
    offset = 16
    if flags & 0x1:
        offset += 8
    if flags & 0x2:
        offset += 4
    if flags & 0x8:
        offset += 4
    if flags & 0x10:
        return int.from_bytes(box[offset : offset + 4], "big")
    return None


def parse_trun(box):
    flags = int.from_bytes(box[9:12], "big")
    count = int.from_bytes(box[12:16], "big")
    offset = 16
    data_offset_at = None
    if flags & 0x1:
        data_offset_at = offset
        offset += 4
    if flags & 0x4:
        offset += 4
    sizes = []
    for _ in range(count):
        size = None
        if flags & 0x100:
            offset += 4
        if flags & 0x200:
            size = int.from_bytes(box[offset : offset + 4], "big")
            offset += 4
        if flags & 0x400:
            offset += 4
        if flags & 0x800:
            offset += 4
        sizes.append(size)
    if offset != len(box):
        fail("A track run is not the size this step parsed.")
    return sizes, data_offset_at


def split_subsamples(sample, length_size):
    parts = []
    pos = 0
    while pos < len(sample):
        if pos + length_size > len(sample):
            fail("A video sample is not length-prefixed.")
        nal_length = int.from_bytes(sample[pos : pos + length_size], "big")
        nal_end = pos + length_size + nal_length
        if nal_length < 1 or nal_end > len(sample):
            fail("A video sample has a truncated NAL.")
        clear = length_size + 1
        protected = nal_length - 1
        parts.append((pos, clear, protected))
        pos = nal_end
    if not parts:
        fail("A video sample has no NAL.")
    return parts


def sample_iv(track_salt, segment_index, sample_index):
    value = (track_salt << 48) | (segment_index << 24) | (sample_index + 1)
    return value.to_bytes(8, "big")


def build_saiz(sizes):
    if any(size > 255 for size in sizes):
        fail("Sample auxiliary info is larger than a saiz box can store.")
    if len(set(sizes)) == 1:
        body = bytes([sizes[0]]) + len(sizes).to_bytes(4, "big")
    else:
        body = bytes([0]) + len(sizes).to_bytes(4, "big") + bytes(sizes)
    payload = b"\x00\x00\x00\x00" + body
    return (8 + len(payload)).to_bytes(4, "big") + b"saiz" + payload


def build_saio():
    payload = b"\x00\x00\x00\x00" + (1).to_bytes(4, "big") + (0).to_bytes(4, "big")
    return (8 + len(payload)).to_bytes(4, "big") + b"saio" + payload


def build_senc(records, subsample):
    flags = b"\x00\x00\x00\x02" if subsample else b"\x00\x00\x00\x00"
    payload = flags + len(records).to_bytes(4, "big") + b"".join(records)
    return (8 + len(payload)).to_bytes(4, "big") + b"senc" + payload


def update_sidx(data, delta):
    sidx = require_box(data, b"sidx")
    size = box_size(data, sidx)
    body = data[sidx + 8 : sidx + size]
    version = body[0]
    offset = 20 if version == 0 else 28
    count = int.from_bytes(body[offset + 2 : offset + 4], "big")
    if count != 1:
        fail("A media segment sidx has more than one reference.")
    offset += 4
    word = int.from_bytes(body[offset : offset + 4], "big")
    referenced = word & 0x7FFFFFFF
    word = (word & 0x80000000) | (referenced + delta)
    data[sidx + 8 + offset : sidx + 12 + offset] = word.to_bytes(4, "big")


def encrypt_segment(path, key, kid, segment_index, track_salt, length_size):
    data = bytearray(path.read_bytes())
    if b"senc" in data:
        fail(f"{path.name} is already encrypted.")
    trun_at = require_box(data, b"trun")
    trun = bytes(data[trun_at : trun_at + box_size(data, trun_at)])
    sizes, data_offset_at = parse_trun(trun)
    if data_offset_at is None:
        fail(f"{path.name} track run has no data offset.")
    tfhd_at = require_box(data, b"tfhd")
    default_size = parse_tfhd_default_size(
        bytes(data[tfhd_at : tfhd_at + box_size(data, tfhd_at)])
    )
    sizes = [size if size is not None else default_size for size in sizes]
    if any(size is None for size in sizes):
        fail(f"{path.name} has a sample with no size.")
    mdat_at = require_box(data, b"mdat")
    payload_size = box_size(data, mdat_at) - 8
    if sum(sizes) != payload_size:
        fail(f"{path.name} sample sizes do not fill mdat.")
    payload = bytearray(data[mdat_at + 8 : mdat_at + 8 + payload_size])
    records = []
    aux_sizes = []
    cursor = 0
    subsample = length_size is not None
    for sample_index, size in enumerate(sizes):
        sample = payload[cursor : cursor + size]
        iv = sample_iv(track_salt, segment_index, sample_index)
        if subsample:
            parts = split_subsamples(sample, length_size)
            protected = b"".join(
                sample[start + clear : start + clear + protected_len]
                for start, clear, protected_len in parts
            )
            encrypted = aes_ctr(key, iv, protected)
            enc_at = 0
            for start, clear, protected_len in parts:
                sample[start + clear : start + clear + protected_len] = encrypted[
                    enc_at : enc_at + protected_len
                ]
                enc_at += protected_len
            record = iv + len(parts).to_bytes(2, "big")
            for _start, clear, protected_len in parts:
                record += clear.to_bytes(2, "big") + protected_len.to_bytes(4, "big")
        else:
            sample = bytearray(aes_ctr(key, iv, bytes(sample)))
            record = iv
        payload[cursor : cursor + size] = sample
        records.append(record)
        aux_sizes.append(len(record))
        cursor += size
    data[mdat_at + 8 : mdat_at + 8 + payload_size] = payload
    # saiz describes each sample's auxiliary info and saio locates it.
    # Inside a movie fragment the saio offset is relative to the moof.
    saiz = build_saiz(aux_sizes)
    saio = build_saio()
    senc = build_senc(records, subsample)
    blob = saiz + saio + senc
    moof_at = require_box(data, b"moof")
    traf_at = require_box(data, b"traf")
    data[trun_at:trun_at] = blob
    grow(data, traf_at, len(blob))
    grow(data, moof_at, len(blob))
    trun_at += len(blob)
    old_offset = int.from_bytes(
        data[trun_at + data_offset_at : trun_at + data_offset_at + 4], "big", signed=True
    )
    data[trun_at + data_offset_at : trun_at + data_offset_at + 4] = (
        old_offset + len(blob)
    ).to_bytes(4, "big", signed=True)
    update_sidx(data, len(blob))
    senc_at = trun_at - len(senc)
    first_iv = senc_at + 16
    saio_at = senc_at - len(saio)
    data[saio_at + 16 : saio_at + 20] = (first_iv - moof_at).to_bytes(4, "big")
    path.write_bytes(data)


def kid_uuid(kid):
    text = kid.hex()
    return f"{text[0:8]}-{text[8:12]}-{text[12:16]}-{text[16:20]}-{text[20:32]}"


def playlist_rates(path):
    lines = path.read_text().splitlines()
    peaks = []
    total_bytes = 0
    total_duration = 0.0
    index = 0
    while index < len(lines):
        line = lines[index]
        if line.startswith("#EXTINF:"):
            duration = float(line.split(":", 1)[1].split(",", 1)[0])
            name = lines[index + 1].strip()
            size = (path.parent / name).stat().st_size
            peaks.append(size * 8 / duration)
            total_bytes += size
            total_duration += duration
            index += 2
            continue
        index += 1
    if not peaks or total_duration <= 0:
        fail(f"{path} has no segment durations.")
    peak = int(max(peaks) + 0.5)
    average = int(total_bytes * 8 / total_duration + 0.5)
    return peak, average


def replace_number(line, name, value, previous):
    if value < previous:
        fail(f"{name} fell from {previous} to {value} after encryption.")
    return re.sub(rf"{name}=\d+", f"{name}={value}", line, count=1)


def write_menus(kid):
    # HLS defines URI, not KEYID. Unrecognized attributes are ignored
    # (draft-pantos-hls-rfc8216bis-22, section 6.3.1), so the key id is
    # carried in the URI. KEYFORMAT names Clear Key.
    key_line = (
        "METHOD=SAMPLE-AES-CTR,"
        f'URI="{LICENSE_URL}?keyId={kid.hex()}",'
        f'KEYFORMAT="{CLEAR_KEY_SYSTEM}",'
        'KEYFORMATVERSIONS="1"'
    )
    master = (out / "master.m3u8").read_text().splitlines()
    if any(line.startswith("#EXT-X-SESSION-KEY:") for line in master):
        fail("The HLS master already names a key.")
    inserted = False
    rewritten = []
    for line in master:
        rewritten.append(line)
        if not inserted and line.startswith("#EXT-X-VERSION:"):
            rewritten.append(f"#EXT-X-SESSION-KEY:{key_line}")
            inserted = True
    if not inserted:
        fail("The HLS master has no version tag.")
    audio_peak, audio_average = playlist_rates(out / "audio" / "media.m3u8")
    rated = []
    index = 0
    while index < len(rewritten):
        line = rewritten[index]
        rated.append(line)
        if line.startswith("#EXT-X-STREAM-INF:"):
            uri = rewritten[index + 1].strip()
            peak, average = playlist_rates(out / uri)
            bandwidth = peak + audio_peak
            combined = average + audio_average
            previous_bandwidth = int(re.search(r"BANDWIDTH=(\d+)", line).group(1))
            previous_average = int(re.search(r"AVERAGE-BANDWIDTH=(\d+)", line).group(1))
            line = replace_number(line, "BANDWIDTH", bandwidth, previous_bandwidth)
            line = replace_number(line, "AVERAGE-BANDWIDTH", combined, previous_average)
            rated[-1] = line
        index += 1
    (out / "master.m3u8").write_text("\n".join(rated) + "\n")
    for playlist in (out / "720p" / "media.m3u8", out / "1080p" / "media.m3u8", out / "audio" / "media.m3u8"):
        lines = playlist.read_text().splitlines()
        if any(line.startswith("#EXT-X-KEY:") for line in lines):
            fail(f"{playlist.name} already names a key.")
        rewritten = []
        inserted = False
        for line in lines:
            rewritten.append(line)
            if not inserted and line.startswith("#EXT-X-MAP:"):
                rewritten.append(f"#EXT-X-KEY:{key_line}")
                inserted = True
        if not inserted:
            fail(f"{playlist} has no initialization map.")
        playlist.write_text("\n".join(rewritten) + "\n")
    mpd = (out / "manifest.mpd").read_text()
    if "ContentProtection" in mpd:
        fail("The DASH menu already names a key.")
    if 'xmlns="urn:mpeg:dash:schema:mpd:2011"' not in mpd:
        fail("The DASH menu has no MPD namespace.")
    mpd = mpd.replace(
        '<MPD xmlns="urn:mpeg:dash:schema:mpd:2011"',
        '<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" '
        'xmlns:cenc="urn:mpeg:cenc:2013" '
        'xmlns:clearkey="http://dashif.org/guidelines/clearKey"',
        1,
    )
    block = (
        f'\n        <ContentProtection schemeIdUri="urn:mpeg:dash:mp4protection:2011" '
        f'value="cenc" cenc:default_KID="{kid_uuid(kid)}"/>\n'
        f'        <ContentProtection schemeIdUri="{CLEAR_KEY_SYSTEM}" value="ClearKey1.0">\n'
        f'          <clearkey:Laurl Lic_type="EME-1.0">{LICENSE_URL}</clearkey:Laurl>\n'
        "        </ContentProtection>"
    )
    for content_type in ("video", "audio"):
        needle = f'<AdaptationSet contentType="{content_type}"'
        start = mpd.find(needle)
        if start < 0:
            fail(f"The DASH menu has no {content_type} adaptation set.")
        end = mpd.find(">", start)
        mpd = mpd[: end + 1] + block + mpd[end + 1 :]
    if mpd.count('schemeIdUri="urn:mpeg:dash:mp4protection:2011"') != 2 or mpd.count(CLEAR_KEY_SYSTEM) != 2:
        fail("DASH content protection was not limited to video and audio.")
    if 'contentType="text"' not in mpd or mpd.split('contentType="text"', 1)[1].count(
        "ContentProtection"
    ):
        fail("DASH content protection was written onto the captions.")
    for folder in ("720p", "1080p", "audio"):
        peak, _average = playlist_rates(out / folder / "media.m3u8")
        match = re.search(rf'<Representation id="{folder}"[^>]*bandwidth="(\d+)"', mpd)
        if not match:
            fail(f"DASH has no bandwidth for {folder}.")
        previous = int(match.group(1))
        if peak < previous:
            fail(f"DASH {folder} bandwidth fell from {previous} to {peak} after encryption.")
        mpd = mpd[: match.start(1)] + str(peak) + mpd[match.end(1) :]
    (out / "manifest.mpd").write_text(mpd)


def player_check(init, segment, key, kind, selector):
    directory = Path(tempfile.mkdtemp(prefix="playpath-cenc-"))
    proof = directory / "proof.mp4"
    frame = "v" if selector.endswith("v:0") else "a"

    def run(extra):
        return subprocess.run(
            ["ffmpeg", "-v", "error", *extra, "-i", str(proof), "-map", selector, f"-frames:{frame}", "30", "-f", "null", "-"],
            capture_output=True,
            check=False,
        )

    try:
        with proof.open("wb") as handle:
            handle.write(init.read_bytes())
            handle.write(segment.read_bytes())
        if run([]).returncode == 0:
            fail(f"A player with no key decoded the protected {kind} segment.")
        wrong = bytes(byte ^ 0xFF for byte in key)
        if run(["-decryption_key", wrong.hex()]).returncode == 0:
            fail(f"A player with the wrong key decoded the protected {kind} segment.")
        opened = run(["-decryption_key", key.hex()])
        if opened.returncode != 0:
            detail = opened.stderr.decode(errors="replace").strip().splitlines()
            tail = " ".join(detail[-3:])
            fail(f"The protected {kind} segment did not decode with the lab key. {tail}")
    finally:
        shutil.rmtree(directory)


config = json.loads(key_file.read_text())
if config.get("keySystem") != "org.w3.clearkey":
    fail("The lab key config is not org.w3.clearkey.")
try:
    kid = bytes.fromhex(config["keyId"])
    key = bytes.fromhex(config["key"])
except (KeyError, ValueError):
    fail("The lab key config needs a 16-byte key id and a 16-byte key.")
if len(kid) != 16 or len(key) != 16 or kid == key:
    fail("The lab key id and the key must be different 16-byte values.")

tracks = {
    "720p": (1, True),
    "1080p": (2, True),
    "audio": (3, False),
}
for folder, (salt, is_video) in tracks.items():
    init_path = require_init(out / folder)
    original = encrypt_init(init_path, kid)
    length_size = None
    if is_video:
        clear_init = require_init(clear / folder).read_bytes()
        stsd = require_box(clear_init, b"stsd")
        entry_at = stsd + 16
        entry = clear_init[entry_at : entry_at + box_size(clear_init, entry_at)]
        length_size = nal_length_size(entry)
    if is_video and original != b"avc1":
        fail(f"{folder} was not AVC.")
    segments = sorted((out / folder).glob("seg_*.m4s"), key=lambda path: int(path.stem.split("_")[1]))
    if len(segments) != 10:
        fail(f"{folder} does not have 10 segments.")
    for index, segment in enumerate(segments):
        before = (clear / folder / segment.name).read_bytes()
        encrypt_segment(segment, key, kid, index, salt, length_size)
        if segment.read_bytes() == before:
            fail(f"{folder}/{segment.name} was not encrypted.")

subtitle = out / "subtitles" / "playpath-bars.vtt"
if subtitle.read_bytes() != (clear / "subtitles" / "playpath-bars.vtt").read_bytes():
    fail("Encryption changed the caption file.")

write_menus(kid)

for menu in (
    out / "master.m3u8",
    out / "720p" / "media.m3u8",
    out / "1080p" / "media.m3u8",
    out / "audio" / "media.m3u8",
    out / "manifest.mpd",
):
    text = menu.read_text()
    if kid.hex() not in text and kid_uuid(kid) not in text:
        fail(f"{menu.name} does not name the key id.")
    if key.hex() in text:
        fail(f"{menu.name} contains the content key.")

if key.hex() in (out / "subtitles" / "media.m3u8").read_text():
    fail("The subtitle playlist contains the content key.")
if "EXT-X-KEY" in (out / "subtitles" / "media.m3u8").read_text():
    fail("The subtitle playlist names a key.")

for folder in tracks:
    if b"tenc" in require_init(clear / folder).read_bytes():
        fail("Encryption changed the clear init segment.")

player_check(require_init(out / "720p"), next((out / "720p").glob("seg_0.m4s")), key, "video", "0:v:0")
player_check(require_init(out / "audio"), next((out / "audio").glob("seg_0.m4s")), key, "audio", "0:a:0")

print(f"Key id: {kid.hex()}")
print("Key system: org.w3.clearkey")
PY
then
  rm -rf "${work}"
  exit 1
fi
shopt -s nullglob
playlists=("${master_dir}"/*.m3u8 "${master_dir}"/*.mpd "${master_dir}"/*.m4s "${master_dir}"/*.ts)
if ((${#playlists[@]} > 0)); then
  rm -rf "${work}"
  echo "Encryption wrote a playlist or a segment into the master directory." >&2
  printf '%s\n' "${playlists[@]}" >&2
  exit 1
fi

if ! "${root}/pipeline/timelines.sh"; then
  rm -rf "${work}"
  exit 1
fi

rm -rf "${out}"
mv "${work}" "${out}"

echo "Title id: ${title}"
