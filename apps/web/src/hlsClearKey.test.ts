import { describe, expect, it } from "vitest";
import { rewriteClearKeyPlaylist } from "./hlsClearKey";

const playlist = `#EXTM3U
#EXT-X-KEY:METHOD=SAMPLE-AES-CTR,URI="http://127.0.0.1:8082/?keyId=00112233445566778899aabbccddeeff",KEYFORMAT="urn:uuid:e2719d58-a985-b3c9-781a-b030af78d30e",KEYFORMATVERSIONS="1"
#EXT-X-MAP:URI="init_0.mp4"
seg_0.m4s
`;

describe("rewriteClearKeyPlaylist", () => {
  it("keeps the published key id and does not add the content key", () => {
    const rewritten = rewriteClearKeyPlaylist(playlist);
    expect(rewritten).not.toContain(
      "urn:uuid:e2719d58-a985-b3c9-781a-b030af78d30e",
    );
    expect(rewritten).toContain(
      "urn:uuid:edef8ba9-79d6-4ace-a3c8-27dcd51d21ed",
    );
    expect(rewritten).toContain('URI="init_0.mp4"');
    expect(rewritten).not.toContain("ffefcdab");
    const uri = rewritten.match(
      /data:application\/octet-stream;base64,([^"]+)/,
    );
    expect(uri?.[1]).toBeDefined();
    const pssh = atob(uri?.[1] ?? "");
    expect(pssh).toContain("pssh");
    expect(pssh).toContain(
      String.fromCharCode(
        0x10,
        0x77,
        0xef,
        0xec,
        0xc0,
        0xb2,
        0x4d,
        0x02,
        0xac,
        0xe3,
        0x3c,
        0x1e,
        0x52,
        0xe2,
        0xfb,
        0x4b,
      ),
    );
    const keyId = String.fromCharCode(
      0x00,
      0x11,
      0x22,
      0x33,
      0x44,
      0x55,
      0x66,
      0x77,
      0x88,
      0x99,
      0xaa,
      0xbb,
      0xcc,
      0xdd,
      0xee,
      0xff,
    );
    expect(pssh).toContain(keyId);
  });

  it("leaves a playlist without the lab key format unchanged", () => {
    const clear = "#EXTM3U\nseg_0.m4s\n";
    expect(rewriteClearKeyPlaylist(clear)).toBe(clear);
  });
});
