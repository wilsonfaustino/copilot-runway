import Core
import Foundation
import Testing

private let sidebarNow = utcDate("2026-10-16T00:00:00Z")
private let sidebarReset = utcDate("2026-11-01T00:00:00Z")

private func makeInput(
  copilotState: CopilotState = .copilot,
  copilotUsage: QuotaUsage? = makeUsage(creditsUsed: 6100),
  hasCopilotError: Bool = false,
  combined: CombinedBudget? = nil,
  portkeySpentUSD: Double = 0,
  portkeyRequestCount: Int = 0,
  portkeyBudgetUSD: Double? = nil,
  resetDate: Date? = sidebarReset,
  mode: GaugeMode = .left
) -> DashboardSidebarInput {
  DashboardSidebarInput(
    copilotState: copilotState, copilotUsage: copilotUsage, hasCopilotError: hasCopilotError, combined: combined,
    portkeySpentUSD: portkeySpentUSD, portkeyRequestCount: portkeyRequestCount, portkeyBudgetUSD: portkeyBudgetUSD,
    resetDate: resetDate, mode: mode, days: .calendar)
}

private func sidebarRows(_ input: DashboardSidebarInput) -> [DashboardSidebarRow] {
  DashboardSidebar.rows(input, now: sidebarNow, locale: usLocale)
}

private func row(_ tab: DashboardTab, in rows: [DashboardSidebarRow]) throws -> DashboardSidebarRow {
  try #require(rows.first { $0.tab == tab })
}

@Test func restoredWidthClampsSavedValues() {
  #expect(DashboardSidebar.restoredWidth(saved: nil) == 220)
  #expect(DashboardSidebar.restoredWidth(saved: 100) == 200)
  #expect(DashboardSidebar.restoredWidth(saved: 170) == 200)
  #expect(DashboardSidebar.restoredWidth(saved: 240) == 240)
  #expect(DashboardSidebar.restoredWidth(saved: 400) == 260)
}

@Test func tabsForEachCopilotState() {
  let withPortkey = sidebarRows(makeInput(portkeySpentUSD: 4, portkeyRequestCount: 3, portkeyBudgetUSD: 10))
  #expect(withPortkey.map(\.tab) == [.general, .copilot, .portkey])
  #expect(withPortkey.map(\.isEnabled) == [true, true, true])

  let withoutPortkey = sidebarRows(makeInput())
  #expect(withoutPortkey.map(\.tab) == [.general, .copilot])
  #expect(withoutPortkey.map(\.isEnabled) == [true, true])

  let portkeyOnly = sidebarRows(
    makeInput(copilotState: .portkeyOnly(.noSeat), copilotUsage: nil, portkeySpentUSD: 4, portkeyRequestCount: 3))
  #expect(portkeyOnly.map(\.tab) == [.general, .copilot, .portkey])
  #expect(portkeyOnly.map(\.isEnabled) == [true, false, true])

  let noPortkeyData = sidebarRows(makeInput(copilotState: .noPortkeyData(.notLoggedIn), copilotUsage: nil))
  #expect(noPortkeyData.map(\.tab) == [.general])
  #expect(noPortkeyData.map(\.isEnabled) == [true])
}

@Test func generalSplitsCopilotThenPortkey() throws {
  let copilotUsage = makeUsage(creditsUsed: 6100)
  let combined = try #require(CombinedBudget.make(copilot: copilotUsage, portkeySpentUSD: 9.26, portkeyBudgetUSD: 50))
  for mode in [GaugeMode.left, .spent] {
    let rows = sidebarRows(
      makeInput(
        copilotUsage: copilotUsage, combined: combined, portkeySpentUSD: 9.26, portkeyRequestCount: 3,
        portkeyBudgetUSD: 50, mode: mode))
    let generalGauge = try #require(try row(.general, in: rows).gauge)
    #expect(generalGauge.parts == combined.parts(mode: mode))
    #expect(generalGauge.percent == Runway.wholeGaugePercent(usage: combined.usage, mode: mode))
  }
  let leftRows = sidebarRows(
    makeInput(copilotUsage: copilotUsage, combined: combined, portkeySpentUSD: 9.26, portkeyRequestCount: 3, portkeyBudgetUSD: 50))
  #expect(try row(.general, in: leftRows).status == "$99.74 left · 59%")
  let spentRows = sidebarRows(
    makeInput(
      copilotUsage: copilotUsage, combined: combined, portkeySpentUSD: 9.26, portkeyRequestCount: 3, portkeyBudgetUSD: 50,
      mode: .spent))
  #expect(try row(.general, in: spentRows).status == "$70.26 spent · 41%")
}

@Test func generalWithoutCombinedMirrorsCopilot() throws {
  let rows = sidebarRows(makeInput())
  let generalRow = try row(.general, in: rows)
  let copilotRow = try row(.copilot, in: rows)
  #expect(generalRow.status == copilotRow.status)
  #expect(generalRow.gauge == copilotRow.gauge)
  #expect(generalRow.health == copilotRow.health)
}

@Test func copilotRowUsesCreditsStatus() throws {
  let leftRow = try row(.copilot, in: sidebarRows(makeInput()))
  #expect(leftRow.status == "5,900 credits left · 49%")
  #expect(leftRow.gauge == GaugeTile.make(usage: makeUsage(creditsUsed: 6100), hasError: false, mode: .left))
  let spentRow = try row(.copilot, in: sidebarRows(makeInput(mode: .spent)))
  #expect(spentRow.status == "6,100 credits spent · 51%")
}

@Test func portkeyRowWithBudget() throws {
  let portkeyRow = try row(.portkey, in: sidebarRows(makeInput(portkeySpentUSD: 4, portkeyRequestCount: 3, portkeyBudgetUSD: 10)))
  #expect(portkeyRow.status == "$6.00 left · 60%")
  let portkeyGauge = try #require(portkeyRow.gauge)
  #expect(portkeyGauge.percent == 60)
  #expect(!portkeyGauge.isSample)
}

@Test func portkeyRowWithoutBudget() throws {
  let portkeyRow = try row(.portkey, in: sidebarRows(makeInput(portkeySpentUSD: 9.26, portkeyRequestCount: 3)))
  #expect(portkeyRow.status == "$9.26 spent")
  #expect(portkeyRow.gauge == nil)
  #expect(portkeyRow.health == .unavailable)
}

@Test func noGaugeWhileLoadingOrOnErrorOrUnlimited() throws {
  let loadingRow = try row(.copilot, in: sidebarRows(makeInput(copilotUsage: nil)))
  #expect(loadingRow.status == "Loading")
  #expect(loadingRow.gauge == nil)

  let errorRow = try row(.copilot, in: sidebarRows(makeInput(hasCopilotError: true)))
  #expect(errorRow.status == "Unavailable")
  #expect(errorRow.gauge == nil)
  #expect(errorRow.health == .unavailable)

  let unlimitedUsage = makeUsage(creditsUsed: 50, entitlement: 0, isUnlimited: true)
  let unlimitedRow = try row(.copilot, in: sidebarRows(makeInput(copilotUsage: unlimitedUsage)))
  #expect(unlimitedRow.status == "Unlimited")
  #expect(unlimitedRow.gauge == nil)
}

@Test func copilotErrorKeepsPortkeyRow() throws {
  let copilotUsage = makeUsage(creditsUsed: 6100)
  let combined = CombinedBudget.make(copilot: copilotUsage, portkeySpentUSD: 4, portkeyBudgetUSD: 10)
  for resetDate in [sidebarReset, nil] {
    let rows = sidebarRows(
      makeInput(
        copilotUsage: copilotUsage, hasCopilotError: true, combined: combined, portkeySpentUSD: 4, portkeyRequestCount: 3,
        portkeyBudgetUSD: 10, resetDate: resetDate))
    for tab in [DashboardTab.general, .copilot] {
      let unavailableRow = try row(tab, in: rows)
      #expect(unavailableRow.status == "Unavailable")
      #expect(unavailableRow.gauge == nil)
      #expect(unavailableRow.health == .unavailable)
    }
    let portkeyRow = try row(.portkey, in: rows)
    #expect(portkeyRow.status == "$6.00 left · 60%")
    #expect(portkeyRow.gauge != nil)
  }
}

@Test func overageLeftAmountFloorsAtZero() throws {
  let copilotRow = try row(.copilot, in: sidebarRows(makeInput(copilotUsage: makeUsage(creditsUsed: 13000))))
  #expect(copilotRow.status == "0 credits left · 0%")
}

@Test func portkeyOnlyGeneralMirrorsPortkey() throws {
  let rows = sidebarRows(
    makeInput(
      copilotState: .portkeyOnly(.noSeat), copilotUsage: nil, portkeySpentUSD: 4, portkeyRequestCount: 3, portkeyBudgetUSD: 10,
      resetDate: nil))
  let generalRow = try row(.general, in: rows)
  let portkeyRow = try row(.portkey, in: rows)
  #expect(generalRow.status == "$6.00 left · 60%")
  #expect(generalRow.status == portkeyRow.status)
  #expect(generalRow.gauge == portkeyRow.gauge)
  #expect(generalRow.health == portkeyRow.health)
}

@Test func portkeyOnlyCopilotRowIsDisabled() throws {
  let copilotRow = try row(
    .copilot, in: sidebarRows(makeInput(copilotState: .portkeyOnly(.ghNotFound), copilotUsage: nil, portkeySpentUSD: 4)))
  #expect(!copilotRow.isEnabled)
  #expect(copilotRow.status == "Copilot data is off")
  #expect(copilotRow.gauge == nil)
  #expect(copilotRow.health == .unavailable)
}

@Test func noPortkeyDataGeneralIsUnavailable() throws {
  let generalRow = try row(.general, in: sidebarRows(makeInput(copilotState: .noPortkeyData(.noSeat), copilotUsage: nil)))
  #expect(generalRow.status == "Unavailable")
  #expect(generalRow.gauge == nil)
}

@Test func rowHealthFollowsRunwayHealth() throws {
  // 9000 of 12000 in 15 days is 600 a day, so the 3000 left last 5 days and run out before the reset.
  let shortUsage = makeUsage(creditsUsed: 9000)
  #expect(RunwayHealth(usage: shortUsage, now: sidebarNow) == .short)
  let copilotRow = try row(.copilot, in: sidebarRows(makeInput(copilotUsage: shortUsage)))
  #expect(copilotRow.health == .short)
}

@Test func accessibilityLabelHasTabAndStatus() throws {
  let copilotRow = try row(.copilot, in: sidebarRows(makeInput()))
  #expect(copilotRow.accessibilityLabel == "Copilot, 5,900 credits left · 49%")
}

@Test func resolvedTabFallsBackToGeneral() {
  let copilotOnlyRows = sidebarRows(makeInput())
  #expect(DashboardSidebar.resolvedTab(saved: .portkey, rows: copilotOnlyRows) == .general)
  let portkeyOnlyRows = sidebarRows(makeInput(copilotState: .portkeyOnly(.noSeat), copilotUsage: nil, portkeySpentUSD: 4))
  #expect(DashboardSidebar.resolvedTab(saved: .copilot, rows: portkeyOnlyRows) == .general)
  #expect(DashboardSidebar.resolvedTab(saved: nil, rows: copilotOnlyRows) == .general)
  #expect(DashboardSidebar.resolvedTab(saved: .copilot, rows: copilotOnlyRows) == .copilot)
}
