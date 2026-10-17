import Foundation

// Counts Copilot code reviews on your own PRs. No organization qualifier: automatic reviews bill the PR author
// on any repo. Only a number leaves Core. See Core/README.md for the query and its limits.
extension GitHubOutcomesClient {
  static let copilotReviewerLogin = "copilot-pull-request-reviewer"

  // updated filters on any PR activity, so the search finds candidates and the page keeps reviews submitted in the cycle.
  static let copilotReviewSelection = """
    pageInfo { hasNextPage endCursor }
    nodes {
      ... on PullRequest {
        reviews(first: 100) {
          nodes { author { login } submittedAt }
        }
      }
    }
    """

  static let copilotReviewDocument = """
    query($q: String!, $after: String) {
      search(query: $q, type: ISSUE, first: 100, after: $after) {
        \(copilotReviewSelection)
      }
    }
    """

  public static func copilotReviewSearchQuery(since cycleStart: Date) -> String {
    "author:@me is:pr updated:\(dateQualifier(cycleStart))"
  }

  public static func copilotReviewArguments(since cycleStart: Date, after cursor: String?) -> [String] {
    var arguments = ["api", "graphql", "-f", "query=\(copilotReviewDocument)", "-f", "q=\(copilotReviewSearchQuery(since: cycleStart))"]
    if let cursor { arguments += ["-f", "after=\(cursor)"] }
    return arguments
  }

  public struct CopilotReviewPage: Sendable {
    public let reviewCount: Int
    public let resultCount: Int
    public let nextCursor: String?
  }

  public static func copilotReviewPage(from data: Data, since cycleStart: Date) throws(GitHubOutcomesError) -> CopilotReviewPage {
    guard let search = try decodeGraphQL(CopilotReviewData.self, from: data).search else { throw GitHubOutcomesError.searchFailed }
    return copilotReviewPage(search, since: cycleStart)
  }

  static func copilotReviewPage(_ search: CopilotReviewData.Search, since cycleStart: Date) -> CopilotReviewPage {
    let reviews = search.nodes.flatMap { $0.reviews?.nodes ?? [] }
    let reviewCount = reviews.count { review in
      guard review.author?.login == copilotReviewerLogin, let submittedAt = review.submittedAt else { return false }
      return submittedAt >= cycleStart
    }
    let nextCursor = search.pageInfo.hasNextPage ? search.pageInfo.endCursor : nil
    return CopilotReviewPage(reviewCount: reviewCount, resultCount: search.nodes.count, nextCursor: nextCursor)
  }
}

// Decodes only the reviewer login and review date: no PR title, repo name or review text is kept.
struct CopilotReviewData: Decodable {
  struct Search: Decodable {
    let pageInfo: PageInfo
    let nodes: [Node]
  }
  struct PageInfo: Decodable {
    let hasNextPage: Bool
    let endCursor: String?
  }
  struct Node: Decodable {
    let reviews: Reviews?
  }
  struct Reviews: Decodable {
    let nodes: [Review]
  }
  struct Review: Decodable {
    let author: Author?
    let submittedAt: Date?
  }
  struct Author: Decodable {
    let login: String
  }
  let search: Search?
}
