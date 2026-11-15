# Combined Budget Gauge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** With a Portkey budget set, every gauge shows one USD budget (Copilot limit plus Portkey budget), split into a Copilot part and a Portkey part in two tones of the health color.

**Architecture:** One new pure Core type, `CombinedBudget`, maps Copilot credits and Portkey USD onto one `QuotaUsage` in USD and computes the two gauge parts. The existing `MenuBarTitle`, `Runway`, `RunwayHealth` and `RunwayInsight` take that `QuotaUsage` unchanged. `UsageStore` exposes a gauge usage (combined, else Copilot) and every gauge view draws `GaugeParts`.

**Tech Stack:** Swift 6, SwiftUI and AppKit, Swift Testing (`import Testing`, `@Test`, `#expect`), XcodeGen.

**Spec:** GitHub issue #73 (body plus the "Design approved" comment). Design canvas (private): https://claude.ai/artifact/Bu1MDYJGnoer4Sax91pBmD. Canvas numbers are illustrative; the tests below pin the real values.

## Global Constraints

- Branch `wilsonfaustino/combined-budget-gauge` from `main`. `main` needs a PR.
- New files need `xcodegen generate` before a build. Never edit the `.pbxproj`.
- Whole suite: `xcodebuild test -scheme CopilotRunway -destination 'platform=macOS' -derivedDataPath build/combined` -> `** TEST SUCCEEDED **`.
- No em dashes anywhere (code, comments, strings, docs). 2-space indent. No new protocols.
- No new setting and no new UserDefaults key. The existing `UsageStore.portkeyBudgetKey` turns the combined gauge on (budget > 0) and off.
- 1 credit = US$0.01: use `Credits.usdPerCredit`, do not add a second constant.
- Combined only when a Portkey budget > 0 is set and the Copilot plan is not unlimited. Otherwise every gauge looks and reads as today.
- Tones: Copilot part = `Theme.accent(health)` at full opacity; Portkey part = same color at opacity 0.6 (`RunwayGlyph.portkeyOpacity`); track stays `RunwayGlyph.trackOpacity` (0.28).
- Draw order on every gauge: track, then one arc or bar to the total fraction in the Portkey tone (only when the Portkey part > 0), then the Copilot part in full tone on top. No gap between parts.
- Stays Copilot only: popover Used, Daily burn and Per PR cards; Dashboard insight banner, burn KPI, burn chart and breakdown cards; Copy summary; run-out notifications (per provider, unchanged); the Portkey card and section.
- Demo mode ignores the real Portkey budget (as `PopoverView.shownPortkeyBudgetUSD` does today), so demo builds show no combined gauge.

## Review Focus

1. Saving or clearing the Portkey budget in Settings while the app runs: menu bar title and glyph switch on the next `UserDefaults.didChangeNotification`, no relaunch (Task 3 hand check; `reloadGaugeMode` must not return early when only the budget changed).
2. Portkey spend loads after the Copilot fetch: the title must update again after `apply(sessionCredits)`, not wait for the next poll (Task 3 hand check).
3. One provider over its own budget: parts never go below 0 and still add up to the gauge (Task 1 tests).
4. Non-US locale: the USD headroom line follows the locale like other Portkey amounts (Task 2 pt_BR test).
5. Popover sweep animation and the static Share image both show the split with the same ratio (Task 4 hand check).

---

### Task 1: Core `CombinedBudget` and `GaugeParts`

**Files:**
- Create: `Core/CombinedBudget.swift`
- Modify: `Core/MenuBarTitle.swift` (add `gaugeParts`)
- Test: `CoreTests/CombinedBudgetTests.swift`

**Interfaces:**
- Produces:
  - `public struct GaugeParts: Equatable, Sendable { public let copilot: Double; public let portkey: Double; public var total: Double { copilot + portkey } }` with a public memberwise init.
  - `public struct CombinedBudget: Equatable, Sendable` with `public let usage: QuotaUsage` (USD) and the four provider amounts it needs.
  - `public static func make(copilot: QuotaUsage, portkeySpentUSD: Double, portkeyBudgetUSD: Double?) -> CombinedBudget?`
  - `public func parts(mode: GaugeMode) -> GaugeParts` (fractions of the combined budget)
  - `public func amountsUSD(mode: GaugeMode) -> GaugeParts` (left mode: each provider's USD left, floored at 0; spent mode: each provider's USD spent)
  - `MenuBarTitle.gaugeParts(usage: QuotaUsage?, combined: CombinedBudget?, mode: GaugeMode) -> GaugeParts`: `combined?.parts(mode:)`, else `GaugeParts(copilot: gaugeFraction(usage:mode:), portkey: 0)`.

- [ ] **Step 1: Write the failing tests** in `CoreTests/CombinedBudgetTests.swift`

Fixture: reset `utcDate("2026-12-01T00:00:00Z")`, now `utcDate("2026-11-15T12:00:00Z")`. Copilot `QuotaUsage(creditsUsed: 10216, entitlement: 15000, creditsRemaining: 4784, percentRemaining: 31.8933, isUnlimited: false, resetDate: reset)`. Compare doubles with a `1e-9` tolerance helper.

- `noBudgetGivesNil`: budget `nil` -> nil; budget `0` -> nil; budget `-5` -> nil.
- `unlimitedCopilotGivesNil`: Copilot `isUnlimited: true`, budget 50 -> nil.
- `combinesCopilotUSDAndPortkey`: spent 9.26, budget 50 -> `usage.creditsUsed` 111.42, `entitlement` 200, `creditsRemaining` 88.58, `percentRemaining` 44.29, `isUnlimited` false, `resetDate` == reset.
- `zeroPortkeySpendStillCombines`: spent 0, budget 50 -> not nil, entitlement 200.
- `leftParts`: same inputs, `.left` -> copilot 0.2392, portkey 0.2037; `amountsUSD(.left)` -> 47.84, 40.74.
- `spentParts`: `.spent` -> copilot 0.5108, portkey 0.0463, total 0.5571; `amountsUSD(.spent)` -> 102.16, 9.26.
- `portkeyOverBudget`: Copilot used 10000 (remaining 5000), Portkey spent 60 of 50 -> `.left` copilot 0.20, portkey 0; `amountsUSD(.left).portkey` 0.
- `copilotOverLimit`: Copilot used 16000 (remaining -1000), Portkey spent 10 of 50 -> `.left` copilot 0, portkey 0.15.
- `combinedOverBudget`: Copilot used 16000, Portkey spent 60 of 50 -> `.left` total 0; `.spent` copilot 0.80, portkey 0.20.
- `partsAddUpToGaugeFraction`: for every case above and both modes, `parts(mode).total` == `MenuBarTitle.gaugeFraction(usage: combined.usage, mode:)`, and no part < 0.
- `gaugePartsWithoutCombinedIsCopilotOnly`: `MenuBarTitle.gaugeParts(usage: copilot, combined: nil, mode: .left)` == `GaugeParts(copilot: gaugeFraction, portkey: 0)`.
- `combinedTitle`: `MenuBarTitle.title(usage: combined.usage, now: now, mode: .left)` == `"44% · 11d"`.

- [ ] **Step 2: Run `xcodegen generate`, then the suite.** Expected: build fails, `CombinedBudget` not found.

- [ ] **Step 3: Implement `Core/CombinedBudget.swift` and `MenuBarTitle.gaugeParts`**

Copilot USD = credits x `Credits.usdPerCredit` (used from `creditsUsed`, left from `creditsRemaining`). `percentRemaining` = combined left / combined budget x 100. Split rule (from the spec):

```swift
let gauge = MenuBarTitle.gaugeFraction(usage: usage, mode: mode)
let copilotAmount = mode == .left ? copilotLeftUSD : copilotSpentUSD
let copilotPart = min(max(copilotAmount / usage.entitlement, 0), gauge)
return GaugeParts(copilot: copilotPart, portkey: gauge - copilotPart)
```

- [ ] **Step 4: Run the suite.** Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit** `Core/CombinedBudget.swift Core/MenuBarTitle.swift CoreTests/CombinedBudgetTests.swift`: "Add CombinedBudget for the Copilot plus Portkey gauge".

### Task 2: Core USD headroom text and split gauge tiles

**Files:**
- Modify: `Core/RunwayInsight.swift` (`headroomText`, `popoverSentence`)
- Modify: `Core/GaugeTile.swift`
- Test: `CoreTests/RunwayInsightTests.swift`, `CoreTests/GaugeTileTests.swift`

**Interfaces:**
- Consumes: `CombinedBudget`, `GaugeParts` (Task 1).
- Produces:
  - `public enum BudgetUnit: Sendable { case credits, usd }` in `Core/RunwayInsight.swift`.
  - `RunwayInsight.headroomText(usage:now:locale:days:unit: BudgetUnit = .credits) -> String?`. USD form: `"\(PortkeySpend.formatted(abs(headroom), locale:))/\(days.dayWord()) of headroom"` or `"... over budget"`.
  - `RunwayInsight.popoverSentence(usage:now:locale:days:unit: BudgetUnit = .credits) -> String?`. Passes `unit` to the headroom line. With `.usd` and `creditsUsed == 0` it returns `"Nothing spent yet."` instead of `"No credits used yet."`.
  - `GaugeTile` gains `public let parts: GaugeParts`. The existing `init(fraction:percent:isSample:)` keeps working and sets `parts = GaugeParts(copilot: fraction, portkey: 0)`; `fraction` stays equal to `parts.total`.
  - `GaugeTile.make(usage:hasError:mode:combined: CombinedBudget? = nil)`: with `combined` (and no error), `parts = combined.parts(mode:)`, `percent = Runway.wholeGaugePercent(usage: combined.usage, mode:)`.

- [ ] **Step 1: Write the failing tests** (Task 1 fixture, combined with spent 9.26 of 50)

- `combinedHeadroomInUSD`: `headroomText(usage: combined.usage, now:, locale: Locale(identifier: "en_US"), unit: .usd)` == `"$1.97/day over budget"`.
- `combinedHeadroomFollowsLocale`: same with `pt_BR` contains `"US$"` and `"1,97"` and does not contain `"credits"`.
- `combinedPopoverSentenceUsesUSD`: `popoverSentence(..., unit: .usd)` ends with `"\n$1.97/day over budget."`.
- `combinedNothingSpent`: Copilot used 0, Portkey spent 0, budget 50 -> `popoverSentence(..., unit: .usd)` == `"Nothing spent yet."`.
- `creditsUnitUnchanged`: existing tests pass untouched (default `.credits`).
- `combinedTileSplits`: `GaugeTile.make(usage: copilot, hasError: false, mode: .left, combined: combined)` -> `percent` 44, `parts` == `combined.parts(mode: .left)`, `fraction` == `parts.total`, `isSample` false.
- `combinedTileWithErrorIsSample`: same with `hasError: true` -> `isSample` true, `parts.portkey` 0.

- [ ] **Step 2: Run the suite.** Expected: build fails on the new parameters.
- [ ] **Step 3: Implement** the signatures above. Default parameters keep every current call site compiling.
- [ ] **Step 4: Run the suite.** Expected: `** TEST SUCCEEDED **`.
- [ ] **Step 5: Commit** the four files: "Show USD headroom and split tiles for the combined gauge".

### Task 3: Store gauge usage and the menu bar glyph

**Files:**
- Modify: `App/UsageStore.swift`, `App/AppDelegate.swift`, `App/RunwayGlyph.swift`

**Interfaces:**
- Consumes: `CombinedBudget.make`, `MenuBarTitle.gaugeParts` (Task 1).
- Produces (App, used by Tasks 4 and 5):
  - `UsageStore.combinedBudget: CombinedBudget?` (`private(set)`).
  - `UsageStore.gaugeUsage: QuotaUsage?` = `combinedBudget?.usage ?? usage`.
  - `UsageStore.gaugeParts: GaugeParts` = `MenuBarTitle.gaugeParts(usage: usage, combined: combinedBudget, mode: gaugeMode)`.
  - `RunwayGlyph.portkeyOpacity = 0.6`.
  - `RunwayGlyph.menuBarImage(parts: GaugeParts, health: RunwayHealth) -> NSImage` (replaces the `gaugeFraction:` form).

- [ ] **Step 1: In `UsageStore`, add one private method that recomputes `combinedBudget` and `title`** from `usage`, `portkeySpend.totalUSD`, the saved budget (nil in demo mode) and the current mode and days. Title uses `gaugeUsage`; an error title stays as is. Call it where the title is set today after a fetch, at the end of `apply(_:)`, in `applyDemo`, and in `reloadGaugeMode`. `reloadGaugeMode` must also run it when only the budget changed (Review Focus 1).
- [ ] **Step 2: Glyph.** `AppDelegate` passes `usageStore.gaugeParts` and `RunwayHealth(usage: usageStore.gaugeUsage, ...)`. `menuBarImage(parts:health:)` follows the Global Constraints draw order.
- [ ] **Step 3: Build** `xcodebuild -scheme CopilotRunway build -derivedDataPath build/combined` -> `** BUILD SUCCEEDED **`, then the suite -> `** TEST SUCCEEDED **`.
- [ ] **Step 4: Hand check (Debug build, real data, Portkey budget set):** menu bar shows the combined percent and days and the two tones; clear the budget in Settings -> Copilot-only title and one tone with no relaunch; set it again -> combined; quit and relaunch -> title turns combined right after the session scan, not at the next poll; `-demo typical` -> one tone.
- [ ] **Step 5: Commit** the three files: "Drive the menu bar from the combined gauge".

### Task 4: Popover ring, legend and Settings tiles

**Files:**
- Create: `App/GaugeLegend.swift`
- Modify: `App/PopoverView.swift`, `App/SettingsTabs.swift`

**Interfaces:**
- Consumes: `UsageStore.gaugeUsage`, `.gaugeParts`, `.combinedBudget` (Task 3); `BudgetUnit`, `GaugeTile.make(...combined:)` (Task 2); `RunwayGlyph.portkeyOpacity`.
- Produces: `struct GaugeLegend: View { let amountsUSD: GaugeParts; let color: Color }`: two swatch plus label items, "Copilot $47.84" and "Portkey $40.74" (amounts via `PortkeySpend.formatted`), swatches at full and 0.6 opacity. Used by Task 5.

- [ ] **Step 1: Popover.** `health` and `runwaySection` read `gaugeUsage`. `RunwayRing` takes `parts: GaugeParts` instead of `gaugeFraction`; the sweep scales both parts by the shown total over the target total so the ratio holds while it animates; the static (Share) path draws the target parts. `popoverSentence` gets `unit: combinedBudget == nil ? .credits : .usd`. With a combined budget, a box under the runway row shows the header `"Copilot + Portkey · <left> of <budget> left"` (spent mode: `"<spent> of <budget> spent"`) and `GaugeLegend(amountsUSD: combined.amountsUSD(mode:))`. Ring VoiceOver with combined: `"44 percent of combined budget left. Copilot $47.84, Portkey $40.74."` (spent: `"... spent. Copilot $102.16, Portkey $9.26."`). Stat cards keep `usageStore.usage`.
- [ ] **Step 2: Settings tiles.** `gaugeTileButton` uses `GaugeTile.make(usage: usageStore.usage, hasError:, mode:, combined: usageStore.combinedBudget)` and health from `gaugeUsage`; `GaugeTileRing` draws `tile.parts` in the same order. No legend.
- [ ] **Step 3: `xcodegen generate`, build, suite.** Expected: both succeed.
- [ ] **Step 4: Hand check** against the canvas Popover and Settings artboards, dark and light: ring tones and order, legend amounts, header, USD headroom line, VoiceOver label, left and spent mode, Share image shows the split, tiles split.
- [ ] **Step 5: Commit** the three files: "Split the popover ring and Settings tiles by provider".

### Task 5: Dashboard cards and README

**Files:**
- Modify: `App/DashboardView.swift`, `README.md`

**Interfaces:**
- Consumes: `UsageStore.gaugeUsage`, `.gaugeParts`, `.combinedBudget` (Task 3); `GaugeLegend` (Task 4).

- [ ] **Step 1: Dashboard.** `runwayCard` and `remainingCard` read `gaugeUsage`, with health from it. `remainingCard` with combined: bar draws `gaugeParts` (two segments, same tones), detail `"<spent> of <budget> used"` in USD via `PortkeySpend.formatted`, then `GaugeLegend`. The insight banner, burn KPI, chart and breakdown cards keep `usageStore.usage`.
- [ ] **Step 2: README.** In the Portkey section, replace "they never count in the Copilot gauge, runway, burn rate or breakdowns" with: with a Portkey budget set, the gauge, runway days and run-out combine the Copilot limit in USD and the Portkey budget, drawn in two tones; burn rate, breakdowns and Copy summary stay Copilot only. In Settings > Gauge shows, add one sentence that the tiles show the split with a Portkey budget. No em dashes.
- [ ] **Step 3: Build and suite.** Expected: both succeed.
- [ ] **Step 4: Hand check** against the canvas Dashboard artboard, dark and light, left and spent mode; clear the budget -> card as today.
- [ ] **Step 5: Commit** the two files: "Show the combined budget in the Dashboard".
