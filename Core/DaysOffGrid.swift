import Foundation

public struct DaysOffGrid {
  public struct Cell: Equatable {
    public let day: LocalDay
    public let isWeekend: Bool
  }

  public let leadingBlanks: Int
  public let cells: [Cell]

  private static let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }()

  // firstWeekday uses the Calendar convention: 1 is Sunday, 2 is Monday.
  public init(resetDate: Date, firstWeekday: Int) {
    let cycleStart = Runway.cycleStart(resetDate: resetDate)
    let firstDay = LocalDay(date: cycleStart, calendar: Self.utcCalendar)
    let weekdayOfFirstDay = Self.weekday(of: firstDay)
    leadingBlanks = (weekdayOfFirstDay - firstWeekday + 7) % 7
    cells = (1...Runway.cycleDayCount(resetDate: resetDate)).map { dayOfMonth in
      let day = LocalDay(string: String(format: "%04d-%02d-%02d", firstDay.year, firstDay.month, dayOfMonth))!
      return Cell(day: day, isWeekend: Self.isWeekend(day))
    }
  }

  public static func inCycle(_ days: Set<LocalDay>, resetDate: Date) -> Set<LocalDay> {
    let cycleStart = LocalDay(date: Runway.cycleStart(resetDate: resetDate), calendar: utcCalendar)
    return days.filter { $0.year == cycleStart.year && $0.month == cycleStart.month && !isWeekend($0) }
  }

  public static func range(from firstDay: LocalDay, to secondDay: LocalDay) -> Set<LocalDay> {
    let start = min(firstDay, secondDay)
    let end = max(firstDay, secondDay)
    var workdays: Set<LocalDay> = []
    var date = noonUTC(of: start)
    while true {
      let day = LocalDay(date: date, calendar: utcCalendar)
      if day > end { break }
      if !isWeekend(day) { workdays.insert(day) }
      date = utcCalendar.date(byAdding: .day, value: 1, to: date)!
    }
    return workdays
  }

  // A plain click toggles the day. A shift-click marks the range from the last clicked day, or toggles when there is none.
  public static func clicking(
    _ day: LocalDay, in markedDays: Set<LocalDay>, isShift: Bool, lastClicked: LocalDay?
  ) -> Set<LocalDay> {
    if isShift, let lastClicked {
      return markedDays.union(range(from: lastClicked, to: day))
    }
    return markedDays.symmetricDifference([day])
  }

  private static func noonUTC(of day: LocalDay) -> Date {
    utcCalendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))!
  }

  private static func weekday(of day: LocalDay) -> Int {
    utcCalendar.component(.weekday, from: noonUTC(of: day))
  }

  private static func isWeekend(_ day: LocalDay) -> Bool {
    let weekday = weekday(of: day)
    return weekday == 1 || weekday == 7
  }
}
