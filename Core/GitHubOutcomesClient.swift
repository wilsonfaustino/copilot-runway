import Foundation

// Runs `gh api graphql` and `gh api search/commits`. gh reads its own token, so this client never sees it.
// Only result counts leave this type. See Core/README.md for the requests and their limits.
public enum GitHubOutcomesClient {
  // GitHub search returns at most 1,000 results per query, so the reviewed and Copilot review pages stop there.
  public static let resultLimit = 1000

  // Runs gh with the arguments and returns stdout. Tests pass a closure that returns fixture JSON.
  typealias Run = ([String]) async throws(GitHubOutcomesError) -> Data

  public static func normalizedOrganization(_ text: String) -> String? {
    let organization = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return organization.isEmpty ? nil : organization
  }

  // The organization goes into search strings, so a space or ":" could add qualifiers.
  // GitHub logins use only ASCII letters, digits and hyphens, and do not start with a hyphen.
  public static func isValidOrganization(_ organization: String) -> Bool {
    guard let firstCharacter = organization.first, firstCharacter != "-" else { return false }
    return organization.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
  }

  // GraphQL search has no commit type. per_page=1 keeps the response small: only total_count is read.
  // --method=GET puts the fields in the URL query. Without it gh sends them as a POST body.
  public static func commitsArguments(organization: String, since cycleStart: Date) -> [String] {
    let query = "author:@me author-date:\(dateQualifier(cycleStart)) user:\(organization)"
    return ["api", "--method=GET", "search/commits", "-f", "q=\(query)", "-f", "per_page=1"]
  }

  static let loginArguments = ["api", "graphql", "-f", "query={ viewer { login } }"]

  // reviewed-by matches a PR reviewed at any time, and updated filters on any PR activity.
  // So the search finds candidates, and reviewedPage keeps a PR only if your last review is in the cycle.
  // reviews(author:) needs a login, and GraphQL cannot pass viewer.login to it in the same query.
  static let reviewedSelection = """
    pageInfo { hasNextPage endCursor }
    nodes {
      ... on PullRequest {
        reviews(author: $login, last: 1, states: [APPROVED, CHANGES_REQUESTED, COMMENTED, DISMISSED]) {
          nodes { submittedAt }
        }
      }
    }
    """

  static let reviewedDocument = """
    query($q: String!, $login: String!, $after: String) {
      search(query: $q, type: ISSUE, first: 100, after: $after) {
        \(reviewedSelection)
      }
    }
    """

  // GraphQL rejects a declared variable that the document does not use, so the organization searches
  // and their variables are left out when no organization is set.
  static func outcomesDocument(includesOrganization: Bool) -> String {
    guard includesOrganization else {
      return """
        query($copilotQuery: String!) {
          copilotReviews: search(query: $copilotQuery, type: ISSUE, first: 100) {
            \(copilotReviewSelection)
          }
        }
        """
    }
    return """
      query($openQuery: String!, $mergedQuery: String!, $reviewedQuery: String!, $login: String!, $copilotQuery: String!) {
        openPullRequests: search(query: $openQuery, type: ISSUE, first: 0) { issueCount }
        mergedPullRequests: search(query: $mergedQuery, type: ISSUE, first: 0) { issueCount }
        reviewed: search(query: $reviewedQuery, type: ISSUE, first: 100) {
          \(reviewedSelection)
        }
        copilotReviews: search(query: $copilotQuery, type: ISSUE, first: 100) {
          \(copilotReviewSelection)
        }
      }
      """
  }

  // state is "open" or "merged". A PR closed without a merge is in neither search, so it does not count.
  public static func pullRequestSearchQuery(organization: String, state: String, since cycleStart: Date) -> String {
    "org:\(organization) is:pr author:@me is:\(state) created:\(dateQualifier(cycleStart))"
  }

  public static func reviewedSearchQuery(organization: String, since cycleStart: Date) -> String {
    "org:\(organization) is:pr reviewed-by:@me -author:@me updated:\(dateQualifier(cycleStart))"
  }

  // -f sends each value as a GraphQL string variable, so no value is part of the query document.
  // Without an organization only the Copilot review search runs.
  public static func outcomesArguments(organization: String?, login: String?, since cycleStart: Date) -> [String] {
    var arguments = ["api", "graphql", "-f", "query=\(outcomesDocument(includesOrganization: organization != nil))"]
    if let organization, let login {
      arguments += [
        "-f", "openQuery=\(pullRequestSearchQuery(organization: organization, state: "open", since: cycleStart))",
        "-f", "mergedQuery=\(pullRequestSearchQuery(organization: organization, state: "merged", since: cycleStart))",
        "-f", "reviewedQuery=\(reviewedSearchQuery(organization: organization, since: cycleStart))",
        "-f", "login=\(login)",
      ]
    }
    return arguments + ["-f", "copilotQuery=\(copilotReviewSearchQuery(since: cycleStart))"]
  }

  public static func reviewedArguments(organization: String, login: String, since cycleStart: Date, after cursor: String?) -> [String] {
    var arguments = [
      "api", "graphql", "-f", "query=\(reviewedDocument)",
      "-f", "q=\(reviewedSearchQuery(organization: organization, since: cycleStart))", "-f", "login=\(login)",
    ]
    if let cursor { arguments += ["-f", "after=\(cursor)"] }
    return arguments
  }

  public static func dateQualifier(_ date: Date) -> String {
    ">=\(date.formatted(.iso8601))"
  }

  // total_count is exact, also above 1,000. Only the result list stops at 1,000.
  public static func totalCount(from data: Data) throws(GitHubOutcomesError) -> Int {
    guard let response = try? JSONDecoder().decode(TotalCountData.self, from: data) else {
      throw GitHubOutcomesError.searchFailed
    }
    return response.totalCount
  }

  public static func login(from data: Data) throws(GitHubOutcomesError) -> String {
    let response = try decodeGraphQL(LoginData.self, from: data)
    guard let login = response.viewer?.login, !login.isEmpty else { throw GitHubOutcomesError.searchFailed }
    return login
  }

  public struct ReviewedPage: Sendable {
    public let reviewedCount: Int
    public let resultCount: Int
    public let nextCursor: String?
  }

  public static func reviewedPage(from data: Data, since cycleStart: Date) throws(GitHubOutcomesError) -> ReviewedPage {
    guard let search = try decodeGraphQL(ReviewedData.self, from: data).search else { throw GitHubOutcomesError.searchFailed }
    return reviewedPage(search, since: cycleStart)
  }

  static func reviewedPage(_ search: ReviewedData.Search, since cycleStart: Date) -> ReviewedPage {
    let reviewedCount = search.nodes.count { node in
      guard let submittedAt = node.reviews?.nodes.last?.submittedAt else { return false }
      return submittedAt >= cycleStart
    }
    let nextCursor = search.pageInfo.hasNextPage ? search.pageInfo.endCursor : nil
    return ReviewedPage(reviewedCount: reviewedCount, resultCount: search.nodes.count, nextCursor: nextCursor)
  }

  // The first page of every search in one response. pullRequestCounts and reviewedPage are nil without an organization.
  public struct OutcomesResponse: Sendable {
    public let pullRequestCounts: (merged: Int, open: Int)?
    public let reviewedPage: ReviewedPage?
    public let copilotReviewPage: CopilotReviewPage
  }

  public static func outcomesResponse(
    from data: Data,
    includesOrganization: Bool,
    since cycleStart: Date
  ) throws(GitHubOutcomesError) -> OutcomesResponse {
    let response = try decodeGraphQL(OutcomesData.self, from: data)
    guard let copilotReviews = response.copilotReviews else { throw GitHubOutcomesError.searchFailed }
    let firstCopilotReviewPage = copilotReviewPage(copilotReviews, since: cycleStart)
    guard includesOrganization else {
      return OutcomesResponse(pullRequestCounts: nil, reviewedPage: nil, copilotReviewPage: firstCopilotReviewPage)
    }
    guard let openPullRequests = response.openPullRequests, let mergedPullRequests = response.mergedPullRequests,
      let reviewed = response.reviewed
    else {
      throw GitHubOutcomesError.searchFailed
    }
    return OutcomesResponse(
      pullRequestCounts: (merged: mergedPullRequests.issueCount, open: openPullRequests.issueCount),
      reviewedPage: reviewedPage(reviewed, since: cycleStart),
      copilotReviewPage: firstCopilotReviewPage
    )
  }

  // Rejects an errors list as well, so a response with exit status 0 never counts as 0 results.
  static func decodeGraphQL<Payload: Decodable>(_ type: Payload.Type, from data: Data) throws(GitHubOutcomesError) -> Payload {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let response = try? decoder.decode(GraphQLResponse<Payload>.self, from: data) else {
      throw GitHubOutcomesError.searchFailed
    }
    if let errors = response.errors, !errors.isEmpty {
      throw error(exitStatus: 0, standardError: errors.map(\.message).joined(separator: "\n"))
    }
    guard let payload = response.data else { throw GitHubOutcomesError.searchFailed }
    return payload
  }

  // stderr can hold the organization and the query, so it never goes to the UI.
  public static func error(exitStatus: Int32, standardError: String) -> GitHubOutcomesError {
    let lowercasedError = standardError.lowercased()
    // gh exits with 4 when it has no login.
    if exitStatus == 4 || lowercasedError.contains("401") || lowercasedError.contains("bad credentials") {
      return .notLoggedIn
    }
    if lowercasedError.contains("cannot be searched") { return .organizationNotFound }
    if lowercasedError.contains("rate limit") { return .rateLimited }
    return .searchFailed
  }

  public static func fetchActivity(
    organization: String?,
    login: String?,
    since cycleStart: Date
  ) async throws(GitHubOutcomesError) -> GitHubActivity {
    guard let ghPath = CopilotUsageClient.ghPaths.first(where: FileManager.default.isExecutableFile(atPath:)) else {
      throw GitHubOutcomesError.ghNotFound
    }
    return try await fetchActivity(organization: organization, login: login, since: cycleStart) { arguments throws(GitHubOutcomesError) in
      try await runGh(ghPath: ghPath, arguments: arguments)
    }
  }

  // One GraphQL request for the first page of every search, plus the commit count with an organization,
  // plus the login when the caller has none yet. Later pages run only for a search that has more.
  // An organization failure fails only the outcomes, so the Copilot review count still loads.
  static func fetchActivity(
    organization: String?,
    login knownLogin: String?,
    since cycleStart: Date,
    run: Run
  ) async throws(GitHubOutcomesError) -> GitHubActivity {
    var login = knownLogin
    var organizationSearch: (organization: String, login: String, commits: Int)?
    var organizationFailure: GitHubOutcomesError?
    if let organization {
      do throws(GitHubOutcomesError) {
        guard isValidOrganization(organization) else { throw GitHubOutcomesError.organizationNotFound }
        // Runs first: an unknown organization gives a 422 here, but 0 results in GraphQL search.
        let commits = try totalCount(from: await run(commitsArguments(organization: organization, since: cycleStart)))
        let searchLogin: String
        if let login {
          searchLogin = login
        } else {
          searchLogin = try self.login(from: await run(loginArguments))
        }
        login = searchLogin
        organizationSearch = (organization, searchLogin, commits)
      } catch {
        organizationFailure = error
      }
    }

    let arguments = outcomesArguments(organization: organizationSearch?.organization, login: organizationSearch?.login, since: cycleStart)
    let response = try outcomesResponse(from: await run(arguments), includesOrganization: organizationSearch != nil, since: cycleStart)

    var copilotReviewCount = response.copilotReviewPage.reviewCount
    var copilotResultCount = response.copilotReviewPage.resultCount
    var copilotCursor = response.copilotReviewPage.nextCursor
    while let cursor = copilotCursor, copilotResultCount < resultLimit {
      let page = try copilotReviewPage(from: await run(copilotReviewArguments(since: cycleStart, after: cursor)), since: cycleStart)
      copilotReviewCount += page.reviewCount
      copilotResultCount += page.resultCount
      copilotCursor = page.nextCursor
    }

    let outcomes: Result<GitHubOutcomes, GitHubOutcomesError>?
    if let organizationSearch, let pullRequestCounts = response.pullRequestCounts, let firstReviewedPage = response.reviewedPage {
      var reviewedCount = firstReviewedPage.reviewedCount
      var reviewedResultCount = firstReviewedPage.resultCount
      var reviewedCursor = firstReviewedPage.nextCursor
      while let cursor = reviewedCursor, reviewedResultCount < resultLimit {
        let pageArguments = reviewedArguments(
          organization: organizationSearch.organization, login: organizationSearch.login, since: cycleStart, after: cursor
        )
        let page = try reviewedPage(from: await run(pageArguments), since: cycleStart)
        reviewedCount += page.reviewedCount
        reviewedResultCount += page.resultCount
        reviewedCursor = page.nextCursor
      }
      outcomes = .success(
        GitHubOutcomes(
          prsMerged: pullRequestCounts.merged, prsOpen: pullRequestCounts.open, prsReviewed: reviewedCount,
          commits: organizationSearch.commits
        )
      )
    } else {
      outcomes = organizationFailure.map { .failure($0) }
    }
    return GitHubActivity(outcomes: outcomes, copilotReviewCount: copilotReviewCount, login: login)
  }

  static func runGh(
    ghPath: String,
    arguments: [String],
    timeout: Duration = GhRunner.defaultTimeout
  ) async throws(GitHubOutcomesError) -> Data {
    let output: GhRunner.Output
    do throws(GhRunner.Failure) {
      output = try await GhRunner.run(path: ghPath, arguments: arguments, readsStandardError: true, timeout: timeout)
    } catch {
      switch error {
      case .launchFailed: throw GitHubOutcomesError.ghNotFound
      case .timedOut: throw GitHubOutcomesError.searchFailed
      }
    }
    guard output.exitStatus == 0 else {
      // For a REST error gh prints only "HTTP 422" to stderr. The reason is in the response body on stdout.
      let errorText = String(decoding: output.standardError + output.standardOutput, as: UTF8.self)
      throw self.error(exitStatus: output.exitStatus, standardError: errorText)
    }
    return output.standardOutput
  }
}

private struct GraphQLResponse<Payload: Decodable>: Decodable {
  let data: Payload?
  let errors: [GraphQLError]?
}

private struct GraphQLError: Decodable {
  let message: String
}

private struct LoginData: Decodable {
  struct Viewer: Decodable {
    let login: String
  }
  let viewer: Viewer?
}

private struct TotalCountData: Decodable {
  let totalCount: Int

  enum CodingKeys: String, CodingKey {
    case totalCount = "total_count"
  }
}

// One key per alias in outcomesDocument. The organization keys are missing when no organization is set.
private struct OutcomesData: Decodable {
  struct IssueCount: Decodable {
    let issueCount: Int
  }
  let openPullRequests: IssueCount?
  let mergedPullRequests: IssueCount?
  let reviewed: ReviewedData.Search?
  let copilotReviews: CopilotReviewData.Search?
}

// Decodes only review dates: no PR title, repo name or review text is kept.
struct ReviewedData: Decodable {
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
    let submittedAt: Date?
  }
  let search: Search?
}
