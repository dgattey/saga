//
//  BookCoverPicker.swift
//  Saga
//
//  Created by Dylan Gattey on 10/20/26.
//

import SwiftUI
import UniformTypeIdentifiers

#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

/// Cover preview plus every way to change it: default cover search, paste, drag and drop,
/// a file picker, or a typed image URL.
struct BookCoverPicker: View {
  private static let previewSize = CGSize(
    width: 104,
    height: 104 / BookCoverImageView.coverAspectRatio
  )

  @ObservedObject var viewModel: BookEditorViewModel
  @State private var isDropTargeted = false
  @State private var isImportingFile = false

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      preview
      controls
    }
    .padding(.vertical, 4)
    .fileImporter(isPresented: $isImportingFile, allowedContentTypes: [.image]) { result in
      viewModel.importCoverFile(result)
    }
  }

  // MARK: - Preview

  private var preview: some View {
    previewImage
      .frame(width: Self.previewSize.width, height: Self.previewSize.height)
      .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
      .overlay {
        if viewModel.coverSearchState == .searching {
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay { ProgressView().controlSize(.small) }
        }
      }
      .overlay {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .strokeBorder(
            Color.botanicalDeepMoss,
            style: StrokeStyle(lineWidth: 2, dash: [6, 4])
          )
          .opacity(isDropTargeted ? 1 : 0)
      }
      .physicalCoverShadow()
      .onDrop(of: CoverInput.acceptedTypes, isTargeted: $isDropTargeted) { providers in
        Task { @MainActor in
          let input = await CoverInput.load(from: providers)
          viewModel.applyCoverInput(input)
        }
        return true
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Cover image")
      .accessibilityHint("Drop an image or image URL here to use it as the cover")
  }

  @ViewBuilder
  private var previewImage: some View {
    if let data = viewModel.previewImageData, let image = Image(coverImageData: data) {
      image
        .resizable()
        .aspectRatio(contentMode: .fill)
    } else {
      AssetImageView(url: viewModel.previewCoverURL, targetSize: Self.previewSize)
        .aspectRatio(contentMode: .fill)
    }
  }

  // MARK: - Controls

  private var controls: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button {
        viewModel.searchForCover()
      } label: {
        Label("Find Cover", systemImage: "magnifyingglass")
      }
      .disabled(viewModel.coverSearchState == .searching)

      HStack(spacing: 8) {
        Button {
          viewModel.pasteCover()
        } label: {
          Label("Paste", systemImage: "doc.on.clipboard")
        }
        Button {
          isImportingFile = true
        } label: {
          Label("Choose…", systemImage: "photo")
        }
      }

      TextField("Image URL", text: $viewModel.coverURLText)
        .lineLimit(1)
        #if os(iOS)
          .textContentType(.URL)
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        #endif

      if viewModel.hasCustomCover {
        Button(viewModel.mode.isCreating ? "Remove Cover" : "Use Synced Cover") {
          viewModel.resetCover()
        }
        .buttonStyle(.borderless)
      }

      Text(viewModel.coverMessage ?? "Or drag an image onto the cover.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

extension Image {
  /// Creates an image from encoded image bytes (JPEG, PNG, HEIC, TIFF, ...).
  init?(coverImageData data: Data) {
    #if canImport(AppKit)
      guard let image = NSImage(data: data) else { return nil }
      self.init(nsImage: image)
    #elseif canImport(UIKit)
      guard let image = UIImage(data: data) else { return nil }
      self.init(uiImage: image)
    #endif
  }
}
