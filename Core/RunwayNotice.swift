import Foundation

public struct RunwayNotice: Equatable, Sendable {
  // The raw values are part of the stored keys, so a rename must keep them.
  public enum Kind: String, CaseIterable, Sendable {
    case used80 = "used80"
    case short = "short"
    case critical = "critical"
    case limitReached = "limitReached"
  }

  public let kind: Kind
  public let key: String
  public let title: String
  public let body: String

  public init(kind: Kind, key: String, title: String, body: String) {
    self.kind = kind
    self.key = key
    self.title = title
    self.body = body
  }

  static let usedShareThreshold = 0.8

  // For example "used80-2026-11-01". The reset date makes each kind fire once per billing cycle.
  public static func key(kind: Kind, resetDate: Date) -> String {
    "\(kind.rawValue)-\(resetDate.formatted(.iso8601.year().month().day()))"
  }

  // The notices to send now, in Kind order. A kind fires when it applies and its key is not in sentKeys.
  // Each kind is independent: a more severe notice does not cancel a less severe one that was never sent.
  // critical needs credits left and limitReached needs none, so the two never fire for the same refresh.
  // Missing usage, an unlimited plan, and usage from a past cycle give no notices.
  public static func toSend(
    usage: CopilotUsage?,
    now: Date,
    sentKeys: Set<String>,
    locale: Locale = .current
  ) -> [RunwayNotice] {
    guard let usage, !usage.isUnlimited, usage.entitlement > 0, now < usage.resetDate else { return [] }
    let health = RunwayHealth(usage: usage, now: now)
    let runOutSentence = RunwayInsight.runOutSentence(usage: usage, now: now, locale: locale) ?? ""
    return Kind.allCases.compactMap { kind in
      let key = key(kind: kind, resetDate: usage.resetDate)
      guard !sentKeys.contains(key) else { return nil }
      switch kind {
      case .used80:
        guard usage.creditsUsed >= usage.entitlement * usedShareThreshold else { return nil }
        return RunwayNotice(kind: kind, key: key, title: "80% of credits used", body: runOutSentence)
      case .short:
        guard health == .short, let daysLeft = Runway.wholeDaysLeft(usage: usage, now: now) else { return nil }
        let daysText = daysLeft == 1 ? "1 day" : "\(daysLeft) days"
        return RunwayNotice(kind: kind, key: key, title: "Runway is short: \(daysText) left", body: runOutSentence)
      case .critical:
        guard health == .critical, usage.creditsRemaining > 0 else { return nil }
        return RunwayNotice(kind: kind, key: key, title: "Runway is critical: under 1 day left", body: runOutSentence)
      case .limitReached:
        guard usage.creditsRemaining <= 0 else { return nil }
        return RunwayNotice(
          kind: kind, key: key, title: "Credit limit reached", body: RunwayInsight.limitSentence(usage: usage, locale: locale)
        )
      }
    }
  }
}
