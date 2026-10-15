import Foundation

// Counts only. No PR title, repo name or commit message leaves Core.
public struct GitHubOutcomes: Equatable, Sendable {
  public let prsOpened: Int
  public let prsReviewed: Int
  public let commits: Int

  public init(prsOpened: Int, prsReviewed: Int, commits: Int) {
    self.prsOpened = prsOpened
    self.prsReviewed = prsReviewed
    self.commits = commits
  }

  // Commits are shown but are not outcomes.
  public var outcomeCount: Int { prsOpened + prsReviewed }

  public func creditsPerOutcome(creditsUsed: Double) -> Double? {
    outcomeCount > 0 ? creditsUsed / Double(outcomeCount) : nil
  }

  // Search results stop at GitHubOutcomesClient.resultLimit, so a count at the limit can be higher.
  public static func countText(_ count: Int) -> String {
    let countText = count.formatted(.number.locale(Locale(identifier: "en_US")))
    return count >= GitHubOutcomesClient.resultLimit ? "\(countText)+" : countText
  }
}

public enum GitHubOutcomesError: Error, Equatable, Sendable {
  case ghNotFound
  case notLoggedIn
  case organizationNotFound
  case rateLimited
  case searchFailed

  public var message: String {
    switch self {
    case .ghNotFound: "GitHub CLI not found. Install it with: brew install gh"
    case .notLoggedIn: "Not logged in to GitHub. Run: gh auth login"
    case .organizationNotFound: "Organization not found, or you have no access to it. Check Settings."
    case .rateLimited: "GitHub search rate limit reached. Outcomes retry in 30 minutes."
    case .searchFailed: "Cannot load GitHub outcomes. Outcomes retry in 30 minutes."
    }
  }
}

// The organization and cycle a fetch ran for, and when it started.
public struct OutcomesFetch: Equatable, Sendable {
  public let organization: String
  public let cycleStart: Date
  public let startDate: Date

  public init(organization: String, cycleStart: Date, startDate: Date) {
    self.organization = organization
    self.cycleStart = cycleStart
    self.startDate = startDate
  }

  // The search API has a low rate limit, so outcomes refresh much less often than credits.
  public static let refreshInterval: TimeInterval = 30 * 60

  public static func isDue(lastFetch: OutcomesFetch?, organization: String, cycleStart: Date, now: Date) -> Bool {
    guard let lastFetch else { return true }
    return lastFetch.organization != organization
      || lastFetch.cycleStart != cycleStart
      || now.timeIntervalSince(lastFetch.startDate) >= refreshInterval
  }
}
