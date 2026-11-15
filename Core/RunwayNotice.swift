import Foundation

public struct RunwayNotice: Equatable, Sendable {
  // The raw values are part of the stored keys, so a rename must keep them.
  public enum Kind: String, CaseIterable, Sendable {
    case used80 = "used80"
    case short = "short"
    case critical = "critical"
    case limitReached = "limitReached"
  }

  // What runs out: Copilot credits, or the Portkey budget in USD from PortkeyBudget.usage.
  public enum Subject: Sendable {
    case copilot
    case portkey
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

  // For example "used80-2026-11-01", or "portkey-used80-2026-11-01". The reset date makes each kind fire once per
  // billing cycle. Copilot keys have no prefix, so the keys stored before Portkey notices stay valid.
  public static func key(kind: Kind, resetDate: Date, subject: Subject = .copilot) -> String {
    let prefix = subject == .portkey ? "portkey-" : ""
    return "\(prefix)\(kind.rawValue)-\(resetDate.formatted(.iso8601.year().month().day()))"
  }

  // The notices to send now, in Kind order. A kind fires when it applies and its key is not in sentKeys.
  // Each kind is independent: a more severe notice does not cancel a less severe one that was never sent.
  // critical needs credits left and limitReached needs none, so the two never fire for the same refresh.
  // Missing usage, an unlimited plan, and usage from a past cycle give no notices.
  public static func toSend(
    usage: QuotaUsage?,
    now: Date,
    sentKeys: Set<String>,
    locale: Locale = .current,
    days: RunwayDays = .calendar,
    subject: Subject = .copilot
  ) -> [RunwayNotice] {
    guard let usage, !usage.isUnlimited, usage.entitlement > 0, now < usage.resetDate else { return [] }
    let health = RunwayHealth(usage: usage, now: now, days: days)
    let isPortkey = subject == .portkey
    let runOutSentence =
      isPortkey
      ? RunwayInsight.portkeyRunOutSentence(usage: usage, now: now, locale: locale, days: days) ?? ""
      : RunwayInsight.runOutSentence(usage: usage, now: now, locale: locale, days: days) ?? ""
    let runwayTitle = isPortkey ? "Portkey runway" : "Runway"
    return Kind.allCases.compactMap { kind in
      let key = key(kind: kind, resetDate: usage.resetDate, subject: subject)
      guard !sentKeys.contains(key) else { return nil }
      switch kind {
      case .used80:
        guard usage.creditsUsed >= usage.entitlement * usedShareThreshold else { return nil }
        return RunwayNotice(kind: kind, key: key, title: isPortkey ? "Portkey: 80% of budget used" : "80% of credits used", body: runOutSentence)
      case .short:
        guard health == .short, let daysLeft = Runway.wholeDaysLeft(usage: usage, now: now, days: days) else { return nil }
        let daysText = "\(daysLeft) \(days.dayWord(count: daysLeft))"
        return RunwayNotice(kind: kind, key: key, title: "\(runwayTitle) is short: \(daysText) left", body: runOutSentence)
      case .critical:
        guard health == .critical, usage.creditsRemaining > 0 else { return nil }
        return RunwayNotice(kind: kind, key: key, title: "\(runwayTitle) is critical: under 1 \(days.dayWord()) left", body: runOutSentence)
      case .limitReached:
        guard usage.creditsRemaining <= 0 else { return nil }
        return RunwayNotice(
          kind: kind, key: key, title: isPortkey ? "Portkey budget reached" : "Credit limit reached",
          body: isPortkey
            ? RunwayInsight.portkeyLimitSentence(usage: usage, locale: locale)
            : RunwayInsight.limitSentence(usage: usage, locale: locale)
        )
      }
    }
  }
}
