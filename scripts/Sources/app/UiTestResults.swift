import Common
import Foundation

func runUiTests(
  projectPath: String,
  derivedDataPath: String,
  arch: String,
  verbose: Bool,
  resultBundlePath: String,
  screenshotsPath: String
) throws {
  terminateProcess(named: "Saga")
  try waitForProcessToExit(named: "Saga")

  try FileManager.default.createDirectory(
    at: URL(fileURLWithPath: resultBundlePath).deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  if FileManager.default.fileExists(atPath: resultBundlePath) {
    try FileManager.default.removeItem(atPath: resultBundlePath)
  }

  print("Running Saga UI tests...")
  var args = [
    "-project", projectPath,
    "-scheme", "Saga",
    "-configuration", "Debug",
    "-destination", "platform=macOS,arch=\(arch)",
    "-derivedDataPath", derivedDataPath,
    "-resultBundlePath", resultBundlePath,
    "test",
  ]
  if !verbose {
    args.insert("-quiet", at: 0)
  }
  try runCommand("xcodebuild", args)
  try exportUiTestScreenshots(
    resultBundlePath: resultBundlePath,
    screenshotsPath: screenshotsPath,
    verbose: verbose
  )
}

struct UiTestAttachment {
  let id: String
  let filename: String
}

func exportUiTestScreenshots(
  resultBundlePath: String,
  screenshotsPath: String,
  verbose: Bool
) throws {
  let json = try runCommand(
    "xcrun",
    [
      "xcresulttool",
      "get",
      "object",
      "--legacy",
      "--path",
      resultBundlePath,
      "--format",
      "json",
    ],
    emitOutput: false
  )
  guard let data = json.data(using: .utf8) else {
    throw ScriptError("Failed to read xcresult JSON output.")
  }
  let object = try JSONSerialization.jsonObject(with: data, options: [])
  var attachments: [UiTestAttachment] = []
  var attachmentIds = Set<String>()
  var testReferenceIds: [String] = []
  collectReferenceIds(forKey: "testsRef", in: object, results: &testReferenceIds)
  let uniqueTestRefs = Array(Set(testReferenceIds))
  guard !uniqueTestRefs.isEmpty else {
    print("No test references found in xcresult.")
    return
  }

  var toVisit: [Any] = []
  var visitedReferences = Set<String>(uniqueTestRefs)

  for id in uniqueTestRefs {
    if let referencedObject = try? fetchReferencedObject(
      id: id,
      resultBundlePath: resultBundlePath
    ) {
      toVisit.append(referencedObject)
    }
  }

  while let current = toVisit.popLast() {
    var references: [String] = []
    collectAttachmentsAndReferences(
      in: current,
      attachments: &attachments,
      attachmentIds: &attachmentIds,
      references: &references
    )

    for id in references where !visitedReferences.contains(id) {
      visitedReferences.insert(id)
      if let referencedObject = try? fetchReferencedObject(
        id: id,
        resultBundlePath: resultBundlePath
      ) {
        toVisit.append(referencedObject)
      }
    }
  }
  let pngAttachments = attachments.filter { $0.filename.lowercased().hasSuffix(".png") }

  guard !pngAttachments.isEmpty else {
    print("No screenshot attachments found in xcresult.")
    return
  }

  try FileManager.default.createDirectory(
    at: URL(fileURLWithPath: screenshotsPath),
    withIntermediateDirectories: true
  )

  for (index, attachment) in pngAttachments.enumerated() {
    let filename = sanitizedScreenshotFilename(attachment.filename, index: index)
    let outputPath = URL(fileURLWithPath: screenshotsPath)
      .appendingPathComponent(filename)
      .path
    try runCommand(
      "xcrun",
      [
        "xcresulttool",
        "export",
        "object",
        "--legacy",
        "--path",
        resultBundlePath,
        "--id",
        attachment.id,
        "--output-path",
        outputPath,
        "--type",
        "file",
      ],
      emitOutput: verbose
    )
  }

  print("Exported \(pngAttachments.count) screenshot(s) to \(screenshotsPath).")
}

func collectAttachmentsAndReferences(
  in value: Any,
  attachments: inout [UiTestAttachment],
  attachmentIds: inout Set<String>,
  references: inout [String]
) {
  if let dict = value as? [String: Any] {
    if let typeName = typeName(from: dict), typeName == "Reference" {
      if let idValue = dict["id"], let id = extractString(from: idValue) {
        references.append(id)
      }
    }
    if let typeName = typeName(from: dict), typeName == "ActionTestAttachment" {
      if let filename = extractString(from: dict["filename"]),
        let payloadRef = dict["payloadRef"],
        let id = extractAttachmentId(from: payloadRef),
        !attachmentIds.contains(id)
      {
        attachments.append(UiTestAttachment(id: id, filename: filename))
        attachmentIds.insert(id)
      }
    }
    for child in dict.values {
      collectAttachmentsAndReferences(
        in: child,
        attachments: &attachments,
        attachmentIds: &attachmentIds,
        references: &references
      )
    }
  } else if let array = value as? [Any] {
    for item in array {
      collectAttachmentsAndReferences(
        in: item,
        attachments: &attachments,
        attachmentIds: &attachmentIds,
        references: &references
      )
    }
  }
}

func typeName(from dict: [String: Any]) -> String? {
  guard let type = dict["_type"] as? [String: Any] else { return nil }
  return extractString(from: type["_name"])
}

func collectReferenceIds(forKey key: String, in value: Any, results: inout [String]) {
  if let dict = value as? [String: Any] {
    if let target = dict[key], let id = extractAttachmentId(from: target) {
      results.append(id)
    }
    for child in dict.values {
      collectReferenceIds(forKey: key, in: child, results: &results)
    }
  } else if let array = value as? [Any] {
    for item in array {
      collectReferenceIds(forKey: key, in: item, results: &results)
    }
  }
}

func fetchReferencedObject(id: String, resultBundlePath: String) throws -> Any? {
  let referencedJson = try runCommand(
    "xcrun",
    [
      "xcresulttool",
      "get",
      "object",
      "--legacy",
      "--path",
      resultBundlePath,
      "--id",
      id,
      "--format",
      "json",
    ],
    emitOutput: false
  )
  guard let referencedData = referencedJson.data(using: .utf8) else {
    return nil
  }
  return try JSONSerialization.jsonObject(with: referencedData, options: [])
}

func extractAttachmentId(from value: Any) -> String? {
  if let dict = value as? [String: Any] {
    if let idValue = dict["id"], let id = extractString(from: idValue) {
      return id
    }
    if let id = extractString(from: dict["_value"]) {
      return id
    }
  }
  return extractString(from: value)
}

func extractString(from value: Any?) -> String? {
  guard let value else { return nil }
  if let string = value as? String {
    return string
  }
  if let dict = value as? [String: Any], let string = dict["_value"] as? String {
    return string
  }
  return nil
}

func sanitizedScreenshotFilename(_ filename: String, index: Int) -> String {
  let cleaned = filename.replacingOccurrences(of: "/", with: "_")
  let base = cleaned.isEmpty ? "screenshot-\(index)" : cleaned
  let normalized = base.lowercased().hasSuffix(".png") ? base : "\(base).png"
  return String(format: "%02d-%@", index + 1, normalized)
}
