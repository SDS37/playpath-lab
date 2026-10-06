const labKeyFormat = "urn:uuid:e2719d58-a985-b3c9-781a-b030af78d30e";

// Shaka's HLS parser recognizes this key format and reads init data from a data URI.
// keySystemsMapping then selects org.w3.clearkey, so the license request stays on the lab server.
const recognizedKeyFormat = "urn:uuid:edef8ba9-79d6-4ace-a3c8-27dcd51d21ed";

// The Clear Key CDM accepts this common system id inside a cenc pssh. The lab
// playlist id is a DASH scheme id, and the CDM rejects that box.
const clearKeySystemId = "1077efecc0b24d02ace33c1e52e2fb4b";

export function rewriteClearKeyPlaylist(playlist: string): string {
  const found = playlist.match(/keyId=([0-9a-fA-F]{32})/);
  const keyId = found?.[1];
  if (keyId === undefined || !playlist.includes(labKeyFormat)) {
    return playlist;
  }
  const uri = `data:application/octet-stream;base64,${bytesToBase64(clearKeyPssh(keyId))}`;
  return playlist
    .split("\n")
    .map((line) => {
      if (!line.includes(labKeyFormat)) {
        return line;
      }
      return line
        .replace(labKeyFormat, recognizedKeyFormat)
        .replace(/URI="[^"]*"/, `URI="${uri}"`);
    })
    .join("\n");
}

function clearKeyPssh(keyIdHex: string): Uint8Array {
  const box = new Uint8Array(52);
  const view = new DataView(box.buffer);
  view.setUint32(0, 52);
  box.set([0x70, 0x73, 0x73, 0x68], 4);
  view.setUint32(8, 0x01000000);
  box.set(hexToBytes(clearKeySystemId), 12);
  view.setUint32(28, 1);
  box.set(hexToBytes(keyIdHex), 32);
  view.setUint32(48, 0);
  return box;
}

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i += 1) {
    const pair = hex.slice(i * 2, i * 2 + 2);
    bytes[i] = Number.parseInt(pair, 16);
  }
  return bytes;
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}
