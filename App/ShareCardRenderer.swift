import AppKit
import SwiftUI

enum ShareCardRenderer {
  // ImageRenderer does not capture the NSPopover chrome, so the card draws its own opaque background.
  // Theme colors come from NSColor providers that resolve with the drawing appearance, not the SwiftUI scheme.
  @MainActor
  static func image(usageStore: UsageStore) -> NSImage? {
    let appearance = NSApp.effectiveAppearance
    let colorScheme: ColorScheme = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    // windowBackgroundColor renders as #282828 in dark mode. ImageRenderer lifts dark values, so 23 renders as the target #1E1E1E.
    let darkBackground = Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
    let renderer = ImageRenderer(
      content: PopoverView(usageStore: usageStore, closePopover: {}, forShare: true)
        .background(colorScheme == .dark ? darkBackground : Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, colorScheme)
    )
    renderer.scale = 2
    renderer.isOpaque = true
    var image: NSImage?
    appearance.performAsCurrentDrawingAppearance { image = renderer.nsImage }
    return image
  }
}
