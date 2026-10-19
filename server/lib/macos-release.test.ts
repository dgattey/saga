import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { FALLBACK_MACOS_RELEASE, formatMinimumMacOS, parseAppcastXml } from "./macos-release.ts";

const SAMPLE = `<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <title>Saga</title>
    <item>
      <title>1.4.1</title>
      <sparkle:version>22346</sparkle:version>
      <sparkle:shortVersionString>1.4.1</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <enclosure url="https://github.com/dgattey/saga/releases/download/v1.4.1/Saga-1.4.1.zip" length="5674479" type="application/octet-stream"/>
    </item>
  </channel>
</rss>`;

describe("parseAppcastXml", () => {
  it("parses version, build, and absolute GitHub release download URL", () => {
    const release = parseAppcastXml(SAMPLE);
    assert.ok(release);
    assert.equal(release.version, "1.4.1");
    assert.equal(release.build, "22346");
    assert.equal(release.minimumSystemVersion, "26.0");
    assert.equal(release.zipPath, "/dgattey/saga/releases/download/v1.4.1/Saga-1.4.1.zip");
    assert.equal(
      release.downloadUrl,
      "https://github.com/dgattey/saga/releases/download/v1.4.1/Saga-1.4.1.zip",
    );
  });

  it("returns null for invalid xml", () => {
    assert.equal(parseAppcastXml("<rss></rss>"), null);
  });

  it("provides a valid v1.6.0 fallback release", () => {
    assert.equal(FALLBACK_MACOS_RELEASE.version, "1.6.0");
    assert.equal(FALLBACK_MACOS_RELEASE.downloadReady, true);
  });
});

describe("formatMinimumMacOS", () => {
  it("drops trailing zero components", () => {
    assert.equal(formatMinimumMacOS("26.0"), "macOS 26+");
    assert.equal(formatMinimumMacOS("26.1"), "macOS 26.1+");
  });
});
