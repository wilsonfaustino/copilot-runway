import Foundation

// Same request as the OpenCode and Pi Copilot credits plugins, with the `gh` token.
// The token lives only inside fetchCurrentUsage(). Never log it or return it.
public enum CopilotUsageClient {
  static let usageURL = URL(string: "https://api.github.com/copilot_internal/user")!
  static let ghPaths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]

  // A wake refresh can run before Wi-Fi is back, so the request waits for a connection up to this limit.
  static let resourceTimeout: TimeInterval = 30

  public static func fetchCurrentUsage() async throws(CopilotUsageError) -> CopilotUsage {
    guard let ghPath = ghPaths.first(where: FileManager.default.isExecutableFile(atPath:)) else {
      throw CopilotUsageError.ghNotFound
    }
    let token = try await readGitHubToken(ghPath: ghPath)
    // Ephemeral: no disk cache for the response, no stored credentials.
    let configuration = URLSessionConfiguration.ephemeral
    configuration.waitsForConnectivity = true
    configuration.timeoutIntervalForResource = resourceTimeout
    let session = URLSession(configuration: configuration)
    defer { session.finishTasksAndInvalidate() }
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: makeRequest(token: token), delegate: RedirectRefusal())
    } catch {
      throw CopilotUsageError.network
    }
    guard let httpResponse = response as? HTTPURLResponse else { throw CopilotUsageError.invalidResponse }
    return try usage(from: data, statusCode: httpResponse.statusCode)
  }

  public static func makeRequest(token: String) -> URLRequest {
    var request = URLRequest(url: usageURL, cachePolicy: .reloadIgnoringLocalCacheData)
    request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("vscode/1.99.0", forHTTPHeaderField: "Editor-Version")
    return request
  }

  public static func usage(from data: Data, statusCode: Int) throws(CopilotUsageError) -> CopilotUsage {
    if statusCode == 401 { throw CopilotUsageError.notLoggedIn }
    // RedirectRefusal stops every redirect, so a 3xx arrives here as the final response.
    if (300..<400).contains(statusCode) { throw CopilotUsageError.invalidResponse }
    guard (200..<300).contains(statusCode) else { throw CopilotUsageError.httpStatus(statusCode) }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    guard
      let body = try? decoder.decode(UserResponse.self, from: data),
      let resetDate = try? Date(body.quotaResetDateUtc, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true))
    else { throw CopilotUsageError.invalidResponse }
    let premium = body.quotaSnapshots.premiumInteractions
    return CopilotUsage(
      creditsUsed: premium.creditsUsed,
      entitlement: premium.entitlement,
      creditsRemaining: premium.quotaRemaining,
      percentRemaining: premium.percentRemaining,
      isUnlimited: premium.unlimited,
      resetDate: resetDate
    )
  }

  // GUI apps do not get the shell PATH, so fetchCurrentUsage() looks for gh in the usual install folders.
  // stderr goes to /dev/null, so no gh output can reach an error.
  static func readGitHubToken(ghPath: String, timeout: Duration = GhRunner.defaultTimeout) async throws(CopilotUsageError) -> String {
    let output: GhRunner.Output
    do throws(GhRunner.Failure) {
      output = try await GhRunner.run(path: ghPath, arguments: ["auth", "token"], readsStandardError: false, timeout: timeout)
    } catch {
      switch error {
      case .launchFailed: throw CopilotUsageError.ghNotFound
      case .timedOut: throw CopilotUsageError.network
      }
    }
    let token = String(decoding: output.standardOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    guard output.exitStatus == 0, !token.isEmpty else { throw CopilotUsageError.notLoggedIn }
    return token
  }
}

// Refuses every redirect, so the Authorization header never goes to a host other than api.github.com.
final class RedirectRefusal: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest
  ) async -> URLRequest? {
    nil
  }
}

private struct UserResponse: Decodable {
  let quotaResetDateUtc: String
  let quotaSnapshots: QuotaSnapshots

  struct QuotaSnapshots: Decodable {
    let premiumInteractions: PremiumInteractions
  }

  struct PremiumInteractions: Decodable {
    let creditsUsed: Double
    let entitlement: Double
    let quotaRemaining: Double
    let percentRemaining: Double
    let unlimited: Bool
  }
}
