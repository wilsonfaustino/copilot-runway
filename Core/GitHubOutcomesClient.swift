import Foundation

// Runs `gh search` and `gh api graphql`. gh reads its own token, so this client never sees it.
// Only result counts leave this type. See Core/README.md for the commands and their limits.
public enum GitHubOutcomesClient {
  // GitHub search returns at most 1,000 results per query.
  public static let resultLimit = 1000

  public enum Search: Sendable {
    case prsOpened
    case commits
  }

  public static func normalizedOrganization(_ text: String) -> String? {
    let organization = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return organization.isEmpty ? nil : organization
  }

  // The organization goes into a search string for reviewed PRs, so a space or ":" could add qualifiers.
  // GitHub logins use only ASCII letters, digits and hyphens, and do not start with a hyphen.
  public static func isValidOrganization(_ organization: String) -> Bool {
    guard let firstCharacter = organization.first, firstCharacter != "-" else { return false }
    return organization.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
  }

  // Every value uses the --flag=value form, so an organization that starts with "-" cannot become a flag.
  public static func arguments(for search: Search, organization: String, since cycleStart: Date) -> [String] {
    let since = dateQualifier(cycleStart)
    switch search {
    case .prsOpened:
      return ["search", "prs", "--owner=\(organization)", "--author=@me", "--created=\(since)", "--json=number", "--limit=\(resultLimit)"]
    case .commits:
      return ["search", "commits", "--owner=\(organization)", "--author=@me", "--author-date=\(since)", "--json=sha", "--limit=\(resultLimit)"]
    }
  }

  static let loginArguments = ["api", "graphql", "-f", "query={ viewer { login } }"]

  // reviewed-by matches a PR reviewed at any time, and updated filters on any PR activity.
  // So the search finds candidates, and reviewedPage keeps a PR only if your last review is in the cycle.
  // reviews(author:) needs a login, and GraphQL cannot pass viewer.login to it in the same query.
  static let reviewedDocument = """
    query($q: String!, $login: String!, $after: String) {
      search(query: $q, type: ISSUE, first: 100, after: $after) {
        pageInfo { hasNextPage endCursor }
        nodes {
          ... on PullRequest {
            reviews(author: $login, last: 1, states: [APPROVED, CHANGES_REQUESTED, COMMENTED, DISMISSED]) {
              nodes { submittedAt }
            }
          }
        }
      }
    }
    """

  public static func reviewedSearchQuery(organization: String, since cycleStart: Date) -> String {
    "org:\(organization) is:pr reviewed-by:@me -author:@me updated:\(dateQualifier(cycleStart))"
  }

  // -f sends each value as a GraphQL string variable, so no value is part of the query document.
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

  public static func count(from data: Data) throws(GitHubOutcomesError) -> Int {
    guard let results = try? JSONDecoder().decode([SearchResult].self, from: data) else {
      throw GitHubOutcomesError.searchFailed
    }
    return results.count
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
    let reviewedCount = search.nodes.count { node in
      guard let submittedAt = node.reviews?.nodes.last?.submittedAt else { return false }
      return submittedAt >= cycleStart
    }
    let nextCursor = search.pageInfo.hasNextPage ? search.pageInfo.endCursor : nil
    return ReviewedPage(reviewedCount: reviewedCount, resultCount: search.nodes.count, nextCursor: nextCursor)
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

  // Blocks while gh runs, so call it off the main thread.
  public static func fetchOutcomes(organization: String, since cycleStart: Date) throws(GitHubOutcomesError) -> GitHubOutcomes {
    guard isValidOrganization(organization) else { throw GitHubOutcomesError.organizationNotFound }
    guard let ghPath = CopilotUsageClient.ghPaths.first(where: FileManager.default.isExecutableFile(atPath:)) else {
      throw GitHubOutcomesError.ghNotFound
    }
    func searchCount(_ search: Search) throws(GitHubOutcomesError) -> Int {
      try count(from: runGh(ghPath: ghPath, arguments: arguments(for: search, organization: organization, since: cycleStart)))
    }
    return GitHubOutcomes(
      prsOpened: try searchCount(.prsOpened),
      prsReviewed: try reviewedCount(ghPath: ghPath, organization: organization, since: cycleStart),
      commits: try searchCount(.commits)
    )
  }

  static func reviewedCount(ghPath: String, organization: String, since cycleStart: Date) throws(GitHubOutcomesError) -> Int {
    let login = try login(from: runGh(ghPath: ghPath, arguments: loginArguments))
    var reviewedCount = 0
    var resultCount = 0
    var cursor: String?
    repeat {
      let arguments = reviewedArguments(organization: organization, login: login, since: cycleStart, after: cursor)
      let page = try reviewedPage(from: runGh(ghPath: ghPath, arguments: arguments), since: cycleStart)
      reviewedCount += page.reviewedCount
      resultCount += page.resultCount
      cursor = page.nextCursor
    } while cursor != nil && resultCount < resultLimit
    return reviewedCount
  }

  static func runGh(ghPath: String, arguments: [String]) throws(GitHubOutcomesError) -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: ghPath)
    process.arguments = arguments
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    do {
      try process.run()
    } catch {
      throw GitHubOutcomesError.ghNotFound
    }
    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw error(exitStatus: process.terminationStatus, standardError: String(decoding: errorData, as: UTF8.self))
    }
    return outputData
  }
}

// Decodes no fields: only the number of results is kept.
private struct SearchResult: Decodable {}

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

// Decodes only review dates: no PR title, repo name or review text is kept.
private struct ReviewedData: Decodable {
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
