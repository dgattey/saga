import assert from "node:assert/strict";
import test from "node:test";

import handler, {
  buildCmaBookFields,
  buildGoodreadsRssUrl,
  buildRichTextDocument,
  computeBookDiff,
  extractPlainTextFromRichText,
  findMatchingContentfulEntry,
  mergeShelfBooks,
  normalizeContentfulBookEntry,
  parseGoodreadsRssXml,
  parseIsbn13Number,
  resolveBestCoverUrl,
  resolveIsbnFromOpenLibrary,
  resolveReadDates,
  runGoodreadsSync,
  upgradeGoodreadsCoverUrl,
} from "./goodreads-sync.mjs";

const SAMPLE_READ_RSS = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
  <channel>
    <title>Dylan's bookshelf: read</title>
    <item>
      <guid>https://www.goodreads.com/review/show/1001</guid>
      <pubDate>Wed, 15 Jan 2025 06:00:00 -0800</pubDate>
      <title><![CDATA[Three Cups of Tea: One Man's Mission to Promote Peace ... One School at a Time]]></title>
      <book_id>4929</book_id>
      <book_large_image_url><![CDATA[https://i.gr-assets.com/images/S/compressed.photo.goodreads.com/books/1348499866l/4929._SX318_.jpg]]></book_large_image_url>
      <author_name>Greg Mortenson</author_name>
      <isbn>0143038257</isbn>
      <user_rating>4</user_rating>
      <user_read_at><![CDATA[Wed, 15 Jan 2019 06:00:00 +0000]]></user_read_at>
      <user_date_added><![CDATA[Tue, 01 Jan 2019 06:00:00 +0000]]></user_date_added>
      <user_date_created><![CDATA[Tue, 01 Jan 2019 06:00:00 +0000]]></user_date_created>
      <user_shelves>read</user_shelves>
      <user_review><![CDATA[An inspiring story.<br/><br/>Highly recommended &amp; memorable.]]></user_review>
      <book description=""><![CDATA[<p>desc</p>]]></book>
      <num_pages>349</num_pages>
      <book_published>2006</book_published>
    </item>
  </channel>
</rss>`;

const SAMPLE_CURRENTLY_READING_RSS = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <item>
      <title><![CDATA[Urban Jungle: The History and Future of Nature in the City]]></title>
      <book_id>62919402</book_id>
      <book_large_image_url><![CDATA[https://s.gr-assets.com/assets/nophoto/book/111x148-bcc042a9c91a29c1d680899eff700a03.png]]></book_large_image_url>
      <author_name>Ben Wilson</author_name>
      <isbn>9780385545938</isbn>
      <user_rating>0</user_rating>
      <user_read_at></user_read_at>
      <user_date_added><![CDATA[Fri, 23 Jan 2026 06:00:00 +0000]]></user_date_added>
      <user_date_created><![CDATA[Fri, 23 Jan 2026 06:00:00 +0000]]></user_date_created>
      <user_shelves>currently-reading</user_shelves>
      <user_review></user_review>
      <num_pages>384</num_pages>
      <book_published>2023</book_published>
    </item>
  </channel>
</rss>`;

test("parseIsbn13Number converts ISBN-10 and ISBN-13 accurately", () => {
  assert.equal(parseIsbn13Number("0143038257"), 9780143038252);
  assert.equal(parseIsbn13Number('="9780316010665"'), 9780316010665);
  assert.equal(parseIsbn13Number("978-0-385-54593-8"), 9780385545938);
  assert.equal(parseIsbn13Number(""), null);
  assert.equal(parseIsbn13Number("invalid"), null);
});

test("parseGoodreadsRssXml parses read and currently-reading shelves", () => {
  const readItems = parseGoodreadsRssXml(SAMPLE_READ_RSS, "read");
  assert.equal(readItems.length, 1);
  const book = readItems[0];
  assert.equal(
    book.title,
    "Three Cups of Tea: One Man's Mission to Promote Peace ... One School at a Time",
  );
  assert.equal(book.author, "Greg Mortenson");
  assert.equal(book.isbn, 9780143038252);
  assert.equal(book.rating, 4);
  assert.equal(book.status, "read");
  assert.equal(book.readDateStarted, "2019-01-01T06:00:00Z");
  assert.equal(book.readDateFinished, "2019-01-15T06:00:00Z");
  assert.equal(book.reviewText, "An inspiring story.\n\nHighly recommended & memorable.");
  assert.equal(
    book.goodreadsCoverUrl,
    "https://i.gr-assets.com/images/S/compressed.photo.goodreads.com/books/1348499866l/4929.jpg",
  );

  const readingItems = parseGoodreadsRssXml(SAMPLE_CURRENTLY_READING_RSS, "currently-reading");
  assert.equal(readingItems.length, 1);
  const readingBook = readingItems[0];
  assert.equal(readingBook.status, "reading");
  assert.equal(readingBook.rating, null);
  assert.equal(readingBook.readDateStarted, "2026-01-23T06:00:00Z");
  assert.equal(readingBook.readDateFinished, null);
  assert.equal(readingBook.goodreadsCoverUrl, null); // nophoto filtered out
});

test("buildRichTextDocument and extractPlainTextFromRichText round-trip cleanly", () => {
  const doc = buildRichTextDocument("First paragraph<br/><br/>Second &amp; final paragraph");
  assert.deepEqual(doc, {
    nodeType: "document",
    data: {},
    content: [
      {
        nodeType: "paragraph",
        data: {},
        content: [{ nodeType: "text", value: "First paragraph", marks: [], data: {} }],
      },
      {
        nodeType: "paragraph",
        data: {},
        content: [{ nodeType: "text", value: "Second & final paragraph", marks: [], data: {} }],
      },
    ],
  });
  assert.equal(
    extractPlainTextFromRichText(doc),
    "First paragraph\n\nSecond & final paragraph",
  );
});

test("mergeShelfBooks deduplicates and prioritizes read over currently-reading", () => {
  const readingItem = parseGoodreadsRssXml(SAMPLE_CURRENTLY_READING_RSS, "currently-reading")[0];
  const finishedItem = {
    ...readingItem,
    shelf: "read",
    status: "read",
    rating: 5,
    readDateFinished: "2026-02-10T06:00:00Z",
  };

  const merged = mergeShelfBooks([readingItem, finishedItem]);
  assert.equal(merged.length, 1);
  assert.equal(merged[0].status, "read");
  assert.equal(merged[0].rating, 5);
  assert.equal(merged[0].readDateFinished, "2026-02-10T06:00:00Z");
});

test("computeBookDiff skips unchanged books and detects status/rating/review transitions", () => {
  const existingCmaEntry = normalizeContentfulBookEntry({
    sys: { id: "BOOK-1", version: 2, publishedVersion: 1 },
    fields: {
      title: {
        "en-US":
          "Three Cups of Tea: One Man's Mission to Promote Peace ... One School at a Time",
      },
      author: { "en-US": "Greg Mortenson" },
      isbn: { "en-US": 9780143038252 },
      rating: { "en-US": 4 },
      readDateStarted: { "en-US": "2019-01-01T06:00:00Z" },
      readDateFinished: { "en-US": "2019-01-15T06:00:00Z" },
      coverImage: {
        "en-US": { sys: { type: "Link", linkType: "Asset", id: "ASSET-1" } },
      },
      reviewDescription: {
        "en-US": buildRichTextDocument(
          "An inspiring story.<br/><br/>Highly recommended &amp; memorable.",
        ),
      },
    },
  });

  const rssBook = parseGoodreadsRssXml(SAMPLE_READ_RSS, "read")[0];
  const matched = findMatchingContentfulEntry(rssBook, [existingCmaEntry]);
  assert.equal(matched?.id, "BOOK-1");

  const unchangedDiff = computeBookDiff(rssBook, matched);
  assert.equal(unchangedDiff.action, "skip");
  assert.deepEqual(unchangedDiff.changedFields, []);

  // Transition from currently-reading to read with a new rating
  const currentlyReadingEntry = normalizeContentfulBookEntry({
    sys: { id: "BOOK-2", version: 4, publishedVersion: 3 },
    fields: {
      title: { "en-US": "Urban Jungle: The History and Future of Nature in the City" },
      author: { "en-US": "Ben Wilson" },
      isbn: { "en-US": 9780385545938 },
      readDateStarted: { "en-US": "2026-01-23T06:00:00Z" },
      coverImage: {
        "en-US": { sys: { type: "Link", linkType: "Asset", id: "ASSET-2" } },
      },
    },
  });

  const finishedUrbanJungle = {
    ...parseGoodreadsRssXml(SAMPLE_CURRENTLY_READING_RSS, "currently-reading")[0],
    status: "read",
    rating: 5,
    readDateFinished: "2026-03-01T06:00:00Z",
    reviewText: "Fantastic urban history.",
    reviewDescription: buildRichTextDocument("Fantastic urban history."),
  };

  const transitionDiff = computeBookDiff(finishedUrbanJungle, currentlyReadingEntry);
  assert.equal(transitionDiff.action, "update");
  assert.deepEqual(transitionDiff.changedFields, [
    "rating",
    "reviewDescription",
    "readDateFinished",
  ]);

  const cmaFields = buildCmaBookFields(transitionDiff.merged);
  assert.equal(cmaFields.rating["en-US"], 5);
  assert.equal(cmaFields.readDateStarted["en-US"], "2026-01-23T06:00:00Z");
  assert.equal(cmaFields.readDateFinished["en-US"], "2026-03-01T06:00:00Z");
  assert.equal(cmaFields.coverImage["en-US"].sys.id, "ASSET-2");
});

test("runGoodreadsSync dry-run orchestrates RSS polling and Contentful diffing", async () => {
  const mockFetch = async (url) => {
    const urlStr = String(url);
    if (urlStr.includes("shelf=read")) {
      return new Response(SAMPLE_READ_RSS, { status: 200 });
    }
    if (urlStr.includes("shelf=currently-reading")) {
      return new Response(SAMPLE_CURRENTLY_READING_RSS, { status: 200 });
    }
    if (urlStr.includes("shelf=to-read")) {
      return new Response("<rss><channel></channel></rss>", { status: 200 });
    }
    if (urlStr.includes("api.contentful.com")) {
      return new Response(
        JSON.stringify({
          total: 1,
          items: [
            {
              sys: { id: "EXISTING-1", version: 2, publishedVersion: 1 },
              fields: {
                title: {
                  "en-US":
                    "Three Cups of Tea: One Man's Mission to Promote Peace ... One School at a Time",
                },
                author: { "en-US": "Greg Mortenson" },
                isbn: { "en-US": 9780143038252 },
                rating: { "en-US": 4 },
                readDateStarted: { "en-US": "2019-01-01T06:00:00Z" },
                readDateFinished: { "en-US": "2019-01-15T06:00:00Z" },
                coverImage: {
                  "en-US": { sys: { type: "Link", linkType: "Asset", id: "ASSET-1" } },
                },
                reviewDescription: {
                  "en-US": buildRichTextDocument(
                    "An inspiring story.<br/><br/>Highly recommended &amp; memorable.",
                  ),
                },
              },
            },
          ],
        }),
        { status: 200 },
      );
    }
    return new Response("{}", { status: 404 });
  };

  const result = await runGoodreadsSync({
    goodreadsUserId: "12345",
    goodreadsRssKey: "secret-rss-key",
    contentfulSpaceId: "space-1",
    contentfulManagementToken: "cma-token-1",
    dryRun: true,
    fetchImpl: mockFetch,
  });

  assert.equal(result.ok, true);
  assert.equal(result.skippedCount, 1);
  assert.equal(result.createdCount, 1);
  assert.equal(
    result.created[0].title,
    "Urban Jungle: The History and Future of Nature in the City",
  );
});

test("handler enforces Bearer CRON_SECRET authentication", async () => {
  const prevSecret = process.env.CRON_SECRET;
  process.env.CRON_SECRET = "super-secret-token";

  try {
    let statusCode = 200;
    let payload = null;
    const mockRes = {
      status(code) {
        statusCode = code;
        return this;
      },
      json(body) {
        payload = body;
        return this;
      },
    };

    await handler({ method: "POST", headers: {} }, mockRes);
    assert.equal(statusCode, 401);
    assert.equal(payload.ok, false);

    await handler(
      { method: "PUT", headers: { authorization: "Bearer super-secret-token" } },
      mockRes,
    );
    assert.equal(statusCode, 405);
  } finally {
    if (prevSecret === undefined) {
      delete process.env.CRON_SECRET;
    } else {
      process.env.CRON_SECRET = prevSecret;
    }
  }
});

test("resolveBestCoverUrl falls back to Goodreads large image URL when OpenLibrary/Bookcover 404", async () => {
  const mockFetch = async () => new Response("Not Found", { status: 404 });
  const url = await resolveBestCoverUrl(
    {
      isbn: 9780143038252,
      title: "Three Cups of Tea",
      author: "Greg Mortenson",
      goodreadsCoverUrl:
        "https://i.gr-assets.com/images/S/compressed.photo.goodreads.com/books/1348499866l/4929._SY475_.jpg",
    },
    mockFetch,
  );
  assert.equal(
    url,
    "https://i.gr-assets.com/images/S/compressed.photo.goodreads.com/books/1348499866l/4929.jpg",
  );
  assert.equal(
    upgradeGoodreadsCoverUrl(
      "https://s.gr-assets.com/assets/nophoto/book/111x148-bcc042a9c91a29c1d680899eff700a03.png",
    ),
    null,
  );
  assert.equal(
    buildGoodreadsRssUrl({ userId: "999", rssKey: "abc", shelf: "read" }),
    "https://www.goodreads.com/review/list_rss/999?shelf=read&per_page=200&key=abc",
  );
});

test("resolveReadDates matches GoodreadsCSVParser when finished < started", () => {
  // When userReadAt (Date Read) is explicitly set and earlier than userDateAdded (Date Added),
  // GoodreadsCSVParser clears readDateStarted = null and keeps readDateFinished.
  const withReadAt = resolveReadDates({
    shelf: "read",
    userShelves: "read",
    userReadAt: "2012/01/13",
    userDateAdded: "2019/01/15",
  });
  assert.equal(withReadAt.status, "read");
  assert.equal(withReadAt.readDateStarted, null);
  assert.equal(withReadAt.readDateFinished, "2012-01-13T00:00:00Z");

  // When userReadAt is NOT set (so finished came from Date Added) and userDateStarted > userDateAdded,
  // GoodreadsCSVParser clears readDateFinished = null and keeps readDateStarted.
  const withoutReadAt = resolveReadDates({
    shelf: "read",
    userShelves: "read",
    userReadAt: null,
    userDateStarted: "2020/05/01",
    userDateAdded: "2019/01/15",
  });
  assert.equal(withoutReadAt.status, "reading");
  assert.equal(withoutReadAt.readDateStarted, "2020-05-01T00:00:00Z");
  assert.equal(withoutReadAt.readDateFinished, null);
});

test("resolveIsbnFromOpenLibrary prioritizes English + author/title match and falls back to work editions", async () => {
  const mockFetch = async (url) => {
    const urlStr = String(url);
    if (urlStr.includes("/search.json")) {
      return new Response(
        JSON.stringify({
          docs: [
            {
              key: "/works/OL1W",
              title: "Other Book",
              author_name: ["Someone Else"],
              language: ["fre"],
              editions: {
                docs: [{ title: "Other Book", isbn: ["9781111111116"] }],
              },
            },
            {
              key: "/works/OL2W",
              title: "Fahrenheit 451",
              author_name: ["Ray Bradbury"],
              language: ["eng"],
              editions: {
                docs: [],
              },
            },
          ],
        }),
        { status: 200 },
      );
    }
    if (urlStr.includes("/works/OL2W/editions.json")) {
      return new Response(
        JSON.stringify({
          entries: [
            {
              languages: [{ key: "/languages/eng" }],
              isbn_13: ["9780007491568"],
            },
          ],
        }),
        { status: 200 },
      );
    }
    return new Response("Not Found", { status: 404 });
  };

  const isbn = await resolveIsbnFromOpenLibrary("Fahrenheit 451", "Ray Bradbury", mockFetch);
  assert.equal(isbn, 9780007491568);
});
