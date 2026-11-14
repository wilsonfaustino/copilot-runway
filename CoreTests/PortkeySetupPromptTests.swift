import Core
import Foundation
import Testing

private let fireworksModel = "@fireworks-ai-global/accounts/fireworks/models/glm-5p3-flash"

private func record(_ model: String, _ source: SessionSource, _ cost: Double?, at seconds: TimeInterval) -> PortkeyRecord {
  PortkeyRecord(model: model, timestamp: Date(timeIntervalSince1970: seconds), source: source, costUSD: cost)
}

@Test func unpricedModelsUsesNewestRecordPerAgentAndModel() {
  let records = [
    record("a", .pi, nil, at: 1), record("a", .pi, 0.01, at: 2),
    record("b", .pi, nil, at: 1),
    record("a", .opencode, 0.01, at: 1), record("a", .opencode, nil, at: 2),
  ]
  #expect(PortkeySetupPrompt.unpricedModels(in: records) == [.pi: ["b"], .opencode: ["a"]])
}

@Test func unpricedModelsIsEmptyWhenEveryNewestRecordHasACost() {
  #expect(PortkeySetupPrompt.unpricedModels(in: []).isEmpty)
  #expect(PortkeySetupPrompt.unpricedModels(in: [record("a", .omp, 0.02, at: 1)]).isEmpty)
}

@Test func textWithoutUnpricedModelsHasEveryAgentSection() {
  let text = PortkeySetupPrompt.text(records: [record("a", .pi, 0.01, at: 1)])
  for heading in ["## Pi", "## OpenCode", "## omp"] {
    #expect(text.contains(heading))
  }
  #expect(text.contains("<model id>"))
  #expect(text.contains("<your.portkey.gateway.com>"))
  #expect(text.contains("I do not know which models need a price."))
  #expect(text == PortkeySetupPrompt.text(records: []))
}

@Test func textListsOnlyAgentsWithUnpricedModels() {
  let text = PortkeySetupPrompt.text(records: [record(fireworksModel, .pi, nil, at: 1)])
  #expect(text.contains("- Pi: `\(fireworksModel)`"))
  #expect(text.contains("## Pi"))
  #expect(!text.contains("## OpenCode"))
  #expect(!text.contains("## omp"))
  #expect(!text.contains("I do not know which models need a price."))
}

@Test func textListsEachModelOnce() {
  let text = PortkeySetupPrompt.text(records: [record("m", .pi, nil, at: 1), record("m", .pi, nil, at: 2)])
  #expect(text.components(separatedBy: "`m`").count == 2)
}

@Test func textListsTheSameModelUnderEachAgent() {
  let text = PortkeySetupPrompt.text(records: [record("m", .pi, nil, at: 1), record("m", .opencode, nil, at: 1)])
  #expect(text.contains("- Pi: `m`"))
  #expect(text.contains("- OpenCode: `m`"))
}

@Test func textOrdersSectionsPiOpenCodeOmp() throws {
  let text = PortkeySetupPrompt.text(records: [])
  let pi = try #require(text.range(of: "## Pi")).lowerBound
  let openCode = try #require(text.range(of: "## OpenCode")).lowerBound
  let omp = try #require(text.range(of: "## omp")).lowerBound
  #expect(pi < openCode && openCode < omp)
}

@Test func textAlwaysHasSafetyAndPriceRules() {
  for text in [PortkeySetupPrompt.text(records: []), PortkeySetupPrompt.text(records: [record("m", .omp, nil, at: 1)])] {
    #expect(text.contains("Before you save any change, show me the diff and wait for my approval."))
    #expect(text.contains("Never print, log, copy or echo an API key."))
    #expect(text.contains("Do not search the web or fill in a price yourself, unless I explicitly ask you to."))
    #expect(text.contains("wait for my confirmation"))
    #expect(text.contains("$(date +%Y%m%d-%H%M%S)"))
  }
}

@Test func genericTextHasNoCompanyDetails() {
  let text = PortkeySetupPrompt.text(records: []).lowercased()
  for banned in ["fireworks", "~/.secrets", "x-portkey-api-key", "https://"] {
    #expect(!text.contains(banned))
  }
}
