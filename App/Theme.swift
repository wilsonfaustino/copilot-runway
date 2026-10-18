import AppKit
import Core
import SwiftUI

enum Theme {
  enum Radius {
    static let bar: CGFloat = 3
    static let control: CGFloat = 8
    static let card: CGFloat = 10
    static let panel: CGFloat = 14
  }

  enum Spacing {
    static let tight: CGFloat = 4
    static let small: CGFloat = 6
    static let regular: CGFloat = 10
    static let section: CGFloat = 14
    static let panel: CGFloat = 16
  }

  static func accent(_ health: RunwayHealth) -> Color {
    Color(nsColor: accentNSColor(health))
  }

  // Dark values come from the mockup. Light values are darker so text keeps contrast on a white background.
  static func accentNSColor(_ health: RunwayHealth) -> NSColor {
    switch health {
    case .healthy: dynamicColor(dark: 0x64A8FF, light: 0x0062CC)
    case .short: dynamicColor(dark: 0xFF9F0A, light: 0xC45A00)
    case .critical: dynamicColor(dark: 0xFF6961, light: 0xD70015)
    case .unavailable: .secondaryLabelColor
    }
  }

  static let cardFill = Color.primary.opacity(0.05)
  static let cardBorder = Color.primary.opacity(0.08)

  // Split bar ramps, one hue per card. Dark values come from the mockup. Each light ramp is darker so its
  // lightest step keeps 2:1 contrast on a white background (checked with the dataviz palette validator).
  // Dark planning is lighter than the mockup, so it keeps 2:1 contrast on the dark card.
  static func taskColor(_ category: TaskCategory) -> Color {
    let nsColor =
      switch category {
      case .investigation: dynamicColor(dark: 0xCDE2FB, light: 0x61A7FF)
      case .debugging: dynamicColor(dark: 0x9EC5F4, light: 0x3F8DEB)
      case .implementation: dynamicColor(dark: 0x6DA7EC, light: 0x2374D0)
      case .review: dynamicColor(dark: 0x3987E5, light: 0x005BB4)
      case .uncategorized: dynamicColor(dark: 0x256ABF, light: 0x00468D)
      case .planning: dynamicColor(dark: 0x1C58A6, light: 0x003167)
      }
    return Color(nsColor: nsColor)
  }

  // By credit rank, because the model set changes. ShareBreakdown.namedModelLimit is the count.
  private static let modelRamp = [
    Color(nsColor: dynamicColor(dark: 0x7FD3AE, light: 0x3FB787)),
    Color(nsColor: dynamicColor(dark: 0x199E70, light: 0x028A60)),
    Color(nsColor: dynamicColor(dark: 0x0F7050, light: 0x015C3F)),
  ]

  // The dashboard and the popover both draw the model breakdown, so a model has one color in both.
  static func modelColors(for breakdown: ShareBreakdown) -> [ShareItem.ID: Color] {
    let namedModelIDs = breakdown.items.filter { $0.kind == .entry }.map(\.id)
    return Dictionary(uniqueKeysWithValues: zip(namedModelIDs, modelRamp))
  }

  static func agentColor(_ source: SessionSource) -> Color {
    switch source {
    case .opencode: Color(nsColor: dynamicColor(dark: 0xF2A27E, light: 0xF57242))
    case .pi: Color(nsColor: dynamicColor(dark: 0xD95926, light: 0xC04200))
    }
  }

  // System grays switch with the appearance. The stripes, not a hue, tell the gap from the solid Other models gray.
  static let otherModelsColor = Color(nsColor: .tertiaryLabelColor)
  static let notInLocalSessionsStripe = Color(nsColor: .systemGray)

  private static func dynamicColor(dark: Int, light: Int) -> NSColor {
    NSColor(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      return rgbColor(isDark ? dark : light)
    }
  }

  private static func rgbColor(_ hex: Int) -> NSColor {
    NSColor(
      srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
      green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255,
      alpha: 1
    )
  }
}

extension View {
  func cardStyle(padding: CGFloat = Theme.Spacing.regular) -> some View {
    self
      .padding(padding)
      .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
      .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.cardBorder))
  }

  func bigFigureStyle(size: CGFloat = 30) -> some View {
    font(.system(size: size, weight: .bold, design: .rounded)).monospacedDigit()
  }

  func captionStyle() -> some View {
    font(.system(size: 11)).foregroundStyle(.secondary)
  }
}
