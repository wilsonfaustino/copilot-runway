import Foundation

public struct CopilotUsage: Equatable, Sendable {
  public let creditsUsed: Double
  public let entitlement: Double
  public let creditsRemaining: Double
  public let percentRemaining: Double
  public let isUnlimited: Bool
  public let resetDate: Date

  public init(
    creditsUsed: Double,
    entitlement: Double,
    creditsRemaining: Double,
    percentRemaining: Double,
    isUnlimited: Bool,
    resetDate: Date
  ) {
    self.creditsUsed = creditsUsed
    self.entitlement = entitlement
    self.creditsRemaining = creditsRemaining
    self.percentRemaining = percentRemaining
    self.isUnlimited = isUnlimited
    self.resetDate = resetDate
  }
}

public enum CopilotUsageError: Error, Equatable, Sendable {
  case ghNotFound
  case notLoggedIn
  case network
  case httpStatus(Int)
  case invalidResponse

  public var message: String {
    switch self {
    case .ghNotFound: "GitHub CLI not found. Install it with: brew install gh"
    case .notLoggedIn: "Not logged in to GitHub. Run: gh auth login"
    case .network: "Cannot reach api.github.com. Check your connection."
    case .httpStatus(let statusCode): "GitHub returned HTTP \(statusCode)."
    case .invalidResponse: "GitHub returned an unexpected response."
    }
  }
}
