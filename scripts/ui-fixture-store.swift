// Writes a Core Data store of fixture books for scripts/ui-screenshots.sh, which copies it into the
// simulator's app container so the unmodified app has books to show without Contentful credentials.
//
// Usage: xcrun swift scripts/ui-fixture-store.swift <Saga.momd> <output.sqlite>

import CoreData
import Foundation

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

let books: [(title: String, author: String, rating: Int, started: String, finished: String?)] = [
  ("Exhalation", "Ted Chiang", 0, "2026-10-01", nil),
  ("The Left Hand of Darkness", "Ursula K. Le Guin", 5, "2026-08-02", "2026-08-30"),
  ("Children of Time", "Adrian Tchaikovsky", 4, "2026-06-10", "2026-07-15"),
  ("Piranesi", "Susanna Clarke", 5, "2026-05-01", "2026-05-12"),
  ("Project Hail Mary", "Andy Weir", 4, "2026-03-03", "2026-03-20"),
  ("A Psalm for the Wild-Built", "Becky Chambers", 4, "2026-02-01", "2026-02-05"),
]

for (index, fixture) in books.enumerated() {
  let book = NSEntityDescription.insertNewObject(forEntityName: "Book", into: context)
  book.setValue("ui-fixture-\(index)", forKey: "id")
  book.setValue(fixture.title, forKey: "title")
  book.setValue(fixture.author, forKey: "author")
  book.setValue(fixture.rating, forKey: "rating")
  book.setValue(day(fixture.started), forKey: "readDateStarted")
  book.setValue(fixture.finished.map(day), forKey: "readDateFinished")
  book.setValue(day(fixture.started), forKey: "createdAt")
  book.setValue(day(fixture.finished ?? fixture.started), forKey: "updatedAt")
}
try context.save()
print("ui-fixture-store: wrote \(books.count) books to \(storeURL.path)")
