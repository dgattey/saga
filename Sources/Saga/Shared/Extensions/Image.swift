//
//  Image.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

import SwiftUI

#if canImport(UIKit)
  import UIKit
  public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
  import AppKit
  public typealias PlatformImage = NSImage
#endif

extension Image {

  /// Delegates to the proper platform API for initializer
  init(platformImage: PlatformImage) {
    #if canImport(UIKit)
      self.init(uiImage: platformImage)
    #elseif canImport(AppKit)
      self.init(nsImage: platformImage)
    #endif
  }
}
