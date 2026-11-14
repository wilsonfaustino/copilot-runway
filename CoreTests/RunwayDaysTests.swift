import Core
import Foundation
import Testing

let utcWorkdays = RunwayDays.workdays(TimeZone(identifier: "UTC")!)

@Test func calendarDayCountIsSecondsOverADay() {
  #expect(RunwayDays.calendar.dayCount(from: utcDate("2026-10-09T12:00:00Z"), to: utcDate("2026-10-12T12:00:00Z")) == 3)
}

@Test func workdayCountSkipsTheWeekend() {
  #expect(utcWorkdays.dayCount(from: utcDate("2026-10-05T00:00:00Z"), to: utcDate("2026-10-12T00:00:00Z")) == 5)
  #expect(utcWorkdays.dayCount(from: utcDate("2026-10-09T12:00:00Z"), to: utcDate("2026-10-12T12:00:00Z")) == 1)
  #expect(utcWorkdays.dayCount(from: utcDate("2026-10-10T00:00:00Z"), to: utcDate("2026-10-11T12:00:00Z")) == 0)
}

@Test func workdayCountFollowsTheTimeZone() {
  // Friday 22:00 UTC to Saturday 03:00 UTC: 2 workday hours in UTC, 5 in Sao Paulo (Friday 19:00 to midnight).
  let start = utcDate("2026-10-09T22:00:00Z")
  let end = utcDate("2026-10-10T03:00:00Z")
  #expect(abs(utcWorkdays.dayCount(from: start, to: end) - 2.0 / 24) < 1e-9)
  #expect(abs(RunwayDays.workdays(TimeZone(identifier: "America/Sao_Paulo")!).dayCount(from: start, to: end) - 5.0 / 24) < 1e-9)
}

@Test func addingWorkdaysStepsOverTheWeekend() {
  #expect(utcWorkdays.date(addingDays: 1, to: utcDate("2026-10-09T12:00:00Z")) == utcDate("2026-10-12T12:00:00Z"))
  #expect(utcWorkdays.date(addingDays: 0.5, to: utcDate("2026-10-10T00:00:00Z")) == utcDate("2026-10-12T12:00:00Z"))
}

@Test func addingWorkdaysEndingOnABoundaryReturnsTheEndOfTheLastWorkday() {
  #expect(utcWorkdays.date(addingDays: 5, to: utcDate("2026-10-10T00:00:00Z")) == utcDate("2026-10-17T00:00:00Z"))
  #expect(utcWorkdays.date(addingDays: 5, to: utcDate("2026-10-09T12:00:00Z")) == utcDate("2026-10-16T12:00:00Z"))
  #expect(utcWorkdays.date(addingDays: 5, to: utcDate("2026-10-11T00:00:00Z")) == utcDate("2026-10-17T00:00:00Z"))
}

@Test func addingWorkdaysRoundTripsWithDayCount() {
  let start = utcDate("2026-10-07T09:00:00Z")
  for workdayCount in [7.0, 12.5, 40.0] {
    let end = utcWorkdays.date(addingDays: workdayCount, to: start)
    #expect(abs(utcWorkdays.dayCount(from: start, to: end) - workdayCount) < 1e-9)
  }
}

@Test func addingWorkdaysFollowsTheTimeZone() {
  // Sao Paulo is UTC-3: Friday 19:00 local leaves 5h of Friday, then 7h of Monday from 03:00Z.
  let saoPaulo = RunwayDays.workdays(TimeZone(identifier: "America/Sao_Paulo")!)
  #expect(saoPaulo.date(addingDays: 0.5, to: utcDate("2026-10-09T22:00:00Z")) == utcDate("2026-10-12T10:00:00Z"))
}

@Test func addingNegativeDaysUsesCalendarTime() {
  #expect(utcWorkdays.date(addingDays: -2, to: utcDate("2026-10-12T00:00:00Z")) == utcDate("2026-10-10T00:00:00Z"))
}

@Test func addingHugeWorkdaysReturns() {
  let start = utcDate("2026-10-05T00:00:00Z")
  #expect(utcWorkdays.date(addingDays: 1e9, to: start) > start)
}

@Test func dayWordsFollowTheMode() {
  #expect(RunwayDays.calendar.dayWord() == "day")
  #expect(RunwayDays.calendar.dayWord(count: 3) == "days")
  #expect(utcWorkdays.dayWord() == "workday")
  #expect(utcWorkdays.dayWord(count: 0) == "workdays")
}

private let utcTimeZone = TimeZone(identifier: "UTC")!
private let saoPauloTimeZone = TimeZone(identifier: "America/Sao_Paulo")!

private func localDays(_ strings: String...) -> Set<LocalDay> {
  Set(strings.compactMap(LocalDay.init(string:)))
}

@Test func workdayCountSkipsADayOff() {
  let days = RunwayDays.workdays(utcTimeZone, daysOff: localDays("2026-11-20"))
  #expect(days.dayCount(from: utcDate("2026-11-16T00:00:00Z"), to: utcDate("2026-11-23T00:00:00Z")) == 4)
}

@Test func addingWorkdaysStepsOverADayOff() {
  let days = RunwayDays.workdays(utcTimeZone, daysOff: localDays("2026-11-20"))
  #expect(days.date(addingDays: 2, to: utcDate("2026-11-19T00:00:00Z")) == utcDate("2026-11-24T00:00:00Z"))
}

@Test func theWholeWeekJumpDoesNotCrossADayOff() {
  let start = utcDate("2026-11-02T00:00:00Z")
  let withoutDaysOff = utcWorkdays.date(addingDays: 30, to: start)
  let withDayOff = RunwayDays.workdays(utcTimeZone, daysOff: localDays("2026-11-20")).date(addingDays: 30, to: start)
  #expect(withoutDaysOff == utcDate("2026-12-12T00:00:00Z"))
  #expect(withDayOff == utcWorkdays.date(addingDays: 1, to: withoutDaysOff))
  #expect(withDayOff == utcDate("2026-12-15T00:00:00Z"))
}

@Test func aWeekendDayOffChangesNothing() {
  let days = RunwayDays.workdays(utcTimeZone, daysOff: localDays("2026-11-21"))
  let start = utcDate("2026-11-16T00:00:00Z")
  #expect(days.dayCount(from: start, to: utcDate("2026-11-23T00:00:00Z")) == 5)
  for workdayCount in [2.0, 7.5, 30.0] {
    #expect(days.date(addingDays: workdayCount, to: start) == utcWorkdays.date(addingDays: workdayCount, to: start))
  }
}

@Test func aDayOffFollowsTheTimeZone() {
  // In Sao Paulo (UTC-3) Friday 2026-11-20 runs from 03:00Z to 03:00Z the next day.
  let days = RunwayDays.workdays(saoPauloTimeZone, daysOff: localDays("2026-11-20"))
  #expect(abs(days.dayCount(from: utcDate("2026-11-20T00:00:00Z"), to: utcDate("2026-11-21T06:00:00Z")) - 3.0 / 24) < 1e-9)
  // Thursday 19:00 local leaves 5h of Thursday, then 7h of Monday from 03:00Z.
  #expect(days.date(addingDays: 0.5, to: utcDate("2026-11-19T22:00:00Z")) == utcDate("2026-11-23T10:00:00Z"))
}

@Test func aDayOffOnTheLastLocalDayCrossesTheUTCReset() {
  // Monday 2026-11-30 in Sao Paulo ends at 03:00Z on December 1, after a 00:00Z reset.
  let start = utcDate("2026-11-30T00:00:00Z")
  let reset = utcDate("2026-12-01T00:00:00Z")
  let saoPaulo = RunwayDays.workdays(saoPauloTimeZone)
  #expect(abs(saoPaulo.dayCount(from: start, to: reset) - 21.0 / 24) < 1e-9)
  #expect(RunwayDays.workdays(saoPauloTimeZone, daysOff: localDays("2026-11-30")).dayCount(from: start, to: reset) == 0)
}

@Test func aWholeWeekOffIsSkipped() {
  let days = RunwayDays.workdays(utcTimeZone, daysOff: localDays("2026-11-16", "2026-11-17", "2026-11-18", "2026-11-19", "2026-11-20"))
  let start = utcDate("2026-11-16T00:00:00Z")
  #expect(days.dayCount(from: start, to: utcDate("2026-11-23T00:00:00Z")) == 0)
  #expect(days.date(addingDays: 1, to: start) == utcDate("2026-11-24T00:00:00Z"))
  #expect(days.date(addingDays: 10, to: start) == utcDate("2026-12-05T00:00:00Z"))
}

@Test func aDayOffFromThePastCycleDoesNotChangeTheBurn() {
  // The December cycle starts at 00:00Z on December 1, which is still Monday 2026-11-30 at 21:00 in Sao Paulo.
  // Without the November mark, 3h of November 30 plus all of December 1 give 1.125 workdays: 90 / 1.125 = 80.
  let usage = makeUsage(creditsUsed: 90, resetDate: utcDate("2027-01-01T00:00:00Z"))
  let now = utcDate("2026-12-02T03:00:00Z")
  let days = RunwayDays.workdays(saoPauloTimeZone, daysOff: localDays("2026-11-30"))
    .keepingDaysOff(inCycleEndingAt: usage.resetDate)
  #expect(days == RunwayDays.workdays(saoPauloTimeZone))
  #expect(abs(Runway.averageDailyBurn(usage: usage, now: now, days: days) - 80) < 1e-9)
}

@Test func daysOffInTheCycleStayAndCalendarModeIsUnchanged() {
  let reset = utcDate("2026-12-01T00:00:00Z")
  let days = RunwayDays.workdays(utcTimeZone, daysOff: localDays("2026-10-30", "2026-11-20"))
  #expect(days.keepingDaysOff(inCycleEndingAt: reset) == RunwayDays.workdays(utcTimeZone, daysOff: localDays("2026-11-20")))
  #expect(RunwayDays.calendar.keepingDaysOff(inCycleEndingAt: reset) == .calendar)
}
