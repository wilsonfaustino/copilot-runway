import Foundation

public enum RunwayDays: Equatable, Sendable {
  case calendar
  case workdays(TimeZone)

  private static let secondsPerDay: Double = 86_400
  private static let workdaysPerWeek: Double = 5
  private static let maxCalendarWeekJump: Double = 1_000_000

  public func dayCount(from start: Date, to end: Date) -> Double {
    guard case .workdays(let timeZone) = self, end > start else {
      return end.timeIntervalSince(start) / Self.secondsPerDay
    }
    let calendar = Self.gregorianCalendar(in: timeZone)
    var workdaySeconds = 0.0
    var cursor = start
    while cursor < end {
      let segmentEnd = min(Self.nextMidnight(after: cursor, in: calendar), end)
      if Self.isWorkday(cursor, in: calendar) {
        workdaySeconds += segmentEnd.timeIntervalSince(cursor)
      }
      cursor = segmentEnd
    }
    return workdaySeconds / Self.secondsPerDay
  }

  public func date(addingDays days: Double, to start: Date) -> Date {
    guard case .workdays(let timeZone) = self, days > 0 else {
      return start.addingTimeInterval(days * Self.secondsPerDay)
    }
    let calendar = Self.gregorianCalendar(in: timeZone)
    var cursor = start
    var remainingDays = days

    // Whole weeks first: a huge count (early in a cycle, or a large Portkey budget) would otherwise walk day by day for ages.
    // Stop one week short so the walk ends the count inside a workday, at the earliest instant.
    let wholeWeeks = (remainingDays / Self.workdaysPerWeek).rounded(.up) - 1
    if wholeWeeks > 0 {
      if !Self.isWorkday(cursor, in: calendar) {
        cursor = Self.nextWorkdayStart(from: cursor, in: calendar)
      }
      if wholeWeeks >= Self.maxCalendarWeekJump {
        // Far beyond any real cycle: calendar math is slow here, so ignore the sub-week remainder's weekends.
        return cursor.addingTimeInterval((wholeWeeks * 7 + remainingDays - wholeWeeks * Self.workdaysPerWeek) * Self.secondsPerDay)
      }
      cursor = calendar.date(byAdding: .day, value: Int(wholeWeeks) * 7, to: cursor)
        ?? cursor.addingTimeInterval(wholeWeeks * 7 * Self.secondsPerDay)
      remainingDays -= wholeWeeks * Self.workdaysPerWeek
    }

    while remainingDays > 0 {
      if !Self.isWorkday(cursor, in: calendar) {
        cursor = Self.nextWorkdayStart(from: cursor, in: calendar)
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

  private static func isWorkday(_ date: Date, in calendar: Calendar) -> Bool {
    // Weekday 1 is Sunday and 7 is Saturday in the Gregorian calendar.
    (2...6).contains(calendar.component(.weekday, from: date))
  }

  private static func nextMidnight(after date: Date, in calendar: Calendar) -> Date {
    let dayStart = calendar.startOfDay(for: date)
    return calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(secondsPerDay)
  }

  private static func nextWorkdayStart(from date: Date, in calendar: Calendar) -> Date {
    var cursor = nextMidnight(after: date, in: calendar)
    while !isWorkday(cursor, in: calendar) {
      cursor = nextMidnight(after: cursor, in: calendar)
    }
    return cursor
  }
}
