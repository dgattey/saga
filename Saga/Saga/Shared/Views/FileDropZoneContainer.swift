//
//  FileDropZoneContainer.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import SwiftUI

struct FileDropZoneContainer<Content: View>: View {
    private let onDrop: ([URL]) async -> Void
    private var completedSteps: Binding<Int>
    private var totalSteps: Binding<Int>
    @State private var isDropTargeted = false
    @State private var isProcessingFiles = false
    let content: Content

    init(
        onDrop: (@escaping ([URL]) async -> Void),
        completedSteps: Binding<Int>,
        totalSteps: Binding<Int>,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.onDrop = onDrop
        self.completedSteps = completedSteps
        self.totalSteps = totalSteps
    }

    var body: some View {
        ZStack {
            content
            
            if isDropTargeted || isProcessingFiles {
                overlay
            }

            // Shows a drop zone if targeted
            if isDropTargeted && !isProcessingFiles {
                DropZone {
                    Image(systemName: "document.badge.arrow.up")
                        .font(.system(size: 48))
                        .foregroundStyle(.accent)
                        .symbolEffect(
                            .bounce.down.byLayer,
                            options: .repeat(.periodic(delay: 0.75))
                        )
                    Text("Drop file to upload")
                }
            }
            
            // Determinate bar if we know progress
            else if isProcessingFiles && totalSteps.wrappedValue > 0 {
                DropZone {
                    Text(
                        "Processing \(completedSteps.wrappedValue)/\(totalSteps.wrappedValue)"
                    )
                    ProgressView(
                        value: Float(completedSteps.wrappedValue),
                        total: Float(totalSteps.wrappedValue)
                    )
                    .foregroundStyle(.accent)
                }
                
            }
            
            // Otherwise just a spinner
            else if isProcessingFiles {
                DropZone {
                    ProgressView()
                        .foregroundStyle(.accent)
                }
            }
        }
        .onKeyPress(.escape, action: {
            if isProcessingFiles {
                return .ignored
            }
            isDropTargeted = false
            return .handled
        })
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            if isProcessingFiles {
                return false
            }
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
                    completedSteps.wrappedValue = 0
                    totalSteps.wrappedValue = 0
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
                    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
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
        .padding(32)
        .frame(maxWidth: 200)
        .controlSize(.regular)
        .foregroundColor(.primary.opacity(0.8))
        .fontWeight(.bold)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.bar)
                .stroke(.primary.opacity(0.2), style: StrokeStyle())
                .defaultShadow()
        )
        .transition(.scale(0.5).combined(with: .opacity))
    }
}
