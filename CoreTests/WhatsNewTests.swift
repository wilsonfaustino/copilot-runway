import Core
import Testing

let testNotes: [String: [String]] = [
  "1.1.0": ["Gauge toggle in Settings."],
  "1.3.0": ["New Dashboard card.", "Faster refresh."],
]

func whatsNewDecision(
  current: String,
  lastSeen: String?,
  isExistingUser: Bool = true
) -> WhatsNew.Decision {
  WhatsNew.decide(currentVersion: current, lastSeenVersion: lastSeen, isExistingUser: isExistingUser, notes: testNotes)
}

@Test func freshInstallShowsNoBannerAndStoresCurrentVersion() {
  #expect(whatsNewDecision(current: "1.1.0", lastSeen: nil, isExistingUser: false) == WhatsNew.Decision(banner: nil, versionToStore: "1.1.0"))
}

@Test func upgradeWithNotesShowsBannerAndStoresOnDismiss() {
  #expect(whatsNewDecision(current: "1.1.0", lastSeen: "1.0.2") == WhatsNew.Decision(
    banner: WhatsNew(version: "1.1.0", lines: ["Gauge toggle in Settings."]),
    versionToStore: nil
  ))
}

@Test func existingUserWithoutStoredVersionCountsAsUpgrade() {
  #expect(whatsNewDecision(current: "1.1.0", lastSeen: nil, isExistingUser: true) == WhatsNew.Decision(
    banner: WhatsNew(version: "1.1.0", lines: ["Gauge toggle in Settings."]),
    versionToStore: nil
  ))
}

@Test func upgradeWithoutNotesShowsNoBannerAndStoresCurrentVersion() {
  #expect(whatsNewDecision(current: "1.1.1", lastSeen: "1.1.0") == WhatsNew.Decision(banner: nil, versionToStore: "1.1.1"))
}

@Test func releaseWithoutNotesDoesNotHideALaterReleaseWithNotes() {
  #expect(whatsNewDecision(current: "1.3.0", lastSeen: "1.1.1").banner?.version == "1.3.0")
}

@Test func skippedVersionsShowOnlyTheCurrentNotes() {
  #expect(whatsNewDecision(current: "1.3.0", lastSeen: "1.0.2") == WhatsNew.Decision(
    banner: WhatsNew(version: "1.3.0", lines: ["New Dashboard card.", "Faster refresh."]),
    versionToStore: nil
  ))
}

@Test func sameVersionShowsNoBanner() {
  #expect(whatsNewDecision(current: "1.1.0", lastSeen: "1.1.0") == WhatsNew.Decision(banner: nil, versionToStore: nil))
}

@Test func downgradeShowsNoBannerAndKeepsStoredVersion() {
  #expect(whatsNewDecision(current: "1.1.0", lastSeen: "1.3.0") == WhatsNew.Decision(banner: nil, versionToStore: nil))
}

@Test func unparsableCurrentVersionShowsNoBannerAndStoresNothing() {
  for current in ["", "?", "1.x", "v"] {
    #expect(whatsNewDecision(current: current, lastSeen: "1.0.0") == WhatsNew.Decision(banner: nil, versionToStore: nil))
  }
}

@Test func unparsableStoredVersionCountsAsNoStoredVersion() {
  #expect(whatsNewDecision(current: "1.1.0", lastSeen: "garbage", isExistingUser: true).banner?.version == "1.1.0")
  #expect(whatsNewDecision(current: "1.1.0", lastSeen: "garbage", isExistingUser: false) == WhatsNew.Decision(
    banner: nil,
    versionToStore: "1.1.0"
  ))
}

@Test func shortAndLongVersionStringsAreTheSameVersion() {
  #expect(whatsNewDecision(current: "1.1", lastSeen: "1.1.0") == WhatsNew.Decision(banner: nil, versionToStore: nil))
  #expect(whatsNewDecision(current: "1.1", lastSeen: "1.0.2").banner?.lines == ["Gauge toggle in Settings."])
}

@Test func everyBundledNotesKeyIsAVersion() {
  for version in WhatsNew.bundledNotes.keys {
    #expect(WhatsNew.decide(currentVersion: version, lastSeenVersion: "0.0.1", isExistingUser: true).banner != nil, "\(version)")
  }
}

@Test func noTwoBundledNotesKeysAreTheSameVersion() {
  let versions = Array(WhatsNew.bundledNotes.keys)
  for (index, version) in versions.enumerated() {
    for otherVersion in versions[(index + 1)...] {
      let isSameVersion =
        ReleaseCheck.newerVersion(latestTag: version, currentVersion: otherVersion) == nil
        && ReleaseCheck.newerVersion(latestTag: otherVersion, currentVersion: version) == nil
      #expect(!isSameVersion, "\(version) and \(otherVersion)")
    }
  }
}
