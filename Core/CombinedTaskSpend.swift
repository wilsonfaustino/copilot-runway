import Foundation

public struct CategoryUSD: Equatable, Sendable {
  public let category: TaskCategory
  public let usd: Double

  public init(category: TaskCategory, usd: Double) {
    self.category = category
    self.usd = usd
  }
}

// Copilot local credits and Portkey spend per task, both in USD, for the General By task card.
public enum CombinedTaskSpend {
  // Copilot credits at US$0.01 each plus the Portkey cost of each category. Unpriced Portkey records add no row.
  // Highest spend first, then by category, as Credits.byCategory.
  public static func byCategory(copilot: [CategoryCredits], portkeyRecords: [PortkeyRecord]) -> [CategoryUSD] {
    var usdByCategory: [TaskCategory: Double] = [:]
    for categoryCredits in copilot {
      usdByCategory[categoryCredits.category, default: 0] += categoryCredits.credits * Credits.usdPerCredit
    }
    for record in portkeyRecords {
      guard let costUSD = record.costUSD else { continue }
      usdByCategory[record.category, default: 0] += costUSD
    }
    return usdByCategory.map { CategoryUSD(category: $0.key, usd: $0.value) }.sorted { left, right in
      if left.usd != right.usd { return left.usd > right.usd }
      return left.category.rawValue < right.category.rawValue
    }
  }

  // The split bar of the card: as ShareBreakdown.tasks, in USD.
  public static func breakdown(copilot: [CategoryCredits], portkeyRecords: [PortkeyRecord]) -> ShareBreakdown {
    let categoryUSD = byCategory(copilot: copilot, portkeyRecords: portkeyRecords)
    // ShareBreakdown.tasks takes CategoryCredits, so credits holds USD here.
    let tasks = ShareBreakdown.tasks(categoryUSD.map { CategoryCredits(category: $0.category, credits: $0.usd) })
    return ShareBreakdown(shareTotal: tasks.shareTotal, items: tasks.items, unit: ShareBreakdown.localUSDUnit, isUSD: true)
  }
}
