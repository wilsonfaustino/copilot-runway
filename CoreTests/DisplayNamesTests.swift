import Core
import Foundation
import Testing

@Test func displayNameForKnownIDIsGitHubName() {
  #expect(ModelDisplayName.name(for: "gpt-6.1-sol") == "GPT-6.1 Sol")
  #expect(ModelDisplayName.name(for: "gemini-3.8-flash") == "Gemini 3.8 Flash")
}

@Test func displayNameForUnknownIDIsTheID() {
  #expect(ModelDisplayName.name(for: "grok-5") == "grok-5")
  #expect(ModelDisplayName.name(for: "") == "")
}

@Test func everyBundledPriceHasADisplayName() {
  #expect(Set(ModelDisplayName.bundled.keys) == Set(PriceTable.bundled.keys))
}

@Test func displayNamesAreUnique() {
  #expect(Set(ModelDisplayName.bundled.values).count == ModelDisplayName.bundled.count)
}

@Test func efficiencyNoteUsesDisplayNames() {
  let luna = ModelEfficiency(model: "gpt-6-luna", editTurns: 12, retryTurns: 1, creditsPerEditTurn: 3)
  let sol = ModelEfficiency(model: "gpt-6.1-sol", editTurns: 20, retryTurns: 4, creditsPerEditTurn: 5)
  #expect(
    ModelEfficiency.note([sol, luna], locale: Locale(identifier: "en_US"))
      == "GPT-6 Luna costs 40% less per edit turn than GPT-6.1 Sol. Retry rate 8% against 20%."
  )
}

@Test func unknownModelKeepsItsIDInShareItemsAndUnpricedNote() {
  let modelCredits = [
    ModelCredits(model: "gpt-6.1-sol", credits: 100),
    ModelCredits(model: "grok-5", credits: 50),
    ModelCredits(model: "claude-sonnet-5.5", credits: nil),
  ]
  #expect(ShareBreakdown.models(modelCredits, githubCredits: 150).items.map(\.name) == ["GPT-6.1 Sol", "grok-5"])
  #expect(ShareBreakdown.unpricedModelsNote(modelCredits) == "1 model has no price: Claude Sonnet 5.5")
}
