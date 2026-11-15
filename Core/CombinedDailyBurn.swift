import Foundation

public struct CombinedDay: Equatable, Sendable {
  public let day: Date
  public let copilotUSD: Double
  public let portkeyUSD: Double

  public var totalUSD: Double { copilotUSD + portkeyUSD }

  public init(day: Date, copilotUSD: Double, portkeyUSD: Double) {
    self.day = day
    self.copilotUSD = copilotUSD
    self.portkeyUSD = portkeyUSD
  }
}

// Copilot local credits and Portkey spend per day, both in USD, for the Daily burn chart.
public enum CombinedDailyBurn {
  // One entry per entry of copilot. Portkey records on days that copilot does not list are ignored.
  public static func days(
    copilot: [DailyCredits],
    portkeyRecords: [PortkeyRecord],
    calendar: Calendar = Runway.utcCalendar
  ) -> [CombinedDay] {
    var portkeyUSDByDay: [Date: Double] = [:]
    for record in portkeyRecords {
      portkeyUSDByDay[calendar.startOfDay(for: record.timestamp), default: 0] += record.costUSD ?? 0
    }
    return copilot.map { dailyCredits in
      CombinedDay(
        day: dailyCredits.day,
        copilotUSD: dailyCredits.credits * Credits.usdPerCredit,
        portkeyUSD: portkeyUSDByDay[dailyCredits.day] ?? 0
      )
    }
  }
}
