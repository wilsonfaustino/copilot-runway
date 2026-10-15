import Foundation

public enum MenuBarTitle {
  public static let placeholder = "--% · --d"

  public static func title(usage: CopilotUsage, now: Date) -> String {
    if usage.isUnlimited { return "∞" }
    let percentRemaining = Int(usage.percentRemaining.rounded())
    let daysLabel = Runway.daysLeft(usage: usage, now: now).map { "\(Int($0.rounded(.down)))d" } ?? "--d"
    return "\(percentRemaining)% · \(daysLabel)"
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
