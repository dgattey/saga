//
//  GoodreadsUploadDropzoneContainer.swift
//  Saga
//
//  Created by Dylan Gattey on 8/20/25.
//

import SwiftUI


/// Wraps some view with the ability to upload files to Goodreads via our CSV
/// parser. Keeps track of number of steps completed/etc and shows progress.
struct GoodreadsUploadDropzoneContainer<Content: View>: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var completedCSVImportSteps = 0
    @State private var totalCSVImportSteps = 0
    
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        FileDropZoneContainer(
            onDrop: handleCsvFileDrop,
            completedSteps: $completedCSVImportSteps,
            totalSteps: $totalCSVImportSteps
        ) {
            content
        }
    }
    
    /// Discard all but the csv files, and parse them
    private func handleCsvFileDrop(_ fileUrls: [URL]) async {
        do {
            for fileUrl in fileUrls {
                if !fileUrl.pathExtension.lowercased().contains("csv") {
                    continue
                }
                try await GoodreadsCSVParser
                    .parse(
                        into: viewContext,
                        from: fileUrl,
                        completedSteps: $completedCSVImportSteps,
                        totalSteps: $totalCSVImportSteps
                    )
            }
        } catch {
            print("CSV file parse failed with error: \(error)")
        }
    }
}
