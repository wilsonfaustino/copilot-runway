import Core
import Foundation
import Testing

@Test func absenceClassification() {
  #expect(PortkeyOnly.absence(for: .ghNotFound) == .ghNotFound)
  #expect(PortkeyOnly.absence(for: .notLoggedIn) == .notLoggedIn)
  for noSeatError in [CopilotUsageError.httpStatus(400), .httpStatus(403), .httpStatus(404), .invalidResponse] {
    #expect(PortkeyOnly.absence(for: noSeatError) == .noSeat)
  }
  for outageError in [CopilotUsageError.network, .httpStatus(429), .httpStatus(500), .httpStatus(503)] {
    #expect(PortkeyOnly.absence(for: outageError) == nil)
  }
}

@Test func resetDateMidMonth() {
  #expect(PortkeyOnly.resetDate(now: utcDate("2026-11-16T10:00:00Z")) == utcDate("2026-12-01T00:00:00Z"))
}

@Test func resetDateOnTheFirst() {
  #expect(PortkeyOnly.resetDate(now: utcDate("2026-11-01T00:00:00Z")) == utcDate("2026-12-01T00:00:00Z"))
}

@Test func resetDateLastSecond() {
  #expect(PortkeyOnly.resetDate(now: utcDate("2026-11-30T23:59:59Z")) == utcDate("2026-12-01T00:00:00Z"))
}

@Test func resetDateDecember() {
  #expect(PortkeyOnly.resetDate(now: utcDate("2026-12-31T12:00:00Z")) == utcDate("2027-01-01T00:00:00Z"))
}

@Test func resetDateLeapFebruary() {
  let resetDate = PortkeyOnly.resetDate(now: utcDate("2028-02-29T08:00:00Z"))
  #expect(resetDate == utcDate("2028-03-01T00:00:00Z"))
  #expect(Runway.cycleStart(resetDate: resetDate) == utcDate("2028-02-01T00:00:00Z"))
}

@Test func causeLines() {
  #expect(
    PortkeyOnly.causeLine(.ghNotFound, hasBudget: true)
      == "GitHub CLI not found, so Copilot data is off. The runway shows your Portkey budget.")
  #expect(
    PortkeyOnly.causeLine(.ghNotFound, hasBudget: false)
      == "GitHub CLI not found, so Copilot data is off. Showing Portkey spend only.")
  #expect(
    PortkeyOnly.causeLine(.notLoggedIn, hasBudget: true)
      == "GitHub CLI not logged in, so Copilot data is off. The runway shows your Portkey budget.")
  #expect(
    PortkeyOnly.causeLine(.notLoggedIn, hasBudget: false)
      == "GitHub CLI not logged in, so Copilot data is off. Showing Portkey spend only.")
  #expect(
    PortkeyOnly.causeLine(.noSeat, hasBudget: true)
      == "No Copilot seat for this GitHub account, so Copilot data is off. The runway shows your Portkey budget.")
  #expect(
    PortkeyOnly.causeLine(.noSeat, hasBudget: false)
      == "No Copilot seat for this GitHub account, so Copilot data is off. Showing Portkey spend only.")
}

@Test func spentTitleUsesUSD() {
  #expect(PortkeyOnly.spentTitle(spentUSD: 10.17, locale: Locale(identifier: "en_US")) == "$10.17")
}

@Test func firstAbsenceEntersAtOnce() {
  var tracker = CopilotAbsenceTracker()
  tracker.observe(.notLoggedIn)
  #expect(tracker.absence == .notLoggedIn)
}

@Test func goodThenOneAbsenceKeepsCopilot() {
  var tracker = CopilotAbsenceTracker()
  tracker.observeSuccess()
  tracker.observe(.httpStatus(403))
  #expect(tracker.absence == nil)
}

@Test func goodThenTwoAbsencesEnters() {
  var tracker = CopilotAbsenceTracker()
  tracker.observeSuccess()
  tracker.observe(.httpStatus(403))
  tracker.observe(.httpStatus(404))
  #expect(tracker.absence == .noSeat)
}

@Test func outageBetweenAbsencesDoesNotCount() {
  var tracker = CopilotAbsenceTracker()
  tracker.observeSuccess()
  tracker.observe(.httpStatus(403))
  tracker.observe(.network)
  #expect(tracker.absence == nil)
  tracker.observe(.notLoggedIn)
  #expect(tracker.absence == .notLoggedIn)
}

@Test func outageKeepsPortkeyOnly() {
  var tracker = CopilotAbsenceTracker()
  tracker.observe(.ghNotFound)
  tracker.observe(.network)
  #expect(tracker.absence == .ghNotFound)
}

@Test func outageFirstKeepsNil() {
  var tracker = CopilotAbsenceTracker()
  tracker.observe(.network)
  #expect(tracker.absence == nil)
}

@Test func successLeaves() {
  var tracker = CopilotAbsenceTracker()
  tracker.observe(.ghNotFound)
  tracker.observeSuccess()
  #expect(tracker.absence == nil)
}

@Test func latestCauseWins() {
  var tracker = CopilotAbsenceTracker()
  tracker.observe(.ghNotFound)
  tracker.observe(.notLoggedIn)
  #expect(tracker.absence == .notLoggedIn)
}
