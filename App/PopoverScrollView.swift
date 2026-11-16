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

// SwiftUI has no API for the scroller style, so this sets it on the NSScrollView behind the ScrollView.
private struct OverlayScrollerStyle: NSViewRepresentable {
  func makeNSView(context: Context) -> OverlayScrollerStyleView {
    OverlayScrollerStyleView()
  }

  func updateNSView(_ nsView: OverlayScrollerStyleView, context: Context) {
    nsView.applyOverlayStyle()
  }
}

private final class OverlayScrollerStyleView: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    NotificationCenter.default.addObserver(
      self, selector: #selector(preferredScrollerStyleDidChange),
      name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    applyOverlayStyle()
  }

  func applyOverlayStyle() {
    enclosingScrollView?.scrollerStyle = .overlay
  }

  // NSScrollView resets its style on this notification too, so the overlay style is applied after it.
  @objc private func preferredScrollerStyleDidChange() {
    DispatchQueue.main.async { [weak self] in self?.applyOverlayStyle() }
  }
}
