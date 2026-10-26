//
//  Bundle.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import SwiftUI

extension Bundle {
  var appVersion: String {
    infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
  }

  var buildNumber: String {
    infoDictionary?["CFBundleVersion"] as? String ?? "1"
  }

  var formattedVersion: String {
    "v\(appVersion) (\(buildNumber))"
  }

  var iconFileName: String? {
    #if os(iOS)
      guard let icons = object(forInfoDictionaryKey: "CFBundleIcons") as? NSDictionary,
        let primaryIcon = icons["CFBundlePrimaryIcon"] as? NSDictionary,
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
