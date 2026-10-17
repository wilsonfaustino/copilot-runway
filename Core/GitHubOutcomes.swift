import Foundation

// Counts only. No PR title, repo name or commit message leaves Core.
public struct GitHubOutcomes: Equatable, Sendable {
  // PRs created in the cycle that are merged or open. A PR closed without a merge does not count.
  public let prsMerged: Int
  public let prsOpen: Int
  public let prsReviewed: Int
  public let commits: Int

  public init(prsMerged: Int, prsOpen: Int, prsReviewed: Int, commits: Int) {
    self.prsMerged = prsMerged
    self.prsOpen = prsOpen
    self.prsReviewed = prsReviewed
    self.commits = commits
  }

  public var prs: Int { prsMerged + prsOpen }

  // PRs reviewed and commits are shown as counts but are not in the divisor.
  public func creditsPerPRAuthored(creditsUsed: Double) -> Double? {
    prs > 0 ? creditsUsed / Double(prs) : nil
  }

  // PR and commit counts are exact totals from search, also above GitHubOutcomesClient.resultLimit.
  public static func countText(_ count: Int) -> String {
    count.formatted(.number.locale(Locale(identifier: "en_US")))
  }
}

// What one GitHub refresh returns.
public struct GitHubActivity: Equatable, Sendable {
  // nil when no organization is set.
  public let outcomes: Result<GitHubOutcomes, GitHubOutcomesError>?
  public let copilotReviewCount: Int
  // The login from the request, for the next refresh. nil until a refresh with an organization fetches it.
  public let login: String?

  public init(outcomes: Result<GitHubOutcomes, GitHubOutcomesError>?, copilotReviewCount: Int, login: String?) {
    self.outcomes = outcomes
    self.copilotReviewCount = copilotReviewCount
    self.login = login
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

// The organization and cycle a fetch ran for, and when it started. organization is nil when none is set.
public struct OutcomesFetch: Equatable, Sendable {
  public let organization: String?
  public let cycleStart: Date
  public let startDate: Date

  public init(organization: String?, cycleStart: Date, startDate: Date) {
    self.organization = organization
    self.cycleStart = cycleStart
    self.startDate = startDate
  }

  // The search API has a low rate limit, so outcomes refresh much less often than credits.
  public static let refreshInterval: TimeInterval = 30 * 60

  public static func isDue(lastFetch: OutcomesFetch?, organization: String?, cycleStart: Date, now: Date) -> Bool {
    guard let lastFetch else { return true }
    return lastFetch.organization != organization
      || lastFetch.cycleStart != cycleStart
      || now.timeIntervalSince(lastFetch.startDate) >= refreshInterval
  }
}
