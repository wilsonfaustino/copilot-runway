import Foundation

// Same request as the OpenCode and Pi plugins in reference/, with the `gh` token.
// The token lives only inside fetchCurrentUsage(). Never log it or return it.
public enum CopilotUsageClient {
  static let usageURL = URL(string: "https://api.github.com/copilot_internal/user")!
  static let ghPaths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]

  public static func fetchCurrentUsage() async throws -> CopilotUsage {
    let token = try readGitHubToken()
    // Ephemeral: no disk cache for the response, no stored credentials.
    let session = URLSession(configuration: .ephemeral)
    defer { session.finishTasksAndInvalidate() }
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: makeRequest(token: token))
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

  public static func usage(from data: Data, statusCode: Int) throws -> CopilotUsage {
    if statusCode == 401 { throw CopilotUsageError.notLoggedIn }
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

  // GUI apps do not get the shell PATH, so look for gh in the usual install folders.
  static func readGitHubToken() throws -> String {
    guard let ghPath = ghPaths.first(where: FileManager.default.isExecutableFile(atPath:)) else {
      throw CopilotUsageError.ghNotFound
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: ghPath)
    process.arguments = ["auth", "token"]
    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      throw CopilotUsageError.ghNotFound
    }
    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let token = String(decoding: outputData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    guard process.terminationStatus == 0, !token.isEmpty else { throw CopilotUsageError.notLoggedIn }
    return token
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
