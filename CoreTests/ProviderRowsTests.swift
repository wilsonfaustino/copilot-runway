import Core
import Foundation
import Testing

// 15 calendar days and 11 workdays into the Oct 1 to Nov 1 cycle.
private let providerNow = utcDate("2026-10-16T00:00:00Z")

private func providerRows(
  copilotUsage: QuotaUsage = makeUsage(creditsUsed: 6100),
  portkeySpentUSD: Double = 0,
  portkeyRequestCount: Int = 0,
  portkeyBudgetUSD: Double? = nil,
  mode: GaugeMode = .left,
  days: RunwayDays = .calendar
) -> [ProviderRow] {
  // The first record carries the whole spend; the others only add to the request count.
  let portkeyRecords = (0..<portkeyRequestCount).map { recordIndex in
    PortkeyRecord(model: "demo-model", timestamp: providerNow, source: .pi, costUSD: recordIndex == 0 ? portkeySpentUSD : 0)
  }
  return ProviderRows.rows(
    copilotUsage: copilotUsage, portkeySpend: PortkeySpend(records: portkeyRecords),
    portkeyBudgetUSD: portkeyBudgetUSD, mode: mode, days: days, now: providerNow, locale: usLocale)
}

@Test func providerRowsInLeftMode() {
  let rows = providerRows(portkeySpentUSD: 9.26, portkeyRequestCount: 3, portkeyBudgetUSD: 50)
  #expect(rows.map(\.tab) == [.copilot, .portkey])
  #expect(rows[0].amountText == "$59.00 of $120.00 left")
  #expect(rows[0].barFraction == MenuBarTitle.gaugeFraction(usage: makeUsage(creditsUsed: 6100), mode: .left))
  #expect(rows[0].burnText == "$4.07/day")
  #expect(rows[1].amountText == "$40.74 of $50.00 left")
  #expect(abs((rows[1].barFraction ?? 0) - 0.8148) < 1e-9)
  #expect(rows[1].burnText == "$0.62/day")
  #expect(rows[0].accessibilityLabel == "Copilot, $59.00 of $120.00 left, $4.07 per day")
}

@Test func providerRowsInSpentMode() {
  let rows = providerRows(portkeySpentUSD: 9.26, portkeyRequestCount: 3, portkeyBudgetUSD: 50, mode: .spent)
  #expect(rows[0].amountText == "$61.00 of $120.00 spent")
  #expect(abs((rows[0].barFraction ?? 0) - 61.0 / 120) < 1e-9)
  #expect(rows[1].amountText == "$9.26 of $50.00 spent")
  #expect(abs((rows[1].barFraction ?? 0) - 9.26 / 50) < 1e-9)
}

@Test func copilotOverageFloorsLeftAtZeroAndCapsSpentBar() {
  for portkeyBudgetUSD in [nil, 50.0] {
    let leftRow = providerRows(copilotUsage: makeUsage(creditsUsed: 13000), portkeyBudgetUSD: portkeyBudgetUSD)[0]
    #expect(leftRow.amountText == "$0.00 of $120.00 left")
    #expect(leftRow.barFraction == 0)
    let spentRow = providerRows(
      copilotUsage: makeUsage(creditsUsed: 13000), portkeyBudgetUSD: portkeyBudgetUSD, mode: .spent)[0]
    #expect(spentRow.amountText == "$130.00 of $120.00 spent")
    #expect(spentRow.barFraction == 1)
  }
}

@Test func portkeyOverageFloorsLeftAtZeroAndCapsSpentBar() {
  let leftRow = providerRows(portkeySpentUSD: 60, portkeyRequestCount: 3, portkeyBudgetUSD: 50)[1]
  #expect(leftRow.amountText == "$0.00 of $50.00 left")
  #expect(leftRow.barFraction == 0)
  let spentRow = providerRows(portkeySpentUSD: 60, portkeyRequestCount: 3, portkeyBudgetUSD: 50, mode: .spent)[1]
  #expect(spentRow.amountText == "$60.00 of $50.00 spent")
  #expect(spentRow.barFraction == 1)
}

@Test func portkeyWithoutBudgetShowsSpendAndNoBar() {
  let portkeyRow = providerRows(portkeySpentUSD: 12.34, portkeyRequestCount: 5)[1]
  #expect(portkeyRow.amountText == "$12.34 spent")
  #expect(portkeyRow.barFraction == nil)
  #expect(portkeyRow.burnText == "$0.82/day")
}

@Test func noPortkeyDataGivesOnlyTheCopilotRow() {
  #expect(providerRows().map(\.tab) == [.copilot])
}

@Test func unlimitedCopilotShowsSpendAndNoBar() {
  let rows = providerRows(
    copilotUsage: makeUsage(creditsUsed: 6100, isUnlimited: true), portkeySpentUSD: 9.26, portkeyRequestCount: 3,
    portkeyBudgetUSD: 50)
  #expect(rows[0].amountText == "$61.00 spent")
  #expect(rows[0].barFraction == nil)
  #expect(rows[0].burnText == "$4.07/day")
  #expect(rows[1].amountText == "$40.74 of $50.00 left")
}

@Test func burnUsesTheRunwayDayUnit() {
  let rows = providerRows(
    portkeySpentUSD: 9.26, portkeyRequestCount: 3, portkeyBudgetUSD: 50, days: .workdays(TimeZone(identifier: "UTC")!))
  #expect(rows[0].burnText == "$5.55/workday")
  #expect(rows[1].burnText == "$0.84/workday")
  #expect(rows[1].accessibilityLabel == "Portkey, $40.74 of $50.00 left, $0.84 per workday")
}

@Test func unlimitedCopilotAndPortkeyWithoutBudgetShowNoBars() {
  let rows = providerRows(
    copilotUsage: makeUsage(creditsUsed: 6100, isUnlimited: true), portkeySpentUSD: 12.34, portkeyRequestCount: 5)
  #expect(rows.map(\.tab) == [.copilot, .portkey])
  #expect(rows.map(\.barFraction) == [nil, nil])
  #expect(rows.map(\.burnText) == ["$4.07/day", "$0.82/day"])
}
