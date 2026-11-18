# Portkey-only Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A user with no usable Copilot (gh missing, gh logged out, no seat) and Portkey data sees Portkey runway or spend in the menu bar, popover and Dashboard instead of only an error.

**Architecture:** A Core type classifies Copilot errors, debounces them, and gives the calendar month reset date and the copy. `UsageStore` gets a Copilot state (Copilot, Portkey only, no Portkey data). In Portkey only, `gaugeUsage` comes from `PortkeyBudget.usage` with the month reset, so the ring, menu bar, notices and `Runway` math from item 42 work unchanged. Views branch on the store state, never on `usageError` directly.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Testing (`import Testing`, `@Test`, `#expect`), Xcode 27.2 project with synchronized folders.

**Spec:** `docs/superpowers/specs/2026-11-16-portkey-only-mode-design.md`. Canvas (private): https://claude.ai/artifact/PUWxSWHedPPqi5Q3saVgEm. Review: `implementation_readiness_report.md` (all findings folded in).

## Global Constraints

- No em dashes anywhere (code, comments, strings, docs). 2-space indent, LF, final newline.
- No new network call. No token handling change.
- "No Copilot" errors: `ghNotFound`, `notLoggedIn`, `httpStatus` 400...499 except 429, `invalidResponse`. Outage: `network`, `httpStatus(429)`, `httpStatus` 500 and up (and any other status).
- Portkey-only cycle: reset = 1st of next month 00:00 UTC (`Runway.utcCalendar`). Copilot mode keeps the Copilot cycle for Portkey (no change).
- Copilot users and Copilot outages: no visible change.
- Gauge in Portkey only: `GaugeParts(copilot: fraction, portkey: 0)`, so every renderer draws it full tone in the health accent, the same as a Copilot-only gauge (no renderer change).
- Share in Portkey only: image only, no summary text (user decision B2 default, 2026-11-16). Copy summary stays disabled.
- Copy (exact):
  - cause `ghNotFound`: "GitHub CLI not found, so Copilot data is off."
  - cause `notLoggedIn`: "GitHub CLI not logged in, so Copilot data is off."
  - cause `noSeat`: "No Copilot seat for this GitHub account, so Copilot data is off."
  - second sentence, budget set: "The runway shows your Portkey budget." No budget: "Showing Portkey spend only."
  - header chip: "Portkey only"
  - no-budget popover caption: "spent this month"; link: "Set a monthly budget to see runway"
  - no-data card title: "Using Portkey without Copilot?"; body: "Copilot Runway also shows Portkey spend from OpenCode, Pi and omp sessions. It found no Portkey requests this month. Set a monthly budget in Settings to see runway."; button: "Open Settings"
  - Dashboard banner headline, no budget: "<amount> spent on Portkey this month."; no spend with a budget: "Nothing spent on Portkey yet this month."
- Test command: `xcodebuild test -scheme CopilotRunway -destination 'platform=macOS'` (add `-only-testing:CoreTests/<File>` for one file). Build: `xcodebuild -scheme CopilotRunway build`.
- Debug launch: `-openDashboard` must be the last argument, because AppKit pairs a `-key` argument with the next token.
- Branch: `wilsonfaustino/portkey-only-mode`. Commit only with the user's OK; stage files by name.

## Review Focus

1. A Copilot user hit by one 403 (secondary rate limit) or a keychain-locked `gh auth token` after wake: must keep Copilot numbers (dimmed, error title), never flip to Portkey only. Test in Task 1 (`goodThenOneAbsenceKeepsCopilot`).
2. A Portkey-only user during an outage (offline): must stay Portkey only, not drop to the bare error. Test in Task 1 (`outageKeepsPortkeyOnly`).
3. Month edges: the last second of a month, the 1st at 00:00 UTC exactly, December, leap February. Tests in Task 1.
4. A user who sets or clears the Portkey budget in Settings while in a no-Copilot state: the state, the menu bar title and the ring must change without a relaunch. Hand check in Task 3 Step 7.
5. Days off marks in Portkey only: filtered to the calendar month, not dropped and not kept from another cycle. Hand check in Task 3 Step 7.

---

### Task 1: Core `PortkeyOnly` and the Portkey-only banner

**Files:**
- Create: `Core/PortkeyOnly.swift`
- Modify: `Core/RunwayInsight.swift`
- Test: `CoreTests/PortkeyOnlyTests.swift`, `CoreTests/RunwayInsightTests.swift`

**Interfaces:**
- Produces:
  - `public enum CopilotAbsence: Equatable, Sendable { case ghNotFound, notLoggedIn, noSeat }`
  - `public enum PortkeyOnly`:
    - `static func absence(for error: CopilotUsageError) -> CopilotAbsence?` (nil = outage)
    - `static func resetDate(now: Date) -> Date`
    - `static func causeLine(_ absence: CopilotAbsence, hasBudget: Bool) -> String` (two sentences joined by one space)
    - `static func spentTitle(spentUSD: Double, locale: Locale = .current) -> String` (= `PortkeySpend.formatted`)
  - `public struct CopilotAbsenceTracker: Equatable, Sendable`:
    - `public init()`
    - `public private(set) var absence: CopilotAbsence?` (non-nil = a no-Copilot state is on)
    - `public mutating func observeSuccess()`
    - `public mutating func observe(_ error: CopilotUsageError)`
  - `RunwayInsight.portkeyOnlyBanner(usage: QuotaUsage?, spentUSD: Double, absence: CopilotAbsence, now: Date, locale: Locale = .current, days: RunwayDays = .calendar) -> (headline: String, detail: String)`

- [ ] **Step 1: Write the failing tests** in `CoreTests/PortkeyOnlyTests.swift` (the `utcDate` helper is in `CopilotUsageClientTests.swift`):
  - `absenceClassification`: `ghNotFound` gives `.ghNotFound`; `notLoggedIn` gives `.notLoggedIn`; each of `httpStatus(400)`, `httpStatus(403)`, `httpStatus(404)` and `invalidResponse` gives `.noSeat`; each of `network`, `httpStatus(429)`, `httpStatus(500)` and `httpStatus(503)` gives nil.
  - `resetDateMidMonth`: now `2026-11-16T10:00:00Z` gives `2026-12-01T00:00:00Z`.
  - `resetDateOnTheFirst`: now `2026-11-01T00:00:00Z` gives `2026-12-01T00:00:00Z`.
  - `resetDateLastSecond`: now `2026-11-30T23:59:59Z` gives `2026-12-01T00:00:00Z`.
  - `resetDateDecember`: now `2026-12-31T12:00:00Z` gives `2027-01-01T00:00:00Z`.
  - `resetDateLeapFebruary`: now `2028-02-29T08:00:00Z` gives `2028-03-01T00:00:00Z`, and `Runway.cycleStart(resetDate:)` of that gives `2028-02-01T00:00:00Z`.
  - `causeLines`: all six combinations equal the Global Constraints copy, for example `.noSeat, hasBudget: true` gives "No Copilot seat for this GitHub account, so Copilot data is off. The runway shows your Portkey budget."
  - `spentTitleUsesUSD`: `spentTitle(spentUSD: 10.17, locale: Locale(identifier: "en_US"))` == "$10.17".
  - `firstAbsenceEntersAtOnce`: new tracker, `observe(.notLoggedIn)`, then `absence == .notLoggedIn`.
  - `goodThenOneAbsenceKeepsCopilot`: `observeSuccess()`, `observe(.httpStatus(403))`, then `absence == nil`.
  - `goodThenTwoAbsencesEnters`: `observeSuccess()`, `observe(.httpStatus(403))`, `observe(.httpStatus(404))`, then `absence == .noSeat`.
  - `outageBetweenAbsencesDoesNotCount`: `observeSuccess()`, `observe(.httpStatus(403))`, `observe(.network)`, then `absence == nil`; then `observe(.notLoggedIn)`, then `absence == .notLoggedIn` (the outage does not reset the streak).
  - `outageKeepsPortkeyOnly`: `observe(.ghNotFound)`, `observe(.network)`, then `absence == .ghNotFound`.
  - `outageFirstKeepsNil`: new tracker, `observe(.network)`, then `absence == nil`.
  - `successLeaves`: `observe(.ghNotFound)`, `observeSuccess()`, then `absence == nil`.
  - `latestCauseWins`: `observe(.ghNotFound)`, `observe(.notLoggedIn)`, then `absence == .notLoggedIn`.
  And in `CoreTests/RunwayInsightTests.swift` (reset `2026-12-01`, now `2026-11-16T00:00:00Z`, en_US):
  - `portkeyOnlyBannerNoBudget`: usage nil, spent 10.17, `.notLoggedIn` gives headline "$10.17 spent on Portkey this month." and detail `PortkeyOnly.causeLine(.notLoggedIn, hasBudget: false)`.
  - `portkeyOnlyBannerRunsOut`: usage from `PortkeyBudget.usage(spentUSD: 9, budgetUSD: 12, resetDate:)` gives the headline that `portkeyRunOutSentence` gives (contains "your Portkey budget runs out") and detail `causeLine(.noSeat, hasBudget: true)`.
  - `portkeyOnlyBannerOverBudget`: spent 13 of 12 gives `portkeyLimitSentence`.
  - `portkeyOnlyBannerNothingSpent`: spent 0 of 12 gives "Nothing spent on Portkey yet this month."

- [ ] **Step 2: Run** `xcodebuild test -scheme CopilotRunway -destination 'platform=macOS' -only-testing:CoreTests/PortkeyOnlyTests -only-testing:CoreTests/RunwayInsightTests`. Expected: build FAIL, `PortkeyOnly` not found.

- [ ] **Step 3: Implement `Core/PortkeyOnly.swift`.** Tracker state: `absence`, `hasSeenCopilot: Bool`, `absenceStreak: Int`. `observeSuccess`: set `absence` to nil, `hasSeenCopilot` to true and the streak to 0. `observe`: an outage changes nothing. An absence error adds 1 to the streak and sets `absence` when `!hasSeenCopilot || absenceStreak >= 2`. Comment the 2: a 403 rate limit or a locked keychain after wake gives one false absence. `resetDate`: the start of the UTC month of `now`, plus one month.

- [ ] **Step 4: Implement `portkeyOnlyBanner`** in `Core/RunwayInsight.swift`. Headline order: usage nil gives the no-budget sentence; `creditsRemaining <= 0` gives `portkeyLimitSentence`; else `portkeyRunOutSentence`, or "Nothing spent on Portkey yet this month." when that is nil. Detail: `PortkeyOnly.causeLine(absence, hasBudget: usage != nil)`.

- [ ] **Step 5: Run** the Step 2 command. Expected: PASS.

- [ ] **Step 6: Commit** `Core/PortkeyOnly.swift Core/RunwayInsight.swift CoreTests/PortkeyOnlyTests.swift CoreTests/RunwayInsightTests.swift`: "Add PortkeyOnly classification, debounce, month reset and banner".

---

### Task 2: Demo scenarios

**Files:**
- Modify: `Core/DemoScenario.swift`
- Test: `CoreTests/DemoScenarioTests.swift`

**Interfaces:**
- Consumes: `PortkeyOnly.resetDate(now:)`, `PortkeyOnly.absence(for:)` (Task 1).
- Produces on `DemoScenario`:
  - `Name` cases `portkeyOnly = "portkey-only"`, `portkeyOnlyNoBudget = "portkey-only-no-budget"`, `noCopilotEmpty = "no-copilot-empty"`.
  - `public let copilotError: CopilotUsageError?`: nil for the 7 existing scenarios; `.httpStatus(403)` for `portkey-only`; `.notLoggedIn` for the other two. The store feeds it to the same tracker path as a real error, so demo sets `errorMessage` and `usageError` like a real run.
  - `public let portkeyBudgetUSD: Double?`: nil except `portkey-only`.
  - `public let portkeyRecords: [PortkeyRecord]`
  - `sessionCredits` passes `portkeyRecords` to `SessionCredits.aggregate`.

- [ ] **Step 1: Write the failing tests** in `DemoScenarioTests.swift` (fixed now `2026-11-16T12:00:00Z`):
  - `copilotScenariosHaveNoPortkeyOnlyData`: the 7 existing names have `copilotError == nil`, `portkeyBudgetUSD == nil` and empty `portkeyRecords`.
  - `portkeyOnlyScenario`:
    - `PortkeyOnly.absence(for: copilotError!) == .noSeat`
    - `usage.resetDate == PortkeyOnly.resetDate(now:)`
    - every record in `sessionCredits.portkey.records` is at or after `2026-11-01T00:00:00Z` and at or before now
    - `sessionCredits.portkey.byModel.count == 3` and `bySource.count == 3`
    - `sessionCredits.byModel.isEmpty`
    - the budget gives a short runway: with `budgetUsage = PortkeyBudget.usage(spentUSD: sessionCredits.portkey.totalUSD, budgetUSD: portkeyBudgetUSD, resetDate:)`, `Runway.lastsTheCycle(usage: budgetUsage, now:) == false` and `Runway.wholeDaysLeft(usage: budgetUsage, now:)` is between 1 and 15.
  - `portkeyOnlyHasLastMonth`: `sessionCredits.previousPortkey.requestCount > 0`.
  - `portkeyOnlyNoBudgetScenario`: `.notLoggedIn`, budget nil, `sessionCredits.portkey.requestCount > 0`.
  - `noCopilotEmptyScenario`: `.notLoggedIn`, budget nil, records empty.
  - The existing `allCases` tests must pass for the new names with no change to those tests.

- [ ] **Step 2: Run** `-only-testing:CoreTests/DemoScenarioTests`. Expected: build FAIL.

- [ ] **Step 3: Implement.**
  1. Give each new case a `Shape` equal to `edgeEmpty`: `entitlement: 1_500, creditsUsed: 0, elapsedDays: 0, turnsPerDay: 0` and the same models, categories, outcomes and review count.
  2. In `init`, when `copilotError` is set, set `usage.resetDate` to `PortkeyOnly.resetDate(now:)`. The store ignores `usage` in a no-Copilot state.
  3. Make the Portkey records for `portkey-only` and `portkey-only-no-budget`. They run from the start of the previous month through now, at 10:00, 13:00 and 16:00 UTC (three records per day). Models rotate `gpt-6.1-sol`, `gemini-3.8-flash` and `gpt-6-luna`, and sources rotate `.opencode`, `.pi` and `.omp`. The cost by model is 0.30, 0.12 and 0.06 USD. Every seventh record has `costUSD: nil`, so the unpriced note shows.
  4. Set the `portkey-only` budget so the runway always ends at about half of the days left: `spent + averageDailyBurn * max(daysUntilReset / 2, 1)`, rounded up to whole dollars. Spent and the burn come from this month's records. Comment the formula.

- [ ] **Step 4: Run** the DemoScenarioTests command, then the full test command. Expected: PASS for both.

- [ ] **Step 5: Commit** `Core/DemoScenario.swift CoreTests/DemoScenarioTests.swift`: "Add Portkey-only demo scenarios".

---

### Task 3: `UsageStore` Copilot state, menu bar and Share

**Files:**
- Modify: `App/UsageStore.swift`, `App/AppDelegate.swift`, `App/SharePicker.swift`, `App/PopoverView.swift` (budget property only), `App/DashboardView.swift` (budget property only)

**Interfaces:**
- Consumes: Tasks 1 and 2.
- Produces (read by Tasks 4 and 5):
  - `enum CopilotState: Equatable { case copilot, portkeyOnly(CopilotAbsence), noPortkeyData(CopilotAbsence) }` in `App/UsageStore.swift`.
  - `private(set) var copilotState: CopilotState = .copilot`
  - `var isPortkeyOnly: Bool`: the state is `.portkeyOnly`.
  - `private(set) var portkeyBudgetUSD: Double?`: a stored, observed property. Demo gives the scenario budget. Otherwise it comes from `UserDefaults` `portkeyBudgetKey`, where 0 or less is nil. It is set at init and in `reloadGaugeMode`.
  - `private(set) var portkeyOnlyResetDate: Date?`: set on each no-Copilot refresh.
  - `var cycleResetDate: Date?`: `usage?.resetDate` in `.copilot`, `portkeyOnlyResetDate` otherwise. It is nil before the first fetch, so `gaugeUsage` is nil then.
  - `var hasUsageError: Bool`: `usageError != nil && !isPortkeyOnly`. Views use it in place of `usageError != nil`.
  - `gaugeUsage` in Portkey only: `cycleResetDate.flatMap { PortkeyBudget.usage(spentUSD: portkeySpend.totalUSD, budgetUSD: portkeyBudgetUSD, resetDate: $0) }`.
  - `gaugeParts` in Portkey only: `GaugeParts(copilot: MenuBarTitle.gaugeFraction(usage: gaugeUsage, mode: gaugeMode), portkey: 0)`.
  - `SharePicker.show(image: NSImage, summary: String?, relativeTo:)`

- [ ] **Step 1: Change `refresh()`:**
  1. Keep a `@ObservationIgnored private var absenceTracker = CopilotAbsenceTracker()`.
  2. On success, call `observeSuccess()` and set the state to `.copilot`. The rest of the success path does not change.
  3. On an error, call `observe(error)`. Set `usageError` and `errorMessage` as the current code does.
  4. When `absenceTracker.absence` is non-nil, run a new `refreshWithoutCopilot(absence:)`:
     1. Set `usage` and `combinedBudget` to nil and `portkeyOnlyResetDate` to `PortkeyOnly.resetDate(now: .now)`.
     2. Set `runwayDays` from `savedRunwayDays(resetDate: portkeyOnlyResetDate)`.
     3. Scan sessions from `Runway.cycleStart(resetDate:)` of that date, then call `apply(sessionCredits)`.
     4. Clear the Copilot aggregates: `modelCredits`, `categoryCredits`, `modelCategoryCredits`, `sourceCredits`, `projectCredits`, `sessionSpends`, `cacheHits`, `lowCacheSentences`, `modelEfficiencyNote`, `cycleComparisonSentence`, `outcomes` and `copilotReviewCount`. Map `dailyCredits` and `previousDailyCredits` to the same days with credits 0, so the chart keeps its days and shows only Portkey.
     5. Run the state choice: `.portkeyOnly(absence)` when `PortkeyBudget.showsBlock(requestCount: portkeySpend.requestCount, budgetUSD: portkeyBudgetUSD)`, else `.noPortkeyData(absence)`.
     6. Set `lastRefresh = .now` and call `updateGauge()`.
     7. With a budget in Portkey only, send Portkey notices with `gaugeUsage` and `subject: .portkey`. Copilot notices and the outcomes fetch do not run.
  5. When the absence is nil and `usage` is nil (an outage with nothing known), keep the current early return. Rewrite the comment there so it names both paths.
- [ ] **Step 2: Change `updateGauge()`.** Replace the `usageError == nil` guard with a switch on `copilotState`:
  - `.copilot`: the current behavior.
  - `.portkeyOnly`: `MenuBarTitle.title(usage: gaugeUsage, ...)` when `gaugeUsage` is non-nil, else `PortkeyOnly.spentTitle(spentUSD: portkeySpend.totalUSD)`.
  - `.noPortkeyData`: `MenuBarTitle.title(error: usageError!)`.
  In `apply()`, the state must be set before `updateGauge()` runs. `refreshWithoutCopilot` calls `updateGauge()` again after the state choice.
- [ ] **Step 3: Change `reloadGaugeMode()`.**
  - Also read the saved budget. When it differs from `portkeyBudgetUSD`, store it.
  - In a no-Copilot state, run the state choice again with the new budget (no new scan).
  - Keep the existing checks for gauge mode, run-out days and combined budget.
  - Every `savedRunwayDays(resetDate:)` call uses `cycleResetDate`.
- [ ] **Step 4: Demo.**
  - `applyDemo`: when the scenario has `copilotError`, set `usageError` and `errorMessage` from it. Call `absenceTracker.observe(error)`. Then run `refreshWithoutCopilot` with the scenario records and budget in place of the scan. When it has no error, keep the current path.
  - Delete `shownPortkeyBudgetUSD` in `PopoverView.swift` and in `DashboardView.swift`, and read `usageStore.portkeyBudgetUSD` instead. Demo Copilot scenarios give nil, so they still show no combined gauge.
  - Remove the `DemoLaunch.isActive` budget override in `currentCombinedBudget()` and use `portkeyBudgetUSD`.
- [ ] **Step 5: Change `AppDelegate.updateLabel`.** Branch on `hasUsageError`, not `usageError`, so Portkey only draws the gauge with `gaugeParts`. Its `RunwayHealth` uses `hasError: false`, as the current code does.
- [ ] **Step 6: Share.**
  - `SharePicker.show` takes `summary: String?`. The items are `[image]`, plus the summary when it is non-nil. Leave out the "Copy summary" custom item when the summary is nil.
  - `AppDelegate.share` passes `usageStore.summaryText()`, which may be nil, and needs only the image.
  - `PopoverView`'s Share button is disabled when `!(isPortkeyOnly || (usage != nil && usageError == nil))`.
- [ ] **Step 7: Verify.** Run the full test command. Expected: PASS. Run the build. Expected: `** BUILD SUCCEEDED **`. Launch the Debug build:
  1. Launch with `-demo portkey-only`. Expected: the menu bar shows "NN% · Nd" next to a gauge, with no error symbol.
  2. Launch with `-demo portkey-only-no-budget`. Expected: the menu bar shows a dollar amount and an empty gauge.
  3. Launch with `-demo no-copilot-empty`. Expected: the error symbol and "gh login".
  4. Launch with `-demo typical`. Expected: no change from the current app.
  Hand checks for the user:
  1. Back up the defaults with `defaults export`. Log out of `gh` (`gh auth logout`) and launch the Release-like Debug build on real data. Expected: Portkey only within one refresh.
  2. Set the Portkey budget to 0 in Settings. Expected: the title becomes a dollar amount without a relaunch. Set it back. Expected: "NN% · Nd".
  3. Turn on Count only weekdays and mark a day off this month. Expected: the days figure drops by one, and a mark from another month has no effect.
  4. Log in again with `gh auth login`. Expected: Copilot mode on the next refresh.
- [ ] **Step 8: Commit** `App/UsageStore.swift App/AppDelegate.swift App/SharePicker.swift App/PopoverView.swift App/DashboardView.swift`: "Add Portkey-only state to UsageStore".

---

### Task 4: Popover

**Files:**
- Modify: `App/PopoverView.swift`

**Interfaces:**
- Consumes: the Task 3 store members; Task 1 `PortkeyOnly.causeLine`.

- [ ] **Step 1: Add the header chip** "Portkey only" when `isPortkeyOnly`. Show it in the Share image too. Style it like the existing "USD, not credits" capsule in `PortkeyCard`.
- [ ] **Step 2: Branch the error row on `copilotState`:**
  - `.portkeyOnly(absence)`: a grey info label (`info.circle`, secondary color, 12 pt) with `PortkeyOnly.causeLine(absence, hasBudget: portkeyBudgetUSD != nil)`. Hide it when `forShare`.
  - `.copilot` and `.noPortkeyData`: the existing red label from `errorMessage`.
- [ ] **Step 3: Change the runway section in Portkey only.** Compute health with `hasError: hasUsageError`, and do not dim the section.
  - With a budget: the existing ring and figure from `gaugeUsage`, with `unit: .usd`.
  - Without a budget:
    - an empty ring track with "--";
    - the big figure is `PortkeySpend.formatted(portkeySpend.totalUSD)`, with the caption "spent this month";
    - a link button "Set a monthly budget to see runway" that sets `settingsTab = .sources` and shows Settings, as `perPRCard` does. Hide the link when `forShare`.
- [ ] **Step 4: Change the stat cards in Portkey only.**
  - With a budget: three cards.
    - Spent: `$x`, with the detail "of $budget".
    - Daily burn: `Runway.averageDailyBurn(credits: portkeySpend.totalUSD, resetDate: cycleResetDate!, now:, days:)`, with the detail "USD/" plus `dayWord()`.
    - Requests: with the detail "this month".
  - Without a budget: Daily burn and Requests only.
  - Hide `modelBars`, which also hides the Copilot review note inside it, and hide the combined box.
- [ ] **Step 5: Leave the Portkey card as it is.** Its `budgetStatus` already comes from `usage.flatMap`, which gives nil in Portkey only, so the budget status line hides with no new flag.
- [ ] **Step 6: Add the no-data card** in `.noPortkeyData`. Show it under the red label, with the exact title, body and "Open Settings" button (Sources tab). Hide it when `forShare`.
- [ ] **Step 7: Verify.** Run the build. Launch `-demo portkey-only`, `-demo portkey-only-no-budget`, `-demo no-copilot-empty` and `-demo typical`, and compare each with the canvas artboards. Share from `portkey-only`. Expected: the share sheet offers the image with the chip, and no info line. Repeat in light mode with `-NSRequiresAquaSystemAppearance YES`.
- [ ] **Step 8: Commit** `App/PopoverView.swift`: "Show Portkey-only popover".

---

### Task 5: Dashboard and Settings

**Files:**
- Modify: `App/DashboardView.swift` (holds `DailyBurnChart`), `App/PortkeyViews.swift` (`PortkeyDashboardSection`), `App/SettingsTabs.swift`

**Interfaces:**
- Consumes: Task 1 `RunwayInsight.portkeyOnlyBanner` and the Task 3 store members.
- Produces:
  - `PortkeyDashboardSection` gets `var isPortkeyOnly = false`.
  - `DailyBurnChart` gets `var portkeyBarsFullTone = false`.
  - `dailyBurnChart` and `portkeySection` take `resetDate: Date` in place of `usage: QuotaUsage`.

- [ ] **Step 1: Branch the body on `copilotState`:**
  - `.copilot`: the existing body.
  - `.portkeyOnly`: the insight banner, the KPI row, the daily burn chart and the Portkey section. Leave out Outcomes, By task, By model, By agent, By project and Top sessions.
  - `.noPortkeyData`: the existing error text.
  The top `health` and `gaugeHealth` values use `hasUsageError`. `bannerSymbolName` checks `hasUsageError` before `usageError`.
- [ ] **Step 2: Change the subtitle** in Portkey only to "Portkey only · <cycle start> to <last cycle day> · resets <reset date>", built from `cycleResetDate`.
- [ ] **Step 3: Change the insight banner** in Portkey only to use `RunwayInsight.portkeyOnlyBanner(usage: gaugeUsage, spentUSD: portkeySpend.totalUSD, absence:, now:, days:)`.
- [ ] **Step 4: Change the KPI row** in Portkey only.
  - With a budget: Runway; Left (`$left of $budget, n%`); Average daily burn (USD per day); Requests (`$avg each`).
  - Without a budget: Runway "--" with the detail "Set a monthly budget to see runway", which matches the popover; then Spent, Average daily burn and Requests.
- [ ] **Step 5: Change the daily burn chart.** Use the USD form with `CombinedDailyBurn.days` and the zeroed `dailyCredits` from Task 3, and pass `portkeyBarsFullTone: true`. The average line comes from `gaugeUsage` with a budget, else from `Runway.averageDailyBurn(credits: portkeySpend.totalUSD, resetDate:, now:, days:)`. The last-cycle line and the comparison sentence use `previousPortkeySpend` with the zeroed `previousDailyCredits`, as the combined form does.
- [ ] **Step 6: Pass `isPortkeyOnly: true` to the Portkey section.** Its caption then drops "Not part of the Copilot runway.", and its date range comes from `cycleResetDate`.
- [ ] **Step 7: Confirm Copy summary.** It stays disabled, because `usage == nil` already disables it. No code change.
- [ ] **Step 8: Change Settings.** In the days-off grid of the Runway tab, read `cycleResetDate` in place of `usageStore.usage?.resetDate`. In the gauge tile view, call `GaugeTile.make(usage: gaugeUsage, hasError: hasUsageError, ...)` and its `RunwayHealth` with `hasError: hasUsageError`. With `combined` nil, the tile draws the whole fraction full tone, which matches the menu bar.
- [ ] **Step 9: Verify.** Run the build and the full tests. Expected: PASS. Launch `-demo portkey-only -openDashboard` and `-demo portkey-only-no-budget -openDashboard`, and compare with the Dashboard artboard. Launch `-demo typical -openDashboard`. Expected: no change.
- [ ] **Step 10: Commit** `App/DashboardView.swift App/PortkeyViews.swift App/SettingsTabs.swift`: "Show Portkey-only Dashboard".

---

### Task 6: Docs

**Files:**
- Modify: `README.md`, `Core/README.md`

- [ ] **Step 1: Add a "Without Copilot" section to README.md** (ASD-STE100, sentence case). It covers:
  - the conditions that turn the mode on: gh missing, gh logged out, or no Copilot seat;
  - that a GitHub outage does not turn it on;
  - the calendar month cycle;
  - what the app shows with and without a budget;
  - what the popover and Dashboard hide;
  - that Copy summary is off and Share sends only the image;
  - the three demo scenarios, in the Debug demo list.
  Also change the "Zero setup" wording so it does not say Copilot is required.
- [ ] **Step 2: Add one line to Core/README.md** on `PortkeyOnly` and `CopilotAbsenceTracker`, next to the Portkey entries.
- [ ] **Step 3: Verify** with `git diff -U0 README.md Core/README.md | grep -n $'\xe2\x80\x94'`. Expected: no output.
- [ ] **Step 4: Commit** `README.md Core/README.md`: "Document Portkey-only mode".

## Not in this plan

- What's New entry and `MARKETING_VERSION`: in the release PR.
- Serena roadmap update: done by the main session after merge.
