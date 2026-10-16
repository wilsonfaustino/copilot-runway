import Core
import Foundation
import Testing

let latestReleaseFixture = fixturesDirectory.appending(path: "releases/latest.json")

@Test func newerReleaseIsReported() {
  #expect(ReleaseCheck.newerVersion(latestTag: "0.1.2", currentVersion: "0.1.1") == "0.1.2")
  #expect(ReleaseCheck.newerVersion(latestTag: "1.0.0", currentVersion: "0.9.9") == "1.0.0")
}

@Test func sameReleaseIsNotAnUpdate() {
  #expect(ReleaseCheck.newerVersion(latestTag: "0.1.1", currentVersion: "0.1.1") == nil)
}

@Test func olderReleaseIsNotAnUpdate() {
  #expect(ReleaseCheck.newerVersion(latestTag: "0.1.0", currentVersion: "0.1.1") == nil)
  #expect(ReleaseCheck.newerVersion(latestTag: "0.9.9", currentVersion: "1.0.0") == nil)
}

@Test func leadingVIsStripped() {
  #expect(ReleaseCheck.newerVersion(latestTag: "v0.1.2", currentVersion: "0.1.1") == "0.1.2")
  #expect(ReleaseCheck.newerVersion(latestTag: "v0.1.1", currentVersion: "0.1.1") == nil)
}

@Test func missingComponentsCountAsZero() {
  #expect(ReleaseCheck.newerVersion(latestTag: "v0.2", currentVersion: "0.2.0") == nil)
  #expect(ReleaseCheck.newerVersion(latestTag: "v0.2.0", currentVersion: "0.2") == nil)
  #expect(ReleaseCheck.newerVersion(latestTag: "v0.2.1", currentVersion: "0.2") == "0.2.1")
  #expect(ReleaseCheck.newerVersion(latestTag: "v1", currentVersion: "0.9.9") == "1")
}

@Test func twoDigitComponentsCompareAsNumbers() {
  #expect(ReleaseCheck.newerVersion(latestTag: "v0.1.10", currentVersion: "0.1.9") == "0.1.10")
  #expect(ReleaseCheck.newerVersion(latestTag: "v0.1.9", currentVersion: "0.1.10") == nil)
}

@Test(arguments: ["", "v", "latest", "1..2", "1.a", "0.2.0-beta", "v+1.0", "-1.0", " 1.0", "1.0."])
func unparsableVersionIsNotAnUpdate(garbage: String) {
  #expect(ReleaseCheck.newerVersion(latestTag: garbage, currentVersion: "0.1.1") == nil)
  #expect(ReleaseCheck.newerVersion(latestTag: "v9.9.9", currentVersion: garbage) == nil)
}

@Test func decodesTagFromReleaseFixture() throws {
  let data = try Data(contentsOf: latestReleaseFixture)
  let latestTag = try #require(ReleaseCheck.latestTag(from: data))
  #expect(latestTag == "v0.1.2")
  #expect(ReleaseCheck.newerVersion(latestTag: latestTag, currentVersion: "0.1.1") == "0.1.2")
}

@Test func releaseWithoutTagNameHasNoTag() {
  #expect(ReleaseCheck.latestTag(from: Data(#"{"name": "Copilot Runway 0.1.2"}"#.utf8)) == nil)
  #expect(ReleaseCheck.latestTag(from: Data("not json".utf8)) == nil)
}

@Test func releaseRequestSendsNoAuthorizationHeader() {
  let request = ReleaseCheck.makeRequest()
  #expect(request.url?.absoluteString == "https://api.github.com/repos/wilsonfaustino/copilot-runway/releases/latest")
  #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
  #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
}
