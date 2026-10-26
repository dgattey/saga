//
//  PersistentScrollView.swift
//  Saga
//
//  Created by Dylan Gattey on 1/24/26.
//

import SwiftUI

struct PersistentScrollView<Content: View>: View {
  @Environment(ScrollPositionStore.self) private var scrollStore

  let scrollKey: ScrollKey
  let axis: Axis.Set
  let showsIndicators: Bool
  let onRestore: (() -> Void)?
  let content: () -> Content

  init(
    scrollKey: ScrollKey,
    axis: Axis.Set = .vertical,
    showsIndicators: Bool = true,
    onRestore: (() -> Void)? = nil,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.scrollKey = scrollKey
    self.axis = axis
    self.showsIndicators = showsIndicators
    self.onRestore = onRestore
    self.content = content
  }

  var body: some View {
    PersistentScrollViewBody(
      scrollStore: scrollStore,
      scrollKey: scrollKey,
      axis: axis,
      showsIndicators: showsIndicators,
      initialOffset: scrollStore.position(for: scrollKey),
      onRestore: onRestore,
      content: content
    )
    .id(scrollKey)
  }
}

private final class ScrollLifecycleState {
  var isRestoring = false
  var didNotifyRestore = false
  var pendingRestoreNotify = false
}

private struct PersistentScrollViewBody<Content: View>: View {
  let scrollStore: ScrollPositionStore

  let scrollKey: ScrollKey
  let axis: Axis.Set
  let showsIndicators: Bool
  let onRestore: (() -> Void)?
  let content: () -> Content

  @State private var position: ScrollPosition
  @State private var lifecycle = ScrollLifecycleState()

  init(
    scrollStore: ScrollPositionStore,
    scrollKey: ScrollKey,
    axis: Axis.Set,
    showsIndicators: Bool,
    initialOffset: Double?,
    onRestore: (() -> Void)?,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.scrollStore = scrollStore
    self.scrollKey = scrollKey
    self.axis = axis
    self.showsIndicators = showsIndicators
    self.onRestore = onRestore
    self.content = content
    if let initialOffset {
      if axis.contains(.vertical) {
        _position = State(initialValue: ScrollPosition(y: CGFloat(initialOffset)))
      } else {
        _position = State(initialValue: ScrollPosition(x: CGFloat(initialOffset)))
      }
    } else {
      _position = State(
        initialValue: ScrollPosition(edge: axis.contains(.vertical) ? .top : .leading))
    }
  }

  var body: some View {
    ScrollView(axis, showsIndicators: showsIndicators) {
      content()
    }
    .scrollContentBackground(.hidden)
    .scrollPosition($position)
    .onScrollGeometryChange(for: Int.self) { geometry in
      let rawOffset = axis.contains(.vertical) ? geometry.contentOffset.y : geometry.contentOffset.x
      guard rawOffset.isFinite else { return 0 }
      return Int(rawOffset.rounded())
    } action: { _, newValue in
      if lifecycle.pendingRestoreNotify {
        lifecycle.pendingRestoreNotify = false
        notifyRestoreIfNeeded()
      }
      guard !lifecycle.isRestoring else { return }
      scrollStore.update(Double(newValue), for: scrollKey)
    }
    .onChange(of: scrollStore.resetToken) {
      restorePosition()
    }
    .onAppear {
      lifecycle.pendingRestoreNotify = true
    }
  }

  private func restorePosition() {
    lifecycle.isRestoring = true
    if let storedPosition = scrollStore.position(for: scrollKey) {
      if axis.contains(.vertical) {
        position = ScrollPosition(y: CGFloat(storedPosition))
      } else {
        position = ScrollPosition(x: CGFloat(storedPosition))
      }
    } else {
      position = ScrollPosition(edge: axis.contains(.vertical) ? .top : .leading)
    }

    let currentLifecycle = lifecycle
    DispatchQueue.main.async {
      currentLifecycle.isRestoring = false
      currentLifecycle.pendingRestoreNotify = true
    }
  }

  private func notifyRestoreIfNeeded() {
    guard !lifecycle.didNotifyRestore else { return }
    lifecycle.didNotifyRestore = true
    onRestore?()
  }
}
