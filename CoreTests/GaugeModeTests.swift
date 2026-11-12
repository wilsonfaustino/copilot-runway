import Core
import Testing

// 6100 of 12000 used gives 49% left and 51% spent, so a swapped formula fails.
private let asymmetricUsage = makeUsage(creditsUsed: 6100)
private let unlimitedUsage = QuotaUsage(
  creditsUsed: 50, entitlement: 0, creditsRemaining: 0, percentRemaining: 100, isUnlimited: true,
  resetDate: utcDate("2026-11-01T00:00:00Z"))

@Test func leftGaugeFractionIsTheShareOfCreditsLeft() {
  #expect(abs(MenuBarTitle.gaugeFraction(usage: asymmetricUsage, mode: .left) - 0.4917) < 0.0001)
}

@Test func spentGaugeFractionIsTheShareOfCreditsSpent() {
  #expect(abs(MenuBarTitle.gaugeFraction(usage: asymmetricUsage, mode: .spent) - 0.5083) < 0.0001)
}

@Test func spentGaugeFractionIsFullAtOverage() {
  #expect(MenuBarTitle.gaugeFraction(usage: makeUsage(creditsUsed: 13000), mode: .spent) == 1)
}

@Test func spentGaugeFractionIsEmptyWhenNothingIsUsed() {
  #expect(MenuBarTitle.gaugeFraction(usage: makeUsage(creditsUsed: 0), mode: .spent) == 0)
}

@Test func gaugeFractionForUnlimitedPlanIsFullLeftAndEmptySpent() {
  #expect(MenuBarTitle.gaugeFraction(usage: unlimitedUsage, mode: .left) == 1)
  #expect(MenuBarTitle.gaugeFraction(usage: unlimitedUsage, mode: .spent) == 0)
}

@Test func gaugeFractionWithoutUsageIsEmptyInBothModes() {
  #expect(MenuBarTitle.gaugeFraction(usage: nil, mode: .left) == 0)
  #expect(MenuBarTitle.gaugeFraction(usage: nil, mode: .spent) == 0)
}

@Test func wholeGaugePercentInBothModes() {
  #expect(Runway.wholeGaugePercent(usage: asymmetricUsage, mode: .left) == 49)
  #expect(Runway.wholeGaugePercent(usage: asymmetricUsage, mode: .spent) == 51)
}

@Test func wholeGaugePercentAtOverageStaysAtOneHundredSpent() {
  // 12500 of 12000 used -> -4.17% left before the clamp.
  let overageUsage = makeUsage(creditsUsed: 12500)
  #expect(Runway.wholeGaugePercent(usage: overageUsage, mode: .left) == 0)
  #expect(Runway.wholeGaugePercent(usage: overageUsage, mode: .spent) == 100)
}

@Test func wholeGaugePercentAboveOneHundredLeftStaysAtZeroSpent() {
  // -240 used -> 102% left before the upper clamp.
  let refundUsage = makeUsage(creditsUsed: -240)
  #expect(Runway.wholeGaugePercent(usage: refundUsage, mode: .left) == 102)
  #expect(Runway.wholeGaugePercent(usage: refundUsage, mode: .spent) == 0)
}

@Test func wholeGaugePercentForUnlimitedPlan() {
  #expect(Runway.wholeGaugePercent(usage: unlimitedUsage, mode: .left) == 100)
  #expect(Runway.wholeGaugePercent(usage: unlimitedUsage, mode: .spent) == 0)
}

@Test func sweepStartsFullForLeftAndEmptyForSpent() {
  #expect(GaugeMode.left.sweepStartFraction == 1)
  #expect(GaugeMode.spent.sweepStartFraction == 0)
}

@Test func titleShowsTheGaugePercentInBothModes() {
  // 10 days in, 6100 used -> 9.67 days left.
  let now = utcDate("2026-10-11T00:00:00Z")
  #expect(MenuBarTitle.title(usage: asymmetricUsage, now: now, mode: .left) == "49% · 9d")
  #expect(MenuBarTitle.title(usage: asymmetricUsage, now: now, mode: .spent) == "51% · 9d")
}

@Test func spentTitleAtOverageShowsOneHundredPercentAndZeroDays() {
  let title = MenuBarTitle.title(usage: makeUsage(creditsUsed: 12500), now: utcDate("2026-10-21T00:00:00Z"), mode: .spent)
  #expect(title == "100% · 0d")
}

@Test func spentTitleWithoutRunwayEstimate() {
  let title = MenuBarTitle.title(usage: makeUsage(creditsUsed: 0), now: utcDate("2026-10-11T00:00:00Z"), mode: .spent)
  #expect(title == "0% · --d")
}

@Test func spentTitleForUnlimitedPlanIsInfinity() {
  #expect(MenuBarTitle.title(usage: unlimitedUsage, now: utcDate("2026-10-11T00:00:00Z"), mode: .spent) == "∞")
}

@Test func summaryUsedLineInBothModes() {
  let leftText = QuotaSummary.text(
    usage: asymmetricUsage, now: summaryNow, modelCredits: [], categoryCredits: [], gaugeMode: .left)
  let spentText = QuotaSummary.text(
    usage: asymmetricUsage, now: summaryNow, modelCredits: [], categoryCredits: [], gaugeMode: .spent)
  #expect(leftText.split(separator: "\n")[1] == "Used: 6,100 of 12,000 credits (49% remaining)")
  #expect(spentText.split(separator: "\n")[1] == "Used: 6,100 of 12,000 credits (51% spent)")
}

@Test func summaryUsedLineAtOverage() {
  let overageUsage = makeUsage(creditsUsed: 12500)
  let leftText = QuotaSummary.text(usage: overageUsage, now: summaryNow, modelCredits: [], categoryCredits: [])
  let spentText = QuotaSummary.text(
    usage: overageUsage, now: summaryNow, modelCredits: [], categoryCredits: [], gaugeMode: .spent)
  // Left mode keeps its rounding without a clamp, so overage reads -4%.
  #expect(leftText.split(separator: "\n")[1] == "Used: 12,500 of 12,000 credits (-4% remaining)")
  #expect(spentText.split(separator: "\n")[1] == "Used: 12,500 of 12,000 credits (100% spent)")
}

@Test func summaryUsedLineForUnlimitedPlanIsTheSameInBothModes() {
  let leftText = QuotaSummary.text(usage: unlimitedUsage, now: summaryNow, modelCredits: [], categoryCredits: [])
  let spentText = QuotaSummary.text(
    usage: unlimitedUsage, now: summaryNow, modelCredits: [], categoryCredits: [], gaugeMode: .spent)
  #expect(spentText == leftText)
  #expect(spentText.split(separator: "\n")[1] == "Used: 50 credits (unlimited plan)")
}
