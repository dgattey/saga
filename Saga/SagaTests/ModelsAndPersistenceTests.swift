//
//  ModelsAndPersistenceTests.swift
//  SagaTests
//
//  Created by Dylan Gattey on 10/14/26.
//

import CoreData
import Foundation
import SwiftUI
import Testing

import class Contentful.RichTextDocument

@testable import Saga

@Suite("Book & Asset Models")
struct ModelsAndPersistenceTests {
  @Test("ReadingStatus derives from start and finish dates and advances monotonically")
  func readingStatusDerivationAndAdvance() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let finish = Date(timeIntervalSince1970: 1_700_500_000)

    #expect(ReadingStatus(readDateStarted: nil, readDateFinished: nil) == .notStarted)
    #expect(ReadingStatus(readDateStarted: start, readDateFinished: nil) == .reading)
    #expect(ReadingStatus(readDateStarted: start, readDateFinished: finish) == .read)
    #expect(ReadingStatus(readDateStarted: nil, readDateFinished: finish) == .read)

    var status = ReadingStatus.notStarted
    status.advance()
    #expect(status == .reading)
    status.advance()
    #expect(status == .read)
    status.advance()
    #expect(status == .read)
  }

  @Test("Book.sidebarFetchRequest configures sort descriptors, prefetching, and batch size")
  func sidebarFetchRequestConfiguration() {
    let request = Book.sidebarFetchRequest()
    #expect(request.entityName == "Book")
    #expect(request.fetchBatchSize == 100)
    #expect(request.relationshipKeyPathsForPrefetching == ["coverImage"])
    #expect(request.sortDescriptors?.count == 1)
    #expect(request.sortDescriptors?.first?.key == "readDateStarted")
    #expect(request.sortDescriptors?.first?.ascending == false)
  }

  @Test("Book and Asset persist in-memory and map to searchable DTOs")
  @MainActor
  func bookAndAssetPersistenceAndDTOMapping() throws {
    let container = TestCoreDataStack.makeContainer()
    let context = container.viewContext

    let book = try TestCoreDataStack.makeBook(
      in: context,
      id: "book-1",
      title: "Piranesi",
      author: "Susanna Clarke",
      isbn: 9_781_635_575_637,
      rating: 5,
      reviewPlainText: "The House is infinite.\n\nThe Tides are regular.",
      coverURLString: "https://example.com/piranesi.jpg"
    )

    #expect(book.readingStatus == .read)
    #expect(book.coverImage?.assetURL == URL(string: "https://example.com/piranesi.jpg"))

    let dto = book.toDTO()
    #expect(dto.id == "book-1")
    #expect(dto.title == "Piranesi")
    #expect(dto.author == "Susanna Clarke")
    #expect(dto.isbn == "9781635575637")
    #expect(dto.rating == "5")
    #expect(dto.reviewDescription == "The House is infinite.\n\nThe Tides are regular.")
    #expect(dto.coverImage?.urlString == "https://example.com/piranesi.jpg")
    #expect(dto.description == "Piranesi")
  }

  @Test("Asset.add deduplicates existing assets case-insensitively by URL")
  func assetAddDeduplication() async throws {
    let container = TestCoreDataStack.makeContainer()
    let context = container.viewContext

    let nilAsset = try await Asset.add(to: context, withURL: nil)
    #expect(nilAsset == nil)

    let first = try #require(
      await Asset.add(to: context, withURL: "https://example.com/Cover.JPG")
    )
    try context.save()

    let duplicate = try #require(
      await Asset.add(to: context, withURL: "https://example.com/cover.jpg")
    )
    #expect(first.objectID == duplicate.objectID)

    let count = try context.count(for: NSFetchRequest<Asset>(entityName: "Asset"))
    #expect(count == 1)
  }

  @Test("Book.add merges into existing duplicate book by author and contained title")
  func bookAddMergesDuplicates() async throws {
    let container = TestCoreDataStack.makeContainer()
    let context = container.viewContext

    let existing = try TestCoreDataStack.makeBook(
      in: context,
      title: "Dune",
      author: "Frank Herbert",
      isbn: 9_780_441_172_719,
      rating: nil,
      readDateStarted: nil,
      readDateFinished: nil,
      reviewPlainText: nil,
      coverURLString: "https://example.com/dune.jpg"
    )

    let finishDate = Date(timeIntervalSince1970: 1_710_000_000)
    try await Book.add(
      to: context,
      title: "Dune (Deluxe Edition)",
      author: "frank herbert",
      getISBN: { NSNumber(value: 9_780_441_013_593 as Int64) },
      readDateStarted: nil,
      readDateFinished: finishDate,
      rating: NSNumber(value: 5),
      reviewDescription: RichTextDocument(fromPlainText: "Spice must flow.")
    )
    try context.save()

    let allBooks = try context.fetch(NSFetchRequest<Book>(entityName: "Book"))
    #expect(allBooks.count == 1)
    #expect(existing.title == "Dune (Deluxe Edition)")
    #expect(existing.isbn?.int64Value == 9_780_441_172_719)
    #expect(existing.rating?.intValue == 5)
    #expect(existing.readDateFinished == finishDate)
    #expect(existing.reviewDescription?.plainText == "Spice must flow.")
  }

  @Test("GoodreadsCSVParser imports read and currently-reading rows and skips to-read")
  @MainActor
  func goodreadsCSVParserImportsAndDeduplicates() async throws {
    let container = TestCoreDataStack.makeContainer()
    let context = container.viewContext

    let csvContents = #"""
      Title,Author,ISBN,ISBN13,My Rating,Date Read,Date Added,Date Started,Exclusive Shelf,My Review
      "Project Hail Mary","Andy Weir","=""0593135202""","=""9780593135204""",5,2025/04/12,2025/04/01,2025/04/02,read,"Amaze! <br/>Grace and Rocky."
      "TheMartian","Andy Weir","=""0553418025""","",4,,2025/05/01,2025/05/02,currently-reading,""
      "Unread Book","Someone Else","=""1234567890""","=""9781234567897""",0,,2025/05/01,,to-read,""
      """#

    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("goodreads-test-\(UUID().uuidString).csv")
    try csvContents.write(to: tempURL, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    var completed = 0
    var total = 0
    let completedBinding = Binding(get: { completed }, set: { completed = $0 })
    let totalBinding = Binding(get: { total }, set: { total = $0 })

    try await GoodreadsCSVParser.parse(
      into: context,
      from: tempURL,
      completedSteps: completedBinding,
      totalSteps: totalBinding
    )

    #expect(total == 2)
    #expect(completed == 2)

    let request = NSFetchRequest<Book>(entityName: "Book")
    request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
    let books = try context.fetch(request)
    #expect(books.count == 2)

    let hailMary = try #require(books.first(where: { $0.title == "Project Hail Mary" }))
    #expect(hailMary.author == "Andy Weir")
    #expect(hailMary.isbn?.int64Value == 9_780_593_135_204)
    #expect(hailMary.rating?.intValue == 5)
    #expect(hailMary.readingStatus == .read)
    #expect(hailMary.reviewDescription?.plainText == "Amaze! \n\nGrace and Rocky.")

    let martian = try #require(books.first(where: { $0.title == "TheMartian" }))
    #expect(martian.isbn?.int64Value == 9_780_553_418_026)
    #expect(martian.readingStatus == .reading)
  }
}
