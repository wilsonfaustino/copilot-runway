import Core
import Foundation
import Testing

@Test func bundledPricesMatchGitHubTable() {
  #expect(PriceTable.bundled["gpt-6.1-sol"] == ModelPrice(
    standard: TokenRates(input: 2.00, cachedInput: 0.10, cacheWrite: 2.50, output: 10.00),
    longContextThreshold: 272_000,
    longContext: TokenRates(input: 4.00, cachedInput: 0.20, cacheWrite: 5.00, output: 15.00)
  ))
  #expect(PriceTable.bundled["gpt-6-luna"] == ModelPrice(
    standard: TokenRates(input: 0.10, cachedInput: 0.01, cacheWrite: 0.125, output: 0.50),
    longContextThreshold: 272_000,
    longContext: TokenRates(input: 0.20, cachedInput: 0.02, cacheWrite: 0.25, output: 0.75)
  ))
  #expect(PriceTable.bundled["gemini-3.8-flash"] == ModelPrice(
    standard: TokenRates(input: 0.75, cachedInput: 0.075, cacheWrite: 0, output: 3.75)
  ))
}

@Test func bundledRatesAreNotNegative() {
  for (modelId, price) in PriceTable.bundled {
    for rates in [price.standard, price.longContext].compactMap({ $0 }) {
      #expect(rates.input >= 0 && rates.cachedInput >= 0 && rates.cacheWrite >= 0 && rates.output >= 0, "\(modelId)")
    }
  }
}

@Test func longContextEntriesHaveThresholdAndRates() {
  for (modelId, price) in PriceTable.bundled {
    #expect((price.longContextThreshold == nil) == (price.longContext == nil), "\(modelId)")
    if let threshold = price.longContextThreshold {
      #expect(threshold > 0, "\(modelId)")
    }
  }
}

@Test func bundledOpenAIPricesMatchGitHubTable() {
  #expect(PriceTable.bundled["gpt-5.5"] == ModelPrice(
    standard: TokenRates(input: 5.00, cachedInput: 0.50, cacheWrite: 0, output: 30.00),
    longContextThreshold: 272_000,
    longContext: TokenRates(input: 10.00, cachedInput: 1.00, cacheWrite: 0, output: 45.00)
  ))
  #expect(PriceTable.bundled["gpt-5.6-luna"] == ModelPrice(
    standard: TokenRates(input: 0.20, cachedInput: 0.02, cacheWrite: 0.25, output: 1.20),
    longContextThreshold: 200_000,
    longContext: TokenRates(input: 0.40, cachedInput: 0.04, cacheWrite: 0.50, output: 1.80)
  ))
  #expect(PriceTable.bundled["gpt-6-sol"] == ModelPrice(
    standard: TokenRates(input: 2.00, cachedInput: 0.20, cacheWrite: 2.50, output: 10.00),
    longContextThreshold: 272_000,
    longContext: TokenRates(input: 4.00, cachedInput: 0.40, cacheWrite: 5.00, output: 15.00)
  ))
  #expect(PriceTable.bundled["gpt-5.3-codex"] == ModelPrice(
    standard: TokenRates(input: 1.75, cachedInput: 0.175, cacheWrite: 0, output: 14.00)
  ))
}

@Test func bundledAnthropicPricesMatchGitHubTable() {
  #expect(PriceTable.bundled["claude-sonnet-4.6"] == ModelPrice(
    standard: TokenRates(input: 3.00, cachedInput: 0.30, cacheWrite: 3.75, output: 15.00)
  ))
  #expect(PriceTable.bundled["claude-opus-5.5"] == ModelPrice(
    standard: TokenRates(input: 4.00, cachedInput: 0.20, cacheWrite: 5.00, output: 20.00)
  ))
  #expect(PriceTable.bundled["claude-haiku-5.5"] == ModelPrice(
    standard: TokenRates(input: 0.10, cachedInput: 0.01, cacheWrite: 0.125, output: 0.50),
    longContextThreshold: 100_000,
    longContext: TokenRates(input: 0.50, cachedInput: 0.05, cacheWrite: 0.625, output: 2.50)
  ))
  #expect(PriceTable.bundled["claude-fable-5.1"] == ModelPrice(
    standard: TokenRates(input: 10.00, cachedInput: 0.25, cacheWrite: 12.50, output: 50.00)
  ))
}

@Test func bundledGoogleMicrosoftXAIAndMoonshotPricesMatchGitHubTable() {
  #expect(PriceTable.bundled["gemini-4-argon"] == ModelPrice(
    standard: TokenRates(input: 2.00, cachedInput: 0.10, cacheWrite: 0, output: 10.00)
  ))
  #expect(PriceTable.bundled["mai-code-1.1-flash"] == ModelPrice(
    standard: TokenRates(input: 0.20, cachedInput: 0.02, cacheWrite: 0, output: 1.20)
  ))
  #expect(PriceTable.bundled["grok-4.6"] == ModelPrice(
    standard: TokenRates(input: 2.00, cachedInput: 0.50, cacheWrite: 0, output: 6.00),
    longContextThreshold: 200_000,
    longContext: TokenRates(input: 4.00, cachedInput: 1.00, cacheWrite: 0, output: 12.00)
  ))
  #expect(PriceTable.bundled["kimi-k3"] == ModelPrice(
    standard: TokenRates(input: 3.00, cachedInput: 0.30, cacheWrite: 0, output: 15.00)
  ))
}

@Test func missingOverrideUsesBundledPrices() throws {
  let missingFile = FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString).json")
  #expect(try PriceTable.load(overrideURL: missingFile) == PriceTable.bundled)
}

@Test func overrideReplacesAndAddsModels() throws {
  let overrideFile = try writeTemporaryFile("""
    {
      "gpt-6.1-sol": { "standard": { "input": 3, "cachedInput": 0.3, "cacheWrite": 3.5, "output": 12 } },
      "example-model": { "standard": { "input": 0.5, "cachedInput": 0.05, "cacheWrite": 0, "output": 3 } }
    }
    """)
  defer { try? FileManager.default.removeItem(at: overrideFile) }
  let prices = try PriceTable.load(overrideURL: overrideFile)
  #expect(prices["gpt-6.1-sol"] == ModelPrice(standard: TokenRates(input: 3, cachedInput: 0.3, cacheWrite: 3.5, output: 12)))
  #expect(prices["example-model"] == ModelPrice(standard: TokenRates(input: 0.5, cachedInput: 0.05, cacheWrite: 0, output: 3)))
  #expect(prices["gpt-6-luna"] == PriceTable.bundled["gpt-6-luna"])
}

@Test func invalidOverrideThrows() throws {
  let overrideFile = try writeTemporaryFile(#"{ "gpt-6.1-sol": { "input": 3 } }"#)
  defer { try? FileManager.default.removeItem(at: overrideFile) }
  #expect(throws: PriceTableError.invalidOverride) {
    try PriceTable.load(overrideURL: overrideFile)
  }
}

func writeTemporaryFile(_ contents: String) throws -> URL {
  let fileURL = FileManager.default.temporaryDirectory.appending(path: "prices-\(UUID().uuidString).json")
  try Data(contents.utf8).write(to: fileURL)
  return fileURL
}
