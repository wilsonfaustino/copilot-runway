import AppKit
import Core
import Observation

// Runs the Homebrew update for the Update button and relaunches the app when a newer version is on disk.
@MainActor
@Observable
final class AppUpdater {
  enum State {
    case unknown, preparing, unavailable, ready, checking, updating, failed, noNewVersion
  }

  private(set) var state = State.unknown
  @ObservationIgnored private var brewPath: String?

  private var caskFullName: String {
    #if DEBUG
    return DemoLaunch.upgradeCaskFullName ?? BrewUpgrade.caskFullName
    #else
    return BrewUpgrade.caskFullName
    #endif
  }

  // Runs once per launch. .preparing is set before the first await, so a second control on screen cannot start a second check.
  func prepareIfNeeded() async {
    guard state == .unknown else { return }
    state = .preparing
    guard let foundBrewPath = BrewUpgrade.findBrew() else {
      state = .unavailable
      return
    }
    brewPath = foundBrewPath
    switch await BrewUpgrade.isInstalledByCask(brewPath: foundBrewPath, caskFullName: caskFullName) {
    case true: state = .ready
    case false: state = .unavailable
    // brew did not finish; the next time the controls appear, they ask again.
    case nil: state = .unknown
    }
  }

  var statusMessage: String? {
    switch state {
    case .failed: "Update failed."
    case .noNewVersion: "No new version yet."
    default: nil
    }
  }

  func update() async {
    guard [.ready, .failed, .noNewVersion].contains(state), let brewPath else { return }
    state = .checking
    guard await BrewUpgrade.updateHomebrew(brewPath: brewPath) == .succeeded else {
      state = .failed
      return
    }
    state = .updating
    guard await BrewUpgrade.upgrade(brewPath: brewPath, caskFullName: caskFullName) == .succeeded else {
      state = .failed
      return
    }
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    guard BrewUpgrade.installedVersionIsNewer(bundleURL: Bundle.main.bundleURL, currentVersion: currentVersion) else {
      state = .noNewVersion
      return
    }
    let relauncher = Process()
    relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
    relauncher.arguments = BrewUpgrade.relaunchArguments(
      processIdentifier: ProcessInfo.processInfo.processIdentifier,
      bundlePath: Bundle.main.bundlePath
    )
    do {
      try relauncher.run()
    } catch {
      state = .failed
      return
    }
    NSApplication.shared.terminate(nil)
  }
}
