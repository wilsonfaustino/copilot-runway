import Core
import Foundation
import Testing

private func portkeyRecord(_ category: TaskCategory, costUSD: Double?) -> PortkeyRecord {
  PortkeyRecord(
    model: "deepseek-v4p1-flash", timestamp: utcDate("2026-11-04T10:00:00Z"), source: .pi, costUSD: costUSD, category: category
  )
}

private func expectUSD(_ actual: Double, _ expected: Double, sourceLocation: SourceLocation = #_sourceLocation) {
  #expect(abs(actual - expected) < 1e-9, "\(actual) is not \(expected)", sourceLocation: sourceLocation)
}

@Test func combinedTaskSpendAddsCopilotCreditsAtOneCentToPortkeyUSD() {
  let categoryUSD = CombinedTaskSpend.byCategory(
    copilot: [
      CategoryCredits(category: .implementation, credits: 300),
      CategoryCredits(category: .investigation, credits: 100),
    ],
    portkeyRecords: [
      portkeyRecord(.implementation, costUSD: 1),
      portkeyRecord(.investigation, costUSD: 0.25),
      portkeyRecord(.investigation, costUSD: 0.25),
      portkeyRecord(.review, costUSD: 0.75),
    ]
  )
  #expect(categoryUSD.map(\.category) == [.implementation, .investigation, .review])
  expectUSD(categoryUSD[0].usd, 4)
  expectUSD(categoryUSD[1].usd, 1.5)
  expectUSD(categoryUSD[2].usd, 0.75)
}

@Test func unpricedPortkeyRecordsAddNothing() {
  let categoryUSD = CombinedTaskSpend.byCategory(
    copilot: [CategoryCredits(category: .implementation, credits: 100)],
    portkeyRecords: [portkeyRecord(.implementation, costUSD: nil), portkeyRecord(.debugging, costUSD: nil)]
  )
  #expect(categoryUSD == [CategoryUSD(category: .implementation, usd: 1)])
}

// Portkey-only mode with every request unpriced: the card shows its empty text.
@Test func onlyUnpricedPortkeyRecordsGiveAnEmptyBreakdown() {
  #expect(CombinedTaskSpend.breakdown(copilot: [], portkeyRecords: [portkeyRecord(.review, costUSD: nil)]).isEmpty)
}

@Test func copilotOnlyIsCopilotCreditsInUSD() {
  let copilot = [
    CategoryCredits(category: .debugging, credits: 250),
    CategoryCredits(category: .planning, credits: 50),
    CategoryCredits(category: .uncategorized, credits: 0),
  ]
  let breakdown = CombinedTaskSpend.breakdown(copilot: copilot, portkeyRecords: [])
  let copilotBreakdown = ShareBreakdown.tasks(copilot)
  expectUSD(breakdown.shareTotal, 3)
  #expect(breakdown.items.map(\.name) == copilotBreakdown.items.map(\.name))
  #expect(breakdown.items.map(\.share) == copilotBreakdown.items.map(\.share))
  expectUSD(breakdown.items[0].credits, 2.5)
}

@Test func portkeyOnlyIsPortkeyUSD() {
  let breakdown = CombinedTaskSpend.breakdown(
    copilot: [],
    portkeyRecords: [portkeyRecord(.review, costUSD: 0.3), portkeyRecord(.implementation, costUSD: 0.9)]
  )
  #expect(breakdown.items.map(\.name) == ["Implementation", "Review", "Uncategorized"])
  #expect(breakdown.items.map(\.share) == [75, 25, 0])
  expectUSD(breakdown.shareTotal, 1.2)
}

// A turn with Copilot and Portkey messages gives both its category, so the two amounts land in one item.
@Test func mixedTurnSumsIntoOneCategory() {
  let breakdown = CombinedTaskSpend.breakdown(
    copilot: [CategoryCredits(category: .investigation, credits: 40)],
    portkeyRecords: [portkeyRecord(.investigation, costUSD: 0.6)]
  )
  #expect(breakdown.items.map(\.name) == ["Investigation", "Uncategorized"])
  expectUSD(breakdown.items[0].credits, 1)
  #expect(breakdown.items[0].share == 100)
}

@Test func uncategorizedAlwaysHasAnItemAndSumsLikeOtherTasks() {
  let withoutUncategorized = CombinedTaskSpend.breakdown(
    copilot: [CategoryCredits(category: .review, credits: 100)], portkeyRecords: []
  )
  #expect(withoutUncategorized.items.last?.name == "Uncategorized")
  #expect(withoutUncategorized.items.last?.credits == 0)

  let withUncategorized = CombinedTaskSpend.breakdown(
    copilot: [CategoryCredits(category: .uncategorized, credits: 100)],
    portkeyRecords: [portkeyRecord(.uncategorized, costUSD: 1)]
  )
  #expect(withUncategorized.items.map(\.name) == ["Uncategorized"])
  expectUSD(withUncategorized.items[0].credits, 2)
}

// Three equal thirds round with the largest remainder method: the first item on a tie gets the extra percent.
@Test func combinedSharesRoundWithTheLargestRemainderMethod() {
  let breakdown = CombinedTaskSpend.breakdown(
    copilot: [CategoryCredits(category: .review, credits: 100)],
    portkeyRecords: [portkeyRecord(.debugging, costUSD: 1), portkeyRecord(.implementation, costUSD: 1)]
  )
  #expect(breakdown.items.map(\.name) == ["Debugging", "Implementation", "Review", "Uncategorized"])
  #expect(breakdown.items.map(\.share) == [34, 33, 33, 0])
}

@Test func combinedBreakdownShowsUSD() {
  let breakdown = CombinedTaskSpend.breakdown(copilot: [CategoryCredits(category: .review, credits: 347)], portkeyRecords: [])
  #expect(breakdown.isUSD)
  #expect(breakdown.unit == ShareBreakdown.localUSDUnit)
  #expect(breakdown.formattedAmount(breakdown.shareTotal, locale: englishLocale) == "$3.47")
  #expect(ShareBreakdown.tasks([]).formattedAmount(1_234.4, locale: englishLocale) == "1,234")
}
