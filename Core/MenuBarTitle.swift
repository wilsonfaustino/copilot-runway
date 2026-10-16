import Foundation

public enum MenuBarTitle {
  public static let placeholder = "--% · --d"

  public static func title(usage: CopilotUsage, now: Date) -> String {
    if usage.isUnlimited { return "∞" }
    let percentRemaining = Int(usage.percentRemaining.rounded())
    let daysLabel = Runway.daysLeft(usage: usage, now: now).map { "\(Int($0.rounded(.down)))d" } ?? "--d"
    return "\(percentRemaining)% · \(daysLabel)"
  }

  // The share of credits left, 0...1, from the same percent the title shows. No usage yet gives 0.
  // An unlimited plan gives 1, to match its infinity title.
  public static func remainingFraction(usage: CopilotUsage?) -> Double {
    guard let usage else { return 0 }
    if usage.isUnlimited { return 1 }
    return min(max(usage.percentRemaining / 100, 0), 1)
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
