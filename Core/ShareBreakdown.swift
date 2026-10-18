import Foundation

public struct ShareItem: Equatable, Sendable, Identifiable {
  // An entry is keyed by its raw model id, or by its name for a task or an agent. A model id can read
  // "Other models", so the folded and gap items have their own cases.
  public enum ID: Hashable, Sendable {
    case entry(String)
    case otherModels
    case notInLocalSessions
  }

  public enum Kind: Equatable, Sendable {
    case entry
    case otherModels
    case notInLocalSessions
  }

  public let id: ID
  // The label to draw. Not unique, because a raw model id can equal the display name of another.
  public let name: String
  public let credits: Double
  // Rounded percent of the breakdown's share total.
  public let share: Int

  public init(id: ID, name: String, credits: Double, share: Int) {
    self.id = id
    self.name = name
    self.credits = credits
    self.share = share
  }

  public var kind: Kind {
    switch id {
    case .entry: .entry
    case .otherModels: .otherModels
    case .notInLocalSessions: .notInLocalSessions
    }
  }
}

// The items of one split bar. The item credits add up to shareTotal, except that a gap under 1% is left out.
public struct ShareBreakdown: Equatable, Sendable {
  public static let localCreditsUnit = "local credits"
  public static let githubCreditsUnit = "GitHub credits"
  public static let otherModelsName = "Other models"
  public static let notInLocalSessionsName = "Not in local sessions"
  // The popover has 3 model colors. More models fold into one "Other models" item.
  public static let namedModelLimit = 3
  // The dashboard By model bars are split by task and need no model colors, so they name more models.
  public static let taskSplitModelLimit = 5

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
      items: entries.map { item(id: .entry($0.name), name: $0.name, credits: $0.credits, of: localTotal) }
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
  public static func models(
    _ modelCredits: [ModelCredits], githubCredits: Double, namedModelLimit: Int = ShareBreakdown.namedModelLimit
  ) -> ShareBreakdown {
    let pricedModels: [(model: String, credits: Double)] = modelCredits.compactMap { model in
      model.credits.map { (model.model, $0) }
    }
    .sorted { left, right in
      if left.credits != right.credits { return left.credits > right.credits }
      return left.model < right.model
    }
    let localTotal = pricedModels.reduce(0) { $0 + $1.credits }
    guard localTotal > 0 else { return ShareBreakdown(shareTotal: githubCredits, items: [], unit: githubCreditsUnit) }
    let shareTotal = max(githubCredits, localTotal)
    var items = pricedModels.prefix(namedModelLimit).map {
      item(id: .entry($0.model), name: ModelDisplayName.name(for: $0.model), credits: $0.credits, of: shareTotal)
    }
    if pricedModels.count > namedModelLimit {
      let otherCredits = pricedModels.dropFirst(namedModelLimit).reduce(0) { $0 + $1.credits }
      items.append(item(id: .otherModels, name: otherModelsName, credits: otherCredits, of: shareTotal))
    }
    if githubCredits > localTotal {
      let gapItem = item(
        id: .notInLocalSessions, name: notInLocalSessionsName, credits: githubCredits - localTotal, of: shareTotal
      )
      if gapItem.share > 0 { items.append(gapItem) }
    }
    return ShareBreakdown(
      shareTotal: shareTotal, items: items, unit: githubCredits >= localTotal ? githubCreditsUnit : localCreditsUnit
    )
  }

  // The line under the "Not in local sessions" item: Copilot code reviews are the likely source of the remainder.
  // nil without reviews or that item, and when a local model has no price, because the remainder then holds
  // that model's use too.
  public func copilotReviewNote(reviewCount: Int, modelCredits: [ModelCredits], locale: Locale = .current) -> String? {
    guard reviewCount > 0, !modelCredits.contains(where: { $0.credits == nil }),
      let remainder = items.first(where: { $0.kind == .notInLocalSessions })
    else { return nil }
    let creditsPerReview = Credits.formatted(remainder.credits / Double(reviewCount), locale: locale)
    if reviewCount == 1 { return "Likely 1 Copilot review, ~\(creditsPerReview) credits" }
    return "Likely \(reviewCount) Copilot reviews, ~\(creditsPerReview) each"
  }

  // The dashboard By model note that names the models without a price. nil when every model has one.
  public static func unpricedModelsNote(_ modelCredits: [ModelCredits]) -> String? {
    let unpricedModels = modelCredits.filter { $0.credits == nil }.map(\.model).sorted().map(ModelDisplayName.name(for:))
    switch unpricedModels.count {
    case 0: return nil
    case 1: return "1 model has no price: \(unpricedModels[0])"
    default: return "\(unpricedModels.count) models have no price: \(unpricedModels.joined(separator: ", "))"
    }
  }

  // The models without a price, as raw id and label, in the order of modelCredits.
  public static func unpricedModels(_ modelCredits: [ModelCredits]) -> [(id: String, name: String)] {
    modelCredits.filter { $0.credits == nil }.map { ($0.model, ModelDisplayName.name(for: $0.model)) }
  }

  // The low cache hit percent of each model, keyed like the model items.
  public static func lowCachePercents(_ cacheHits: [ModelCacheHit]) -> [ShareItem.ID: Int] {
    Dictionary(
      cacheHits.filter(\.isLow).compactMap { cacheHit in cacheHit.wholePercent.map { (.entry(cacheHit.model), $0) } },
      uniquingKeysWith: { first, _ in first }
    )
  }

  private static func item(id: ShareItem.ID, name: String, credits: Double, of shareTotal: Double) -> ShareItem {
    ShareItem(id: id, name: name, credits: credits, share: Credits.sharePercent(credits, of: shareTotal))
  }
}
