@testable import Core
import Foundation
import Testing

private let caskFullName = "wilsonfaustino/tap/copilot-runway"

// A stand-in for brew in its own folder. It logs its arguments and the Homebrew variables, prints a line and exits.
private struct FakeBrew {
  let directory: URL
  let logURL: URL
  var path: String { directory.appending(path: "brew").path }

  init(exitStatus: Int32, printsToStandardError: String = "", body: String? = nil) throws {
    directory = FileManager.default.temporaryDirectory.appending(path: "fake-brew-\(UUID().uuidString)")
    logURL = directory.appending(path: "log")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let logLine = #"echo "$*|$HOMEBREW_NO_ASK|$HOMEBREW_NO_UPGRADE_QUIT_CASKS|$HOMEBREW_NO_AUTO_UPDATE|$PATH" >> "\#(logURL.path)""#
    let script = body ?? "\(logLine)\necho '\(printsToStandardError)' >&2\nexit \(exitStatus)\n"
    try Data("#!/bin/sh\n\(script)".utf8).write(to: URL(fileURLWithPath: path))
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
  }

  func log() throws -> String { try String(contentsOf: logURL, encoding: .utf8) }
  func remove() { try? FileManager.default.removeItem(at: directory) }
}

private func makeAppBundle(version: String?) throws -> URL {
  let bundleURL = FileManager.default.temporaryDirectory.appending(path: "Runway-\(UUID().uuidString).app")
  let contentsURL = bundleURL.appending(path: "Contents")
  try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
  if let version {
    let plist: NSDictionary = ["CFBundleShortVersionString": version]
    try plist.write(to: contentsURL.appending(path: "Info.plist"))
  }
  return bundleURL
}

@Test func findBrewPrefersAppleSiliconPath() {
  #expect(BrewUpgrade.findBrew { _ in true } == "/opt/homebrew/bin/brew")
  #expect(BrewUpgrade.findBrew { $0 == "/usr/local/bin/brew" } == "/usr/local/bin/brew")
  #expect(BrewUpgrade.findBrew { _ in false } == nil)
}

@Test func upgradeSendsCaskArgumentsAndNoPromptEnvironment() async throws {
  let fakeBrew = try FakeBrew(exitStatus: 0)
  defer { fakeBrew.remove() }
  #expect(await BrewUpgrade.upgrade(brewPath: fakeBrew.path, caskFullName: caskFullName) == .succeeded)
  #expect(try fakeBrew.log() == "upgrade --cask \(caskFullName)|1|1|1|\(fakeBrew.directory.path):/usr/bin:/bin:/usr/sbin:/sbin\n")
}

@Test func updateHomebrewRunsUpdateForce() async throws {
  let fakeBrew = try FakeBrew(exitStatus: 0)
  defer { fakeBrew.remove() }
  #expect(await BrewUpgrade.updateHomebrew(brewPath: fakeBrew.path) == .succeeded)
  #expect(try fakeBrew.log().hasPrefix("update --force|1|1|1|"))
}

@Test func upgradeIsFailedOnNonZeroExit() async throws {
  let fakeBrew = try FakeBrew(exitStatus: 1, printsToStandardError: "Error: Download failed")
  defer { fakeBrew.remove() }
  #expect(await BrewUpgrade.upgrade(brewPath: fakeBrew.path, caskFullName: caskFullName) == .failed)
}

@Test func upgradeIsFailedAtTheTimeLimit() async throws {
  let fakeBrew = try FakeBrew(exitStatus: 0, body: "trap 'exit 130' INT\n/bin/sleep 60 &\nwait\n")
  defer { fakeBrew.remove() }
  let clock = ContinuousClock()
  let start = clock.now
  #expect(await BrewUpgrade.upgrade(brewPath: fakeBrew.path, caskFullName: caskFullName, timeout: .seconds(1)) == .failed)
  #expect(clock.now - start < .seconds(5))
}

@Test func upgradeIsFailedWhenBrewCannotLaunch() async {
  #expect(await BrewUpgrade.upgrade(brewPath: "/nonexistent/brew", caskFullName: caskFullName) == .failed)
}

@Test func installedByCaskIsTrueWhenBrewListSucceeds() async throws {
  let fakeBrew = try FakeBrew(exitStatus: 0)
  defer { fakeBrew.remove() }
  #expect(await BrewUpgrade.isInstalledByCask(brewPath: fakeBrew.path, caskFullName: caskFullName))
  #expect(try fakeBrew.log().hasPrefix("list --cask \(caskFullName)|"))
}

@Test func installedByCaskIsFalseWhenBrewListFails() async throws {
  let fakeBrew = try FakeBrew(exitStatus: 1)
  defer { fakeBrew.remove() }
  #expect(await !BrewUpgrade.isInstalledByCask(brewPath: fakeBrew.path, caskFullName: caskFullName))
}

@Test func installedVersionIsNewerReadsThePlistOnDisk() throws {
  let newerBundle = try makeAppBundle(version: "1.3.0")
  let sameBundle = try makeAppBundle(version: "1.2.1")
  let olderBundle = try makeAppBundle(version: "1.0.0")
  defer { [newerBundle, sameBundle, olderBundle].forEach { try? FileManager.default.removeItem(at: $0) } }
  #expect(BrewUpgrade.installedVersionIsNewer(bundleURL: newerBundle, currentVersion: "1.2.1"))
  #expect(!BrewUpgrade.installedVersionIsNewer(bundleURL: sameBundle, currentVersion: "1.2.1"))
  #expect(!BrewUpgrade.installedVersionIsNewer(bundleURL: olderBundle, currentVersion: "1.2.1"))
}

@Test func installedVersionIsNewerIsFalseWithoutAPlist() throws {
  let emptyBundle = try makeAppBundle(version: nil)
  defer { try? FileManager.default.removeItem(at: emptyBundle) }
  #expect(!BrewUpgrade.installedVersionIsNewer(bundleURL: emptyBundle, currentVersion: "1.2.1"))
}

@Test func relaunchArgumentsPassPathAsArgument() {
  let arguments = BrewUpgrade.relaunchArguments(processIdentifier: 42, bundlePath: "/Applications/CopilotRunway Rehearsal.app")
  #expect(arguments.count == 5)
  #expect(arguments[0] == "-c")
  #expect(!arguments[1].contains("Rehearsal"))
  #expect(Array(arguments[2...]) == ["sh", "42", "/Applications/CopilotRunway Rehearsal.app"])
}

@Test func relaunchScriptWaitsForTheProcessToExit() async throws {
  let clock = ContinuousClock()
  // Start before run(), so a scheduling delay cannot shorten the measured wait.
  let start = clock.now
  let sleeper = Process()
  sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
  sleeper.arguments = ["1"]
  try sleeper.run()
  // open fails on a path that does not exist, so the script ends right after the wait loop.
  let output = try await GhRunner.run(
    path: "/bin/sh",
    arguments: BrewUpgrade.relaunchArguments(processIdentifier: sleeper.processIdentifier, bundlePath: "/nonexistent/Runway.app"),
    readsStandardError: false,
    timeout: .seconds(5)
  )
  #expect(clock.now - start >= .seconds(1))
  #expect(output.exitStatus != 0)
}
