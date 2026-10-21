//
//  TestCoreDataStack.swift
//  SagaTests
//
//  Created by Dylan Gattey on 10/14/26.
//

import CoreData
import Foundation

import class Contentful.RichTextDocument

@testable import Saga

enum TestCoreDataStack {
  /// `swift test` has no app bundle, so compile the model with `momc` once per test run.
  static let managedObjectModel: NSManagedObjectModel = {
    let source = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Saga/Saga.xcdatamodeld")
    let outputDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SagaTests-\(UUID().uuidString)")
    let momc = Process()
    momc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    momc.arguments = ["momc", source.path, outputDirectory.path]
    do {
      try FileManager.default.createDirectory(
        at: outputDirectory, withIntermediateDirectories: true)
      try momc.run()
    } catch {
      fatalError("Failed to run momc: \(error)")
    }
    momc.waitUntilExit()
    guard momc.terminationStatus == 0 else {
      fatalError("momc exited with status \(momc.terminationStatus)")
    }
    return PersistenceService.loadManagedObjectModel(
      at: outputDirectory.appendingPathComponent("Saga.momd"))
  }()

  static func makeContainer() -> NSPersistentContainer {
    let container = NSPersistentContainer(
      name: "Saga",
      managedObjectModel: managedObjectModel
    )
    let description = NSPersistentStoreDescription()
    description.url = URL(fileURLWithPath: "/dev/null")
    container.persistentStoreDescriptions = [description]
    container.loadPersistentStores { _, error in
      if let error = error as NSError? {
        fatalError("Failed to load in-memory persistent store: \(error), \(error.userInfo)")
      }
    }
    container.viewContext.automaticallyMergesChangesFromParent = true
    return container
  }

  @discardableResult
  static func makeBook(
    in context: NSManagedObjectContext,
    id: String = UUID().uuidString,
    title: String? = "The Left Hand of Darkness",
    author: String? = "Ursula K. Le Guin",
    isbn: Int64? = 9_780_441_478_125,
    rating: Int? = 5,
    readDateStarted: Date? = Date(timeIntervalSince1970: 1_700_000_000),
    readDateFinished: Date? = Date(timeIntervalSince1970: 1_700_600_000),
    reviewPlainText: String? = "A masterpiece of speculative fiction.",
    coverURLString: String? = "https://images.ctfassets.net/cover.jpg"
  ) throws -> Book {
    let book = Book(context: context)
    book.id = id
    book.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    book.updatedAt = book.createdAt
    book.title = title
    book.author = author
    book.isbn = isbn.map { NSNumber(value: $0) }
    book.rating = rating.map { NSNumber(value: $0) }
    book.readDateStarted = readDateStarted
    book.readDateFinished = readDateFinished
    if let reviewPlainText {
      book.reviewDescription = RichTextDocument(fromPlainText: reviewPlainText)
    }
    if let coverURLString {
      let asset = Asset(context: context)
      asset.id = UUID().uuidString
      asset.createdAt = book.createdAt
      asset.updatedAt = book.updatedAt
      asset.title = title.map { "\($0) Cover" }
      asset.fileName = "cover.jpg"
      asset.urlString = coverURLString
      book.coverImage = asset
    }
    try context.save()
    return book
  }
}
