import Core
import Foundation
import Testing

private let deepSeekGatewayID = "@fireworks-ai-global/accounts/fireworks/models/deepseek-v4p1-flash-1017"

private func portkeySpend(_ requests: [(model: String, source: SessionSource, costUSD: Double?)]) -> PortkeySpend {
  PortkeySpend(
    records: requests.map { request in
      PortkeyRecord(model: request.model, timestamp: utcDate("2026-11-04T10:00:00Z"), source: request.source, costUSD: request.costUSD)
    }
  )
}

private func expectUSD(_ actual: Double, _ expected: Double, sourceLocation: SourceLocation = #_sourceLocation) {
  #expect(abs(actual - expected) < 1e-9, "\(actual) is not \(expected)", sourceLocation: sourceLocation)
}

private func expectUSDBreakdown(_ breakdown: ShareBreakdown, sourceLocation: SourceLocation = #_sourceLocation) {
  #expect(breakdown.isUSD, sourceLocation: sourceLocation)
  #expect(breakdown.unit == ShareBreakdown.localUSDUnit, sourceLocation: sourceLocation)
}

// MARK: By model

@Test func combinedModelsAddCopilotCreditsAtOneCentNextToPortkeyUSD() {
  let breakdown = CombinedBreakdown.models(
    copilot: [ModelCredits(model: "gpt-6.1-sol", credits: 300)],
    portkey: portkeySpend([(deepSeekGatewayID, .pi, 1)])
  )
  expectUSDBreakdown(breakdown)
  #expect(breakdown.items.map(\.id) == [.entry("copilot:gpt-6.1-sol"), .entry("portkey:" + deepSeekGatewayID)])
  #expect(breakdown.items.map(\.name) == ["GPT-6.1 Sol", "DeepSeek V4.1 Flash"])
  #expect(breakdown.items.map(\.share) == [75, 25])
  expectUSD(breakdown.shareTotal, 4)
  expectUSD(breakdown.items[0].credits, 3)
  expectUSD(breakdown.items[1].credits, 1)
}

@Test func combinedModelsCopilotOnly() {
  let breakdown = CombinedBreakdown.models(
    copilot: [ModelCredits(model: "gpt-6-luna", credits: 50), ModelCredits(model: "gpt-6.1-sol", credits: 150)],
    portkey: portkeySpend([])
  )
  expectUSDBreakdown(breakdown)
  #expect(breakdown.items.map(\.name) == ["GPT-6.1 Sol", "GPT-6 Luna"])
  #expect(breakdown.items.map(\.share) == [75, 25])
  expectUSD(breakdown.shareTotal, 2)
}

@Test func combinedModelsPortkeyOnly() {
  let breakdown = CombinedBreakdown.models(copilot: [], portkey: portkeySpend([("glm-5p3-flash", .omp, 0.2), (deepSeekGatewayID, .pi, 0.6)]))
  expectUSDBreakdown(breakdown)
  #expect(breakdown.items.map(\.name) == ["DeepSeek V4.1 Flash", "GLM 5.3 Flash"])
  #expect(breakdown.items.map(\.share) == [75, 25])
  expectUSD(breakdown.shareTotal, 0.8)
}

@Test func copilotModelAndPortkeyGatewayIDForTheSameModelStayTwoRows() {
  let breakdown = CombinedBreakdown.models(
    copilot: [ModelCredits(model: "gemini-3.8-flash", credits: 100)],
    portkey: portkeySpend([("@vertex/gemini-3.8-flash", .pi, 0.5)])
  )
  #expect(breakdown.items.map(\.id) == [.entry("copilot:gemini-3.8-flash"), .entry("portkey:@vertex/gemini-3.8-flash")])
  #expect(breakdown.items.map(\.name) == ["Gemini 3.8 Flash", "gemini-3.8-flash"])
}

@Test func portkeyRowsWithTheSameNameShowTheirGatewayID() {
  let breakdown = CombinedBreakdown.models(copilot: [], portkey: portkeySpend([("a/custom", .pi, 0.6), ("b/custom", .pi, 0.4)]))
  #expect(breakdown.items.map(\.id) == [.entry("portkey:a/custom"), .entry("portkey:b/custom")])
  #expect(breakdown.items.map(\.name) == ["a/custom (Portkey)", "b/custom (Portkey)"])
}

@Test func portkeyIDInTheNameTableGetsItsPortkeyName() {
  let breakdown = CombinedBreakdown.models(copilot: [], portkey: portkeySpend([(deepSeekGatewayID, .opencode, 0.1)]))
  #expect(breakdown.items.map(\.name) == ["DeepSeek V4.1 Flash"])
}

// The Copilot id has no bundled name, so both rows would read "my-model". Only the Portkey row changes.
@Test func bareIDOnBothProvidersRenamesOnlyThePortkeyRow() {
  let breakdown = CombinedBreakdown.models(
    copilot: [ModelCredits(model: "my-model", credits: 200)],
    portkey: portkeySpend([("my-model", .pi, 1)])
  )
  #expect(breakdown.items.map(\.id) == [.entry("copilot:my-model"), .entry("portkey:my-model")])
  #expect(breakdown.items.map(\.name) == ["my-model", "my-model (Portkey)"])
}

@Test func partlyUnpricedCopilotModelAddsItsPricedPart() {
  let breakdown = CombinedBreakdown.models(
    copilot: [ModelCredits(model: "gpt-6-luna", credits: 80, hasUnpricedRecords: true)], portkey: portkeySpend([])
  )
  #expect(breakdown.items.map(\.name) == ["GPT-6 Luna"])
  expectUSD(breakdown.items[0].credits, 0.8)
}

@Test func allUnpricedModelsGiveNoItems() {
  let breakdown = CombinedBreakdown.models(
    copilot: [ModelCredits(model: "demo-unpriced-model", credits: nil)],
    portkey: portkeySpend([(deepSeekGatewayID, .pi, nil)])
  )
  expectUSDBreakdown(breakdown)
  #expect(breakdown.items.isEmpty)
  #expect(breakdown.isEmpty)
}

@Test func threeModelsDoNotFold() {
  let breakdown = CombinedBreakdown.models(
    copilot: [ModelCredits(model: "gpt-6.1-sol", credits: 100)],
    portkey: portkeySpend([("glm-5p3-flash", .pi, 0.5), (deepSeekGatewayID, .pi, 0.25)])
  )
  #expect(breakdown.items.count == 3)
  #expect(breakdown.items.allSatisfy { $0.kind == .entry })
}

@Test func sixEqualModelsFoldThreeIntoOtherModels() {
  let breakdown = CombinedBreakdown.models(
    copilot: [],
    portkey: portkeySpend(["m/a", "m/b", "m/c", "m/d", "m/e", "m/f"].map { ($0, .pi, 0.5) })
  )
  #expect(breakdown.items.map(\.name) == ["a", "b", "c", ShareBreakdown.otherModelsName])
  #expect(breakdown.items.last?.id == .otherModels)
  expectUSD(breakdown.items[3].credits, 1.5)
  expectUSD(breakdown.shareTotal, 3)
  #expect(breakdown.items[3].share == 50)
  #expect(breakdown.items.map(\.share).reduce(0, +) == 100)
}

@Test func pricedRequestsOfOneGatewayIDFromTwoAgentsAreOneRow() {
  let breakdown = CombinedBreakdown.models(
    copilot: [],
    portkey: portkeySpend([(deepSeekGatewayID, .pi, 0.25), (deepSeekGatewayID, .opencode, 0.5), (deepSeekGatewayID, .opencode, nil)])
  )
  #expect(breakdown.items.map(\.id) == [.entry("portkey:" + deepSeekGatewayID)])
  expectUSD(breakdown.items[0].credits, 0.75)
}

// The three Portkey rows tie at $0.50, so the final names decide: "omega", "z/custom (Portkey)", "zeta". By id
// "0/zeta" comes first, and by the name before the rename "custom" comes first.
@Test func tieAtTheCutoffSortsByFinalName() {
  let breakdown = CombinedBreakdown.models(
    copilot: [ModelCredits(model: "gpt-6.1-sol", credits: 400), ModelCredits(model: "custom", credits: 100)],
    portkey: portkeySpend([("z/custom", .pi, 0.5), ("0/zeta", .pi, 0.5), ("a/omega", .pi, 0.5)])
  )
  #expect(breakdown.items.map(\.name) == ["GPT-6.1 Sol", "custom", "omega", ShareBreakdown.otherModelsName])
  expectUSD(breakdown.items[3].credits, 1)
  #expect(breakdown.items.map(\.share) == [62, 15, 8, 15])
  #expect(breakdown.items.map(\.share).reduce(0, +) == 100)
}

// $0.10 + $0.20 sums to 0.30000000000000004, so a raw sort puts "beta" before "alpha" at the cutoff.
@Test func floatingPointSumsTieAtTheCutoffAndSortByName() {
  let breakdown = CombinedBreakdown.models(
    copilot: [ModelCredits(model: "gpt-6.1-sol", credits: 400), ModelCredits(model: "gpt-6-luna", credits: 200)],
    portkey: portkeySpend([("b/beta", .pi, 0.1), ("b/beta", .pi, 0.2), ("a/alpha", .pi, 0.3)])
  )
  #expect(breakdown.items.map(\.name) == ["GPT-6.1 Sol", "GPT-6 Luna", "alpha", ShareBreakdown.otherModelsName])
}

// MARK: By agent

@Test func combinedAgentsBothProviders() {
  let breakdown = CombinedBreakdown.agents(
    copilot: [SourceCredits(source: .copilotCli, credits: 300)],
    portkey: portkeySpend([(deepSeekGatewayID, .opencode, 1)])
  )
  expectUSDBreakdown(breakdown)
  #expect(breakdown.items.map(\.id) == [.entry("Copilot CLI"), .entry("OpenCode")])
  #expect(breakdown.items.map(\.share) == [75, 25])
  expectUSD(breakdown.shareTotal, 4)
}

@Test func combinedAgentsCopilotOnly() {
  let breakdown = CombinedBreakdown.agents(
    copilot: [SourceCredits(source: .pi, credits: 100), SourceCredits(source: .opencode, credits: 100)], portkey: portkeySpend([])
  )
  expectUSDBreakdown(breakdown)
  // A tie sorts by SessionSource.rawValue.
  #expect(breakdown.items.map(\.name) == ["OpenCode", "Pi"])
  expectUSD(breakdown.shareTotal, 2)
}

@Test func floatingPointAgentSumsTieAndSortBySource() {
  let breakdown = CombinedBreakdown.agents(
    copilot: [], portkey: portkeySpend([(deepSeekGatewayID, .pi, 0.1), (deepSeekGatewayID, .pi, 0.2), (deepSeekGatewayID, .omp, 0.3)])
  )
  #expect(breakdown.items.map(\.name) == ["omp", "Pi"])
}

@Test func combinedAgentsPortkeyOnly() {
  let breakdown = CombinedBreakdown.agents(copilot: [], portkey: portkeySpend([(deepSeekGatewayID, .omp, 0.2), (deepSeekGatewayID, .pi, 0.6)]))
  expectUSDBreakdown(breakdown)
  #expect(breakdown.items.map(\.name) == ["Pi", "omp"])
  #expect(breakdown.items.map(\.share) == [75, 25])
}

@Test func agentsWithoutPricedSpendHaveNoRow() {
  let breakdown = CombinedBreakdown.agents(
    copilot: [SourceCredits(source: .copilotCli, credits: 0)],
    portkey: portkeySpend([(deepSeekGatewayID, .opencode, nil), (deepSeekGatewayID, .omp, 0), (deepSeekGatewayID, .pi, 0.4)])
  )
  #expect(breakdown.items.map(\.name) == ["Pi"])
  #expect(breakdown.items[0].share == 100)
}

@Test func oneSourceOnBothProvidersIsOneRow() {
  let breakdown = CombinedBreakdown.agents(
    copilot: [SourceCredits(source: .opencode, credits: 150)],
    portkey: portkeySpend([(deepSeekGatewayID, .opencode, 0.5)])
  )
  #expect(breakdown.items.map(\.id) == [.entry("OpenCode")])
  expectUSD(breakdown.items[0].credits, 2)
}

@Test func allZeroAgentsGiveNoItems() {
  let breakdown = CombinedBreakdown.agents(
    copilot: [SourceCredits(source: .pi, credits: 0)], portkey: portkeySpend([(deepSeekGatewayID, .opencode, nil)])
  )
  expectUSDBreakdown(breakdown)
  #expect(breakdown.items.isEmpty)
}
