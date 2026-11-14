import Core
import Testing

// 6100 of 12000 used gives 49% left and 51% spent, so a swapped mode fails.
private let asymmetricUsage = makeUsage(creditsUsed: 6100)

@Test func tileUsesRealUsage() {
  #expect(
    GaugeTile.make(usage: asymmetricUsage, hasError: false, mode: .left)
      == GaugeTile(fraction: MenuBarTitle.gaugeFraction(usage: asymmetricUsage, mode: .left), percent: 49, isSample: false))
  #expect(
    GaugeTile.make(usage: asymmetricUsage, hasError: false, mode: .spent)
      == GaugeTile(fraction: MenuBarTitle.gaugeFraction(usage: asymmetricUsage, mode: .spent), percent: 51, isSample: false))
}

@Test func tileFallsBackToSampleWithoutUsage() {
  #expect(GaugeTile.make(usage: nil, hasError: false, mode: .left) == GaugeTile(fraction: 0.62, percent: 62, isSample: true))
  #expect(GaugeTile.make(usage: nil, hasError: false, mode: .spent) == GaugeTile(fraction: 0.38, percent: 38, isSample: true))
}

@Test func tileFallsBackToSampleOnError() {
  #expect(GaugeTile.make(usage: asymmetricUsage, hasError: true, mode: .left) == GaugeTile(fraction: 0.62, percent: 62, isSample: true))
}

@Test func tileFallsBackToSampleForUnlimitedPlan() {
  let unlimitedUsage = makeUsage(creditsUsed: 50, entitlement: 0, isUnlimited: true)
  #expect(GaugeTile.make(usage: unlimitedUsage, hasError: false, mode: .left).isSample)
  #expect(GaugeTile.make(usage: unlimitedUsage, hasError: false, mode: .spent).isSample)
}

@Test func spentTileIsFullAtOverage() {
  let overageUsage = makeUsage(creditsUsed: 13000)
  #expect(GaugeTile.make(usage: overageUsage, hasError: false, mode: .spent) == GaugeTile(fraction: 1, percent: 100, isSample: false))
}
