import Foundation

public enum MenuBarTitle {
  public static let placeholder = "--% · --d"

  public static func title(usage: QuotaUsage, now: Date, mode: GaugeMode = .left, days: RunwayDays = .calendar) -> String {
    if usage.isUnlimited { return "∞" }
    let gaugePercent = Runway.wholeGaugePercent(usage: usage, mode: mode)
    if Runway.lastsTheCycle(usage: usage, now: now, days: days) { return "\(gaugePercent)%" }
    let daysLabel = Runway.wholeDaysLeft(usage: usage, now: now, days: days).map { "\($0)d" } ?? "--d"
    return "\(gaugePercent)% · \(daysLabel)"
  }

  // The share of credits left, 0...1, from the same percent the title shows. No usage yet gives 0.
  // An unlimited plan gives 1, to match its infinity title.
  public static func remainingFraction(usage: QuotaUsage?) -> Double {
    guard let usage else { return 0 }
    if usage.isUnlimited { return 1 }
    return min(max(usage.percentRemaining / 100, 0), 1)
  }

  // The fraction the gauges draw. Spent is 1 minus the clamped left fraction, so overage fills the gauge.
  // No usage yet and an unlimited plan both give an empty spent gauge.
  public static func gaugeFraction(usage: QuotaUsage?, mode: GaugeMode) -> Double {
    switch mode {
    case .left: return remainingFraction(usage: usage)
    case .spent:
      guard let usage, !usage.isUnlimited else { return 0 }
      return 1 - remainingFraction(usage: usage)
    }
  }

  // The gauge fraction split by provider. Without a combined budget the whole gauge is Copilot.
  public static func gaugeParts(usage: QuotaUsage?, combined: CombinedBudget?, mode: GaugeMode) -> GaugeParts {
    combined?.parts(mode: mode) ?? GaugeParts(copilot: gaugeFraction(usage: usage, mode: mode), portkey: 0)
  }

  public static func title(error: CopilotUsageError) -> String {
    switch error {
    case .ghNotFound: "gh missing"
    case .notLoggedIn: "gh login"
    case .network: "offline"
    case .httpStatus, .invalidResponse: "error"
    }
  }
}
