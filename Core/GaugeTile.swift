import Foundation

// What a gauge mode picture tile in Settings draws: the user's real gauge, or a sample when there is none to show.
public struct GaugeTile: Equatable, Sendable {
  public let fraction: Double
  public let percent: Int
  public let isSample: Bool
  public let parts: GaugeParts

  public init(fraction: Double, percent: Int, isSample: Bool) {
    self.init(parts: GaugeParts(copilot: fraction, portkey: 0), percent: percent, isSample: isSample)
  }

  public init(parts: GaugeParts, percent: Int, isSample: Bool) {
    self.fraction = parts.total
    self.percent = percent
    self.isSample = isSample
    self.parts = parts
  }

  // No usage yet, an error or an unlimited plan has no real gauge to draw. The sample values only show the shape
  // of each choice: 62% left is the same gauge as 38% spent.
  public static func make(usage: QuotaUsage?, hasError: Bool, mode: GaugeMode, combined: CombinedBudget? = nil) -> GaugeTile {
    guard let usage, !hasError, !usage.isUnlimited else {
      switch mode {
      case .left: return GaugeTile(fraction: 0.62, percent: 62, isSample: true)
      case .spent: return GaugeTile(fraction: 0.38, percent: 38, isSample: true)
      }
    }
    if let combined {
      return GaugeTile(
        parts: combined.parts(mode: mode),
        percent: Runway.wholeGaugePercent(usage: combined.usage, mode: mode),
        isSample: false)
    }
    return GaugeTile(
      fraction: MenuBarTitle.gaugeFraction(usage: usage, mode: mode),
      percent: Runway.wholeGaugePercent(usage: usage, mode: mode),
      isSample: false)
  }
}
