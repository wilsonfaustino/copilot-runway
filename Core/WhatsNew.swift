import Foundation

// The banner the popover shows once after an update. The notes ship in the app, so it makes no network call.
public struct WhatsNew: Equatable, Sendable {
  public let version: String
  public let lines: [String]

  public init(version: String, lines: [String]) {
    self.version = version
    self.lines = lines
  }

  // A short list reads at a glance. The release notes link covers the rest.
  public static let maxLines = 3

  // Opens in the browser, so the app itself makes no network call.
  public var releaseNotesURL: URL {
    URL(string: "https://github.com/wilsonfaustino/copilot-runway/releases/tag/v\(version)")!
  }

  public struct Decision: Equatable, Sendable {
    public let banner: WhatsNew?
    // The new last-seen version to store now. Nil means keep the stored value.
    // When a banner shows, the app stores its version on dismiss instead.
    public let versionToStore: String?

    public init(banner: WhatsNew?, versionToStore: String?) {
      self.banner = banner
      self.versionToStore = versionToStore
    }
  }

  // One entry per release with user-visible changes, keyed by version, at most maxLines lines. Add it in the release commit.
  public static let bundledNotes: [String: [String]] = [
    "1.6.0": [
      "The Dashboard has General, Copilot and Portkey tabs in a sidebar.",
      "General shows USD spend by provider, model, agent, task and PR.",
      "Prices for MAI Code 2, Claude Fable 5.2 and the new Gemini 4 models.",
    ],
    "1.5.0": [
      "Without Copilot data, the app shows only your Portkey budget and spend.",
      "Prices for GPT-6.2 Astra and GPT-6.2 Sol.",
    ],
    "1.4.1": [
      "The popover scrolls on small screens instead of going off the top.",
    ],
    "1.4.0": [
      "With a Portkey budget set, one gauge shows Copilot and Portkey together.",
      "Right-click the menu bar icon for quick actions and shortcuts.",
    ],
    "1.3.0": [
      "Update to new versions from the app with one click.",
      "Portkey alerts and a setup prompt for its pricing.",
      "Runway can count only weekdays and skip your days off.",
    ],
    "1.2.1": [
      "Share image now includes the Portkey card.",
      "Settings window resizes in height and scrolls on small screens.",
    ],
    "1.2.0": [
      "Portkey card: USD spend by model and agent, apart from Copilot credits.",
      "Set a monthly Portkey budget in Settings to see its runway.",
    ]
  ]

  // isExistingUser separates a fresh install from an upgrade from a version older than this feature,
  // because both have no stored last-seen version.
  public static func decide(
    currentVersion: String,
    lastSeenVersion: String?,
    isExistingUser: Bool,
    notes: [String: [String]] = bundledNotes
  ) -> Decision {
    guard ReleaseCheck.versionComponents(currentVersion) != nil else {
      return Decision(banner: nil, versionToStore: nil)
    }
    let isUpgrade: Bool
    if let lastSeenVersion, let order = ReleaseCheck.compareVersions(lastSeenVersion, currentVersion) {
      // Same version or downgrade: keep the stored version, so old notes never show as new.
      guard order == .orderedAscending else { return Decision(banner: nil, versionToStore: nil) }
      isUpgrade = true
    } else {
      // A stored version that does not parse counts like no stored version.
      isUpgrade = isExistingUser
    }
    // Match keys by version, so a "1.1" entry also matches "1.1.0".
    let currentLines = notes.first { ReleaseCheck.compareVersions($0.key, currentVersion) == .orderedSame }?.value
    guard isUpgrade, let currentLines, !currentLines.isEmpty else {
      return Decision(banner: nil, versionToStore: currentVersion)
    }
    return Decision(banner: WhatsNew(version: currentVersion, lines: currentLines), versionToStore: nil)
  }
}
