import AppKit
import Core
import SwiftUI

// An open triangle over a short base line: a runway seen in perspective. Drawn on a 24 by 24 grid.
struct RunwayGlyph: Shape {
  func path(in rect: CGRect) -> Path {
    let scale = min(rect.width, rect.height) / 24
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
      CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
    }
    var path = Path()
    path.move(to: point(4, 18))
    path.addLine(to: point(12, 6))
    path.addLine(to: point(20, 18))
    path.move(to: point(8, 18))
    path.addLine(to: point(16, 18))
    return path
  }

  static let menuBarSize: CGFloat = 16

  // Menu bar labels turn SF Symbols into monochrome templates, so the tinted glyph is a non-template NSImage.
  // The drawing handler runs at draw time, so the dynamic accent color follows the menu bar appearance.
  static func menuBarImage(health: RunwayHealth) -> NSImage {
    let accentColor = Theme.accentNSColor(health)
    let size = NSSize(width: menuBarSize, height: menuBarSize)
    let image = NSImage(size: size, flipped: true) { rect in
      guard let context = NSGraphicsContext.current?.cgContext else { return false }
      context.addPath(RunwayGlyph().path(in: rect).cgPath)
      context.setStrokeColor(accentColor.cgColor)
      // 2 units on the 24 unit grid, as in the mockup.
      context.setLineWidth(2 * menuBarSize / 24)
      context.setLineCap(.round)
      context.setLineJoin(.round)
      context.strokePath()
      return true
    }
    image.isTemplate = false
    return image
  }

  // Neutral template symbols for states with no runway number.
  static func menuBarSymbolName(error: CopilotUsageError) -> String {
    switch error {
    case .ghNotFound: "terminal"
    case .notLoggedIn: "person"
    case .network: "wifi.slash"
    case .httpStatus, .invalidResponse: "exclamationmark.triangle"
    }
  }
}
