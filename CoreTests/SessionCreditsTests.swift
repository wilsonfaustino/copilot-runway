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
    ompDirectory: fixturesDirectory.appending(path: "missing"),
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
    ompDirectory: fixturesDirectory.appending(path: "missing"),
    priceURL: missingPriceURL
  )
  #expect(sessionCredits.warning == "Cannot read some Pi sessions.")
  #expect(sessionCredits.byModel.map(\.model) == ["gpt-6-luna"])
}

// Most users have no ~/.omp folder.
@Test func missingOmpDirectoryGivesNoWarning() {
  let sessionCredits = SessionCredits.load(
    since: fixtureCycleStart,
    now: sessionCreditsNow,
    piDirectory: fixturesDirectory.appending(path: "pi/sessions"),
    openCodeDirectory: fixturesDirectory.appending(path: "missing"),
    ompDirectory: fixturesDirectory.appending(path: "missing/omp"),
    priceURL: missingPriceURL
  )
  #expect(sessionCredits.warning == nil)
  #expect(sessionCredits.bySource.map(\.source) == [.pi])
}

@Test func ompCreditsAppearBySource() throws {
  let sessionCredits = SessionCredits.load(
    since: fixtureCycleStart,
    // After the omp fixture records on 2026-10-19, so byDay holds every record.
    now: utcDate("2026-10-20T00:00:00Z"),
    piDirectory: fixturesDirectory.appending(path: "pi/sessions"),
    openCodeDirectory: fixturesDirectory.appending(path: "missing"),
    ompDirectory: fixturesDirectory.appending(path: "omp/sessions"),
    priceURL: missingPriceURL
  )
  let modelTotal = sessionCredits.byModel.compactMap(\.credits).reduce(0, +)
  let sourceTotal = sessionCredits.bySource.reduce(0) { $0 + $1.credits }
  #expect(sessionCredits.warning == nil)
  #expect(Set(sessionCredits.bySource.map(\.source)) == [.pi, .omp])
  // All 15 omp records are gpt-6-luna below the long context threshold: (45 * 0.10 + 143883 * 0.01 + 31672 * 0.125 + 1001 * 0.50) / 1e6 USD, at 0.01 USD per credit.
  let ompCredits = try #require(sessionCredits.bySource.first { $0.source == .omp }?.credits)
  #expect(abs(ompCredits - 0.590283) < 1e-9)
  #expect(abs(sourceTotal - modelTotal) < 1e-9)
}

@Test func undecodableOmpFileGivesAWarning() {
  let sessionCredits = SessionCredits.load(
    since: fixtureCycleStart,
    now: sessionCreditsNow,
    piDirectory: fixturesDirectory.appending(path: "missing"),
    openCodeDirectory: fixturesDirectory.appending(path: "missing"),
    ompDirectory: fixturesDirectory.appending(path: "pi/undecodable"),
    priceURL: missingPriceURL
  )
  #expect(sessionCredits.warning == "Cannot read some omp sessions.")
}

// One session file with an assistant message per (response id, time). The two times used below are on each side of the cycle boundary.
private func makeSessionRoot(responses: [(responseId: String, time: String)]) throws -> URL {
  let root = FileManager.default.temporaryDirectory.appending(path: "session-root-\(UUID().uuidString)")
  let sessionDirectory = root.appending(path: "--workspace-project--")
  try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
  let lines = responses.map { response in
    let milliseconds = Int(utcDate(response.time).timeIntervalSince1970 * 1000)
    return #"{"type":"message","message":{"role":"assistant","content":[],"provider":"github-copilot","model":"gpt-6-luna","responseId":"\#(response.responseId)","usage":{"input":1000,"output":2000,"cacheRead":0,"cacheWrite":0},"timestamp":\#(milliseconds)}}"#
  }
  try lines.joined(separator: "\n").write(to: sessionDirectory.appending(path: "session.jsonl"), atomically: true, encoding: .utf8)
  return root
}

private let beforeCycleStart = "2026-09-30T12:00:00Z"
private let afterCycleStart = "2026-10-02T12:00:00Z"

private func loadSessionCredits(piDirectory: URL, ompDirectory: URL) -> SessionCredits {
  SessionCredits.load(
    since: fixtureCycleStart,
    now: sessionCreditsNow,
    piDirectory: piDirectory,
    openCodeDirectory: fixturesDirectory.appending(path: "missing"),
    ompDirectory: ompDirectory,
    priceURL: missingPriceURL
  )
}

private func creditsSum(_ days: [DailyCredits]) -> Double {
  days.reduce(0) { $0 + $1.credits }
}

// A session copied between ~/.pi and ~/.omp must not be billed twice. Pi loads first, so Pi keeps the records.
@Test func sameSessionInPiAndOmpRootsCountsOnce() throws {
  let responses = [(responseId: "resp_a", time: beforeCycleStart), (responseId: "resp_b", time: afterCycleStart)]
  let piRoot = try makeSessionRoot(responses: responses)
  let ompRoot = try makeSessionRoot(responses: responses)
  defer {
    try? FileManager.default.removeItem(at: piRoot)
    try? FileManager.default.removeItem(at: ompRoot)
  }
  let missing = fixturesDirectory.appending(path: "missing")
  let oneRoot = loadSessionCredits(piDirectory: piRoot, ompDirectory: missing)
  let twoRoots = loadSessionCredits(piDirectory: piRoot, ompDirectory: ompRoot)
  #expect(creditsSum(oneRoot.byDay) > 0)
  #expect(creditsSum(oneRoot.previousByDay) > 0)
  #expect(twoRoots.byDay == oneRoot.byDay)
  #expect(twoRoots.previousByDay == oneRoot.previousByDay)
  #expect(twoRoots.bySource == oneRoot.bySource)
  #expect(twoRoots.bySource.map(\.source) == [.pi])
}

@Test func independentResponsesInPiAndOmpRootsSum() throws {
  let piRoot = try makeSessionRoot(responses: [(responseId: "resp_a", time: beforeCycleStart), (responseId: "resp_b", time: afterCycleStart)])
  let ompRoot = try makeSessionRoot(responses: [(responseId: "resp_c", time: beforeCycleStart), (responseId: "resp_d", time: afterCycleStart)])
  defer {
    try? FileManager.default.removeItem(at: piRoot)
    try? FileManager.default.removeItem(at: ompRoot)
  }
  let missing = fixturesDirectory.appending(path: "missing")
  let piOnly = loadSessionCredits(piDirectory: piRoot, ompDirectory: missing)
  let ompOnly = loadSessionCredits(piDirectory: missing, ompDirectory: ompRoot)
  let both = loadSessionCredits(piDirectory: piRoot, ompDirectory: ompRoot)
  #expect(abs(creditsSum(both.byDay) - (creditsSum(piOnly.byDay) + creditsSum(ompOnly.byDay))) < 1e-9)
  #expect(abs(creditsSum(both.previousByDay) - (creditsSum(piOnly.previousByDay) + creditsSum(ompOnly.previousByDay))) < 1e-9)
  #expect(Set(both.bySource.map(\.source)) == [.pi, .omp])
}
