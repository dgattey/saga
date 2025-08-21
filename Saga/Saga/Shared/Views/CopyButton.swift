//
//  CopyButton.swift
//  Saga
//
//  Created by Dylan Gattey on 8/20/25.
//

import SwiftUI

/// A generic button to copy some text, usually used inside a context menu on macOS
struct CopyButton: View {
    let labelText: String
    let value: String
    
    init(labelText: String = "Copy", value: String) {
        self.labelText = labelText
        self.value = value
    }
    
    var body: some View {
        Button {
            #if os(iOS)
            UIPasteboard.general.string = value
            #else
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(value, forType: .string)
            #endif
        } label: {
            Label(labelText, systemImage: "doc.on.doc")
        }
    }
}
