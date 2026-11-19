import AppKit
import SwiftUI

// The live popover only. The share card renders PopoverView directly, so it keeps its full height.
struct PopoverScrollView: View {
  let usageStore: UsageStore
  let content: PopoverView
  @State private var contentSize = CGSize.zero

  var body: some View {
    // The ScrollView has no ideal height of its own, so the content measures itself and the popover follows.
    ScrollView(.vertical) {
      content
        .background(OverlayScrollerStyle())
        .onGeometryChange(for: CGSize.self) { $0.size } action: { contentSize = $0 }
    }
    .scrollBounceBehavior(.basedOnSize)
    .frame(width: contentSize.width, height: min(contentSize.height, usageStore.popoverMaxHeight))
  }
}
