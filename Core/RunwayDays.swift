import Foundation

public enum RunwayDays: Equatable, Sendable {
  case calendar
  case workdays(TimeZone, daysOff: Set<LocalDay> = [])

  private static let secondsPerDay: Double = 86_400
  private static let workdaysPerWeek: Double = 5
  private static let maxCalendarWeekJump: Double = 1_000_000

  public func dayCount(from start: Date, to end: Date) -> Double {
    guard case .workdays(let timeZone, let daysOff) = self, end > start else {
      return end.timeIntervalSince(start) / Self.secondsPerDay
    }
    let calendar = Self.gregorianCalendar(in: timeZone)
    var workdaySeconds = 0.0
    var cursor = start
    while cursor < end {
      let segmentEnd = min(Self.nextMidnight(after: cursor, in: calendar), end)
      if Self.isWorkday(cursor, in: calendar, daysOff: daysOff) {
        workdaySeconds += segmentEnd.timeIntervalSince(cursor)
      }
      cursor = segmentEnd
    }
    return workdaySeconds / Self.secondsPerDay
  }

  // Whole UTC days from the day of start up to the day of end, the end day not counted. In workday mode a day counts
  // when its UTC date is Monday to Friday and not a day off, the same rule as the days off grid. The time zone of
  // the mode is not used here, because the sentences show UTC dates.
  func wholeUTCDayCount(fromDayOf start: Date, toDayOf end: Date) -> Int {
    let calendar = Runway.utcCalendar
    let startDay = calendar.startOfDay(for: start)
    let endDay = calendar.startOfDay(for: end)
    guard case .workdays(_, let daysOff) = self else {
      return calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
    }
    var workdayCount = 0
    var cursor = startDay
    while cursor < endDay {
      if Self.isWorkday(cursor, in: calendar, daysOff: daysOff) { workdayCount += 1 }
      cursor = Self.nextMidnight(after: cursor, in: calendar)
    }
    return workdayCount
  }

  public func date(addingDays days: Double, to start: Date) -> Date {
    guard case .workdays(let timeZone, let daysOff) = self, days > 0 else {
      return start.addingTimeInterval(days * Self.secondsPerDay)
    }
    let calendar = Self.gregorianCalendar(in: timeZone)
    var cursor = start
    var remainingDays = days

    // The whole-week jump counts 5 workdays per week, so it waits until the cursor is past the last day off.
    let lastDayOff = daysOff.max()
    var hasTriedWholeWeekJump = false

    while remainingDays > 0 {
      if !hasTriedWholeWeekJump, lastDayOff.map({ LocalDay(date: cursor, calendar: calendar) > $0 }) ?? true {
        hasTriedWholeWeekJump = true
        // Whole weeks first: a huge count (early in a cycle, or a large Portkey budget) would otherwise walk day by day for ages.
        // Stop one week short so the walk ends the count inside a workday, at the earliest instant.
        let wholeWeeks = (remainingDays / Self.workdaysPerWeek).rounded(.up) - 1
        if wholeWeeks > 0 {
          if !Self.isWorkday(cursor, in: calendar, daysOff: daysOff) {
            cursor = Self.nextWorkdayStart(from: cursor, in: calendar, daysOff: daysOff)
          }
          if wholeWeeks >= Self.maxCalendarWeekJump {
            // Far beyond any real cycle: calendar math is slow here, so ignore the sub-week remainder's weekends.
            return cursor.addingTimeInterval((wholeWeeks * 7 + remainingDays - wholeWeeks * Self.workdaysPerWeek) * Self.secondsPerDay)
          }
          cursor = calendar.date(byAdding: .day, value: Int(wholeWeeks) * 7, to: cursor)
            ?? cursor.addingTimeInterval(wholeWeeks * 7 * Self.secondsPerDay)
          remainingDays -= wholeWeeks * Self.workdaysPerWeek
        }
      }
      if !Self.isWorkday(cursor, in: calendar, daysOff: daysOff) {
        cursor = Self.nextWorkdayStart(from: cursor, in: calendar, daysOff: daysOff)
        continue
      }
      let nextMidnight = Self.nextMidnight(after: cursor, in: calendar)
      let daysLeftToday = nextMidnight.timeIntervalSince(cursor) / Self.secondsPerDay
      if remainingDays <= daysLeftToday {
        return cursor.addingTimeInterval(remainingDays * Self.secondsPerDay)
      }
      remainingDays -= daysLeftToday
      cursor = nextMidnight
    }
    return cursor
  }

  // The settings keep marks from past cycles, but only the days off in the cycle that ends at resetDate count.
  public func keepingDaysOff(inCycleEndingAt resetDate: Date) -> RunwayDays {
    guard case .workdays(let timeZone, let daysOff) = self else { return self }
    return .workdays(timeZone, daysOff: DaysOffGrid.inCycle(daysOff, resetDate: resetDate))
  }

  public func dayWord(count: Int = 1) -> String {
    let singular: String
    switch self {
    case .calendar: singular = "day"
    case .workdays: singular = "workday"
    }
    return count == 1 ? singular : singular + "s"
  }

  private static func gregorianCalendar(in timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
  }

  private static func isWorkday(_ date: Date, in calendar: Calendar, daysOff: Set<LocalDay>) -> Bool {
    // Weekday 1 is Sunday and 7 is Saturday in the Gregorian calendar.
    (2...6).contains(calendar.component(.weekday, from: date))
      && (daysOff.isEmpty || !daysOff.contains(LocalDay(date: date, calendar: calendar)))
  }

  private static func nextMidnight(after date: Date, in calendar: Calendar) -> Date {
    let dayStart = calendar.startOfDay(for: date)
    return calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(secondsPerDay)
  }

  private static func nextWorkdayStart(from date: Date, in calendar: Calendar, daysOff: Set<LocalDay>) -> Date {
    var cursor = nextMidnight(after: date, in: calendar)
    while !isWorkday(cursor, in: calendar, daysOff: daysOff) {
      cursor = nextMidnight(after: cursor, in: calendar)
    }
    return cursor
  }
}
