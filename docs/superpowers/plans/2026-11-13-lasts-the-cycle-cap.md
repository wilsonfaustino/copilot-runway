# "Lasts the cycle" cap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When Copilot credits last past the reset, show "Lasts the cycle" instead of a days-left number.

**Architecture:** One Core rule, `Runway.lastsTheCycle(usage:now:)`, plus one Core caption, `RunwayInsight.resetCaption(usage:locale:)`. `MenuBarTitle`, `PopoverView` and `DashboardView` check the rule before they show days. `Runway.wholeDaysLeft` does not change, because `PortkeyBudget` needs the raw days.

**Tech Stack:** Swift, SwiftUI, Swift Testing, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-11-13-lasts-the-cycle-cap-design.md`

## Global Constraints

- Copy, exact: "Lasts the cycle", "Resets <date>" (date as `RunwayInsight.day`, UTC, abbreviated month and day, for example "Resets Dec 1").
- Menu bar past the reset: `"\(gaugePercent)%"` only. `MenuBarTitle.placeholder` stays `"--% · --d"`.
- Copilot only. `PortkeyBudget.status` and `Runway.wholeDaysLeft` stay unchanged.
- No em dashes anywhere. 2-space indent. Comments only for non-obvious rules.
- Test command: `xcodebuild test -scheme CopilotRunway -destination 'platform=macOS'`.

## Review Focus

- Run-out exactly on the reset: shows "Lasts the cycle" (matches `RunwayHealth`, short only when before the reset). Test in Task 1.
- Stale usage (now at or after the reset): keeps today's output, no "Lasts the cycle". Test in Task 1.
- Gauge mode spent: menu bar shows the spent percent alone (`"8%"`), not the left percent. Test in Task 1.
- No burn yet: keeps `"100% · --d"` and the popover "--". Existing test `titleWithoutRunwayEstimate` covers the menu bar.
- Share image: renders `PopoverView` with `forShare`, so it must show the same text. Check by eye in Task 2.

---

### Task 1: Core rule, caption and menu bar title

**Files:**
- Modify: `Core/Runway.swift` (add after `runOutDate`)
- Modify: `Core/RunwayInsight.swift` (add next to `popoverSentence`)
- Modify: `Core/MenuBarTitle.swift:6-11`
- Test: `CoreTests/RunwayTests.swift`, `CoreTests/RunwayInsightTests.swift`, `CoreTests/MenuBarTitleTests.swift`

**Interfaces:**
- Produces: `public static func lastsTheCycle(usage: QuotaUsage, now: Date) -> Bool` on `Runway`.
- Produces: `public static func resetCaption(usage: QuotaUsage, locale: Locale = .current) -> String` on `RunwayInsight`, returns `"Resets \(day(usage.resetDate, locale: locale))"`.

Test values: `makeUsage` resets 2026-11-01, cycle starts 2026-10-01. Now 2026-10-11 is 10 days in.

- [ ] **Step 1: Write the failing tests**

`CoreTests/RunwayTests.swift`:
```swift
@Test func lastsTheCycleFalseWhenRunOutBeforeReset() {
  // 600/day, 6000 left -> runs out Oct 21.
  #expect(!Runway.lastsTheCycle(usage: makeUsage(creditsUsed: 6000), now: utcDate("2026-10-11T00:00:00Z")))
}

@Test func lastsTheCycleTrueWhenRunOutEqualsReset() {
  // 100/day, 2100 left -> runs out exactly Nov 1.
  #expect(Runway.lastsTheCycle(usage: makeUsage(creditsUsed: 1000, entitlement: 3100), now: utcDate("2026-10-11T00:00:00Z")))
}

@Test func lastsTheCycleTrueWhenRunOutAfterReset() {
  #expect(Runway.lastsTheCycle(usage: makeUsage(creditsUsed: 1000), now: utcDate("2026-10-11T00:00:00Z")))
}

@Test func lastsTheCycleFalseWithoutBurnUnlimitedOrStale() {
  let now = utcDate("2026-10-11T00:00:00Z")
  #expect(!Runway.lastsTheCycle(usage: makeUsage(creditsUsed: 0), now: now))
  #expect(!Runway.lastsTheCycle(usage: makeUsage(creditsUsed: 500, entitlement: 0, isUnlimited: true), now: now))
  #expect(!Runway.lastsTheCycle(usage: makeUsage(creditsUsed: 1000), now: utcDate("2026-11-01T00:00:00Z")))
}
```

`CoreTests/RunwayInsightTests.swift`:
```swift
@Test func resetCaptionShowsUTCResetDay() {
  #expect(RunwayInsight.resetCaption(usage: makeUsage(creditsUsed: 1000), locale: Locale(identifier: "en_US")) == "Resets Nov 1")
}
```

`CoreTests/MenuBarTitleTests.swift`:
```swift
@Test func titleDropsDaysWhenCreditsLastTheCycle() {
  // 100/day, 11000 left -> 110 days, past the Nov 1 reset.
  let now = utcDate("2026-10-11T00:00:00Z")
  #expect(MenuBarTitle.title(usage: makeUsage(creditsUsed: 1000), now: now) == "92%")
  #expect(MenuBarTitle.title(usage: makeUsage(creditsUsed: 1000), now: now, mode: .spent) == "8%")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme CopilotRunway -destination 'platform=macOS'`
Expected: build fails, `lastsTheCycle` and `resetCaption` not found.

- [ ] **Step 3: Implement**

- `Runway.lastsTheCycle`: true when `!usage.isUnlimited`, `now < usage.resetDate`, and `runOutDate(usage:now:)` is non-nil and `>= usage.resetDate`. Comment: equal to the reset counts, to match `RunwayHealth`.
- `RunwayInsight.resetCaption` as in Interfaces.
- `MenuBarTitle.title`: after the unlimited check, return `"\(gaugePercent)%"` when `Runway.lastsTheCycle(usage:now:)`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme CopilotRunway -destination 'platform=macOS'`
Expected: `** TEST SUCCEEDED **`, all existing tests still pass.

- [ ] **Step 5: Commit**

```bash
git add Core/Runway.swift Core/RunwayInsight.swift Core/MenuBarTitle.swift CoreTests/RunwayTests.swift CoreTests/RunwayInsightTests.swift CoreTests/MenuBarTitleTests.swift
git commit -m "Add the lasts-the-cycle rule and drop menu bar days past the reset"
```

### Task 2: Popover and Dashboard

**Files:**
- Modify: `App/PopoverView.swift:232-239` (`daysFigure`, `daysCaption`), figure at `:206`
- Modify: `App/DashboardView.swift:163-180` (`runwayCard`)

**Interfaces:**
- Consumes: `Runway.lastsTheCycle(usage:now:)`, `RunwayInsight.resetCaption(usage:locale:)` from Task 1.

- [ ] **Step 1: Popover**

When `usage` is non-nil and `Runway.lastsTheCycle(usage:now:)`: `daysFigure` returns "Lasts the cycle", `daysCaption` returns `RunwayInsight.resetCaption(usage:)`. The figure keeps `.lineLimit(1)` and `.minimumScaleFactor(0.5)`. If "Lasts the cycle" at 40 pt does not fit next to the ring at the popover width, use a smaller size for this case only (builder call, say which size in the commit message).

- [ ] **Step 2: Dashboard**

In `runwayCard`, add a branch before the `wholeDaysLeft` branch: when `Runway.lastsTheCycle(usage:now: .now)`, show "Lasts the cycle" with `bigFigureStyle` (smaller size if it does not fit the KPI card) and `kpiDetail(RunwayInsight.resetCaption(usage: usage))`. Keep the health accent colour.

- [ ] **Step 3: Build, test and check by eye**

Run: `xcodebuild test -scheme CopilotRunway -destination 'platform=macOS'`
Expected: `** TEST SUCCEEDED **`.
Then run a Debug demo build with a scenario whose credits last past the reset. Check the menu bar, popover, Share image and Dashboard in light and dark mode. Capture only the app window, never the full screen.

- [ ] **Step 4: Commit**

```bash
git add App/PopoverView.swift App/DashboardView.swift
git commit -m "Show Lasts the cycle in the popover and Dashboard"
```
