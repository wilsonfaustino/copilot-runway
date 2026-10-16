import Foundation

// Plain-text report for a quota request. It holds only numbers, dates, model ids and category names:
// no login, org, file path, prompt or command.
public enum QuotaSummary {
  static let topCount = 3

  public static func text(
    usage: CopilotUsage,
    now: Date,
    modelCredits: [ModelCredits],
    categoryCredits: [CategoryCredits],
    outcomes: GitHubOutcomes? = nil
  ) -> String {
    let cycleStart = Runway.cycleStart(resetDate: usage.resetDate)
    let lastCycleDay = Runway.lastCycleDay(resetDate: usage.resetDate)
    var lines = ["GitHub Copilot AI credits, cycle \(day(cycleStart)) to \(day(lastCycleDay)) (UTC)"]
    if usage.isUnlimited {
      lines.append("Used: \(number(usage.creditsUsed)) credits (unlimited plan)")
    } else {
      let percentRemaining = Int(usage.percentRemaining.rounded())
      lines.append("Used: \(number(usage.creditsUsed)) of \(number(usage.entitlement)) credits (\(percentRemaining)% remaining)")
    }
    lines.append("Average daily burn: \(number(Runway.averageDailyBurn(usage: usage, now: now))) credits/day")
    if !usage.isUnlimited {
      lines.append(runOutLine(usage: usage, now: now))
    }
    if let outcomes {
      lines.append(outcomesLine(outcomes: outcomes, creditsUsed: usage.creditsUsed))
    }

    let pricedModels = modelCredits.compactMap { model in model.credits.map { (model.model, $0) } }
    let localTotal = pricedModels.reduce(0) { $0 + $1.1 }
    if localTotal > 0 {
      lines.append("Top models (share of \(number(localTotal)) credits in local sessions):")
      lines += topLines(pricedModels, total: localTotal)
      lines.append("Top categories (same local sessions):")
      lines += topLines(categoryCredits.map { ($0.category.displayName, $0.credits) }, total: localTotal)
    }
    return lines.joined(separator: "\n")
  }

  static func runOutLine(usage: CopilotUsage, now: Date) -> String {
    guard let runOutDate = Runway.runOutDate(usage: usage, now: now) else {
      return "Projected run-out: none, no credits used yet"
    }
    if runOutDate < usage.resetDate {
      return "Projected run-out: \(day(runOutDate)), before the reset on \(day(usage.resetDate))"
    }
    return "Projected run-out: after the reset on \(day(usage.resetDate))"
  }

  static func outcomesLine(outcomes: GitHubOutcomes, creditsUsed: Double) -> String {
    let countsText = "\(GitHubOutcomes.countText(outcomes.prsOpened)) PRs opened, "
      + "\(GitHubOutcomes.countText(outcomes.prsReviewed)) PRs reviewed, \(GitHubOutcomes.countText(outcomes.commits)) commits"
    guard let creditsPerOutcome = outcomes.creditsPerOutcome(creditsUsed: creditsUsed) else {
      return "Outcomes: \(countsText); credits per outcome: none, no PRs opened or reviewed yet"
    }
    return "Outcomes: \(countsText); \(number(creditsPerOutcome)) credits per outcome (PRs opened plus reviewed)"
  }

  // Expects entries sorted by credits, highest first, as Credits returns them.
  static func topLines(_ entries: [(name: String, credits: Double)], total: Double) -> [String] {
    entries.filter { $0.credits > 0 }.prefix(topCount).map { entry in
      "- \(entry.name): \(number(entry.credits)) credits (\(Credits.sharePercent(entry.credits, of: total))%)"
    }
  }

  // ISO 8601 dates are in UTC, and the number locale is fixed, so the text is the same on every machine
  // and the dates match the billing cycle.
  static func day(_ date: Date) -> String {
    date.formatted(.iso8601.year().month().day())
  }

  static func number(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0)).locale(Locale(identifier: "en_US")))
  }
}
