import Core
import Foundation
import SQLite3
import Testing

private let deepSeekModel = "@fireworks-ai-global/accounts/fireworks/models/deepseek-v4p1-flash-1017"
private let glmModel = "@fireworks-ai-global/accounts/fireworks/models/glm-5p3-flash"

// A temp folder with a copy of each subfolder of the sources, so one root can hold the Copilot and Portkey fixtures.
private func makeRoot(copying sources: [URL]) throws -> URL {
  let root = FileManager.default.temporaryDirectory.appending(path: "portkey-root-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  for source in sources {
    for name in try FileManager.default.contentsOfDirectory(atPath: source.path) {
      try FileManager.default.copyItem(at: source.appending(path: name), to: root.appending(path: name))
    }
  }
  return root
}

// The Copilot fixtures of Pi, omp and OpenCode, plus the Portkey fixtures when withPortkey is true.
private func loadFixtureSessionCredits(withPortkey: Bool) throws -> SessionCredits {
  let piRoot = try makeRoot(
    copying: [fixturesDirectory.appending(path: "pi/sessions")] + (withPortkey ? [fixturesDirectory.appending(path: "portkey/pi")] : [])
  )
  let ompRoot = try makeRoot(
    copying: [fixturesDirectory.appending(path: "omp/sessions")] + (withPortkey ? [fixturesDirectory.appending(path: "portkey/omp")] : [])
  )
  let openCodeDirectory = try makeOpenCodeDataDirectory()
  defer {
    for directory in [piRoot, ompRoot, openCodeDirectory] { try? FileManager.default.removeItem(at: directory) }
  }
  if withPortkey {
    let portkeySQL = try String(contentsOf: fixturesDirectory.appending(path: "portkey/opencode.sql"), encoding: .utf8)
    var database: OpaquePointer?
    try #require(sqlite3_open(openCodeDirectory.appending(path: "opencode.db").path, &database) == SQLITE_OK)
    defer { sqlite3_close(database) }
    try #require(sqlite3_exec(database, portkeySQL, nil, nil, nil) == SQLITE_OK)
  }
  return SessionCredits.load(
    since: fixtureCycleStart,
    // After the last Copilot and Portkey fixture record.
    now: utcDate("2026-10-20T00:00:00Z"),
    piDirectory: piRoot,
    openCodeDirectory: openCodeDirectory,
    ompDirectory: ompRoot,
    copilotDirectory: fixturesDirectory.appending(path: "missing"),
    priceURL: missingPriceURL
  )
}

private func expectUSD(_ actual: Double, _ expected: Double, sourceLocation: SourceLocation = #_sourceLocation) {
  #expect(abs(actual - expected) < 1e-9, "\(actual) is not \(expected)", sourceLocation: sourceLocation)
}

// Fixture spend in the cycle. Pi: DeepSeek 0.012, GLM 0.002 (provider "PortKey"), DeepSeek with no cost, and DeepSeek
// 0.004 also copied into omp. omp: the copy, then DeepSeek 0.006. OpenCode: DeepSeek 0.01, GLM 0.001, DeepSeek with
// no cost.
// Pi also has DeepSeek 0.5 on 2026-09-30, before the cycle.
@Test func portkeySpendTotalsComeFromStoredCosts() throws {
  let portkey = try loadFixtureSessionCredits(withPortkey: true).portkey
  expectUSD(portkey.totalUSD, 0.035)
  #expect(portkey.requestCount == 8)
  #expect(portkey.unpricedCount == 2)
  // Divided by the 6 priced requests.
  expectUSD(try #require(portkey.averageUSDPerRequest), 0.035 / 6)
}

@Test func portkeySpendSplitsByModel() throws {
  let byModel = try loadFixtureSessionCredits(withPortkey: true).portkey.byModel
  #expect(byModel.map(\.model) == [deepSeekModel, glmModel])
  #expect(byModel.map(\.requestCount) == [6, 2])
  expectUSD(byModel[0].usd, 0.032)
  expectUSD(byModel[1].usd, 0.003)
}

// The copied Pi and omp message counts once, as Pi, which loads first.
@Test func portkeySpendSplitsByAgent() throws {
  let bySource = try loadFixtureSessionCredits(withPortkey: true).portkey.bySource
  #expect(bySource.map(\.source) == [.pi, .opencode, .omp])
  #expect(bySource.map(\.requestCount) == [4, 3, 1])
  expectUSD(bySource[0].usd, 0.018)
  expectUSD(bySource[1].usd, 0.011)
  expectUSD(bySource[2].usd, 0.006)
}

@Test func portkeySpendSplitsByModelAndAgent() throws {
  let cells = try loadFixtureSessionCredits(withPortkey: true).portkey.byModelAndSource
  #expect(cells.map(\.model) == [deepSeekModel, deepSeekModel, deepSeekModel, glmModel, glmModel])
  #expect(cells.map(\.source) == [.pi, .opencode, .omp, .pi, .opencode])
  #expect(cells.map(\.requestCount) == [3, 2, 1, 1, 1])
  for (cell, expectedUSD) in zip(cells, [0.016, 0.01, 0.006, 0.002, 0.001]) {
    expectUSD(cell.usd, expectedUSD)
  }
}

// 0.032 of 0.035 USD is 91%. 0.035 USD over 6 priced requests is 0.0058 USD.
@Test func portkeyInsightNamesTopModelShareAndCostPerRequest() throws {
  let portkey = try loadFixtureSessionCredits(withPortkey: true).portkey
  #expect(
    portkey.insightSentence(locale: englishLocale)
      == "DeepSeek V4.1 Flash is 91% of Portkey spend, about $0.006 per request."
  )
}

@Test func noPortkeyMessagesGiveAnEmptySpend() throws {
  let portkey = try loadFixtureSessionCredits(withPortkey: false).portkey
  #expect(portkey.requestCount == 0)
  #expect(portkey.totalUSD == 0)
  #expect(portkey.averageUSDPerRequest == nil)
  #expect(portkey.insightSentence(locale: englishLocale) == nil)
}

@Test func portkeyMessagesLeaveEveryCopilotAggregateTheSame() throws {
  let withoutPortkey = try loadFixtureSessionCredits(withPortkey: false)
  let withPortkey = try loadFixtureSessionCredits(withPortkey: true)
  #expect(!withoutPortkey.byModel.isEmpty)
  #expect(withPortkey.byModel == withoutPortkey.byModel)
  #expect(withPortkey.byCategory == withoutPortkey.byCategory)
  #expect(withPortkey.byModelAndCategory == withoutPortkey.byModelAndCategory)
  #expect(withPortkey.bySource == withoutPortkey.bySource)
  #expect(withPortkey.byProject == withoutPortkey.byProject)
  #expect(withPortkey.bySession == withoutPortkey.bySession)
  #expect(withPortkey.byDay == withoutPortkey.byDay)
  #expect(withPortkey.previousByDay == withoutPortkey.previousByDay)
  #expect(withPortkey.cacheHits == withoutPortkey.cacheHits)
  #expect(withPortkey.lowCacheSentences == withoutPortkey.lowCacheSentences)
  #expect(withPortkey.modelEfficiencyNote == withoutPortkey.modelEfficiencyNote)
  #expect(withPortkey.cycleComparisonSentence == withoutPortkey.cycleComparisonSentence)
  #expect(withPortkey.warning == withoutPortkey.warning)
}

@Test func portkeyAmountsShowCentsOrTenthsOfACent() {
  #expect(PortkeySpend.formatted(0.73, locale: englishLocale) == "$0.73")
  #expect(PortkeySpend.formatted(0.004, locale: englishLocale) == "$0.004")
  // Rounds to 1 cent, so it shows as cents.
  #expect(PortkeySpend.formatted(0.0097, locale: englishLocale) == "$0.01")
  #expect(PortkeySpend.formatted(0, locale: englishLocale) == "$0.00")
}
