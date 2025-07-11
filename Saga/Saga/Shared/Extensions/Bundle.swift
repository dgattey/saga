//
//  Bundle.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import SwiftUI

extension Bundle {
    var iconFileName: String? {
        #if os(iOS)
        guard let icons = infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
              let iconFileName = iconFiles.last
        else { return nil }
        return iconFileName
        #elseif os(macOS)
        guard let iconFile = infoDictionary?["CFBundleIconFile"] as? String else {
            return nil
        }
        return iconFile
        #endif
    }
}
