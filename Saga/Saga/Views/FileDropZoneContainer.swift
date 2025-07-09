//
//  FileDropZoneContainer.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import SwiftUI

struct FileDropZoneContainer<Content: View>: View {
    private let onDrop: ([URL]) async -> Void
    @State private var isDropTargeted = false
    @State private var isProcessingFiles = false
    let content: Content

    init(onDrop: (@escaping ([URL]) async -> Void), @ViewBuilder content: () -> Content) {
        self.content = content()
        self.onDrop = onDrop
    }

    var body: some View {
        ZStack {
            content
            
            if isDropTargeted || isProcessingFiles {
                overlay
            }

            // Shows a drop zone if targeted
            if isDropTargeted {
                DropZone {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.white.opacity(0.65))
                    Text("Drop file to upload")
                        .foregroundColor(.white.opacity(0.65))
                        .fontWeight(.bold)
                }
            }
            
            // Show a spinner if processing
            if isProcessingFiles {
                DropZone {
                    ProgressView()
                        .controlSize(.regular)
                        .foregroundColor(.white.opacity(0.65))
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            isProcessingFiles = true
            Task {
                var fileUrls: [URL] = []
                for provider in providers {
                    if let url = await loadURLAsync(from: provider) {
                        fileUrls.append(url)
                    }
                }
                await onDrop(fileUrls)
                await MainActor.run {
                    isProcessingFiles = false
                }
            }
            return true
        }
        .animation(.snappy(duration: 0.2), value: isDropTargeted)
    }
    
    /// Dims the background
    private var overlay: some View {
#if os(macOS)
                Color(nsColor: .windowBackgroundColor)
                    .opacity(0.9)
                    .ignoresSafeArea()
                    .animation(.snappy, value: isDropTargeted)
#else
                Color(UIColor.systemBackground)
                    .ignoresSafeArea()
                    .opacity(0.9)
                    .animation(.snappy, value: isDropTargeted)
#endif
    }
    
    func loadURLAsync(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }
}

/// Stylized container
private struct DropZone<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack(spacing: 8) {
            content
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentColor.opacity(0.4))
                .shadow(radius: 12)
        )
        .transition(.scale(0.5).combined(with: .opacity))
    }
}
