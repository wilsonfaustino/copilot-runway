import Foundation

public enum RunwayHealth: Equatable, Sendable {
  case healthy
  case short
  case critical
  case unavailable

  // Critical wins over short. A plan with no limit or no burn yet has no run-out, so it is healthy.
  public init(usage: CopilotUsage, now: Date) {
    guard let daysLeft = Runway.daysLeft(usage: usage, now: now),
      let runOutDate = Runway.runOutDate(usage: usage, now: now)
    else {
      self = .healthy
      return
    }
    if daysLeft < 1 {
      self = .critical
    } else if runOutDate < usage.resetDate {
      self = .short
    } else {
      self = .healthy
    }
  }

  // The last good usage can be stale, so any fetch error makes the health unavailable.
  public init(usage: CopilotUsage?, hasError: Bool, now: Date) {
    guard let usage, !hasError else {
      self = .unavailable
      return
    }
    self.init(usage: usage, now: now)
  }
}
