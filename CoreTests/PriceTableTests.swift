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
