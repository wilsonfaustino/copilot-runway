import AppKit
import SwiftUI

// SwiftUI has no API for the scroller style, so this sets it on the NSScrollView behind the ScrollView.
struct OverlayScrollerStyle: NSViewRepresentable {
  func makeNSView(context: Context) -> OverlayScrollerStyleView {
    OverlayScrollerStyleView()
  }

  func updateNSView(_ nsView: OverlayScrollerStyleView, context: Context) {
    nsView.applyOverlayStyle()
  }
}

final class OverlayScrollerStyleView: NSView {
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
