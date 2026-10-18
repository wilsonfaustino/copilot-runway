import Foundation

// The dashboard By model bars, each split by task. The segments of a bar add up to the credits of its item, so a
// bar shows the task mix of that model. "Other models" sums the folded models. Not in local sessions has no task
// and a model without a price is not an item, so neither has segments.
public struct ModelTaskSplit: Equatable, Sendable {
  // Categories with credits, highest spend first like byCategory. Every bar draws its segments in this order.
  public let categories: [TaskCategory]
  // The segments of each model item, without categories at 0.
  public let segments: [ShareItem.ID: [CategoryCredits]]

  public init(breakdown: ShareBreakdown, modelCategoryCredits: [ModelCategoryCredits]) {
    let namedModelIDs = Set(breakdown.items.filter { $0.kind == .entry }.map(\.id))
    let hasOtherModels = breakdown.items.contains { $0.kind == .otherModels }
    var creditsByItem: [ShareItem.ID: [TaskCategory: Double]] = [:]
    var categoryTotals: [TaskCategory: Double] = [:]
    for entry in modelCategoryCredits where entry.credits > 0 {
      let modelID = ShareItem.ID.entry(entry.model)
      guard namedModelIDs.contains(modelID) || hasOtherModels else { continue }
      let itemID = namedModelIDs.contains(modelID) ? modelID : .otherModels
      creditsByItem[itemID, default: [:]][entry.category, default: 0] += entry.credits
      categoryTotals[entry.category, default: 0] += entry.credits
    }
    let categories = categoryTotals.keys.sorted { left, right in
      if categoryTotals[left] != categoryTotals[right] { return categoryTotals[left]! > categoryTotals[right]! }
      return left.rawValue < right.rawValue
    }
    self.categories = categories
    segments = creditsByItem.mapValues { itemCredits in
      categories.compactMap { category in
        guard let credits = itemCredits[category] else { return nil }
        return CategoryCredits(category: category, credits: credits)
      }
    }
  }

  // The hover text of a segment, for example "Debugging, 31%, 1,925 credits". The share is of the credits of its item.
  public static func segmentSummary(_ segment: CategoryCredits, of itemCredits: Double, locale: Locale = .current) -> String {
    let share = Credits.shareLabel(segment.credits, of: itemCredits)
    return "\(segment.category.displayName), \(share), \(Credits.formatted(segment.credits, locale: locale)) credits"
  }

  // The VoiceOver value of a model row, for example "6,210 credits, 42% of all credits. Debugging, 31%, 1,925 credits.".
  // The task summaries follow the order of the bar. An item without segments has the total and share only.
  public func rowSummary(for item: ShareItem, locale: Locale = .current) -> String {
    let itemSegments = segments[item.id] ?? []
    let segmentsTotal = itemSegments.reduce(0) { $0 + $1.credits }
    let totalSummary = "\(Credits.formatted(item.credits, locale: locale)) credits, \(item.share)% of all credits."
    let taskSummaries = itemSegments.map { Self.segmentSummary($0, of: segmentsTotal, locale: locale) + "." }
    return ([totalSummary] + taskSummaries).joined(separator: " ")
  }
}
