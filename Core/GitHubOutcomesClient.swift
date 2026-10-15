import Foundation

// Runs `gh search`. gh reads its own token, so this client never sees it.
// Only result counts leave this type. See Core/README.md for the commands and their limits.
public enum GitHubOutcomesClient {
  // GitHub search returns at most 1,000 results per query.
  public static let resultLimit = 1000

  public enum Search: Sendable {
    case prsOpened
    case prsReviewed
    case commits
  }

  public static func normalizedOrganization(_ text: String) -> String? {
    let organization = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return organization.isEmpty ? nil : organization
  }

  // Every value uses the --flag=value form, so an organization that starts with "-" cannot become a flag.
  public static func arguments(for search: Search, organization: String, since cycleStart: Date) -> [String] {
    let since = dateQualifier(cycleStart)
    switch search {
    case .prsOpened:
      return ["search", "prs", "--owner=\(organization)", "--author=@me", "--created=\(since)", "--json=number", "--limit=\(resultLimit)"]
    case .prsReviewed:
      // Search has no review date qualifier, so the last update stands in for it.
      return [
        "search", "prs", "--owner=\(organization)", "--reviewed-by=@me", "--updated=\(since)", "--json=number",
        "--limit=\(resultLimit)", "--", "-author:@me",
      ]
    case .commits:
      return ["search", "commits", "--owner=\(organization)", "--author=@me", "--author-date=\(since)", "--json=sha", "--limit=\(resultLimit)"]
    }
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
    guard let ghPath = CopilotUsageClient.ghPaths.first(where: FileManager.default.isExecutableFile(atPath:)) else {
      throw GitHubOutcomesError.ghNotFound
    }
    func searchCount(_ search: Search) throws(GitHubOutcomesError) -> Int {
      try runSearch(ghPath: ghPath, arguments: arguments(for: search, organization: organization, since: cycleStart))
    }
    return GitHubOutcomes(
      prsOpened: try searchCount(.prsOpened),
      prsReviewed: try searchCount(.prsReviewed),
      commits: try searchCount(.commits)
    )
  }

  static func runSearch(ghPath: String, arguments: [String]) throws(GitHubOutcomesError) -> Int {
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
    return try count(from: outputData)
  }
}

// Decodes no fields: only the number of results is kept.
private struct SearchResult: Decodable {}
