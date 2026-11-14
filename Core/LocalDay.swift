import Foundation

public struct LocalDay: Hashable, Comparable, Sendable {
  public let year: Int
  public let month: Int
  public let day: Int

  public init?(string: String) {
    let parts = string.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3,
      zip(parts, [4, 2, 2]).allSatisfy({ part, length in part.count == length && part.allSatisfy(\.isASCII) && part.allSatisfy(\.isNumber) }),
      let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
    else { return nil }
    var utcCalendar = Calendar(identifier: .gregorian)
    utcCalendar.timeZone = TimeZone(identifier: "UTC")!
    guard DateComponents(year: year, month: month, day: day).isValidDate(in: utcCalendar) else { return nil }
    self.year = year
    self.month = month
    self.day = day
  }

  public init(date: Date, timeZone: TimeZone) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    self.init(date: date, calendar: calendar)
  }

  init(date: Date, calendar: Calendar) {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    year = components.year ?? 0
    month = components.month ?? 0
    day = components.day ?? 0
  }

  public var string: String {
    String(format: "%04d-%02d-%02d", year, month, day)
  }

  public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
    (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
  }
}
