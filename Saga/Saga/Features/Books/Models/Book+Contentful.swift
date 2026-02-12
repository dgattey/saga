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
      isbn: isbn?.intValue,
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
  static func upsert(from entry: Entry, in context: NSManagedObjectContext) {
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

    let fields = entry.fields

    book.title = fields["title"] as? String
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

    // Rich text: Contentful may decode it directly to RichTextDocument
    if let richText = fields["reviewDescription"] as? RichTextDocument {
      book.reviewDescription = richText
    } else {
      book.reviewDescription = nil
    }

    // Cover image: field contains a Link object, not an Asset
    // Extract the asset ID from the link to look up our Core Data Asset
    if let link = fields["coverImage"] as? Link {
      let assetRequest = NSFetchRequest<Asset>(entityName: "Asset")
      assetRequest.predicate = NSPredicate(format: "id == %@", link.id)
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
  var isbn: Localized<Int>?
  var rating: Localized<Int>?
  var readDateStarted: Localized<String>?
  var readDateFinished: Localized<String>?
  var coverImage: Localized<ContentfulLink>?
  var reviewDescription: Localized<RichTextJSON>?

  init(
    title: String? = nil,
    author: String? = nil,
    isbn: Int? = nil,
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
