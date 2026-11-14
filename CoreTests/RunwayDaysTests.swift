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
