//
//  Asset+Contentful.swift
//  Saga
//
//  Contentful serialization (push) and deserialization (pull) for Asset.
//  Keeps Asset.swift focused on Core Data model definition.
//

@preconcurrency import Contentful
import CoreData
import Foundation

// MARK: - ContentfulPushable Conformance

extension Asset: ContentfulPushable {
  static var resourceType: ContentfulResourceType { .asset }
  static var cmaContentTypeId: String? { nil }  // Assets don't have content type IDs
  static var entityName: String { "Asset" }

  var displayTitle: String? { title ?? fileName }

  func buildFieldsPayload() -> AssetFieldsPayload {
    // Note: This is only used for metadata updates, not for new uploads.
    // New asset uploads use the special uploadAsset flow.
    AssetFieldsPayload.metadata(title: title, description: assetDescription)
  }
}

// MARK: - Preview Pull (Contentful → Core Data)

extension Asset {
  /// Upserts an Asset from a Contentful Asset (used by preview pull)
  /// Skips objects that have local dirty changes to avoid overwriting unpushed edits.
  static func upsert(from contentfulAsset: Contentful.Asset, in context: NSManagedObjectContext) {
    let request = NSFetchRequest<Asset>(entityName: "Asset")
    request.predicate = NSPredicate(format: "id == %@", contentfulAsset.id)
    request.fetchLimit = 1

    let existing = (try? context.fetch(request))?.first

    // Skip if object has local dirty changes - push will handle it
    if let existing, existing.isDirty {
      return
    }

    let asset = existing ?? Asset(context: context)

    asset.id = contentfulAsset.id
    asset.localeCode = contentfulAsset.localeCode
    asset.updatedAt = contentfulAsset.sys.updatedAt
    asset.createdAt = contentfulAsset.sys.createdAt
    asset.title = contentfulAsset.title
    asset.assetDescription = contentfulAsset.description
    asset.urlString = contentfulAsset.urlString
    asset.fileName = contentfulAsset.file?.fileName
    asset.fileType = contentfulAsset.file?.contentType

    if let size = contentfulAsset.file?.details?.size {
      asset.size = NSNumber(value: size)
    }
    if let width = contentfulAsset.file?.details?.imageInfo?.width {
      asset.width = NSNumber(value: width)
    }
    if let height = contentfulAsset.file?.details?.imageInfo?.height {
      asset.height = NSNumber(value: height)
    }
  }
}

// MARK: - Push Data Extraction

/// Data needed to push an asset to Contentful via CMA
struct AssetPushData {
  let id: String
  let title: String?
  let assetDescription: String?
  let urlString: String?
  let fileName: String?
  let fileType: String?
  let updatedAt: Date?
}

extension Asset {
  /// Extracts push data from an Asset managed object
  static func fetchPushData(
    objectID: NSManagedObjectID, in context: NSManagedObjectContext
  ) async throws -> AssetPushData {
    try await context.perform {
      guard let asset = try? context.existingObject(with: objectID) as? Asset
      else {
        throw ContentfulManagementError.resourceNotFound(
          type: .asset, id: objectID.uriRepresentation().absoluteString)
      }

      return AssetPushData(
        id: asset.id,
        title: asset.title,
        assetDescription: asset.assetDescription,
        urlString: asset.urlString,
        fileName: asset.fileName,
        fileType: asset.fileType,
        updatedAt: asset.updatedAt
      )
    }
  }

  /// Updates an asset's URL and marks it clean (used after upload)
  static func updateURLAndMarkClean(
    objectID: NSManagedObjectID, url: String, version: Int, in container: NSPersistentContainer
  ) async {
    let bgContext = container.newBackgroundContext()
    await bgContext.perform {
      guard let asset = try? bgContext.existingObject(with: objectID) as? Asset
      else { return }

      asset.urlString = url
      asset.isDirty = false
      asset.contentfulVersion = version
      try? bgContext.save()
    }
  }
}

// MARK: - CMA Fields Payload

/// Codable representation of Asset fields for CMA requests (metadata only, not file upload)
struct AssetFieldsPayload: Codable {
  var title: Localized<String>?
  var description: Localized<String>?
  var file: Localized<AssetFile>?

  init(
    title: String? = nil,
    description: String? = nil,
    file: AssetFile? = nil
  ) {
    self.title = title.map { Localized($0) }
    self.description = description.map { Localized($0) }
    self.file = file.map { Localized($0) }
  }

  /// Convenience initializer for metadata-only updates
  static func metadata(title: String?, description: String?) -> AssetFieldsPayload {
    AssetFieldsPayload(title: title, description: description, file: nil)
  }

  /// Convenience initializer for new asset with upload link
  static func withUpload(
    title: String?,
    description: String?,
    fileName: String,
    contentType: String,
    uploadId: String
  ) -> AssetFieldsPayload {
    let file = AssetFile(
      contentType: contentType,
      fileName: fileName,
      uploadFrom: .upload(id: uploadId)
    )
    return AssetFieldsPayload(title: title, description: description, file: file)
  }
}

/// Represents the file field of an asset
struct AssetFile: Codable {
  let contentType: String
  let fileName: String
  let uploadFrom: ContentfulLink?
  let url: String?

  init(
    contentType: String,
    fileName: String,
    uploadFrom: ContentfulLink? = nil,
    url: String? = nil
  ) {
    self.contentType = contentType
    self.fileName = fileName
    self.uploadFrom = uploadFrom
    self.url = url
  }
}

// MARK: - Asset Response (for fetching URL after processing)

/// Response structure when fetching an asset to get its URL
struct AssetResponse: Codable {
  let sys: ContentfulSys
  let fields: AssetResponseFields?
}

struct AssetResponseFields: Codable {
  let file: Localized<AssetResponseFile>?
}

struct AssetResponseFile: Codable {
  let url: String?
}
