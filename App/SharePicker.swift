import AppKit
import SwiftUI

// AppKit keeps only a weak reference to the picker delegate, so the app delegate owns this for the whole flow.
@MainActor
final class SharePicker: NSObject, @preconcurrency NSSharingServicePickerDelegate {
  func show(image: NSImage, summary: String, relativeTo anchorView: NSView) {
    let picker = NSSharingServicePicker(items: [image, summary])
    picker.delegate = self
    picker.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
  }

  // Slack has no share extension, so the copy items are its path: copy, then paste.
  func sharingServicePicker(
    _ sharingServicePicker: NSSharingServicePicker,
    sharingServicesForItems items: [Any],
    proposedSharingServices proposedServices: [NSSharingService]
  ) -> [NSSharingService] {
    guard let image = items.first(where: { $0 is NSImage }) as? NSImage,
      let summary = items.first(where: { $0 is String }) as? String
    else { return proposedServices }
    let copyImage = NSSharingService(
      title: "Copy image", image: NSImage(systemSymbolName: "photo", accessibilityDescription: nil) ?? NSImage(),
      alternateImage: nil
    ) {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.writeObjects([image])
    }
    let copySummary = NSSharingService(
      title: "Copy summary", image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil) ?? NSImage(),
      alternateImage: nil
    ) {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(summary, forType: .string)
    }
    return proposedServices + [copyImage, copySummary]
  }
}

// A SwiftUI button has no NSView, and the picker needs one to point at.
@MainActor
final class ShareAnchor {
  weak var view: NSView?
}

struct ShareAnchorView: NSViewRepresentable {
  let anchor: ShareAnchor

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    anchor.view = view
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {}
}
