//
//  BundleKey.swift
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

import Foundation

/// Documents all keys for the bundle and offers a convenience getter for fetching them, with string fallback to empty if missing
enum BundleKey: String {
  case spaceId = "ContentfulSpaceId"
  case accessToken = "ContentfulAccessToken"
  case sparkleFeedURL = "SUFeedURL"
  case sparklePublicEDKey = "SUPublicEDKey"
  case sparkleEnableAutomaticChecks = "SUEnableAutomaticChecks"
  case sparkleScheduledCheckInterval = "SUScheduledCheckInterval"

  /// Use this to get the actual value from the app bundle
  var bundleValue: String {
    return Bundle.main.object(forInfoDictionaryKey: self.rawValue) as? String ?? ""
  }
}
