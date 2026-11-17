import Foundation

public enum CopilotAbsence: Equatable, Sendable {
  case ghNotFound
  case notLoggedIn
  case noSeat
}

public enum PortkeyOnly {
  // nil means an outage: Copilot may exist, the app just cannot reach it now.
  public static func absence(for error: CopilotUsageError) -> CopilotAbsence? {
    switch error {
    case .ghNotFound: .ghNotFound
    case .notLoggedIn: .notLoggedIn
    case .invalidResponse: .noSeat
    case .network: nil
    case .httpStatus(let statusCode): (400...499).contains(statusCode) && statusCode != 429 ? .noSeat : nil
    }
  }

  public static func resetDate(now: Date) -> Date {
    let calendar = Runway.utcCalendar
    let monthStart = calendar.dateInterval(of: .month, for: now)!.start
    return calendar.date(byAdding: .month, value: 1, to: monthStart)!
  }

  public static func causeLine(_ absence: CopilotAbsence, hasBudget: Bool) -> String {
    let cause =
      switch absence {
      case .ghNotFound: "GitHub CLI not found, so Copilot data is off."
      case .notLoggedIn: "GitHub CLI not logged in, so Copilot data is off."
      case .noSeat: "No Copilot seat for this GitHub account, so Copilot data is off."
      }
    let followUp = hasBudget ? "The runway shows your Portkey budget." : "Showing Portkey spend only."
    return cause + " " + followUp
  }

  public static func spentTitle(spentUSD: Double, locale: Locale = .current) -> String {
    PortkeySpend.formatted(spentUSD, locale: locale)
  }
}

public struct CopilotAbsenceTracker: Equatable, Sendable {
  public private(set) var absence: CopilotAbsence?
  private var hasSeenCopilot = false
  private var absenceStreak = 0

  public init() {}

  public mutating func observeSuccess() {
    absence = nil
    hasSeenCopilot = true
    absenceStreak = 0
  }

  public mutating func observe(_ error: CopilotUsageError) {
    guard let observedAbsence = PortkeyOnly.absence(for: error) else { return }
    absenceStreak += 1
    // A 403 rate limit or a locked keychain after wake gives one false absence, so a user who had Copilot needs two.
    if !hasSeenCopilot || absenceStreak >= 2 {
      absence = observedAbsence
    }
  }
}
