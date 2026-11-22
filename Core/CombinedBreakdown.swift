import Foundation

// Copilot local credits and Portkey spend per model and per agent, both in USD, for the General By model and By agent
// cards. Only priced spend counts, and a row with no priced spend is left out.
public enum CombinedBreakdown {
  // One row per provider and full model id, never joined across providers. A Portkey row whose name is also on another
  // row shows its full gateway id with " (Portkey)". Highest spend first, then by name, then by id. The top
  // namedModelLimit by name and the rest as "Other models".
  public static func models(copilot: [ModelCredits], portkey: PortkeySpend) -> ShareBreakdown {
    let copilotRows = copilot.compactMap { modelCredits -> (id: String, name: String, usd: Double)? in
      guard let credits = modelCredits.credits, credits > 0 else { return nil }
      return ("copilot:" + modelCredits.model, ModelDisplayName.name(for: modelCredits.model), credits * Credits.usdPerCredit)
    }
    let portkeyRows = portkey.byModel.filter { $0.usd > 0 }.map { modelSpend in
      (model: modelSpend.model, name: ModelDisplayName.portkeyName(for: modelSpend.model), usd: modelSpend.usd)
    }
    let rowCountByName = Dictionary((copilotRows.map(\.name) + portkeyRows.map(\.name)).map { ($0, 1) }, uniquingKeysWith: +)
    let rows = (
      copilotRows + portkeyRows.map { row in
        (id: "portkey:" + row.model, name: rowCountByName[row.name, default: 0] > 1 ? row.model + " (Portkey)" : row.name, usd: row.usd)
      }
    )
    .sorted { left, right in
      if left.usd != right.usd { return left.usd > right.usd }
      if left.name != right.name { return left.name < right.name }
      return left.id < right.id
    }
    let namedModelLimit = ShareBreakdown.namedModelLimit
    var entries: [(id: ShareItem.ID, name: String, usd: Double)] = rows.prefix(namedModelLimit).map { (.entry($0.id), $0.name, $0.usd) }
    if rows.count > namedModelLimit {
      entries.append((.otherModels, ShareBreakdown.otherModelsName, rows.dropFirst(namedModelLimit).reduce(0) { $0 + $1.usd }))
    }
    let totalUSD = rows.reduce(0) { $0 + $1.usd }
    let shares = Credits.sharePercents(entries.map(\.usd), of: totalUSD)
    return ShareBreakdown(
      shareTotal: totalUSD,
      items: zip(entries, shares).map { entry, share in ShareItem(id: entry.id, name: entry.name, credits: entry.usd, share: share) },
      unit: ShareBreakdown.localUSDUnit,
      isUSD: true
    )
  }

  // Spend from both providers for one agent adds into one row. Highest spend first, then by source, as Credits.bySource.
  public static func agents(copilot: [SourceCredits], portkey: PortkeySpend) -> ShareBreakdown {
    var usdBySource: [SessionSource: Double] = [:]
    for sourceCredits in copilot {
      usdBySource[sourceCredits.source, default: 0] += sourceCredits.credits * Credits.usdPerCredit
    }
    for sourceSpend in portkey.bySource {
      usdBySource[sourceSpend.source, default: 0] += sourceSpend.usd
    }
    let entries = usdBySource.filter { $0.value > 0 }
      .sorted { left, right in
        if left.value != right.value { return left.value > right.value }
        return left.key.rawValue < right.key.rawValue
      }
      .map { (name: $0.key.displayName, credits: $0.value) }
    // ShareBreakdown.local takes credits, so credits holds USD here.
    let agents = ShareBreakdown.local(entries: entries)
    return ShareBreakdown(shareTotal: agents.shareTotal, items: agents.items, unit: ShareBreakdown.localUSDUnit, isUSD: true)
  }
}
