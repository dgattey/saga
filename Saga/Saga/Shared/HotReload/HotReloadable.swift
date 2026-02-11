//
//  HotReloadable.swift
//  Saga
//
//  Universal hot reload support using InjectionNext/InjectionIII.
//
//  ## Overview
//
//  Hot reload allows you to see code changes in the running app without
//  rebuilding. Save a Swift file → changes appear instantly.
//
//  ## Setup (One-Time)
//
//  1. Install InjectionNext from:
//     https://github.com/johnno1962/InjectionNext/releases
//     Move to /Applications
//
//  2. Open InjectionNext and configure:
//     - Uncheck "Launch Xcode" (we use Cursor + CLI builds)
//     - Click "...or Watch Project" → select `/path/to/saga/Saga`
//       (the folder containing Saga.xcodeproj)
//
//  3. Build once in Xcode GUI (Product → Build):
//     - This creates .xcactivitylog files that InjectionNext parses
//     - Only needed once, or when adding new source files
//     - After this, use `run app` for all builds
//
//  4. Run the app with `run app` — look for:
//     "[HotReload] Injection bundle loaded from ..."
//
//  ## Usage
//
//  The `.hotReloadable()` modifier is applied at the WindowGroup level
//  in SagaApp.swift. No per-view changes needed.
//
//  ## How It Works
//
//  1. InjectionNext watches for file saves in the project folder
//  2. When a .swift file changes, it recompiles just that file
//  3. The new code is injected into the running app
//  4. A notification triggers `.id()` change → SwiftUI recreates views
//
//  ## Caveats
//
//  - Requires Xcode GUI build first (creates build logs InjectionNext parses)
//  - Can only change function bodies, not add/remove properties or methods
//  - New files need another Xcode GUI build to be injectable
//  - InjectionNext icon should be orange when connected (purple = waiting)
//
//  ## Build Settings (Already Configured)
//
//  - OTHER_LDFLAGS: `-Xlinker -interposable` (enables function interposing)
//  - EMIT_FRONTEND_COMMAND_LINES: YES (for Xcode 16.3+)
//  - ENABLE_APP_SANDBOX: NO (Debug only)
//  - Separate Debug entitlements with library validation disabled
//
//  ## Troubleshooting
//
//  - No injection: Check InjectionNext is watching the right folder
//  - "Injection received" but no change: Save again (first injection
//    after adding new code sometimes needs a second save)
//  - Build errors during injection: Check InjectionNext's status icon
//    (yellow = compile error)
//
//  See: https://github.com/johnno1962/InjectionNext
//  See: https://github.com/johnno1962/HotSwiftUI
//

import SwiftUI

// MARK: - InjectionIII Boilerplate (from HotSwiftUI)

// When HotSwiftUI or Inject packages are available, use them directly.
// Otherwise, provide a standalone implementation for InjectionIII.
#if canImport(HotSwiftUI)
  @_exported import HotSwiftUI
#elseif canImport(Inject)
  @_exported import Inject
#else

  #if DEBUG
    import Combine

    /// Loads the injection bundle once on first access.
    /// Tries InjectionNext first, then falls back to InjectionIII.
    private var loadInjectionOnce: () = {
      guard objc_getClass("InjectionClient") == nil else {
        return
      }
      #if os(macOS) || targetEnvironment(macCatalyst)
        let bundleName = "macOSInjection.bundle"
      #elseif os(tvOS)
        let bundleName = "tvOSInjection.bundle"
      #elseif os(visionOS)
        let bundleName = "xrOSInjection.bundle"
      #elseif targetEnvironment(simulator)
        let bundleName = "iOSInjection.bundle"
      #else
        let bundleName = "maciOSInjection.bundle"
      #endif

      // Try InjectionNext first, then InjectionIII
      let candidates = [
        "/Applications/InjectionNext.app/Contents/Resources/" + bundleName,
        "/Applications/InjectionIII.app/Contents/Resources/" + bundleName,
      ]

      for bundlePath in candidates {
        if let bundle = Bundle(path: bundlePath), bundle.load() {
          LoggerService.log(
            "Injection bundle loaded from \(bundlePath)",
            level: .notice,
            surface: .hotReload
          )
          return
        }
      }

      LoggerService.log(
        "Could not load injection bundle — install InjectionNext from "
          + "https://github.com/johnno1962/InjectionNext/releases",
        level: .warning,
        surface: .hotReload
      )
    }()

    /// Global injection observer shared across all views.
    public let injectionObserver = InjectionObserver()

    /// Observes InjectionIII notifications and provides a changing counter
    /// to trigger view updates when code is injected.
    public class InjectionObserver: ObservableObject {
      @Published var injectionNumber = 0
      var cancellable: AnyCancellable?
      let publisher = PassthroughSubject<Void, Never>()

      init() {
        _ = loadInjectionOnce
        cancellable = NotificationCenter.default.publisher(
          for: Notification.Name("INJECTION_BUNDLE_NOTIFICATION")
        )
        .sink { [weak self] _ in
          guard let self else { return }
          self.injectionNumber += 1
          self.publisher.send()
          LoggerService.log(
            "Injection received (count: \(self.injectionNumber)) — refreshing views",
            level: .notice,
            surface: .hotReload
          )
        }
      }
    }

    extension SwiftUI.View {
      /// Wraps view in AnyView to enable injection (loads bundle on first call).
      public func eraseToAnyView() -> some SwiftUI.View {
        _ = loadInjectionOnce
        return AnyView(self)
      }

      /// Enables per-view injection via InjectionIII.
      public func enableInjection() -> some SwiftUI.View {
        eraseToAnyView()
      }

      /// Loads the InjectionIII bundle and enables injection for this view.
      public func loadInjection() -> some SwiftUI.View {
        eraseToAnyView()
      }

      /// Calls the provided closure whenever an injection event occurs.
      public func onInjection(bumpState: @escaping () -> Void) -> some SwiftUI.View {
        self
          .onReceive(injectionObserver.publisher, perform: bumpState)
          .eraseToAnyView()
      }
    }

    @available(iOS 13.0, *)
    @propertyWrapper
    public struct ObserveInjection: DynamicProperty {
      @ObservedObject private var iO = injectionObserver
      public init() {}
      public private(set) var wrappedValue: Int {
        get { 0 }
        set {}
      }
    }

  #else
    extension SwiftUI.View {
      @inline(__always)
      public func eraseToAnyView() -> some SwiftUI.View { self }
      @inline(__always)
      public func enableInjection() -> some SwiftUI.View { self }
      @inline(__always)
      public func loadInjection() -> some SwiftUI.View { self }
      @inline(__always)
      public func onInjection(bumpState: @escaping () -> Void) -> some SwiftUI.View {
        self
      }
    }

    @available(iOS 13.0, *)
    @propertyWrapper
    public struct ObserveInjection {
      public init() {}
      public private(set) var wrappedValue: Int {
        get { 0 }
        set {}
      }
    }
  #endif
#endif

// MARK: - Universal Hot Reload

/// A wrapper view that forces full view hierarchy recreation on injection.
/// Uses the injection counter as a SwiftUI `.id()` so that when InjectionIII
/// injects new code, the entire content tree is destroyed and recreated.
struct HotReloadableView<Content: View>: View {
  @ObservedObject private var observer = injectionObserver
  let content: () -> Content

  init(@ViewBuilder content: @escaping () -> Content) {
    self.content = content
  }

  var body: some View {
    content()
      .id(observer.injectionNumber)
  }
}

extension View {
  /// Enables universal hot reload for this view and all its descendants.
  ///
  /// Apply at the WindowGroup level. When InjectionIII injects new code,
  /// the entire view hierarchy is recreated via an `.id()` change.
  ///
  /// Requirements:
  /// - InjectionIII.app running and watching the project
  /// - Debug build configuration
  /// - `-Xlinker -interposable` in OTHER_LDFLAGS (already configured)
  /// - App sandbox disabled in Debug (already configured)
  func hotReloadable() -> some View {
    HotReloadableView { self }
  }
}
