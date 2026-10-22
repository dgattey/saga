import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { FALLBACK_MACOS_RELEASE, parseAppcastXml } from "./macos-release.ts";

const SAMPLE = `<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <title>Saga</title>
    <item>
      <title>1.9.2</title>
      <sparkle:version>22672</sparkle:version>
      <sparkle:shortVersionString>1.9.2</sparkle:shortVersionString>
      <enclosure url="https://github.com/dgattey/saga/releases/download/v1.9.2/Saga-1.9.2.zip" length="5750698" type="application/octet-stream"/>
    </item>
  </channel>
</rss>`;

describe("parseAppcastXml", () => {
  it("parses version, build, and absolute GitHub release download URL", () => {
    const release = parseAppcastXml(SAMPLE);
    assert.ok(release);
    assert.equal(release.version, "1.9.2");
    assert.equal(release.build, "22672");
    assert.equal(release.zipPath, "/dgattey/saga/releases/download/v1.9.2/Saga-1.9.2.zip");
    assert.equal(
      release.downloadUrl,
      "https://github.com/dgattey/saga/releases/download/v1.9.2/Saga-1.9.2.zip",
    );
  });

  it("returns null for invalid xml", () => {
    assert.equal(parseAppcastXml("<rss></rss>"), null);
  });

  it("provides a valid v1.9.2 fallback release", () => {
    assert.equal(FALLBACK_MACOS_RELEASE.version, "1.9.2");
    assert.equal(FALLBACK_MACOS_RELEASE.downloadReady, true);
  });
});
