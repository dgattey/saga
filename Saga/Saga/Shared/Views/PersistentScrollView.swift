//
//  PersistentScrollView.swift
//  Saga
//
//  Created by Dylan Gattey on 1/24/26.
//

import SwiftUI

struct PersistentScrollView<Content: View>: View {
  @EnvironmentObject private var scrollStore: ScrollPositionStore

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

private struct PersistentScrollViewBody<Content: View>: View {
  @ObservedObject var scrollStore: ScrollPositionStore

  let scrollKey: ScrollKey
  let axis: Axis.Set
  let showsIndicators: Bool
  let onRestore: (() -> Void)?
  let content: () -> Content

  @State private var position: ScrollPosition
  @State private var isRestoring = false
  @State private var didNotifyRestore = false
  @State private var pendingRestoreNotify = false

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
    .scrollPosition($position)
    .onScrollGeometryChange(for: Double.self) { geometry in
      if axis.contains(.vertical) {
        return Double(geometry.contentOffset.y)
      }
      return Double(geometry.contentOffset.x)
    } action: { _, newValue in
      if pendingRestoreNotify {
        pendingRestoreNotify = false
        notifyRestoreIfNeeded()
      }
      guard !isRestoring, newValue.isFinite else { return }
      scrollStore.update(newValue, for: scrollKey)
    }
    .onChange(of: scrollStore.resetToken) {
      restorePosition()
    }
    .onAppear {
      pendingRestoreNotify = true
    }
  }

  private func restorePosition() {
    isRestoring = true
    if let storedPosition = scrollStore.position(for: scrollKey) {
      if axis.contains(.vertical) {
        position = ScrollPosition(y: CGFloat(storedPosition))
      } else {
        position = ScrollPosition(x: CGFloat(storedPosition))
      }
    } else {
      position = ScrollPosition(edge: axis.contains(.vertical) ? .top : .leading)
    }

    DispatchQueue.main.async {
      isRestoring = false
      pendingRestoreNotify = true
    }
  }

  private func notifyRestoreIfNeeded() {
    guard !didNotifyRestore else { return }
    didNotifyRestore = true
    onRestore?()
  }
}
