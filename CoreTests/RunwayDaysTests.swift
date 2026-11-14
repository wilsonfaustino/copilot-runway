import Core
import Foundation
import Testing

private let utcWorkdays = RunwayDays.workdays(TimeZone(identifier: "UTC")!)

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
