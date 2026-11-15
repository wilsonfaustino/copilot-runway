@testable import Core
import Foundation
import Testing

private func copilotDays(_ credits: [Double]) -> [DailyCredits] {
  let firstDay = utcDate("2026-11-01T00:00:00Z")
  return credits.enumerated().map { offset, dayCredits in
    DailyCredits(day: Runway.utcCalendar.date(byAdding: .day, value: offset, to: firstDay)!, credits: dayCredits)
  }
}

private func portkeyRecord(at timestamp: String, costUSD: Double?) -> PortkeyRecord {
  PortkeyRecord(model: "glm", timestamp: utcDate(timestamp), source: .pi, costUSD: costUSD)
}

@Test func daysAddPortkeySpendToTheMatchingDay() {
  let days = CombinedDailyBurn.days(
    copilot: copilotDays([500, 0, 1200]),
    portkeyRecords: [
      portkeyRecord(at: "2026-11-01T10:00:00Z", costUSD: 0.40),
      portkeyRecord(at: "2026-11-01T23:59:00Z", costUSD: 0.10),
      portkeyRecord(at: "2026-11-03T05:00:00Z", costUSD: 1.25),
      portkeyRecord(at: "2026-11-03T06:00:00Z", costUSD: nil),
    ]
  )
  #expect(days.map(\.day) == copilotDays([500, 0, 1200]).map(\.day))
  #expect(days.map(\.copilotUSD) == [5.00, 0, 12.00])
  #expect(days.map(\.portkeyUSD) == [0.50, 0, 1.25])
  #expect(days.map(\.totalUSD) == [5.50, 0, 13.25])
}

@Test func recordsOutsideTheDaysAreIgnored() {
  let days = CombinedDailyBurn.days(
    copilot: copilotDays([500, 0, 1200]),
    portkeyRecords: [portkeyRecord(at: "2026-11-04T08:00:00Z", costUSD: 3)]
  )
  #expect(days.map(\.portkeyUSD) == [0, 0, 0])
}

@Test func emptyCopilotGivesNoDays() {
  let days = CombinedDailyBurn.days(copilot: [], portkeyRecords: [portkeyRecord(at: "2026-11-01T10:00:00Z", costUSD: 1)])
  #expect(days.isEmpty)
}

@Test func aggregateKeepsPreviousCyclePortkeyRecords() {
  let cycleStart = utcDate("2026-11-01T00:00:00Z")
  let sessionCredits = SessionCredits.aggregate(
    turns: [],
    prices: PriceTable.bundled,
    portkeyRecords: [
      portkeyRecord(at: "2026-10-31T10:00:00Z", costUSD: 0.30),
      portkeyRecord(at: "2026-11-02T10:00:00Z", costUSD: 0.70),
    ],
    cycleStart: cycleStart,
    now: utcDate("2026-11-03T00:00:00Z")
  )
  #expect(sessionCredits.previousPortkey.records.map(\.costUSD) == [0.30])
  #expect(sessionCredits.portkey.records.map(\.costUSD) == [0.70])
}
