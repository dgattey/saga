//
//  HotReloadable.swift
//  Saga
//
//  Universal hot reload support using Inject library.
//  Apply `.hotReloadable()` to WindowGroup content views to enable
//  hot reload for the entire view hierarchy.
//

import Combine
import Inject
import SwiftUI

// MARK: - Injection Observer

/// Observes injection notifications and provides a changing ID to force view recreation.
final class InjectionObserver: ObservableObject {
  @Published private(set) var injectionCount = 0

  private var cancellable: AnyCancellable?

  init() {
    // Listen for InjectionIII bundle notifications
    cancellable = NotificationCenter.default
      .publisher(for: Notification.Name("INJECTION_BUNDLE_NOTIFICATION"))
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.injectionCount += 1
      }
  }
}

// MARK: - Hot Reloadable View Wrapper

/// A wrapper view that enables hot reload for its content and all descendants.
/// Uses injection notifications to force full view hierarchy recreation on code changes.
struct HotReloadableView<Content: View>: View {
  @ObserveInjection private var inject
  @StateObject private var observer = InjectionObserver()
  let content: () -> Content

  init(@ViewBuilder content: @escaping () -> Content) {
    self.content = content
  }

  var body: some View {
    content()
      .id(observer.injectionCount)
      .enableInjection()
  }
}

// MARK: - View Extension

extension View {
  /// Enables hot reload for this view and all its descendants.
  ///
  /// Apply this modifier at the WindowGroup level to enable universal hot reload
  /// without needing to modify individual views. When using InjectionIII or
  /// similar tools, saving any Swift file will trigger a refresh of all views
  /// in the hierarchy.
  ///
  /// Usage:
  /// ```swift
  /// WindowGroup {
  ///     ContentView()
  ///         .hotReloadable()
  /// }
  /// ```
  ///
  /// Requirements:
  /// - InjectionIII app running and connected to the project
  /// - Debug build configuration
  /// - Linker flags: -Xlinker -interposable (already configured in project)
  ///
  /// Note: Hot reload only works in DEBUG builds with InjectionIII running.
  /// In release builds, this modifier has no effect on performance.
  func hotReloadable() -> some View {
    HotReloadableView { self }
  }
}
