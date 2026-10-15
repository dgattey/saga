/**
 * Vercel Serverless Function: `/api/cron/goodreads-sync`
 *
 * Automatically polls Goodreads per-shelf RSS feeds (`read`, `currently-reading`, `to-read`),
 * diffs them against existing Contentful `book` entries, resolves/uploads missing cover assets,
 * and upserts + publishes only new or changed books via the Contentful Management API (CMA).
 *
 * Triggered:
 * 1. Automatically every day at 09:00 UTC via Vercel Cron (`vercel.json`).
 * 2. On demand when `Saga.app` launches or when the user triggers a manual refresh (`SyncViewModel`).
 *
 * Required Environment Variables:
 * - `GOODREADS_USER_ID`: Goodreads numeric user ID
 * - `GOODREADS_RSS_KEY`: Goodreads RSS feed key (optional if user's shelves are public)
 * - `CONTENTFUL_SPACE_ID`: Contentful Space ID
 * - `CONTENTFUL_MANAGEMENT_TOKEN` (or `CONTENTFUL_MANAGEMENT_ACCESS_TOKEN`): Contentful CMA personal access token
 * - `CONTENTFUL_ENVIRONMENT_ID`: Contentful Environment ID (defaults to `master`)
 * - `CRON_SECRET` (or `GOODREADS_SYNC_SECRET`): Bearer secret for authenticating incoming requests
 */

import crypto from "node:crypto";

// ---------------------------------------------------------------------------
// Constants & Configuration
// ---------------------------------------------------------------------------

export const DEFAULT_SHELVES = ["currently-reading", "read"];
export const DEFAULT_LOCALE = "en-US";
export const DEFAULT_ENVIRONMENT_ID = "master";
export const CONTENTFUL_CMA_BASE_URL = "https://api.contentful.com";
export const CONTENTFUL_UPLOAD_BASE_URL = "https://upload.contentful.com";
export const BOOKCOVER_API_BASE_URL = "https://bookcover.longitood.com/bookcover";
export const OPENLIBRARY_API_BASE_URL = "https://openlibrary.org";
export const OPENLIBRARY_COVERS_BASE_URL = "https://covers.openlibrary.org";

const MIN_COVER_BYTES = 10_000;
const OPENLIBRARY_PREFER_BOOKCOVER_BELOW_BYTES = 80_000;
const BOOKCOVER_PREFERRED_MIN_BYTES = 30_000;
const BOOKCOVER_PREFERRED_RATIO = 0.85;
const OPENLIBRARY_PREFERRED_COVER_BYTES = 40_000;
const MAX_OPENLIBRARY_SEARCH_CANDIDATES = 4;
const MAX_CONCURRENT_PARSES = 10;

// ---------------------------------------------------------------------------
// String, HTML, ISBN & RichText Helpers (matching Saga Swift logic)
// ---------------------------------------------------------------------------

const NAMED_HTML_ENTITIES = {
  amp: "&",
  lt: "<",
  gt: ">",
  quot: '"',
  apos: "'",
  nbsp: " ",
  rsquo: "\u2019",
  lsquo: "\u2018",
  rdquo: "\u201D",
  ldquo: "\u201C",
  mdash: "\u2014",
  ndash: "\u2013",
  hellip: "\u2026",
};

/**
 * Decodes XML/HTML character entities (`&amp;`, `&#39;`, `&#x2019;`, etc.).
 */
export function decodeXmlEntities(input) {
  if (!input) return "";
  return String(input).replace(/&(#x?[0-9a-fA-F]+|[a-zA-Z]+);/g, (full, entity) => {
    if (entity.startsWith("#x") || entity.startsWith("#X")) {
      const codePoint = Number.parseInt(entity.slice(2), 16);
      return Number.isFinite(codePoint) ? String.fromCodePoint(codePoint) : full;
    }
    if (entity.startsWith("#")) {
      const codePoint = Number.parseInt(entity.slice(1), 10);
      return Number.isFinite(codePoint) ? String.fromCodePoint(codePoint) : full;
    }
    const lower = entity.toLowerCase();
    return Object.prototype.hasOwnProperty.call(NAMED_HTML_ENTITIES, lower)
      ? NAMED_HTML_ENTITIES[lower]
      : full;
  });
}

/**
 * Matches `String.cleanedWhitespace` in `Saga/Saga/Shared/Extensions/String.swift`:
 * collapses all whitespace runs to single spaces and trims leading/trailing whitespace.
 */
export function cleanWhitespace(input) {
  if (!input) return "";
  return String(input).replace(/\s+/g, " ").trim();
}

export function normalizeAuthor(author) {
  return cleanWhitespace(author).toLowerCase();
}

export function normalizeTitle(title) {
  return cleanWhitespace(title).toLowerCase();
}

/**
 * Matches `GoodreadsCSVParser.isDuplicateTitle(_:_:)`:
 * case-insensitive substring containment in either direction.
 */
export function isDuplicateTitle(titleA, titleB) {
  const a = normalizeTitle(titleA);
  const b = normalizeTitle(titleB);
  if (!a || !b) return false;
  return a.includes(b) || b.includes(a);
}

/**
 * Computes ISBN-13 check digit for a 12-digit prefix (matching `GoodreadsCSVParser.isbn13CheckDigit`).
 */
export function isbn13CheckDigit(twelveDigits) {
  if (typeof twelveDigits !== "string" || !/^\d{12}$/.test(twelveDigits)) {
    return null;
  }
  let sum = 0;
  for (let i = 0; i < 12; i += 1) {
    const digit = Number.parseInt(twelveDigits[i], 10);
    sum += i % 2 === 0 ? digit : digit * 3;
  }
  const check = (10 - (sum % 10)) % 10;
  return String(check);
}

/**
 * Converts a raw ISBN-10 or ISBN-13 string into a numeric 13-digit ISBN integer,
 * matching `GoodreadsCSVParser.isbn13(from:)` and `isbnNumber(from:)`.
 */
export function parseIsbn13Number(raw) {
  if (raw === null || raw === undefined) return null;
  const normalized = String(raw)
    .replace(/="/g, "")
    .replace(/"/g, "")
    .replace(/-/g, "")
    .replace(/\s+/g, "")
    .toUpperCase();

  if (!normalized) return null;

  if (/^\d{13}$/.test(normalized)) {
    const num = Number.parseInt(normalized, 10);
    return Number.isSafeInteger(num) && num > 0 ? num : null;
  }

  if (normalized.length === 10 && /^\d{9}[\dX]$/.test(normalized)) {
    const prefix = normalized.slice(0, 9);
    const base = `978${prefix}`;
    const check = isbn13CheckDigit(base);
    if (!check) return null;
    const num = Number.parseInt(`${base}${check}`, 10);
    return Number.isSafeInteger(num) && num > 0 ? num : null;
  }

  return null;
}

/**
 * Cleans HTML markup from Goodreads `<user_review>` into plain text with newline-separated
 * paragraphs, then builds a Contentful RichTextDocument matching `RichTextDocument(fromPlainText:)`
 * in `Saga/Saga/Shared/Models/RichTextDocumentTransformer.swift`:
 *
 * - Replaces `<br>`, `<br/>`, and `\r\n` with `\n`
 * - Splits by `.newlines` and filters out empty lines (`!line.isEmpty`)
 * - Preserves each non-empty line verbatim inside a `paragraph` -> `text` node with `marks: []`
 */
export function normalizeReviewText(rawReview) {
  if (!rawReview) return "";
  const withLineBreaks = String(rawReview)
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .replace(/<br\s*\/?>/gi, "\n");

  const decoded = decodeXmlEntities(withLineBreaks);

  const paragraphs = decoded
    .split("\n")
    .filter((line) => line.length > 0);

  return paragraphs.join("\n\n");
}

/**
 * Converts a review string into a Contentful `RichTextDocument` JSON structure matching
 * `RichTextDocument(fromPlainText:)` in `RichTextDocumentTransformer.swift`.
 */
export function buildRichTextDocument(rawReview) {
  if (!rawReview) return null;
  const withLineBreaks = String(rawReview)
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .replace(/<br\s*\/?>/gi, "\n");

  const decoded = decodeXmlEntities(withLineBreaks);
  const paragraphs = decoded
    .split("\n")
    .filter((line) => line.length > 0);

  if (paragraphs.length === 0) return null;

  return {
    nodeType: "document",
    data: {},
    content: paragraphs.map((line) => ({
      nodeType: "paragraph",
      data: {},
      content: [
        {
          nodeType: "text",
          value: line,
          marks: [],
          data: {},
        },
      ],
    })),
  };
}

/**
 * Extracts plain text from an existing Contentful `RichTextDocument` JSON object,
 * matching `RichTextDocument.plainText` in `RichTextRenderer.swift`.
 */
export function extractPlainTextFromRichText(doc) {
  if (!doc || typeof doc !== "object" || !Array.isArray(doc.content)) {
    return "";
  }

  const parts = [];
  const walkNode = (node) => {
    if (!node || typeof node !== "object") return "";
    if (node.nodeType === "text" && typeof node.value === "string") {
      return node.value;
    }
    if (Array.isArray(node.content)) {
      return node.content.map(walkNode).join("");
    }
    return "";
  };

  for (const node of doc.content) {
    const text = walkNode(node).trim();
    if (text) {
      parts.push(text);
    }
  }
  return parts.join("\n\n");
}

/**
 * Parses a Goodreads RSS date string (RFC 822 / RFC 2822, ISO 8601, or `YYYY/MM/DD`)
 * into a canonical ISO-8601 UTC timestamp string (`YYYY-MM-DDTHH:mm:ssZ`).
 */
export function parseGoodreadsDate(raw) {
  if (!raw) return null;
  const trimmed = String(raw).trim();
  if (!trimmed) return null;

  // Handle YYYY/MM/DD format from Goodreads exports
  const slashMatch = trimmed.match(/^(\d{4})\/(\d{2})\/(\d{2})$/);
  if (slashMatch) {
    const [, year, month, day] = slashMatch;
    return `${year}-${month}-${day}T00:00:00Z`;
  }

  const timestamp = Date.parse(trimmed);
  if (Number.isNaN(timestamp)) return null;
  return new Date(timestamp).toISOString().replace(/\.\d{3}Z$/, "Z");
}

/**
 * Compares two date strings by calendar day (YYYY-MM-DD in UTC) or exact timestamp
 * so minor timezone/formatting differences don't cause unnecessary CMA churn.
 */
export function datesMatch(dateA, dateB) {
  if (!dateA && !dateB) return true;
  if (!dateA || !dateB) return false;
  const tsA = Date.parse(dateA);
  const tsB = Date.parse(dateB);
  if (Number.isNaN(tsA) || Number.isNaN(tsB)) {
    return String(dateA) === String(dateB);
  }
  // Treat same UTC calendar day as matching since Goodreads only tracks day-level read dates
  const dayA = new Date(tsA).toISOString().slice(0, 10);
  const dayB = new Date(tsB).toISOString().slice(0, 10);
  return dayA === dayB;
}

// ---------------------------------------------------------------------------
// Goodreads RSS XML Parser
// ---------------------------------------------------------------------------

/**
 * Extracts the text content of a single XML tag from an `<item>` block,
 * unwrapping `<![CDATA[...]]>` if present and decoding XML entities.
 */
export function extractXmlTag(itemXml, tagName) {
  const regex = new RegExp(`<${tagName}(?:\\s[^>]*)?>([\\s\\S]*?)<\\/${tagName}>`, "i");
  const match = itemXml.match(regex);
  if (!match) return null;

  let raw = match[1].trim();
  const cdataMatch = raw.match(/^<!\[CDATA\[([\s\S]*?)\]\]>$/);
  if (cdataMatch) {
    raw = cdataMatch[1];
  } else {
    raw = decodeXmlEntities(raw);
  }
  const trimmed = raw.trim();
  return trimmed.length > 0 ? trimmed : null;
}

/**
 * Detects Goodreads placeholder "nophoto" URLs so we don't upload blank placeholder covers.
 */
export function isUsableGoodreadsCoverUrl(url) {
  if (!url || typeof url !== "string") return false;
  const trimmed = url.trim();
  if (!trimmed.startsWith("http://") && !trimmed.startsWith("https://")) {
    return false;
  }
  if (/nophoto/i.test(trimmed)) {
    return false;
  }
  return true;
}

/**
 * Upgrades Goodreads thumbnail/medium cover URLs (e.g. `._SX98_.jpg`, `._SY75_.jpg`)
 * to full-resolution cover URLs when possible.
 */
export function upgradeGoodreadsCoverUrl(url) {
  if (!isUsableGoodreadsCoverUrl(url)) return null;
  return url.trim().replace(/\._S[XY]\d+_(?=\.[a-zA-Z]+$)/, "");
}

/**
 * Derives `readDateStarted` and `readDateFinished` from a Goodreads RSS item and shelf,
 * matching `GoodreadsCSVParser.parseRow` and `Book.readingStatus` in Saga:
 *
 * - `to-read` -> `.notStarted`: `readDateStarted = null`, `readDateFinished = null`
 * - `currently-reading` -> `.reading`: `readDateStarted = dateStarted || dateAdded`, `readDateFinished = null`
 * - `read` -> `.read`: `readDateFinished = userReadAt || dateAdded`, `readDateStarted = dateStarted || dateAdded`
 *   If `finished < started`:
 *   - If `userReadAt` (`readDateFinishedFromRead`) was present, `readDateStarted = null`
 *   - Otherwise, `readDateFinished = null`
 */
export function resolveReadDates({
  shelf,
  userShelves,
  userReadAt,
  userDateStarted,
  userDateAdded,
  userDateCreated,
}) {
  const shelvesList = [shelf, ...(userShelves ? userShelves.split(",").map((s) => s.trim()) : [])]
    .filter(Boolean)
    .map((s) => s.toLowerCase());

  const isCurrentlyReading =
    shelf === "currently-reading" || shelvesList.includes("currently-reading");
  const isToRead =
    !isCurrentlyReading &&
    (shelf === "to-read" || (shelvesList.includes("to-read") && !shelvesList.includes("read")));

  const readDateFinishedFromRead = parseGoodreadsDate(userReadAt);
  const readDateFinishedFromAdded =
    parseGoodreadsDate(userDateAdded) || parseGoodreadsDate(userDateCreated);
  const readDateStartedFromStarted = parseGoodreadsDate(userDateStarted);

  if (isToRead && !readDateFinishedFromRead) {
    return {
      status: "notStarted",
      readDateStarted: null,
      readDateFinished: null,
    };
  }

  let readDateStarted = readDateStartedFromStarted || readDateFinishedFromAdded;
  let readDateFinished = null;
  if (readDateFinishedFromRead) {
    readDateFinished = readDateFinishedFromRead;
  } else if (isCurrentlyReading) {
    readDateFinished = null;
  } else {
    readDateFinished = readDateFinishedFromAdded;
  }

  if (readDateFinished && readDateStarted) {
    const finishedTs = Date.parse(readDateFinished);
    const startedTs = Date.parse(readDateStarted);
    if (!Number.isNaN(finishedTs) && !Number.isNaN(startedTs) && finishedTs < startedTs) {
      // Exact parity with GoodreadsCSVParser lines 397-413:
      // If `dateRead` (`user_read_at`) was explicitly set and is earlier than `dateAdded`,
      // clear `readDateStarted = null` (leaving `readDateFinished` intact); otherwise clear `readDateFinished = null`.
      if (readDateFinishedFromRead !== null) {
        readDateStarted = null;
      } else {
        readDateFinished = null;
      }
    }
  }

  const status =
    readDateFinished !== null ? "read" : readDateStarted !== null ? "reading" : "notStarted";

  return {
    status,
    readDateStarted,
    readDateFinished,
  };
}

/**
 * Parses a Goodreads RSS XML feed string into normalized book items.
 */
export function parseGoodreadsRssXml(xml, shelf = "read") {
  if (!xml || typeof xml !== "string") return [];

  const items = [];
  const itemRegex = /<item\b[^>]*>([\s\S]*?)<\/item>/gi;
  let match;

  while ((match = itemRegex.exec(xml)) !== null) {
    const itemXml = match[1];
    const rawTitle = extractXmlTag(itemXml, "title");
    const rawAuthor = extractXmlTag(itemXml, "author_name");
    if (!rawTitle || !rawAuthor) {
      continue;
    }

    const title = cleanWhitespace(rawTitle);
    const author = cleanWhitespace(rawAuthor);
    const bookId = extractXmlTag(itemXml, "book_id");
    const rawIsbn13 = extractXmlTag(itemXml, "isbn13");
    const rawIsbn10 = extractXmlTag(itemXml, "isbn");
    const isbn = parseIsbn13Number(rawIsbn13) ?? parseIsbn13Number(rawIsbn10);

    const rawRating = extractXmlTag(itemXml, "user_rating");
    const parsedRating = rawRating ? Number.parseInt(rawRating, 10) : 0;
    const rating = Number.isInteger(parsedRating) && parsedRating > 0 ? parsedRating : null;

    const userReadAt = extractXmlTag(itemXml, "user_read_at");
    const userDateStarted = extractXmlTag(itemXml, "user_date_started");
    const userDateAdded = extractXmlTag(itemXml, "user_date_added");
    const userDateCreated = extractXmlTag(itemXml, "user_date_created") || extractXmlTag(itemXml, "pubDate");
    const userShelves = extractXmlTag(itemXml, "user_shelves");
    const rawReview = extractXmlTag(itemXml, "user_review");
    const reviewText = normalizeReviewText(rawReview);
    const reviewDescription = buildRichTextDocument(rawReview);

    const largeImageUrl =
      upgradeGoodreadsCoverUrl(extractXmlTag(itemXml, "book_large_image_url")) ||
      upgradeGoodreadsCoverUrl(extractXmlTag(itemXml, "book_medium_image_url")) ||
      upgradeGoodreadsCoverUrl(extractXmlTag(itemXml, "book_image_url"));

    const rawNumPages = extractXmlTag(itemXml, "num_pages");
    const numPages = rawNumPages ? Number.parseInt(rawNumPages, 10) || null : null;
    const bookPublished = extractXmlTag(itemXml, "book_published");

    const { status, readDateStarted, readDateFinished } = resolveReadDates({
      shelf,
      userShelves,
      userReadAt,
      userDateStarted,
      userDateAdded,
      userDateCreated,
    });

    items.push({
      bookId,
      title,
      author,
      isbn,
      rating,
      status,
      shelf,
      userShelves: userShelves || shelf,
      readDateStarted,
      readDateFinished,
      reviewText: reviewText || null,
      reviewDescription,
      goodreadsCoverUrl: largeImageUrl,
      numPages,
      bookPublished,
    });
  }

  return items;
}

/**
 * Merges books across multiple shelves (`read`, `currently-reading`, `to-read`),
 * prioritizing `read` > `currently-reading` > `to-read` if a book appears in multiple feeds.
 */
export function mergeShelfBooks(shelfItemsList) {
  const priority = { read: 3, reading: 2, notStarted: 1 };
  const merged = [];

  for (const item of shelfItemsList) {
    const existingIndex = merged.findIndex(
      (candidate) =>
        (item.bookId && candidate.bookId && item.bookId === candidate.bookId) ||
        (item.isbn && candidate.isbn && item.isbn === candidate.isbn) ||
        (normalizeAuthor(item.author) === normalizeAuthor(candidate.author) &&
          isDuplicateTitle(item.title, candidate.title)),
    );

    if (existingIndex === -1) {
      merged.push(item);
      continue;
    }

    const existing = merged[existingIndex];
    const existingPriority = priority[existing.status] || 0;
    const incomingPriority = priority[item.status] || 0;

    if (incomingPriority > existingPriority) {
      merged[existingIndex] = {
        ...existing,
        ...item,
        isbn: item.isbn ?? existing.isbn,
        rating: item.rating ?? existing.rating,
        reviewText: item.reviewText ?? existing.reviewText,
        reviewDescription: item.reviewDescription ?? existing.reviewDescription,
        goodreadsCoverUrl: item.goodreadsCoverUrl ?? existing.goodreadsCoverUrl,
      };
    } else {
      merged[existingIndex] = {
        ...existing,
        isbn: existing.isbn ?? item.isbn,
        rating: existing.rating ?? item.rating,
        reviewText: existing.reviewText ?? item.reviewText,
        reviewDescription: existing.reviewDescription ?? item.reviewDescription,
        goodreadsCoverUrl: existing.goodreadsCoverUrl ?? item.goodreadsCoverUrl,
      };
    }
  }

  return merged;
}

// ---------------------------------------------------------------------------
// Contentful Entry Normalization & Diffing
// ---------------------------------------------------------------------------

/**
 * Unwraps a localized CMA field (`{ "en-US": value }`) or plain CDA field (`value`).
 */
export function unwrapField(fieldValue, locale = DEFAULT_LOCALE) {
  if (fieldValue === null || fieldValue === undefined) return null;
  if (
    typeof fieldValue === "object" &&
    !Array.isArray(fieldValue) &&
    Object.prototype.hasOwnProperty.call(fieldValue, locale)
  ) {
    return fieldValue[locale];
  }
  return fieldValue;
}

/**
 * Normalizes a Contentful `book` entry (from CMA `/entries`) for fast lookup and diffing.
 */
export function normalizeContentfulBookEntry(entry, locale = DEFAULT_LOCALE) {
  const fields = entry?.fields || {};
  const title = cleanWhitespace(unwrapField(fields.title, locale) || "");
  const author = cleanWhitespace(unwrapField(fields.author, locale) || "");
  const rawIsbn = unwrapField(fields.isbn, locale);
  const isbn = typeof rawIsbn === "number" ? rawIsbn : parseIsbn13Number(rawIsbn);
  const rawRating = unwrapField(fields.rating, locale);
  const rating = typeof rawRating === "number" && rawRating > 0 ? rawRating : null;
  const readDateStarted = unwrapField(fields.readDateStarted, locale) || null;
  const readDateFinished = unwrapField(fields.readDateFinished, locale) || null;
  const coverLink = unwrapField(fields.coverImage, locale);
  const coverImageId = coverLink?.sys?.id || null;
  const reviewDescription = unwrapField(fields.reviewDescription, locale) || null;
  const reviewText = extractPlainTextFromRichText(reviewDescription) || null;

  const isPublished =
    typeof entry?.sys?.publishedVersion === "number" &&
    entry.sys.version === entry.sys.publishedVersion + 1;

  return {
    id: entry?.sys?.id,
    version: entry?.sys?.version ?? 1,
    publishedVersion: entry?.sys?.publishedVersion ?? null,
    isPublished,
    title,
    author,
    isbn,
    rating,
    readDateStarted,
    readDateFinished,
    coverImageId,
    reviewDescription,
    reviewText,
    rawFields: fields,
  };
}

/**
 * Matches a Goodreads book item against existing Contentful `book` entries by:
 * 1. Exact ISBN-13 match
 * 2. Normalized author + case-insensitive title containment (matching `Book.findDuplicate` in Saga)
 */
export function findMatchingContentfulEntry(goodreadsBook, existingEntries) {
  if (goodreadsBook.isbn) {
    const byIsbn = existingEntries.find((entry) => entry.isbn && entry.isbn === goodreadsBook.isbn);
    if (byIsbn) return byIsbn;
  }

  const targetAuthor = normalizeAuthor(goodreadsBook.author);
  return (
    existingEntries.find(
      (entry) =>
        normalizeAuthor(entry.author) === targetAuthor &&
        isDuplicateTitle(goodreadsBook.title, entry.title),
    ) || null
  );
}

/**
 * Computes whether a Goodreads book introduces any changes compared to an existing
 * Contentful `book` entry, preserving existing non-null fields (such as custom covers,
 * existing ISBNs, or user-curated `readDateStarted`) unless Goodreads has newer/more specific data.
 */
export function computeBookDiff(goodreadsBook, existingEntry) {
  if (!existingEntry) {
    return {
      action: "create",
      changedFields: ["title", "author", "isbn", "rating", "readDateStarted", "readDateFinished", "reviewDescription"],
      merged: {
        title: goodreadsBook.title,
        author: goodreadsBook.author,
        isbn: goodreadsBook.isbn ?? null,
        rating: goodreadsBook.rating ?? null,
        readDateStarted: goodreadsBook.readDateStarted ?? null,
        readDateFinished: goodreadsBook.readDateFinished ?? null,
        reviewText: goodreadsBook.reviewText ?? null,
        reviewDescription: goodreadsBook.reviewDescription ?? null,
        coverImageId: null,
      },
    };
  }

  const changedFields = [];

  // Match Book.add in Saga: update title to incoming Goodreads title,
  // and fill nil fields on the existing entry (`??=`) while allowing transition
  // from currently-reading (`readDateFinished == null`) to read (`readDateFinished != null`).
  const title = goodreadsBook.title || existingEntry.title;
  if (title !== existingEntry.title) changedFields.push("title");

  const author = existingEntry.author || goodreadsBook.author;
  if (author !== existingEntry.author) changedFields.push("author");

  // existingBook.isbn ??= isbn
  const isbn = existingEntry.isbn ?? goodreadsBook.isbn ?? null;
  if (isbn !== existingEntry.isbn) changedFields.push("isbn");

  // existingBook.rating ??= rating (also allow newly added rating if previously unrated, or updated rating)
  const rating = existingEntry.rating ?? goodreadsBook.rating ?? null;
  if (goodreadsBook.rating && goodreadsBook.rating !== existingEntry.rating) {
    changedFields.push("rating");
  }
  const mergedRating = goodreadsBook.rating ?? existingEntry.rating ?? null;

  // existingBook.reviewDescription ??= reviewDescription (or updated review in Goodreads)
  let reviewDescription = existingEntry.reviewDescription;
  let reviewText = existingEntry.reviewText;
  if (goodreadsBook.reviewText && goodreadsBook.reviewText !== existingEntry.reviewText) {
    reviewDescription = goodreadsBook.reviewDescription;
    reviewText = goodreadsBook.reviewText;
    changedFields.push("reviewDescription");
  }

  // existingBook.readDateFinished ??= readDateFinished
  // existingBook.readDateStarted ??= readDateStarted
  let readDateStarted = existingEntry.readDateStarted;
  let readDateFinished = existingEntry.readDateFinished;

  if (!existingEntry.readDateFinished && goodreadsBook.readDateFinished) {
    readDateFinished = goodreadsBook.readDateFinished;
    changedFields.push("readDateFinished");
  }
  if (!existingEntry.readDateStarted && goodreadsBook.readDateStarted) {
    readDateStarted = goodreadsBook.readDateStarted;
    changedFields.push("readDateStarted");
  }

  if (!existingEntry.coverImageId) {
    changedFields.push("coverImage");
  }

  return {
    action: changedFields.length > 0 || !existingEntry.isPublished ? "update" : "skip",
    changedFields,
    merged: {
      title,
      author,
      isbn,
      rating: mergedRating,
      readDateStarted,
      readDateFinished,
      reviewText,
      reviewDescription,
      coverImageId: existingEntry.coverImageId,
    },
  };
}

/**
 * Builds the localized CMA `fields` payload for a Contentful `book` entry,
 * matching `BookFieldsPayload` in `Saga`.
 */
export function buildCmaBookFields(merged, locale = DEFAULT_LOCALE) {
  const fields = {
    title: { [locale]: merged.title },
  };

  if (merged.author) {
    fields.author = { [locale]: merged.author };
  }
  if (typeof merged.isbn === "number" && Number.isFinite(merged.isbn)) {
    fields.isbn = { [locale]: merged.isbn };
  }
  if (typeof merged.rating === "number" && merged.rating > 0) {
    fields.rating = { [locale]: merged.rating };
  }
  if (merged.readDateStarted) {
    fields.readDateStarted = { [locale]: merged.readDateStarted };
  }
  if (merged.readDateFinished) {
    fields.readDateFinished = { [locale]: merged.readDateFinished };
  }
  if (merged.coverImageId) {
    fields.coverImage = {
      [locale]: {
        sys: {
          type: "Link",
          linkType: "Asset",
          id: merged.coverImageId,
        },
      },
    };
  }
  if (merged.reviewDescription) {
    fields.reviewDescription = { [locale]: merged.reviewDescription };
  }

  return fields;
}

// ---------------------------------------------------------------------------
// Cover Image & ISBN Resolution (Bookcover API + OpenLibrary + Goodreads Fallback)
// ---------------------------------------------------------------------------

async function probeImageCandidate(url, fetchImpl = fetch, minimumBytes = MIN_COVER_BYTES) {
  if (!url) return null;
  try {
    const res = await fetchImpl(url, { method: "HEAD", redirect: "follow" });
    if (!res.ok || res.status === 404) return null;
    const contentLength = res.headers.get("content-length");
    if (contentLength !== null) {
      const bytes = Number.parseInt(contentLength, 10);
      if (Number.isFinite(bytes)) {
        if (bytes < minimumBytes) return null;
        return { url, bytes };
      }
    }
    return { url, bytes: 0 };
  } catch {
    return null;
  }
}

async function fetchBookcoverCandidate(isbn, fetchImpl = fetch) {
  if (!isbn) return null;
  try {
    const res = await fetchImpl(`${BOOKCOVER_API_BASE_URL}/${isbn}`);
    if (!res.ok) return null;
    const data = await res.json();
    if (!data?.url) return null;
    return await probeImageCandidate(data.url, fetchImpl);
  } catch {
    return null;
  }
}

function cleanOpenLibraryTitle(title) {
  return String(title || "").replace(/ \([^(#)]*#\d+\)$/, "");
}

function normalizeAlphanumeric(value) {
  return String(value || "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "");
}

function openLibraryTitleMatches(candidate, normalizedTitle) {
  if (!candidate || !normalizedTitle) return false;
  const normalizedCandidate = normalizeAlphanumeric(candidate);
  if (!normalizedCandidate) return false;
  return (
    normalizedCandidate === normalizedTitle ||
    normalizedCandidate.includes(normalizedTitle) ||
    normalizedTitle.includes(normalizedCandidate)
  );
}

function openLibraryAuthorMatches(candidates, normalizedAuthor) {
  if (!Array.isArray(candidates) || !normalizedAuthor) return false;
  return candidates.some((candidate) => {
    const normalizedCandidate = normalizeAlphanumeric(candidate);
    if (!normalizedCandidate) return false;
    return (
      normalizedCandidate === normalizedAuthor ||
      normalizedCandidate.includes(normalizedAuthor) ||
      normalizedAuthor.includes(normalizedCandidate)
    );
  });
}

/**
 * Matches `OpenLibraryAPIService.prioritizedDocGroups(from:normalizedTitle:normalizedAuthor:)`:
 * filters to English docs when available, then orders groups:
 * 1. Both author and title match
 * 2. Author matches
 * 3. Title matches
 * 4. All docs
 */
export function prioritizeOpenLibraryDocGroups(docs, title, author) {
  if (!Array.isArray(docs) || docs.length === 0) return [];
  const normalizedTitle = normalizeAlphanumeric(cleanOpenLibraryTitle(title));
  const normalizedAuthor = normalizeAlphanumeric(author);

  const englishDocs = docs.filter(
    (doc) => Array.isArray(doc?.language) && doc.language.includes("eng"),
  );
  const pool = englishDocs.length > 0 ? englishDocs : docs;

  const authorMatchesDocs = pool.filter((doc) =>
    openLibraryAuthorMatches(doc?.author_name, normalizedAuthor),
  );
  const titleMatchesDocs = pool.filter((doc) =>
    openLibraryTitleMatches(doc?.title, normalizedTitle),
  );
  const authorTitleMatchesDocs = authorMatchesDocs.filter((doc) =>
    openLibraryTitleMatches(doc?.title, normalizedTitle),
  );

  return [authorTitleMatchesDocs, authorMatchesDocs, titleMatchesDocs, pool].filter(
    (group) => group.length > 0,
  );
}

function preferredIsbnFromList(rawIsbns) {
  if (!Array.isArray(rawIsbns)) return null;
  const cleaned = rawIsbns
    .map((raw) =>
      String(raw || "")
        .replace(/="/g, "")
        .replace(/"/g, "")
        .replace(/-/g, "")
        .replace(/\s+/g, "")
        .toUpperCase(),
    )
    .filter(Boolean);

  // Prefer 13-digit ISBNs first (matching OpenLibraryAPIService.preferredISBN)
  for (const candidate of cleaned) {
    const digitsOnly = candidate.replace(/\D/g, "");
    if (digitsOnly.length === 13) {
      const parsed = parseIsbn13Number(digitsOnly);
      if (parsed) return parsed;
    }
  }

  // Fall back to 10-digit ISBNs converted to ISBN-13
  for (const candidate of cleaned) {
    if (candidate.length === 10) {
      const parsed = parseIsbn13Number(candidate);
      if (parsed) return parsed;
    }
  }

  return null;
}

function extractIsbnCandidatesFromDocs(docs, normalizedTitle, requireTitleMatch) {
  const editionDocs = docs.flatMap((doc) =>
    Array.isArray(doc?.editions?.docs) ? doc.editions.docs : [],
  );
  const filteredEditions = requireTitleMatch
    ? editionDocs.filter((edition) => openLibraryTitleMatches(edition?.title, normalizedTitle))
    : editionDocs;
  return filteredEditions.flatMap((edition) =>
    Array.isArray(edition?.isbn) ? edition.isbn : [],
  );
}

async function fetchOpenLibrarySearchDocs(title, author, fetchImpl = fetch) {
  try {
    const cleanedTitle = cleanOpenLibraryTitle(title);
    const params = new URLSearchParams({
      q: `${cleanedTitle} ${author}`,
      fields: "key,title,author_name,language,cover_i,cover_edition_key,editions,editions.title,editions.isbn",
      lang: "en",
    });
    const res = await fetchImpl(`${OPENLIBRARY_API_BASE_URL}/search.json?${params.toString()}`);
    if (!res.ok) return [];
    const data = await res.json();
    return Array.isArray(data?.docs) ? data.docs : [];
  } catch {
    return [];
  }
}

async function fetchIsbnsFromOpenLibraryWorkEditions(workKey, fetchImpl = fetch) {
  if (!workKey) return null;
  try {
    const res = await fetchImpl(`${OPENLIBRARY_API_BASE_URL}${workKey}/editions.json`);
    if (!res.ok) return null;
    const data = await res.json();
    const entries = Array.isArray(data?.entries) ? data.entries : [];
    for (const edition of entries) {
      const langs = Array.isArray(edition?.languages) ? edition.languages : [];
      if (langs.some((lang) => lang?.key === "/languages/eng")) {
        if (Array.isArray(edition?.isbn_13) && edition.isbn_13.length > 0) {
          return edition.isbn_13;
        }
      }
    }
    return null;
  } catch {
    return null;
  }
}

/**
 * Resolves a missing ISBN-13 from OpenLibrary search + work editions fallback,
 * matching `OpenLibraryAPIService.isbnFor(title:author:)` in Saga.
 */
export async function resolveIsbnFromOpenLibrary(title, author, fetchImpl = fetch) {
  const docs = await fetchOpenLibrarySearchDocs(title, author, fetchImpl);
  if (docs.length === 0) return null;

  const normalizedTitle = normalizeAlphanumeric(cleanOpenLibraryTitle(title));
  const docGroups = prioritizeOpenLibraryDocGroups(docs, title, author);

  for (const group of docGroups) {
    const exactTitleIsbns = extractIsbnCandidatesFromDocs(group, normalizedTitle, true);
    const exactMatch = preferredIsbnFromList(exactTitleIsbns);
    if (exactMatch) return exactMatch;

    const fallbackIsbns = extractIsbnCandidatesFromDocs(group, normalizedTitle, false);
    const fallbackMatch = preferredIsbnFromList(fallbackIsbns);
    if (fallbackMatch) return fallbackMatch;
  }

  const firstWorkKey = docGroups.map((group) => group[0]?.key).find(Boolean);
  if (firstWorkKey) {
    const editionsIsbns = await fetchIsbnsFromOpenLibraryWorkEditions(firstWorkKey, fetchImpl);
    const editionMatch = preferredIsbnFromList(editionsIsbns);
    if (editionMatch) return editionMatch;
  }

  return null;
}

async function fetchOpenLibraryCoverCandidate(isbn, title, author, fetchImpl = fetch) {
  let isbnCandidate = null;
  if (isbn) {
    isbnCandidate = await probeImageCandidate(
      `${OPENLIBRARY_COVERS_BASE_URL}/b/isbn/${isbn}-L.jpg?default=false`,
      fetchImpl,
    );
    if (isbnCandidate && isbnCandidate.bytes >= OPENLIBRARY_PREFERRED_COVER_BYTES) {
      return isbnCandidate;
    }
  }

  const docs = await fetchOpenLibrarySearchDocs(title, author, fetchImpl);
  const docGroups = prioritizeOpenLibraryDocGroups(docs, title, author);
  let checked = 0;
  let bestSearchCandidate = null;

  for (const group of docGroups) {
    for (const doc of group) {
      const candidateUrls = [];
      if (doc.cover_edition_key) {
        candidateUrls.push(
          `${OPENLIBRARY_COVERS_BASE_URL}/b/olid/${doc.cover_edition_key}-L.jpg?default=false`,
        );
      }
      if (doc.cover_i) {
        candidateUrls.push(
          `${OPENLIBRARY_COVERS_BASE_URL}/b/id/${doc.cover_i}-L.jpg?default=false`,
        );
      }

      for (const candidateUrl of candidateUrls) {
        if (checked >= MAX_OPENLIBRARY_SEARCH_CANDIDATES) break;
        checked += 1;
        const candidate = await probeImageCandidate(candidateUrl, fetchImpl);
        if (candidate && (!bestSearchCandidate || candidate.bytes > bestSearchCandidate.bytes)) {
          bestSearchCandidate = candidate;
        }
      }
      if (checked >= MAX_OPENLIBRARY_SEARCH_CANDIDATES) break;
    }
    if (checked >= MAX_OPENLIBRARY_SEARCH_CANDIDATES) break;
  }

  if (isbnCandidate && bestSearchCandidate) {
    return isbnCandidate.bytes >= bestSearchCandidate.bytes ? isbnCandidate : bestSearchCandidate;
  }
  return isbnCandidate || bestSearchCandidate;
}

function choosePreferredCoverCandidate(openLibrary, bookcover) {
  if (!openLibrary) return bookcover;
  if (!bookcover) return openLibrary;
  if (
    bookcover.bytes >= BOOKCOVER_PREFERRED_MIN_BYTES &&
    bookcover.bytes >= openLibrary.bytes * BOOKCOVER_PREFERRED_RATIO
  ) {
    return bookcover;
  }
  return openLibrary.bytes >= bookcover.bytes ? openLibrary : bookcover;
}

/**
 * Resolves the best cover image URL for a book using the same priority order as `Book.swift`:
 * 1. OpenLibrary + Bookcover API (preferring high-resolution covers)
 * 2. Goodreads `<book_large_image_url>` fallback from the RSS feed
 */
export async function resolveBestCoverUrl(
  { isbn, title, author, goodreadsCoverUrl },
  fetchImpl = fetch,
) {
  const isbnStr = isbn ? String(isbn) : null;
  const openLibraryCandidate = await fetchOpenLibraryCoverCandidate(
    isbnStr,
    title,
    author,
    fetchImpl,
  );

  const shouldCheckBookcover =
    Boolean(isbnStr) &&
    (!openLibraryCandidate ||
      openLibraryCandidate.bytes < OPENLIBRARY_PREFER_BOOKCOVER_BELOW_BYTES);

  const bookcoverCandidate = shouldCheckBookcover
    ? await fetchBookcoverCandidate(isbnStr, fetchImpl)
    : null;

  const preferred = choosePreferredCoverCandidate(openLibraryCandidate, bookcoverCandidate);
  if (preferred?.url) {
    return preferred.url;
  }

  if (isUsableGoodreadsCoverUrl(goodreadsCoverUrl)) {
    return upgradeGoodreadsCoverUrl(goodreadsCoverUrl);
  }

  return null;
}

// ---------------------------------------------------------------------------
// Contentful Management API (CMA) Client
// ---------------------------------------------------------------------------

export class ContentfulCmaClient {
  constructor({
    spaceId,
    environmentId = DEFAULT_ENVIRONMENT_ID,
    managementToken,
    locale = DEFAULT_LOCALE,
    fetchImpl = fetch,
  }) {
    if (!spaceId) throw new Error("Missing CONTENTFUL_SPACE_ID");
    if (!managementToken) throw new Error("Missing CONTENTFUL_MANAGEMENT_TOKEN");
    this.spaceId = spaceId;
    this.environmentId = environmentId;
    this.managementToken = managementToken;
    this.locale = locale;
    this.fetchImpl = fetchImpl;
    this.baseUrl = `${CONTENTFUL_CMA_BASE_URL}/spaces/${spaceId}/environments/${environmentId}`;
    this.uploadUrl = `${CONTENTFUL_UPLOAD_BASE_URL}/spaces/${spaceId}/uploads`;
  }

  async request(path, { method = "GET", headers = {}, body } = {}) {
    const maxRetries = 3;
    for (let attempt = 0; attempt < maxRetries; attempt += 1) {
      const response = await this.fetchImpl(`${this.baseUrl}${path}`, {
        method,
        headers: {
          Authorization: `Bearer ${this.managementToken}`,
          "Content-Type": "application/vnd.contentful.management.v1+json",
          ...headers,
        },
        body: body !== undefined ? JSON.stringify(body) : undefined,
      });

      if (response.status === 429 && attempt < maxRetries - 1) {
        const resetSec =
          Number.parseFloat(response.headers.get("x-contentful-ratelimit-reset") || "1") || 1;
        await new Promise((resolve) => setTimeout(resolve, resetSec * 1000));
        continue;
      }

      if (response.status >= 500 && response.status < 600 && attempt < maxRetries - 1) {
        await new Promise((resolve) => setTimeout(resolve, 2 ** attempt * 500));
        continue;
      }

      const text = await response.text();
      const data = text ? JSON.parse(text) : null;

      if (!response.ok) {
        const error = new Error(
          `Contentful CMA ${method} ${path} failed (${response.status}): ${text.slice(0, 300)}`,
        );
        error.status = response.status;
        error.body = data;
        throw error;
      }

      return data;
    }
    throw new Error(`Contentful CMA ${method} ${path} exhausted retries`);
  }

  async fetchAllBooks() {
    const items = [];
    let skip = 0;
    const limit = 200;

    while (true) {
      const page = await this.request(
        `/entries?content_type=book&limit=${limit}&skip=${skip}`,
      );
      const pageItems = Array.isArray(page?.items) ? page.items : [];
      items.push(...pageItems.map((entry) => normalizeContentfulBookEntry(entry, this.locale)));
      skip += pageItems.length;
      if (pageItems.length === 0 || skip >= (page?.total ?? 0)) {
        break;
      }
    }

    return items;
  }

  async createOrReuseFallbackAsset() {
    const page = await this.request(`/assets?limit=10`);
    const items = Array.isArray(page?.items) ? page.items : [];
    const publishedAsset = items.find((a) => typeof a?.sys?.publishedVersion === "number");
    return publishedAsset?.sys?.id || items[0]?.sys?.id || null;
  }

  /**
   * Uploads binary image data to Contentful's Upload API (`upload.contentful.com/spaces/{spaceId}/uploads`),
   * matching `ContentfulManagementService.uploadFile` in Saga.
   */
  async uploadFile(binaryBuffer) {
    const response = await this.fetchImpl(this.uploadUrl, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${this.managementToken}`,
        "Content-Type": "application/octet-stream",
      },
      body: binaryBuffer,
    });
    const text = await response.text();
    if (!response.ok) {
      throw new Error(`Contentful binary upload failed (${response.status}): ${text.slice(0, 300)}`);
    }
    const data = text ? JSON.parse(text) : null;
    if (!data?.sys?.id) {
      throw new Error("Contentful binary upload response missing sys.id");
    }
    return data.sys.id;
  }

  /**
   * Creates, processes, and publishes a Contentful Asset from a remote cover image URL,
   * matching `TwoWaySyncService.pushAsset` + `ContentfulManagementService.uploadAsset` in Saga:
   * 1. Downloads the image bytes from `imageUrl`
   * 2. Uploads bytes to `upload.contentful.com` (`uploadFrom` link) or falls back to remote `upload: imageUrl`
   * 3. Creates the Asset with `id = UUID().uuidString` (uppercase), `fileName = "${assetId}.jpg"`, `contentType = "image/jpeg"`
   * 4. Calls `/assets/{id}/files/{locale}/process` and polls until `file[locale].url` is populated
   * 5. Publishes the Asset
   */
  async createAndPublishCoverAsset({ title, imageUrl }) {
    const assetId = crypto.randomUUID().toUpperCase();
    const fileName = `${assetId}.jpg`;
    const contentType = "image/jpeg";

    let filePayload = {
      contentType,
      fileName,
      upload: imageUrl,
    };

    try {
      const imageRes = await this.fetchImpl(imageUrl, { method: "GET", redirect: "follow" });
      if (imageRes.ok) {
        const arrayBuffer = await imageRes.arrayBuffer();
        if (arrayBuffer && arrayBuffer.byteLength > 0) {
          const uploadId = await this.uploadFile(new Uint8Array(arrayBuffer));
          filePayload = {
            contentType,
            fileName,
            uploadFrom: {
              sys: {
                type: "Link",
                linkType: "Upload",
                id: uploadId,
              },
            },
          };
        }
      }
    } catch {
      // Fall back to direct remote URL `upload: imageUrl` if binary upload endpoint isn't mocked or fails
    }

    const bodyFields = {
      file: {
        [this.locale]: filePayload,
      },
    };
    if (title) {
      bodyFields.title = { [this.locale]: title };
    }

    const created = await this.request(`/assets/${assetId}`, {
      method: "PUT",
      body: {
        fields: bodyFields,
      },
    });

    await this.request(`/assets/${assetId}/files/${this.locale}/process`, {
      method: "PUT",
      headers: {
        "X-Contentful-Version": String(created.sys.version),
      },
    });

    // Poll until Contentful finishes processing the image file
    let processedAsset = null;
    for (let attempt = 0; attempt < 15; attempt += 1) {
      const delayMs = Math.min(1000 * 2 ** Math.min(attempt, 3), 8000);
      await new Promise((resolve) => setTimeout(resolve, attempt === 0 ? 750 : delayMs));
      const candidate = await this.request(`/assets/${assetId}`);
      const fileField = candidate?.fields?.file?.[this.locale];
      if (fileField?.url) {
        processedAsset = candidate;
        break;
      }
    }

    if (!processedAsset) {
      throw new Error(`Timed out waiting for Contentful asset ${assetId} to process`);
    }

    await this.request(`/assets/${assetId}/published`, {
      method: "PUT",
      headers: {
        "X-Contentful-Version": String(processedAsset.sys.version),
      },
    });

    return assetId;
  }

  async createAndPublishBook(fields) {
    const entryId = crypto.randomUUID().toUpperCase();
    const created = await this.request(`/entries/${entryId}`, {
      method: "PUT",
      headers: {
        "X-Contentful-Content-Type": "book",
      },
      body: { fields },
    });

    const published = await this.request(`/entries/${entryId}/published`, {
      method: "PUT",
      headers: {
        "X-Contentful-Version": String(created.sys.version),
      },
    });

    return published;
  }

  async updateAndPublishBook(entryId, version, fields) {
    const updated = await this.request(`/entries/${entryId}`, {
      method: "PUT",
      headers: {
        "X-Contentful-Version": String(version),
      },
      body: { fields },
    });

    const published = await this.request(`/entries/${entryId}/published`, {
      method: "PUT",
      headers: {
        "X-Contentful-Version": String(updated.sys.version),
      },
    });

    return published;
  }
}

// ---------------------------------------------------------------------------
// End-to-End Goodreads -> Contentful Sync Orchestrator
// ---------------------------------------------------------------------------

export function buildGoodreadsRssUrl({ userId, rssKey, shelf, perPage = 200 }) {
  const params = new URLSearchParams({
    shelf,
    per_page: String(perPage),
  });
  if (rssKey) {
    params.set("key", rssKey);
  }
  return `https://www.goodreads.com/review/list_rss/${encodeURIComponent(userId)}?${params.toString()}`;
}

export async function fetchGoodreadsShelfItems({
  userId,
  rssKey,
  shelves = DEFAULT_SHELVES,
  fetchImpl = fetch,
}) {
  const shelfResults = await Promise.all(
    shelves.map(async (shelf) => {
      const url = buildGoodreadsRssUrl({ userId, rssKey, shelf });
      const response = await fetchImpl(url, {
        headers: {
          "User-Agent": "Saga-Goodreads-Sync/1.0",
          Accept: "application/rss+xml, application/xml, text/xml;q=0.9, */*;q=0.8",
        },
      });
      if (!response.ok) {
        throw new Error(`Goodreads RSS fetch failed for shelf "${shelf}" (${response.status})`);
      }
      const xml = await response.text();
      return parseGoodreadsRssXml(xml, shelf);
    }),
  );

  return mergeShelfBooks(shelfResults.flat());
}

/**
 * Runs a full sync from Goodreads RSS feeds to Contentful CMA.
 */
export async function runGoodreadsSync({
  goodreadsUserId,
  goodreadsRssKey,
  contentfulSpaceId,
  contentfulEnvironmentId = DEFAULT_ENVIRONMENT_ID,
  contentfulManagementToken,
  shelves = DEFAULT_SHELVES,
  dryRun = false,
  fetchImpl = fetch,
}) {
  const startedAt = Date.now();
  const cma = new ContentfulCmaClient({
    spaceId: contentfulSpaceId,
    environmentId: contentfulEnvironmentId,
    managementToken: contentfulManagementToken,
    fetchImpl,
  });

  const [goodreadsBooks, existingEntries] = await Promise.all([
    fetchGoodreadsShelfItems({
      userId: goodreadsUserId,
      rssKey: goodreadsRssKey,
      shelves,
      fetchImpl,
    }),
    cma.fetchAllBooks(),
  ]);

  // Filter to `read` and `currently-reading` by default unless `to-read` items already exist in Contentful,
  // matching `GoodreadsCSVParser.applicableShelves` while still supporting `to-read` shelf polling.
  const applicableBooks = goodreadsBooks.filter(
    (book) =>
      book.status === "read" ||
      book.status === "reading" ||
      findMatchingContentfulEntry(book, existingEntries) !== null,
  );

  const summary = {
    ok: true,
    dryRun,
    shelvesPolled: shelves,
    goodreadsItemsFetched: goodreadsBooks.length,
    applicableBooksCount: applicableBooks.length,
    existingContentfulBooksCount: existingEntries.length,
    createdCount: 0,
    updatedCount: 0,
    skippedCount: 0,
    created: [],
    updated: [],
    errors: [],
    durationMs: 0,
  };

  let fallbackCoverAssetId = null;

  for (const goodreadsBook of applicableBooks) {
    try {
      const existing = findMatchingContentfulEntry(goodreadsBook, existingEntries);
      const diff = computeBookDiff(goodreadsBook, existing);

      if (diff.action === "skip") {
        summary.skippedCount += 1;
        continue;
      }

      const merged = { ...diff.merged };

      if (!merged.isbn) {
        merged.isbn = await resolveIsbnFromOpenLibrary(
          merged.title,
          merged.author,
          fetchImpl,
        );
      }

      if (!merged.coverImageId && !dryRun) {
        const coverUrl = await resolveBestCoverUrl(
          {
            isbn: merged.isbn,
            title: merged.title,
            author: merged.author,
            goodreadsCoverUrl: goodreadsBook.goodreadsCoverUrl,
          },
          fetchImpl,
        );

        if (coverUrl) {
          try {
            merged.coverImageId = await cma.createAndPublishCoverAsset({
              title: merged.title,
              imageUrl: coverUrl,
            });
          } catch (coverError) {
            // Fall back to an existing published asset if remote cover upload fails
            // since `coverImage` is a required field on the `book` content type in Contentful.
            fallbackCoverAssetId =
              fallbackCoverAssetId || (await cma.createOrReuseFallbackAsset());
            merged.coverImageId = fallbackCoverAssetId;
          }
        } else {
          fallbackCoverAssetId =
            fallbackCoverAssetId || (await cma.createOrReuseFallbackAsset());
          merged.coverImageId = fallbackCoverAssetId;
        }
      }

      if (diff.action === "create") {
        if (!dryRun) {
          if (!merged.coverImageId) {
            throw new Error(
              `Cannot create "${merged.title}" without a coverImage asset (required by Contentful schema)`,
            );
          }
          const fields = buildCmaBookFields(merged);
          const createdEntry = await cma.createAndPublishBook(fields);
          existingEntries.push(normalizeContentfulBookEntry(createdEntry));
        }
        summary.createdCount += 1;
        summary.created.push({
          title: merged.title,
          author: merged.author,
          status: goodreadsBook.status,
          changedFields: diff.changedFields,
        });
      } else if (diff.action === "update" && existing) {
        if (!dryRun) {
          const fields = {
            ...existing.rawFields,
            ...buildCmaBookFields(merged),
          };
          await cma.updateAndPublishBook(existing.id, existing.version, fields);
        }
        summary.updatedCount += 1;
        summary.updated.push({
          id: existing.id,
          title: merged.title,
          author: merged.author,
          status: goodreadsBook.status,
          changedFields: diff.changedFields,
        });
      }
    } catch (error) {
      summary.errors.push({
        title: goodreadsBook.title,
        author: goodreadsBook.author,
        message: error instanceof Error ? error.message : String(error),
      });
    }
  }

  summary.ok = summary.errors.length === 0;
  summary.durationMs = Date.now() - startedAt;
  return summary;
}

// ---------------------------------------------------------------------------
// Vercel Serverless HTTP Handler
// ---------------------------------------------------------------------------

function extractBearerToken(req) {
  const authHeader =
    req?.headers?.authorization ||
    req?.headers?.Authorization ||
    (typeof req?.headers?.get === "function" ? req.headers.get("authorization") : null);
  if (!authHeader || typeof authHeader !== "string") return null;
  const match = authHeader.match(/^Bearer\s+(.+)$/i);
  return match ? match[1].trim() : null;
}

export default async function handler(req, res) {
  const method = req?.method || "GET";
  if (method !== "GET" && method !== "POST") {
    return res.status(405).json({ ok: false, error: "Method not allowed" });
  }

  const expectedSecret = (
    process.env.CRON_SECRET ||
    process.env.GOODREADS_SYNC_SECRET ||
    ""
  ).trim();

  if (expectedSecret) {
    const providedToken = extractBearerToken(req);
    if (!providedToken || providedToken !== expectedSecret) {
      return res.status(401).json({ ok: false, error: "Unauthorized" });
    }
  }

  const goodreadsUserId = (process.env.GOODREADS_USER_ID || "").trim();
  const goodreadsRssKey = (process.env.GOODREADS_RSS_KEY || "").trim();
  const contentfulSpaceId = (process.env.CONTENTFUL_SPACE_ID || "").trim();
  const contentfulEnvironmentId = (
    process.env.CONTENTFUL_ENVIRONMENT_ID || DEFAULT_ENVIRONMENT_ID
  ).trim();
  const contentfulManagementToken = (
    process.env.CONTENTFUL_MANAGEMENT_TOKEN ||
    process.env.CONTENTFUL_MANAGEMENT_ACCESS_TOKEN ||
    ""
  ).trim();

  const missingVars = [];
  if (!goodreadsUserId) missingVars.push("GOODREADS_USER_ID");
  if (!contentfulSpaceId) missingVars.push("CONTENTFUL_SPACE_ID");
  if (!contentfulManagementToken) missingVars.push("CONTENTFUL_MANAGEMENT_TOKEN");

  if (missingVars.length > 0) {
    return res.status(500).json({
      ok: false,
      error: `Missing required environment variables: ${missingVars.join(", ")}`,
    });
  }

  const dryRunParam =
    req?.query?.dryRun ??
    req?.query?.dry_run ??
    req?.body?.dryRun ??
    false;
  const dryRun = dryRunParam === true || dryRunParam === "true" || dryRunParam === "1";

  try {
    const result = await runGoodreadsSync({
      goodreadsUserId,
      goodreadsRssKey,
      contentfulSpaceId,
      contentfulEnvironmentId,
      contentfulManagementToken,
      dryRun,
    });
    return res.status(result.ok ? 200 : 207).json(result);
  } catch (error) {
    return res.status(500).json({
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    });
  }
}
