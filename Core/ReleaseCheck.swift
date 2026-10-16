import Foundation

// Asks GitHub for the latest public release. The repository is public, so the request has no
// Authorization header and never reads the gh token.
public enum ReleaseCheck {
  static let latestReleaseURL = URL(string: "https://api.github.com/repos/wilsonfaustino/copilot-runway/releases/latest")!
  public static let upgradeCommand = "brew upgrade --cask copilot-runway"

  // Returns the newer version, or nil when the running version is current.
  // Throws on any network, status or decode failure, so the caller can keep its last result.
  public static func fetchNewerVersion(currentVersion: String) async throws -> String? {
    let session = URLSession(configuration: .ephemeral)
    defer { session.finishTasksAndInvalidate() }
    let (data, response) = try await session.data(for: makeRequest())
    guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
      throw URLError(.badServerResponse)
    }
    guard let latestTag = latestTag(from: data) else { throw URLError(.cannotParseResponse) }
    return newerVersion(latestTag: latestTag, currentVersion: currentVersion)
  }

  public static func makeRequest() -> URLRequest {
    var request = URLRequest(url: latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    return request
  }

  public static func latestTag(from data: Data) -> String? {
    try? JSONDecoder().decode(LatestRelease.self, from: data).tagName
  }

  // Returns the tag without its leading "v" when it is newer than the current version.
  // A version that does not parse never counts as an update.
  public static func newerVersion(latestTag: String, currentVersion: String) -> String? {
    guard
      let latestComponents = versionComponents(latestTag),
      let currentComponents = versionComponents(currentVersion)
    else { return nil }
    let componentCount = max(latestComponents.count, currentComponents.count)
    // Missing components count as 0, so 0.2 and 0.2.0 are the same version.
    let paddedLatest = latestComponents + Array(repeating: 0, count: componentCount - latestComponents.count)
    let paddedCurrent = currentComponents + Array(repeating: 0, count: componentCount - currentComponents.count)
    guard paddedCurrent.lexicographicallyPrecedes(paddedLatest) else { return nil }
    return latestComponents.map(String.init).joined(separator: ".")
  }

  // Int(_:) accepts "+1" and "-0", so every character must be an ASCII digit.
  static func versionComponents(_ version: String) -> [Int]? {
    let trimmedVersion = version.hasPrefix("v") ? String(version.dropFirst()) : version
    let parts = trimmedVersion.split(separator: ".", omittingEmptySubsequences: false)
    var components: [Int] = []
    for part in parts {
      guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let component = Int(part) else { return nil }
      components.append(component)
    }
    return components
  }
}

private struct LatestRelease: Decodable {
  let tagName: String

  enum CodingKeys: String, CodingKey {
    case tagName = "tag_name"
  }
}
