import Foundation

// Updates the app with Homebrew: `brew update --force`, then `brew upgrade --cask`, then a relaunch.
public enum BrewUpgrade {
  public enum Outcome: Equatable, Sendable {
    case succeeded
    case failed
  }

  static let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
  public static let caskFullName = "wilsonfaustino/tap/copilot-runway"
  public static let stepTimeout: Duration = .seconds(300)

  // HOMEBREW_NO_ASK: brew 7 asks [y/n] by default, and nobody can answer it here.
  // HOMEBREW_NO_UPGRADE_QUIT_CASKS: brew 7 quits running cask apps by default; the app quits itself after brew exits.
  // HOMEBREW_NO_AUTO_UPDATE: the explicit `update --force` step replaces auto update.
  // PATH: apps opened from Finder do not get the shell PATH.
  // Variables, not flags: an older brew rejects an unknown flag but ignores an unknown variable.
  static func environment(brewPath: String) -> [String: String] {
    let brewDirectory = URL(fileURLWithPath: brewPath).deletingLastPathComponent().path
    return [
      "HOMEBREW_NO_ASK": "1",
      "HOMEBREW_NO_UPGRADE_QUIT_CASKS": "1",
      "HOMEBREW_NO_AUTO_UPDATE": "1",
      "PATH": "\(brewDirectory):/usr/bin:/bin:/usr/sbin:/sbin",
    ]
  }

  public static func findBrew(isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)) -> String? {
    brewPaths.first(where: isExecutable)
  }

  public static func isInstalledByCask(brewPath: String, caskFullName: String) async -> Bool {
    await run(brewPath: brewPath, arguments: ["list", "--cask", caskFullName], timeout: GhRunner.defaultTimeout) == .succeeded
  }

  public static func updateHomebrew(brewPath: String, timeout: Duration = stepTimeout) async -> Outcome {
    await run(brewPath: brewPath, arguments: ["update", "--force"], timeout: timeout)
  }

  public static func upgrade(brewPath: String, caskFullName: String, timeout: Duration = stepTimeout) async -> Outcome {
    await run(brewPath: brewPath, arguments: ["upgrade", "--cask", caskFullName], timeout: timeout)
  }

  // brew exits 0 when the latest version is already installed, so exit 0 alone does not prove an upgrade.
  // Reads the plist from disk: Bundle caches its Info.plist.
  public static func installedVersionIsNewer(bundleURL: URL, currentVersion: String) -> Bool {
    let plistURL = bundleURL.appending(path: "Contents/Info.plist")
    guard
      let plist = NSDictionary(contentsOf: plistURL),
      let installedVersion = plist["CFBundleShortVersionString"] as? String
    else { return false }
    return ReleaseCheck.compareVersions(currentVersion, installedVersion) == .orderedAscending
  }

  // The path goes in as $2, never into the script text, so spaces and quotes in it are safe.
  public static func relaunchArguments(processIdentifier: Int32, bundlePath: String) -> [String] {
    let relaunchScript = #"while kill -0 "$1" 2>/dev/null; do sleep 0.2; done; exec /usr/bin/open "$2""#
    return ["-c", relaunchScript, "sh", String(processIdentifier), bundlePath]
  }

  private static func run(brewPath: String, arguments: [String], timeout: Duration) async -> Outcome {
    do throws(GhRunner.Failure) {
      let output = try await GhRunner.run(
        path: brewPath,
        arguments: arguments,
        readsStandardError: true,
        timeout: timeout,
        extraEnvironment: environment(brewPath: brewPath),
        interruptsAtTimeLimit: true
      )
      return output.exitStatus == 0 ? .succeeded : .failed
    } catch {
      return .failed
    }
  }
}
