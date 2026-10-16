import Core
import Foundation
import Testing

// A missing override file gives the bundled prices, so the tests do not read the real prices.json.
let missingPriceURL = fixturesDirectory.appending(path: "missing/prices.json")
// After the last fixture record, so byDay holds every record.
let sessionCreditsNow = utcDate("2026-10-10T00:00:00Z")

@Test func sessionTotalsAddUpAcrossAggregates() throws {
  let openCodeDirectory = try makeOpenCodeDataDirectory()
  defer { try? FileManager.default.removeItem(at: openCodeDirectory) }
  let sessionCredits = SessionCredits.load(
    since: fixtureCycleStart,
    now: sessionCreditsNow,
    piDirectory: fixturesDirectory.appending(path: "pi/sessions"),
    openCodeDirectory: openCodeDirectory,
    priceURL: missingPriceURL
  )
  let modelTotal = sessionCredits.byModel.compactMap(\.credits).reduce(0, +)
  let categoryTotal = sessionCredits.byCategory.reduce(0) { $0 + $1.credits }
  let sourceTotal = sessionCredits.bySource.reduce(0) { $0 + $1.credits }
  let dayTotal = sessionCredits.byDay.reduce(0) { $0 + $1.credits }
  #expect(sessionCredits.warning == nil)
  #expect(sessionCredits.bySource.map(\.source).sorted { $0.rawValue < $1.rawValue } == [.opencode, .pi])
  #expect(modelTotal > 0)
  // Each aggregate sums in a different order, so the totals can differ in the last bits.
  #expect(abs(categoryTotal - modelTotal) < 1e-9)
  #expect(abs(sourceTotal - modelTotal) < 1e-9)
  #expect(abs(dayTotal - modelTotal) < 1e-9)
}

@Test func undecodablePiFileGivesAWarningAndKeepsOtherFiles() {
  let sessionCredits = SessionCredits.load(
    since: fixtureCycleStart,
    now: sessionCreditsNow,
    piDirectory: fixturesDirectory.appending(path: "pi/undecodable"),
    openCodeDirectory: fixturesDirectory.appending(path: "missing"),
    priceURL: missingPriceURL
  )
  #expect(sessionCredits.warning == "Cannot read some Pi sessions.")
  #expect(sessionCredits.byModel.map(\.model) == ["gpt-6-luna"])
}
