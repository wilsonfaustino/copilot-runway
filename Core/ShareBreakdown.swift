import Foundation

public struct ShareItem: Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    case entry
    case otherModels
    case notInLocalSessions
  }

  public let name: String
  public let credits: Double
  // Rounded percent of the breakdown's share total.
  public let share: Int
  public let kind: Kind

  public init(name: String, credits: Double, share: Int, kind: Kind) {
    self.name = name
    self.credits = credits
    self.share = share
    self.kind = kind
  }
}

// The items of one split bar. The item credits add up to shareTotal, except that a gap under 1% is left out.
public struct ShareBreakdown: Equatable, Sendable {
  public static let localCreditsUnit = "local credits"
  public static let githubCreditsUnit = "GitHub credits"
  public static let otherModelsName = "Other models"
  public static let notInLocalSessionsName = "Not in local sessions"
  // The dashboard has 3 model colors. More models fold into one "Other models" item.
  public static let namedModelLimit = 3

  public let shareTotal: Double
  public let items: [ShareItem]
  // What shareTotal counts, for the card header.
  public let unit: String

  public init(shareTotal: Double, items: [ShareItem], unit: String = ShareBreakdown.localCreditsUnit) {
    self.shareTotal = shareTotal
    self.items = items
    self.unit = unit
  }

  // True when there is nothing to draw as a bar.
  public var isEmpty: Bool {
    items.isEmpty || shareTotal <= 0
  }

  // Local credits per task or agent. Keeps the order of the entries.
  public static func local(entries: [(name: String, credits: Double)]) -> ShareBreakdown {
    let localTotal = entries.reduce(0) { $0 + $1.credits }
    return ShareBreakdown(
      shareTotal: localTotal,
      items: entries.map { item(name: $0.name, credits: $0.credits, kind: .entry, of: localTotal) }
    )
  }

  // Local credits per task, as local(entries:). Uncategorized always has an item, at 0 when no turn falls in it.
  public static func tasks(_ categoryCredits: [CategoryCredits]) -> ShareBreakdown {
    var entries = categoryCredits.map { (name: $0.category.displayName, credits: $0.credits) }
    if !categoryCredits.contains(where: { $0.category == .uncategorized }) {
      entries.append((TaskCategory.uncategorized.displayName, 0))
    }
    return local(entries: entries)
  }

  // Priced models by credits, the top ones by name and the rest as "Other models". When GitHub reports more
  // credits than local sessions, a last item holds the difference and shares are of the GitHub total.
  // Otherwise shares are of the local total, for example after a price table overestimate, and the unit says so.
  // No local credits gives no items, so the card shows its empty text.
  public static func models(_ modelCredits: [ModelCredits], githubCredits: Double) -> ShareBreakdown {
    let pricedModels: [(name: String, credits: Double)] = modelCredits.compactMap { model in
      model.credits.map { (model.model, $0) }
    }
    .sorted { left, right in
      if left.credits != right.credits { return left.credits > right.credits }
      return left.name < right.name
    }
    let localTotal = pricedModels.reduce(0) { $0 + $1.credits }
    guard localTotal > 0 else { return ShareBreakdown(shareTotal: githubCredits, items: [], unit: githubCreditsUnit) }
    let shareTotal = max(githubCredits, localTotal)
    var items = pricedModels.prefix(namedModelLimit).map { item(name: $0.name, credits: $0.credits, kind: .entry, of: shareTotal) }
    if pricedModels.count > namedModelLimit {
      let otherCredits = pricedModels.dropFirst(namedModelLimit).reduce(0) { $0 + $1.credits }
      items.append(item(name: otherModelsName, credits: otherCredits, kind: .otherModels, of: shareTotal))
    }
    if githubCredits > localTotal {
      let gapItem = item(
        name: notInLocalSessionsName, credits: githubCredits - localTotal, kind: .notInLocalSessions, of: shareTotal
      )
      if gapItem.share > 0 { items.append(gapItem) }
    }
    return ShareBreakdown(
      shareTotal: shareTotal, items: items, unit: githubCredits >= localTotal ? githubCreditsUnit : localCreditsUnit
    )
  }

  // The dashboard By model note that names the models without a price. nil when every model has one.
  public static func unpricedModelsNote(_ modelCredits: [ModelCredits]) -> String? {
    let unpricedModels = modelCredits.filter { $0.credits == nil }.map(\.model).sorted()
    switch unpricedModels.count {
    case 0: return nil
    case 1: return "1 model has no price: \(unpricedModels[0])"
    default: return "\(unpricedModels.count) models have no price: \(unpricedModels.joined(separator: ", "))"
    }
  }

  private static func item(name: String, credits: Double, kind: ShareItem.Kind, of shareTotal: Double) -> ShareItem {
    ShareItem(name: name, credits: credits, share: Credits.sharePercent(credits, of: shareTotal), kind: kind)
  }
}
