import Core
import Foundation
import Testing

func cacheRecord(model: String, input: Int, cachedInput: Int, cacheWrite: Int = 0, output: Int = 0) -> UsageRecord {
  UsageRecord(
    model: model,
    timestamp: utcDate("2026-10-05T12:00:00Z"),
    tokens: TokenUsage(input: input, cachedInput: cachedInput, cacheWrite: cacheWrite, output: output)
  )
}

func cachePrice(input: Double, cachedInput: Double) -> ModelPrice {
  ModelPrice(standard: TokenRates(input: input, cachedInput: cachedInput, cacheWrite: 0, output: 1))
}

@Test func cacheHitRateIsCachedInputOverPromptTokens() {
  // (600 + 200) cached of (1000 + 1000) prompt tokens, cache write included.
  let records = [
    cacheRecord(model: "gpt-6.1-sol", input: 300, cachedInput: 600, cacheWrite: 100, output: 5000),
    cacheRecord(model: "gpt-6.1-sol", input: 800, cachedInput: 200),
  ]
  #expect(CacheHit.rate(records: records) == 0.4)
}

@Test func cacheHitAtThresholdIsNotLow() {
  #expect(CacheHit.lowThreshold == 0.5)
  #expect(!ModelCacheHit(model: "gpt-6.1-sol", rate: 0.5).isLow)
  let justBelow = ModelCacheHit(model: "gpt-6.1-sol", rate: 0.499)
  #expect(justBelow.isLow)
  #expect(justBelow.wholePercent == 49)
  #expect(ModelCacheHit(model: "gpt-6.1-sol", rate: 0.29).wholePercent == 29)
  #expect(ModelCacheHit(model: "gpt-6.1-sol", rate: 0.866).wholePercent == 87)
}

@Test func modelWithoutPromptTokensHasNoCacheHitRate() {
  #expect(CacheHit.rate(records: []) == nil)
  let cacheHits = CacheHit.byModel(
    records: [cacheRecord(model: "gpt-6-luna", input: 0, cachedInput: 0, output: 400)], prices: PriceTable.bundled
  )
  #expect(cacheHits == [ModelCacheHit(model: "gpt-6-luna", rate: nil)])
  #expect(!cacheHits[0].isLow)
  #expect(cacheHits[0].wholePercent == nil)
  #expect(CacheHit.lowSentences(cacheHits: cacheHits, prices: PriceTable.bundled).isEmpty)
}

@Test func cacheSentenceNamesBundledPriceRatios() {
  let cacheHits = ["gpt-6.1-sol", "gpt-6-luna", "gemini-3.8-flash"].map { ModelCacheHit(model: $0, rate: 0.41) }
  #expect(CacheHit.lowSentences(cacheHits: cacheHits, prices: PriceTable.bundled) == [
    "GPT-6.1 Sol cache hit is 41%. Cached input costs one twentieth of fresh input.",
    "GPT-6 Luna cache hit is 41%. Cached input costs one tenth of fresh input.",
    "Gemini 3.8 Flash cache hit is 41%. Cached input costs one tenth of fresh input.",
  ])
}

@Test func cacheSentenceNamesQuarterHalfAndOtherRatios() {
  let prices = [
    "quarter-model": cachePrice(input: 2.00, cachedInput: 0.50),
    "half-model": cachePrice(input: 2.00, cachedInput: 1.00),
    "other-model": cachePrice(input: 2.00, cachedInput: 0.60),
  ]
  let cacheHits = ["quarter-model", "half-model", "other-model"].map { ModelCacheHit(model: $0, rate: 0.2) }
  #expect(CacheHit.lowSentences(cacheHits: cacheHits, prices: prices) == [
    "quarter-model cache hit is 20%. Cached input costs one quarter of fresh input.",
    "half-model cache hit is 20%. Cached input costs half of fresh input.",
    "other-model cache hit is 20%. Cached input costs 30% of the price of fresh input.",
  ])
}

@Test func cacheSentenceWithoutPriceHasRateOnly() {
  let prices = ["no-cached-price-model": cachePrice(input: 2.00, cachedInput: 0)]
  let cacheHits = ["unknown-model", "no-cached-price-model"].map { ModelCacheHit(model: $0, rate: 0.3) }
  #expect(CacheHit.lowSentences(cacheHits: cacheHits, prices: prices) == [
    "unknown-model cache hit is 30%.",
    "no-cached-price-model cache hit is 30%.",
  ])
}

@Test func lowCacheSentencesPutHighestCreditsFirst() {
  let records = [
    cacheRecord(model: "unknown-model", input: 900_000, cachedInput: 100_000),
    cacheRecord(model: "gpt-6-luna", input: 70_000, cachedInput: 30_000),
    cacheRecord(model: "gemini-3.8-flash", input: 100_000, cachedInput: 900_000),
    cacheRecord(model: "gpt-6.1-sol", input: 600_000, cachedInput: 400_000),
  ]
  let cacheHits = CacheHit.byModel(records: records, prices: PriceTable.bundled)
  #expect(cacheHits.map(\.model) == ["gpt-6.1-sol", "gemini-3.8-flash", "gpt-6-luna", "unknown-model"])
  #expect(CacheHit.lowSentences(cacheHits: cacheHits, prices: PriceTable.bundled) == [
    "GPT-6.1 Sol cache hit is 40%. Cached input costs one twentieth of fresh input.",
    "GPT-6 Luna cache hit is 30%. Cached input costs one tenth of fresh input.",
    "unknown-model cache hit is 10%.",
  ])
}

@Test func sessionCacheHitsFollowByModelOrder() throws {
  let openCodeDirectory = try makeOpenCodeDataDirectory()
  defer { try? FileManager.default.removeItem(at: openCodeDirectory) }
  let sessionCredits = SessionCredits.load(
    since: fixtureCycleStart,
    now: sessionCreditsNow,
    piDirectory: fixturesDirectory.appending(path: "pi/sessions"),
    openCodeDirectory: openCodeDirectory,
    ompDirectory: fixturesDirectory.appending(path: "missing"),
    priceURL: missingPriceURL
  )
  #expect(!sessionCredits.cacheHits.isEmpty)
  #expect(sessionCredits.cacheHits.map(\.model) == sessionCredits.byModel.map(\.model))
  #expect(
    sessionCredits.lowCacheSentences
      == CacheHit.lowSentences(cacheHits: sessionCredits.cacheHits, prices: PriceTable.bundled)
  )
}
