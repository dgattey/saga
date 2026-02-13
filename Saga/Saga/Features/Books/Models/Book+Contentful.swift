//
//  Book+Contentful.swift
//  Saga
//
//  Contentful serialization (push) and deserialization (pull) for Book.
//  Keeps Book.swift focused on Core Data model definition.
//

@preconcurrency import Contentful
import CoreData
import Foundation

// MARK: - ContentfulPushable Conformance

extension Book: ContentfulPushable {
  static var resourceType: ContentfulResourceType { .entry }
  static var cmaContentTypeId: String? { contentTypeId }  // Use existing contentTypeId
  static var entityName: String { "Book" }

  var displayTitle: String? { title }

  func buildFieldsPayload() -> BookFieldsPayload {
    BookFieldsPayload(
      title: title,
      author: author,
      isbn: isbn?.int64Value,
      rating: rating?.intValue,
      readDateStarted: readDateStarted,
      readDateFinished: readDateFinished,
      coverImageId: coverImage?.id,
      reviewDescription: reviewDescription
    )
  }
}

// MARK: - Preview Pull (Contentful → Core Data)

extension Book {
  /// Upserts a Book from a raw Contentful Entry (used by preview pull)
  /// Skips objects that have local dirty changes to avoid overwriting unpushed edits.
  /// Skips entries missing required fields (common for draft content in preview mode).
  static func upsert(from entry: Entry, in context: NSManagedObjectContext) {
    let fields = entry.fields

    // Skip entries missing required fields (common for draft content in preview mode)
    guard let title = fields["title"] as? String else {
      return
    }

    let request = NSFetchRequest<Book>(entityName: "Book")
    request.predicate = NSPredicate(format: "id == %@", entry.id)
    request.fetchLimit = 1

    let existing = (try? context.fetch(request))?.first

    // Skip if object has local dirty changes - push will handle it
    if let existing, existing.isDirty {
      return
    }

    let book = existing ?? Book(context: context)

    book.id = entry.id
    book.localeCode = entry.localeCode
    book.updatedAt = entry.sys.updatedAt
    book.createdAt = entry.sys.createdAt

    book.title = title
    book.author = fields["author"] as? String

    if let isbnValue = fields["isbn"] as? Int {
      book.isbn = NSNumber(value: isbnValue)
    } else {
      book.isbn = nil
    }
    if let ratingValue = fields["rating"] as? Int {
      book.rating = NSNumber(value: ratingValue)
    } else {
      book.rating = nil
    }

    let iso = ISO8601DateFormatter()
    if let str = fields["readDateStarted"] as? String {
      book.readDateStarted = iso.date(from: str)
    } else {
      book.readDateStarted = nil
    }
    if let str = fields["readDateFinished"] as? String {
      book.readDateFinished = iso.date(from: str)
    } else {
      book.readDateFinished = nil
    }

    // Rich text: For generic Entry objects, the SDK may store Rich Text as a raw
    // [String: Any] dictionary rather than a RichTextDocument. Try both.
    if let richText = fields["reviewDescription"] as? RichTextDocument {
      book.reviewDescription = richText
    } else if let rawDict = fields["reviewDescription"] as? [String: Any],
      let jsonData = try? JSONSerialization.data(withJSONObject: rawDict),
      let richText = try? JSONDecoder().decode(RichTextDocument.self, from: jsonData)
    {
      book.reviewDescription = richText
    } else if fields["reviewDescription"] == nil || fields["reviewDescription"] is NSNull {
      // Field is explicitly absent or null - clear it
      book.reviewDescription = nil
    }
    // If field exists but couldn't be decoded, preserve existing value to avoid data loss

    // Cover image: extract asset ID to look up our Core Data Asset.
    // The field may be a Link (unresolved) or a Contentful.Asset (resolved when include depth >= 1).
    let coverImageAssetId: String?
    if let link = fields["coverImage"] as? Link {
      coverImageAssetId = link.id
    } else if let resolvedAsset = fields["coverImage"] as? Contentful.Asset {
      coverImageAssetId = resolvedAsset.id
    } else {
      coverImageAssetId = nil
    }

    if let assetId = coverImageAssetId {
      let assetRequest = NSFetchRequest<Asset>(entityName: "Asset")
      assetRequest.predicate = NSPredicate(format: "id == %@", assetId)
      assetRequest.fetchLimit = 1
      book.coverImage = (try? context.fetch(assetRequest))?.first
    } else {
      book.coverImage = nil
    }
  }
}

// MARK: - CMA Fields Payload

/// Codable representation of Book fields for CMA requests
struct BookFieldsPayload: Codable {
  var title: Localized<String>?
  var author: Localized<String>?
  var isbn: Localized<Int64>?
  var rating: Localized<Int>?
  var readDateStarted: Localized<String>?
  var readDateFinished: Localized<String>?
  var coverImage: Localized<ContentfulLink>?
  var reviewDescription: Localized<RichTextJSON>?

  init(
    title: String? = nil,
    author: String? = nil,
    isbn: Int64? = nil,
    rating: Int? = nil,
    readDateStarted: Date? = nil,
    readDateFinished: Date? = nil,
    coverImageId: String? = nil,
    reviewDescription: RichTextDocument? = nil
  ) {
    self.title = title.map { Localized($0) }
    self.author = author.map { Localized($0) }
    self.isbn = isbn.map { Localized($0) }
    self.rating = rating.map { Localized($0) }

    let formatter = ISO8601DateFormatter()
    self.readDateStarted = readDateStarted.map { Localized(formatter.string(from: $0)) }
    self.readDateFinished = readDateFinished.map { Localized(formatter.string(from: $0)) }

    self.coverImage = coverImageId.map { Localized(.asset(id: $0)) }

    // Encode RichTextDocument to JSON for Contentful
    if let rtd = reviewDescription,
      let jsonData = try? JSONEncoder().encode(rtd),
      let jsonObject = try? JSONSerialization.jsonObject(with: jsonData)
    {
      self.reviewDescription = Localized(RichTextJSON(jsonObject))
    } else {
      self.reviewDescription = nil
    }
  }
}
