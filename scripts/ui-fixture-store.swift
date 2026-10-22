// Writes a Core Data store of fixture books for scripts/ui-screenshots.sh, which copies it into the
// simulator's app container so the unmodified app has books to show without Contentful credentials.
//
// Usage: xcrun swift scripts/ui-fixture-store.swift <Saga.momd> <output.sqlite>

import CoreData
import Foundation

@objc(RichTextDocumentTransformer)
final class RichTextDocumentTransformer: ValueTransformer {
  override class func transformedValueClass() -> AnyClass { NSData.self }
  override class func allowsReverseTransformation() -> Bool { true }
  override func transformedValue(_ value: Any?) -> Any? { value as? Data }
  override func reverseTransformedValue(_ value: Any?) -> Any? { value as? Data }
}

ValueTransformer.setValueTransformer(
  RichTextDocumentTransformer(),
  forName: NSValueTransformerName("RichTextDocumentTransformer")
)

struct RichTextMark: Encodable {}

struct RichTextTextNode: Encodable {
  var nodeType = "text"
  let value: String
  var marks: [RichTextMark] = []
}

struct RichTextParagraphNode: Encodable {
  var nodeType = "paragraph"
  let content: [RichTextTextNode]
}

struct RichTextDocumentPayload: Encodable {
  var nodeType = "document"
  let content: [RichTextParagraphNode]
}

func richTextData(_ text: String) throws -> Data? {
  let paragraphs = text.components(separatedBy: .newlines)
    .map { $0.trimmingCharacters(in: .whitespaces) }
    .filter { !$0.isEmpty }
  guard !paragraphs.isEmpty else { return nil }
  let payload = RichTextDocumentPayload(
    content: paragraphs.map { line in
      RichTextParagraphNode(content: [RichTextTextNode(value: line)])
    }
  )
  return try JSONEncoder().encode(payload)
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
  let usage = "usage: ui-fixture-store.swift <Saga.momd> <output.sqlite>\n"
  FileHandle.standardError.write(Data(usage.utf8))
  exit(64)
}
let modelURL = URL(fileURLWithPath: arguments[1])
let storeURL = URL(fileURLWithPath: arguments[2])

guard let model = NSManagedObjectModel(contentsOf: modelURL) else {
  FileHandle.standardError.write(Data("ui-fixture-store: can't load \(modelURL.path)\n".utf8))
  exit(1)
}

for suffix in ["", "-wal", "-shm"] {
  try? FileManager.default.removeItem(atPath: storeURL.path + suffix)
}
let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
try coordinator.addPersistentStore(
  type: .sqlite,
  at: storeURL,
  options: [NSSQLitePragmasOption: ["journal_mode": "DELETE"]]
)
let context = NSManagedObjectContext(.mainQueue)
context.persistentStoreCoordinator = coordinator

func day(_ iso: String) -> Date {
  ISO8601DateFormatter().date(from: "\(iso)T12:00:00Z") ?? Date(timeIntervalSince1970: 0)
}

struct FixtureBook {
  let title: String
  let author: String
  let isbn: Int64
  let rating: Int
  let started: String
  let finished: String?
  let review: String?
  let notes: String?
}

let books: [FixtureBook] = [
  FixtureBook(
    title: "Exhalation",
    author: "Ted Chiang",
    isbn: 9_781_101_947_883,
    rating: 5,
    started: "2026-10-01",
    finished: nil,
    review:
      "Nine fiercely inventive stories about free will, memory, and the nature of consciousness.",
    notes:
      "In The Truth of Fact, the Truth of Feeling: compare digital lifelogs with episodic recall. Share the mechanical lungs passage at book club."
  ),
  FixtureBook(
    title: "The Left Hand of Darkness",
    author: "Ursula K. Le Guin",
    isbn: 9_780_441_478_125,
    rating: 5,
    started: "2026-08-02",
    finished: "2026-08-30",
    review: "A masterpiece of speculative fiction set on the winter world of Gethen.",
    notes:
      "Chapter 15 trek across the Gobrin Ice: Estraven's journal entries on loyalty and episodic endurance."
  ),
  FixtureBook(
    title: "Children of Time",
    author: "Adrian Tchaikovsky",
    isbn: 9_780_316_452_502,
    rating: 4,
    started: "2026-06-10",
    finished: "2026-07-15",
    review: "Deep evolutionary world-building across millennia.",
    notes: nil
  ),
  FixtureBook(
    title: "Piranesi",
    author: "Susanna Clarke",
    isbn: 9_781_635_575_637,
    rating: 5,
    started: "2026-05-01",
    finished: "2026-05-12",
    review: "Labyrinthine and quietly moving.",
    notes: "The House is immeasurable; its Beauty is second only to its Kindness."
  ),
  FixtureBook(
    title: "Project Hail Mary",
    author: "Andy Weir",
    isbn: 9_780_593_135_204,
    rating: 4,
    started: "2026-03-03",
    finished: "2026-03-20",
    review: nil,
    notes: "Rocky's musical chord language and astrophage propulsion calculations."
  ),
  FixtureBook(
    title: "A Psalm for the Wild-Built",
    author: "Becky Chambers",
    isbn: 9_781_250_236_210,
    rating: 4,
    started: "2026-02-01",
    finished: "2026-02-05",
    review: nil,
    notes: nil
  ),
]

for (index, fixture) in books.enumerated() {
  let book = NSEntityDescription.insertNewObject(forEntityName: "Book", into: context)
  book.setValue("ui-fixture-\(index)", forKey: "id")
  book.setValue(fixture.title, forKey: "title")
  book.setValue(fixture.author, forKey: "author")
  book.setValue(NSNumber(value: fixture.isbn), forKey: "isbn")
  book.setValue(fixture.rating, forKey: "rating")
  book.setValue(day(fixture.started), forKey: "readDateStarted")
  book.setValue(fixture.finished.map(day), forKey: "readDateFinished")
  book.setValue(try fixture.review.flatMap(richTextData), forKey: "reviewDescription")
  book.setValue(try fixture.notes.flatMap(richTextData), forKey: "notes")
  book.setValue(day(fixture.started), forKey: "createdAt")
  book.setValue(day(fixture.finished ?? fixture.started), forKey: "updatedAt")
}
try context.save()
print("ui-fixture-store: wrote \(books.count) books to \(storeURL.path)")
