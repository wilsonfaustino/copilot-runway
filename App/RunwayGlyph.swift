import AppKit
import Core
import SwiftUI

// The menu bar credit gauge: a thick horseshoe whose arc shows the share of credits left.
// The gauge is drawn on a 24 unit grid.
struct RunwayGlyph {
  static let menuBarSize: CGFloat = 16

  // Menu bar labels turn SF Symbols into monochrome templates, so the tinted glyph is a non-template NSImage.
  // The drawing handler runs at draw time, so the dynamic accent color follows the menu bar appearance.
  // The track is a 270 degree horseshoe with its gap at the bottom. The arc starts at the lower left and grows
  // clockwise. At 0 only the track shows.
  static func menuBarImage(remainingFraction: Double, health: RunwayHealth) -> NSImage {
    let accentColor = Theme.accentNSColor(health)
    let size = NSSize(width: menuBarSize, height: menuBarSize)
    let image = NSImage(size: size, flipped: true) { rect in
      guard let context = NSGraphicsContext.current?.cgContext else { return false }
      let unitScale = menuBarSize / 24
      let center = CGPoint(x: rect.midX, y: rect.midY)
      let gaugeRadius = 8.5 * unitScale
      let trackStartDegrees = 135.0
      let trackSweepDegrees = 270.0
      func strokeArc(sweepDegrees: Double, color: NSColor) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(3 * unitScale)
        context.setLineCap(.round)
        context.addArc(
          center: center, radius: gaugeRadius,
          startAngle: trackStartDegrees * .pi / 180,
          endAngle: (trackStartDegrees + sweepDegrees) * .pi / 180,
          clockwise: false)
        context.strokePath()
      }
      strokeArc(sweepDegrees: trackSweepDegrees, color: accentColor.withAlphaComponent(0.28))
      if remainingFraction > 0 {
        strokeArc(sweepDegrees: trackSweepDegrees * remainingFraction, color: accentColor)
      }
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
