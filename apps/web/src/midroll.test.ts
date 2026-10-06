import { describe, expect, it } from "vitest";
import { readMidroll } from "./midroll";

const document = `<?xml version="1.0" encoding="UTF-8"?>
<VAST version="4.2">
  <Ad id="midroll">
    <InLine>
      <Extensions>
        <Extension>
          <Cue breakId="midroll" timeOffset="00:00:10.000"/>
        </Extension>
      </Extensions>
      <Creatives>
        <Creative>
          <Linear>
            <MediaFiles>
              <MediaFile delivery="progressive" type="video/mp4"><![CDATA[http://127.0.0.1:8083/preroll/creative.mp4]]></MediaFile>
            </MediaFiles>
          </Linear>
        </Creative>
      </Creatives>
    </InLine>
  </Ad>
</VAST>`;

describe("mid-roll document", () => {
  it("reads the cue and the creative", () => {
    expect(readMidroll(document)).toEqual({
      cueMs: 10_000,
      mediaUrl: "http://127.0.0.1:8083/preroll/creative.mp4",
    });
  });

  it("ignores a document with no creative", () => {
    expect(readMidroll(`<Cue timeOffset="00:00:10.000"/>`)).toBeUndefined();
  });
});
