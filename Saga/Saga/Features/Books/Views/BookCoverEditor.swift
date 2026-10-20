//
//  BookCoverEditor.swift
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

/// The editable cover, in the exact spot the read-mode cover sits. Accepts drag and drop, and a
/// floating pill offers cover search, paste, a file picker, and a URL popover. New books without
/// a cover get a dashed drop well instead.
struct BookCoverEditor: View {
  private static let size = BookEditorialMetrics.coverSize
  private static let cornerRadius = BookEditorialMetrics.coverCornerRadius

  @ObservedObject var viewModel: BookEditorViewModel
  @State private var isDropTargeted = false
  @State private var isImportingFile = false
  @State private var isShowingURLPopover = false
  @State private var urlText = ""

  var body: some View {
    VStack(spacing: 14) {
      cover
      caption
    }
    .frame(width: Self.size.width)
    .fileImporter(isPresented: $isImportingFile, allowedContentTypes: [.image]) { result in
      viewModel.importCoverFile(result)
    }
  }

  // MARK: - Cover

  private var cover: some View {
    ZStack(alignment: .bottom) {
      coverImage
      BookCoverActionBar(
        isCreating: viewModel.mode.isCreating,
        isSearching: viewModel.coverSearchState == .searching,
        onFind: { viewModel.searchForCover() },
        onPaste: { viewModel.pasteCover() },
        onChooseFile: { isImportingFile = true },
        onEnterURL: {
          urlText = viewModel.coverURLText
          isShowingURLPopover = true
        }
      )
      .popover(isPresented: $isShowingURLPopover, arrowEdge: .bottom) {
        urlPopover
      }
      .padding(8)
    }
    .frame(width: Self.size.width, height: Self.size.height)
    .overlay(alignment: .topTrailing) {
      if viewModel.hasCustomCover {
        clearButton
          .padding(8)
      }
    }
    .background {
      RoundedRectangle(cornerRadius: Self.cornerRadius + 6, style: .continuous)
        .strokeBorder(
          Color.botanicalLeaf.opacity(isDropTargeted ? 0.95 : 0.35),
          lineWidth: isDropTargeted ? 2.5 : 1.5
        )
        .padding(-6)
    }
    .scaleEffect(isDropTargeted ? 1.02 : 1)
    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDropTargeted)
    .onDrop(of: CoverInput.acceptedTypes, isTargeted: $isDropTargeted) { providers in
      Task { @MainActor in
        let input = await CoverInput.load(from: providers)
        viewModel.applyCoverInput(input)
      }
      return true
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Cover image")
    .accessibilityHint("Drop an image or image URL here to use it as the cover")
  }

  @ViewBuilder
  private var coverImage: some View {
    let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    if let data = viewModel.previewImageData, let image = Image(coverImageData: data) {
      image
        .resizable()
        .aspectRatio(contentMode: .fill)
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(shape)
        .overlay { searchingOverlay }
        .physicalCoverShadow()
    } else if let url = viewModel.previewCoverURL {
      AssetImageView(url: url, targetSize: Self.size)
        .aspectRatio(contentMode: .fill)
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(shape)
        .overlay { searchingOverlay }
        .physicalCoverShadow()
    } else {
      emptyWell
        .overlay { searchingOverlay }
    }
  }

  private var emptyWell: some View {
    let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    return
      shape
      .fill(Color.botanicalLeaf.opacity(isDropTargeted ? 0.14 : 0.06))
      .overlay {
        shape.strokeBorder(
          Color.botanicalLeaf.opacity(0.55),
          style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
        )
      }
      .overlay {
        VStack(spacing: 8) {
          Image(systemName: "photo.badge.plus")
            .font(.system(size: 30, weight: .light))
            .foregroundStyle(Color.botanicalLeaf)
          Text("Drop or Paste Cover")
            .font(.callout.weight(.medium))
          Text("Or find one by title and author")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 56)
      }
      .frame(width: Self.size.width, height: Self.size.height)
  }

  @ViewBuilder
  private var searchingOverlay: some View {
    if viewModel.coverSearchState == .searching {
      RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        .fill(.ultraThinMaterial)
        .overlay {
          VStack(spacing: 8) {
            ProgressView()
              .controlSize(.small)
            Text("Finding a cover…")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
    }
  }

  private var clearButton: some View {
    Button {
      viewModel.resetCover()
    } label: {
      Image(systemName: "xmark")
        .font(.system(size: 10, weight: .bold))
        .frame(width: 22, height: 22)
        .glassEffect(.regular.interactive(), in: Circle())
    }
    .buttonStyle(.plain)
    .help(viewModel.mode.isCreating ? "Remove cover" : "Use the synced cover")
    .accessibilityLabel(viewModel.mode.isCreating ? "Remove Cover" : "Use Synced Cover")
  }

  // MARK: - Caption & URL popover

  private var caption: some View {
    Text(viewModel.coverMessage ?? "Drag an image onto the cover to use it.")
      .font(.caption)
      .foregroundStyle(
        viewModel.coverMessage == nil
          ? HierarchicalShapeStyle.tertiary : HierarchicalShapeStyle.secondary
      )
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var urlPopover: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Cover from URL")
        .font(.headline)
      TextField("https://…", text: $urlText)
        .textFieldStyle(.roundedBorder)
        .frame(width: 280)
        .onSubmit(useURL)
        #if os(iOS)
          .textContentType(.URL)
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        #endif
      HStack {
        Spacer()
        Button("Cancel") {
          isShowingURLPopover = false
        }
        .keyboardShortcut(.cancelAction)
        Button("Use Image", action: useURL)
          .keyboardShortcut(.defaultAction)
          .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(16)
    .tint(Color.botanicalDeepMoss)
  }

  private func useURL() {
    if viewModel.useCoverURL(urlText) {
      isShowingURLPopover = false
    }
  }
}

/// The frosted pill floating on the cover while editing: find, paste, file, and URL.
struct BookCoverActionBar: View {
  let isCreating: Bool
  let isSearching: Bool
  let onFind: () -> Void
  let onPaste: () -> Void
  let onChooseFile: () -> Void
  let onEnterURL: () -> Void

  var body: some View {
    HStack(spacing: 0) {
      action(
        isCreating ? "Auto-Find" : "Find",
        systemImage: "sparkles",
        help: "Find a cover from the title, author, or ISBN",
        action: onFind
      )
      .disabled(isSearching)
      action("Paste", systemImage: "doc.on.clipboard", help: "Paste an image or image URL") {
        onPaste()
      }
      action("File…", systemImage: "folder", help: "Choose an image file") {
        onChooseFile()
      }
      action("URL…", systemImage: "link", help: "Use an image from a web address") {
        onEnterURL()
      }
    }
    .padding(.horizontal, 4)
    .padding(.vertical, 3)
    .glassEffect(.regular, in: Capsule())
  }

  private func action(
    _ title: String,
    systemImage: String,
    help: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 2) {
        Image(systemName: systemImage)
          .font(.system(size: 13, weight: .medium))
        Text(title)
          .font(.system(size: 9.5, weight: .semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }
      .frame(width: 39, height: 34)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help)
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
