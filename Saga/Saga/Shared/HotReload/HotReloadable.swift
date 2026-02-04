//
//  HotReloadable.swift
//  Saga
//
//  Universal hot reload support using Inject library.
//  Apply `.hotReloadable()` to WindowGroup content views to enable
//  hot reload for the entire view hierarchy.
//

import Inject
import SwiftUI

// MARK: - Hot Reloadable View Wrapper

/// A wrapper view that enables hot reload for its content and all descendants.
/// Uses Inject's `@ObserveInjection` to listen for code changes and trigger view updates.
struct HotReloadableView<Content: View>: View {
  @ObserveInjection private var inject
  let content: () -> Content

  init(@ViewBuilder content: @escaping () -> Content) {
    self.content = content
  }

  var body: some View {
    content()
      .enableInjection()
  }
}

// MARK: - View Modifier

/// View modifier that wraps content in a hot-reloadable container.
struct HotReloadableModifier: ViewModifier {
  func body(content: Content) -> some View {
    HotReloadableView {
      content
    }
  }
}

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
  /// Note: Hot reload only works in DEBUG builds with InjectionIII running.
  /// In release builds, this modifier has no effect on performance.
  func hotReloadable() -> some View {
    modifier(HotReloadableModifier())
  }
}
