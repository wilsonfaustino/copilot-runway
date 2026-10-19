#if DEBUG
import Core
import Foundation
import Testing

let demoNow = utcDate("2026-10-17T12:00:00Z")

func pricedLocalCredits(_ scenario: DemoScenario) -> Double {
  scenario.sessionCredits.byModel.compactMap(\.credits).reduce(0, +)
}

@Test(arguments: DemoScenario.Name.allCases)
func demoScenarioTurnsFallInsideTheCycle(name: DemoScenario.Name) {
  let scenario = DemoScenario(name: name, now: demoNow)
  let cycleStart = Runway.cycleStart(resetDate: scenario.usage.resetDate)
  #expect(scenario.name == name)
  #expect(scenario.usage.entitlement > 0)
  #expect(cycleStart <= demoNow)
  #expect(scenario.usage.resetDate > demoNow)
  #expect(scenario.turns.allSatisfy { $0.timestamp >= cycleStart && $0.timestamp <= demoNow })
}

// The GitHub total also counts usage outside local sessions, so it is never below the local priced credits.
@Test(arguments: DemoScenario.Name.allCases)
func demoScenarioGitHubCreditsCoverLocalPricedCredits(name: DemoScenario.Name) {
  let scenario = DemoScenario(name: name, now: demoNow)
  #expect(scenario.usage.creditsUsed >= pricedLocalCredits(scenario))
}

// February clamping (Jan 31 and Jan 28 starts), month ends (Jan 31, Mar 31) and late-day launches.
let demoLaunchTimes = [
  "2026-02-14T23:59:00Z",
  "2026-02-16T23:59:00Z",
  "2026-02-28T00:00:00Z",
  "2026-01-31T23:59:00Z",
  "2026-03-31T00:00:00Z",
  "2026-03-31T23:59:00Z",
  "2026-10-17T00:00:00Z",
  "2026-10-17T23:59:00Z",
]

@Test(arguments: DemoScenario.Name.allCases, demoLaunchTimes)
func demoScenarioTurnsFallInsideTheCycleAtAnyLaunchTime(name: DemoScenario.Name, launchTime: String) {
  let now = utcDate(launchTime)
  let scenario = DemoScenario(name: name, now: now)
  let cycleStart = Runway.cycleStart(resetDate: scenario.usage.resetDate)
  #expect(cycleStart <= now)
  #expect(scenario.usage.resetDate > now)
  #expect(scenario.turns.allSatisfy { $0.timestamp >= cycleStart && $0.timestamp <= now })
}

@Test(arguments: DemoScenario.Name.allCases, demoLaunchTimes)
func demoScenarioGitHubCreditsCoverLocalPricedCreditsAtAnyLaunchTime(name: DemoScenario.Name, launchTime: String) {
  let scenario = DemoScenario(name: name, now: utcDate(launchTime))
  #expect(scenario.usage.creditsUsed >= pricedLocalCredits(scenario))
}

// Jan 31 plus one month clamps to Feb 28, which moves the Runway cycle start to Jan 28. The sessions still start on Jan 31.
@Test func monthEndClampingDoesNotAddDaysOfSessions() throws {
  let scenario = DemoScenario(name: .heavyPlanning, now: utcDate("2026-02-14T23:59:00Z"))
  let firstTurn = try #require(scenario.turns.first)
  #expect(firstTurn.timestamp >= utcDate("2026-01-31T00:00:00Z"))
}

@Test func typicalDemoHasThreeModelsAllSourcesAndAboutHalfUsed() {
  let scenario = DemoScenario(name: .typical, now: demoNow)
  let sessionCredits = scenario.sessionCredits
  #expect(Set(sessionCredits.byModel.map(\.model)) == ["gpt-6.1-sol", "gpt-6-luna", "gemini-3.8-flash"])
  #expect(Set(sessionCredits.bySource.map(\.source)) == [.opencode, .pi, .omp])
  #expect(sessionCredits.byCategory.count >= 4)
  #expect((40...60).contains(scenario.usage.percentRemaining))
  #expect(scenario.copilotReviewCount > 0)
  #expect(scenario.outcomes.prs > 0)
}

@Test func manyModelsDemoHasAtLeastSevenPricedModels() {
  let modelCredits = DemoScenario(name: .manyModels, now: demoNow).sessionCredits.byModel
  #expect(modelCredits.filter { $0.credits != nil }.count >= 7)
  #expect(modelCredits.allSatisfy { PriceTable.bundled[$0.model] != nil })
}

@Test func heavyPlanningDemoRanksPlanningAndDebuggingFirst() {
  let categoryCredits = DemoScenario(name: .heavyPlanning, now: demoNow).sessionCredits.byCategory
  #expect(Set(categoryCredits.prefix(2).map(\.category)) == [.planning, .debugging])
}

@Test func edgeUnpricedDemoHasAModelMissingFromThePriceTable() {
  let scenario = DemoScenario(name: .edgeUnpriced, now: demoNow)
  let unpricedModels = Set(scenario.turns.flatMap(\.records).map(\.model)).filter { PriceTable.bundled[$0] == nil }
  #expect(unpricedModels.count == 1)
  #expect(scenario.sessionCredits.byModel.last?.credits == nil)
}

@Test func edgeRunoutDemoIsOverTheLimit() {
  let usage = DemoScenario(name: .edgeRunout, now: demoNow).usage
  #expect(usage.creditsRemaining <= 0)
  #expect(Runway.wholePercentRemaining(usage: usage) == 0)
  #expect(Runway.wholeDaysLeft(usage: usage, now: demoNow) == 0)
}

@Test func edgeUncategorizedDemoHasOnlyUncategorizedTurns() {
  let turns = DemoScenario(name: .edgeUncategorized, now: demoNow).turns
  #expect(!turns.isEmpty)
  #expect(turns.allSatisfy { TaskCategorizer.category(of: $0) == .uncategorized })
}

@Test func edgeEmptyDemoHasNoTurnsAndNoCredits() {
  let scenario = DemoScenario(name: .edgeEmpty, now: demoNow)
  #expect(scenario.turns.isEmpty)
  #expect(scenario.usage.creditsUsed == 0)
  #expect(scenario.sessionCredits.byModel.isEmpty)
  #expect(Runway.daysLeft(usage: scenario.usage, now: demoNow) == nil)
}

@Test(arguments: DemoScenario.Name.allCases, demoLaunchTimes)
func demoScenarioPreviousTurnsFallInsideTheLastCycle(name: DemoScenario.Name, launchTime: String) {
  let scenario = DemoScenario(name: name, now: utcDate(launchTime))
  let cycleStart = Runway.cycleStart(resetDate: scenario.usage.resetDate)
  let previousCycleStart = Runway.cycleStart(resetDate: cycleStart)
  #expect(scenario.previousTurns.flatMap(\.records).allSatisfy { $0.timestamp >= previousCycleStart && $0.timestamp < cycleStart })
}

@Test func typicalDemoIsAboutAThirdAboveTheLastCycle() throws {
  let sessionCredits = DemoScenario(name: .typical, now: demoNow).sessionCredits
  let comparison = try #require(CycleComparison.compare(current: sessionCredits.byDay, previous: sessionCredits.previousByDay))
  #expect((30...40).contains(comparison.percentDifference))
  #expect(sessionCredits.cycleComparisonSentence?.contains("% above the same days of last cycle.") == true)
}

@Test func edgeUncategorizedDemoHasNoLastCycle() {
  let sessionCredits = DemoScenario(name: .edgeUncategorized, now: demoNow).sessionCredits
  #expect(!sessionCredits.byDay.isEmpty)
  #expect(sessionCredits.previousByDay.allSatisfy { $0.credits == 0 })
  #expect(sessionCredits.cycleComparisonSentence == nil)
}

@Test func demoLaunchValueIsTheArgumentAfterDemo() {
  #expect(DemoScenario.launchValue(arguments: ["/app", "-demo", "many-models", "-openDashboard"]) == "many-models")
  #expect(DemoScenario.launchValue(arguments: ["/app", "-openDashboard"]) == nil)
  #expect(DemoScenario.launchValue(arguments: ["/app", "-demo"]) == "")
}

@Test func unknownOrMissingDemoNameGivesTypical() {
  #expect(DemoScenario.Name(launchValue: "edge-empty") == .edgeEmpty)
  #expect(DemoScenario.Name(launchValue: "no-such-scenario") == .typical)
  #expect(DemoScenario.Name(launchValue: "") == .typical)
}
#endif
