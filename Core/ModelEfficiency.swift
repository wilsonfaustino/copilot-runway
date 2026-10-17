import Foundation

public struct ModelEfficiency: Equatable, Sendable {
  public let model: String
  // Implementation and Debugging turns.
  public let editTurns: Int
  // Debugging turns.
  public let retryTurns: Int
  public let creditsPerEditTurn: Double

  public init(model: String, editTurns: Int, retryTurns: Int, creditsPerEditTurn: Double) {
    self.model = model
    self.editTurns = editTurns
    self.retryTurns = retryTurns
    self.creditsPerEditTurn = creditsPerEditTurn
  }

  public var retryPercent: Int { Credits.sharePercent(Double(retryTurns), of: Double(editTurns)) }
}

extension ModelEfficiency {
  // Under about 10 edit turns, one turn moves the retry rate by 10 or more points.
  static let minimumEditTurns = 10

  public static func byModel(turns: [Turn], prices: [String: ModelPrice]) -> [ModelEfficiency] {
    var editTurnsByModel: [String: [Turn]] = [:]
    for turn in turns where isEditTurn(turn) {
      let models = Set(turn.records.map(\.model))
      guard models.count == 1, let model = models.first else { continue }
      editTurnsByModel[model, default: []].append(turn)
    }
    let efficiencies = editTurnsByModel.compactMap { model, modelTurns -> ModelEfficiency? in
      guard
        modelTurns.count >= minimumEditTurns,
        let credits = Credits.byModel(records: modelTurns.flatMap(\.records), prices: prices).first?.credits
      else { return nil }
      return ModelEfficiency(
        model: model,
        editTurns: modelTurns.count,
        retryTurns: modelTurns.filter { TaskCategorizer.category(of: $0) == .debugging }.count,
        creditsPerEditTurn: credits / Double(modelTurns.count)
      )
    }
    return efficiencies.sorted { left, right in
      if left.editTurns != right.editTurns { return left.editTurns > right.editTurns }
      return left.model < right.model
    }
  }

  // Compares the first 2 models, the cheaper one first.
  public static func note(_ efficiencies: [ModelEfficiency], locale: Locale = .current) -> String? {
    guard let first = efficiencies.first else { return nil }
    guard efficiencies.count >= 2 else {
      let creditsText = creditsText(first.creditsPerEditTurn, locale: locale)
      let unit = creditsText == "1" ? "credit" : "credits"
      return "\(ModelDisplayName.name(for: first.model)) costs \(creditsText) \(unit) per edit turn. Retry rate \(first.retryPercent)%."
    }
    let second = efficiencies[1]
    let (cheaper, costlier) = first.creditsPerEditTurn <= second.creditsPerEditTurn ? (first, second) : (second, first)
    let percentLess = costlier.creditsPerEditTurn > 0
      ? Int(((1 - cheaper.creditsPerEditTurn / costlier.creditsPerEditTurn) * 100).rounded())
      : 0
    let cheaperName = ModelDisplayName.name(for: cheaper.model)
    let costlierName = ModelDisplayName.name(for: costlier.model)
    let costSentence = percentLess == 0
      ? "\(cheaperName) and \(costlierName) cost the same per edit turn."
      : "\(cheaperName) costs \(percentLess)% less per edit turn than \(costlierName)."
    return "\(costSentence) Retry rate \(cheaper.retryPercent)% against \(costlier.retryPercent)%."
  }

  // Whole credits would show 0 for cheap models, which can spend well under 1 credit per edit turn.
  static func creditsText(_ credits: Double, locale: Locale) -> String {
    guard credits < 1 else { return Credits.formatted(credits, locale: locale) }
    return credits.formatted(.number.precision(.significantDigits(1...2)).locale(locale))
  }

  static func isEditTurn(_ turn: Turn) -> Bool {
    let category = TaskCategorizer.category(of: turn)
    return category == .implementation || category == .debugging
  }
}
