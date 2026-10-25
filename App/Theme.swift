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

  static let taskPalettePreferenceKey = "taskPalettePreference"

  static func taskColor(_ category: TaskCategory, palette: TaskPalette) -> Color {
    switch palette {
    case .standard: standardTaskColor(category)
    case .colorblindSafe: colorblindSafeTaskColor(category)
    }
  }

  // One distinct hue per task, because any two tasks can touch. All pairs pass the dataviz palette validator:
  // normal vision 15.9 dark and 16.6 light, CVD 8.6 dark and 10.4 light. Dark investigation, debugging and
  // uncategorized have 2.49 to 2.68:1 contrast on the dark card: 3:1 there costs the pair separation.
  private static func standardTaskColor(_ category: TaskCategory) -> Color {
    let nsColor =
      switch category {
      case .implementation: dynamicColor(dark: 0x5D9ACE, light: 0x1D9CE3)
      case .debugging: dynamicColor(dark: 0x4662D6, light: 0x3E5CCE)
      case .investigation: dynamicColor(dark: 0x9A42A5, light: 0x841B7F)
      case .review: dynamicColor(dark: 0xE35C9F, light: 0xDE61AD)
      case .planning: dynamicColor(dark: 0xAC9312, light: 0x9E8A0A)
      case .uncategorized: dynamicColor(dark: 0x676767, light: 0x686868)
      }
    return Color(nsColor: nsColor)
  }

  // Okabe-Ito hue families, checked on all pairs with the dataviz palette validator, because any two tasks can touch.
  // Worst CVD delta E is 8.3 (deutan) in dark and 8.4 in light. Dark planning, implementation and debugging stay
  // near 2.5:1 on the dark card: 3:1 there costs the normal-vision floor. The legend and labels carry identity too.
  private static func colorblindSafeTaskColor(_ category: TaskCategory) -> Color {
    let nsColor =
      switch category {
      case .investigation: dynamicColor(dark: 0x177AEA, light: 0x0260C1)
      case .debugging: dynamicColor(dark: 0xC83501, light: 0x9D2700)
      case .implementation: dynamicColor(dark: 0x267847, light: 0x239761)
      case .review: dynamicColor(dark: 0xAC8704, light: 0xB26F04)
      case .uncategorized: dynamicColor(dark: 0xACACAC, light: 0x626262)
      case .planning: dynamicColor(dark: 0x925286, light: 0x802072)
      }
    return Color(nsColor: nsColor)
  }

  // Split bar ramp, one hue per card. Dark values come from the mockup. The light ramp is darker so its
  // lightest step keeps 2:1 contrast on a white background (checked with the dataviz palette validator).
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

  // One hue in three steps, light to dark, so lightness tells agents apart without hue. The ordinal check of the
  // dataviz palette validator passes in both modes. The legend names each agent too.
  // The dark omp vs Pi pair scores 14.5 against the 15 categorical floor. Accepted as an exception, as for the
  // green model ramp at 14.0.
  static func agentColor(_ source: SessionSource) -> Color {
    switch source {
    case .opencode: Color(nsColor: dynamicColor(dark: 0xF2A27E, light: 0xF57242))
    case .pi: Color(nsColor: dynamicColor(dark: 0xD95926, light: 0xC04200))
    case .omp: Color(nsColor: dynamicColor(dark: 0x9C3A12, light: 0x782800))
    }
  }

  // One blue hue in five steps, light to dark by credit rank, because the project set changes. The ordinal check of
  // the dataviz palette validator passes in both modes: lightest dark step 2.48:1 on the dark surface, lightest light
  // step 2.58:1 on white. Adjacent steps score 8.9 against the 15 categorical floor in both modes, accepted because
  // the legend names every project and the 2 pt gaps separate the parts. ProjectName.namedProjectLimit is the count.
  private static let projectRamp = [
    Color(nsColor: dynamicColor(dark: 0x9CC7FF, light: 0x5AA2F5)),
    Color(nsColor: dynamicColor(dark: 0x6EAEFF, light: 0x2F80E0)),
    Color(nsColor: dynamicColor(dark: 0x4A90EE, light: 0x1F64BF)),
    Color(nsColor: dynamicColor(dark: 0x3373CC, light: 0x164C96)),
    Color(nsColor: dynamicColor(dark: 0x2457A6, light: 0x0E356C)),
  ]

  // The named projects come first in ProjectName.breakdown. The folded "Other projects" item gets no color.
  static func projectColors(for breakdown: ShareBreakdown) -> [ShareItem.ID: Color] {
    Dictionary(uniqueKeysWithValues: zip(breakdown.items.prefix(ProjectName.namedProjectLimit).map(\.id), projectRamp))
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
