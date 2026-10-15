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
