# Workday runway Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An opt-in setting "Count only weekdays" makes burn rate, headroom, days left and run-out count only Monday to Friday in the user's time zone.

**Architecture:** New Core enum `RunwayDays` (`.calendar`, `.workdays(TimeZone)`) owns day counting, stepping and the unit word. Every `Runway` function and its Core callers take `days: RunwayDays = .calendar`, so current calls and tests do not change. `UsageStore` reads the toggle and passes the value to views, the menu bar and notifications.

**Tech Stack:** Swift, SwiftUI, Swift Testing, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-11-13-workday-runway-design.md`

## Global Constraints

- Default `.calendar` everywhere; with the toggle off, every output stays byte for byte the same.
- Weekend = Saturday and Sunday in the given `TimeZone`. The App passes `TimeZone.current`. Tests pass `TimeZone(identifier: "UTC")!` or `TimeZone(identifier: "America/Sao_Paulo")!`.
- `cycleStart`, `resetDate`, `lastCycleDay` and date display stay UTC.
- Unit word: "day"/"days" in `.calendar`, "workday"/"workdays" in `.workdays`. Menu bar keeps `Nd`.
- UserDefaults key: `countWeekdaysOnly` (Bool). Toggle label "Count only weekdays", footnote "Burn rate and run-out skip Saturdays and Sundays."
- No em dashes. 2-space indent. Comments only for non-obvious rules.
- New Swift files need `xcodegen generate` before the build (`project.yml` lists folders).
- Test command: `xcodebuild test -scheme CopilotRunway -destination 'platform=macOS'`.

## Review Focus

- Early cycle with a tiny burn gives a huge days left (Portkey budget up to 1,000,000 USD). `RunwayDays.date(addingDays:to:)` must return fast for 1e9 workdays. Test in Task 1.
- Overage gives negative days left. The run-out must stay in the past (callers clamp it to now). Test in Task 1.
- Now on a weekend: elapsed workdays freeze, so the average does not drop over the weekend. Test in Task 2.
- A time zone far from UTC moves the weekend edge. Test in Task 1 (Sao Paulo).
- Toggle flipped while the app runs: the menu bar title updates without a refresh. Check by eye in Task 4.

---

### Task 1: RunwayDays

**Files:**
- Create: `Core/RunwayDays.swift`
- Test: `CoreTests/RunwayDaysTests.swift`

**Interfaces:**
- Produces:
  - `public enum RunwayDays: Equatable, Sendable { case calendar; case workdays(TimeZone) }`
  - `public func dayCount(from start: Date, to end: Date) -> Double`: `.calendar` is seconds / 86,400. `.workdays` is the part of `start..<end` that falls on Monday to Friday in the time zone, in days. `end <= start` gives `end.timeIntervalSince(start) / 86_400` for both cases.
  - `public func date(addingDays days: Double, to start: Date) -> Date`: the inverse of `dayCount` for `days > 0`. `days <= 0` gives `start.addingTimeInterval(days * 86_400)` for both cases.
  - `public func dayWord(count: Int = 1) -> String`: "day"/"days" or "workday"/"workdays" (singular only for 1).

- [ ] **Step 1: Write the failing tests** (all dates 2026; Oct 5 and Oct 12 are Mondays)

```swift
let utcWorkdays = RunwayDays.workdays(TimeZone(identifier: "UTC")!)

@Test func calendarDayCountIsSecondsOverADay() {
  #expect(RunwayDays.calendar.dayCount(from: utcDate("2026-10-09T12:00:00Z"), to: utcDate("2026-10-12T12:00:00Z")) == 3)
}

@Test func workdayCountSkipsTheWeekend() {
  #expect(utcWorkdays.dayCount(from: utcDate("2026-10-05T00:00:00Z"), to: utcDate("2026-10-12T00:00:00Z")) == 5)
  #expect(utcWorkdays.dayCount(from: utcDate("2026-10-09T12:00:00Z"), to: utcDate("2026-10-12T12:00:00Z")) == 1)
  #expect(utcWorkdays.dayCount(from: utcDate("2026-10-10T00:00:00Z"), to: utcDate("2026-10-11T12:00:00Z")) == 0)
}

@Test func workdayCountFollowsTheTimeZone() {
  // Friday 22:00 UTC to Saturday 03:00 UTC: 2 workday hours in UTC, 5 in Sao Paulo (Friday 19:00 to midnight).
  let start = utcDate("2026-10-09T22:00:00Z")
  let end = utcDate("2026-10-10T03:00:00Z")
  #expect(abs(utcWorkdays.dayCount(from: start, to: end) - 2.0 / 24) < 1e-9)
  #expect(abs(RunwayDays.workdays(TimeZone(identifier: "America/Sao_Paulo")!).dayCount(from: start, to: end) - 5.0 / 24) < 1e-9)
}

@Test func addingWorkdaysStepsOverTheWeekend() {
  #expect(utcWorkdays.date(addingDays: 1, to: utcDate("2026-10-09T12:00:00Z")) == utcDate("2026-10-12T12:00:00Z"))
  #expect(utcWorkdays.date(addingDays: 0.5, to: utcDate("2026-10-10T00:00:00Z")) == utcDate("2026-10-12T12:00:00Z"))
}

@Test func addingNegativeDaysUsesCalendarTime() {
  #expect(utcWorkdays.date(addingDays: -2, to: utcDate("2026-10-12T00:00:00Z")) == utcDate("2026-10-10T00:00:00Z"))
}

@Test func addingHugeWorkdaysReturns() {
  let start = utcDate("2026-10-05T00:00:00Z")
  #expect(utcWorkdays.date(addingDays: 1e9, to: start) > start)
}

@Test func dayWordsFollowTheMode() {
  #expect(RunwayDays.calendar.dayWord() == "day")
  #expect(RunwayDays.calendar.dayWord(count: 3) == "days")
  #expect(utcWorkdays.dayWord() == "workday")
  #expect(utcWorkdays.dayWord(count: 0) == "workdays")
}
```

- [ ] **Step 2: Run `xcodegen generate`, then the test command.** Expected: build fails, `RunwayDays` not found.

- [ ] **Step 3: Implement `Core/RunwayDays.swift`.** Use a Gregorian `Calendar` with the enum's time zone. `dayCount` walks local days from `start` to `end` and sums the overlap of weekdays (cycles are at most 31 days). `date(addingDays:to:)`: if `start` is on a weekend, move to the next Monday 00:00 local; jump whole weeks first (`floor(days / 5)` weeks, 7 days each; for counts too big for `Calendar.date(byAdding:)`, use `addingTimeInterval(weeks * 7 * 86_400)`), then walk the remainder day by day. Comment why the week jump exists (huge counts early in a cycle or with a large Portkey budget).

- [ ] **Step 4: Run the test command.** Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Core/RunwayDays.swift CoreTests/RunwayDaysTests.swift CopilotRunway.xcodeproj
git commit -m "Add RunwayDays for calendar and workday counting"
```

### Task 2: Runway, health and menu bar take `days`

**Files:**
- Modify: `Core/Runway.swift`, `Core/RunwayHealth.swift`, `Core/MenuBarTitle.swift`
- Modify: `CoreTests/RunwayTests.swift` (`makeUsage` gets `resetDate: Date = utcDate("2026-11-01T00:00:00Z")`)
- Test: `CoreTests/RunwayTests.swift`, `CoreTests/MenuBarTitleTests.swift`

**Interfaces:**
- Consumes: `RunwayDays.dayCount(from:to:)`, `date(addingDays:to:)` (Task 1).
- Produces: a trailing `days: RunwayDays = .calendar` parameter on `Runway.averageDailyBurn(credits:resetDate:now:days:)`, `averageDailyBurn(usage:now:days:)`, `allowedDailyBurn(usage:now:days:)`, `dailyHeadroom(usage:now:days:)`, `daysLeft(usage:now:days:)`, `wholeDaysLeft(usage:now:days:)`, `runOutDate(usage:now:days:)`, `lastsTheCycle(usage:now:days:)`; `RunwayHealth.init(usage:now:days:)`, `RunwayHealth.init(usage:hasError:now:days:)`; `MenuBarTitle.title(usage:now:mode:days:)`.

Example: `makeUsage` cycle Oct 1 (Thursday) to Nov 1. At Sunday Oct 11 00:00 UTC, 7 workdays have passed and 15 are left.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func workdayAverageCountsOnlyWorkdays() {
  let usage = makeUsage(creditsUsed: 7000)
  let now = utcDate("2026-10-11T00:00:00Z")
  #expect(Runway.averageDailyBurn(usage: usage, now: now, days: utcWorkdays) == 1000)
  #expect(Runway.wholeDaysLeft(usage: usage, now: now, days: utcWorkdays) == 5)
  // 5 workdays from Monday Oct 12 end on Friday Oct 16 at midnight.
  #expect(Runway.runOutDate(usage: usage, now: now, days: utcWorkdays) == utcDate("2026-10-17T00:00:00Z"))
  #expect(abs(Runway.dailyHeadroom(usage: usage, now: now, days: utcWorkdays)! - (5000.0 / 15 - 1000)) < 1e-9)
}

@Test func workdayAverageHoldsOverTheWeekend() {
  let usage = makeUsage(creditsUsed: 7000)
  #expect(Runway.averageDailyBurn(usage: usage, now: utcDate("2026-10-10T00:00:00Z"), days: utcWorkdays)
    == Runway.averageDailyBurn(usage: usage, now: utcDate("2026-10-11T23:00:00Z"), days: utcWorkdays))
}

@Test func headroomIsNilWhenOnlyAWeekendIsLeft() {
  #expect(Runway.dailyHeadroom(usage: makeUsage(creditsUsed: 6000), now: utcDate("2026-10-31T00:00:00Z"), days: utcWorkdays) == nil)
}

@Test func workdayAverageCountsAtLeastOneWorkday() {
  // The Aug 1 2026 cycle starts on a Saturday, so no workday has passed by Sunday noon.
  let usage = makeUsage(creditsUsed: 300, resetDate: utcDate("2026-09-01T00:00:00Z"))
  #expect(Runway.averageDailyBurn(usage: usage, now: utcDate("2026-08-02T12:00:00Z"), days: utcWorkdays) == 300)
}
```

`CoreTests/MenuBarTitleTests.swift`:
```swift
@Test func titleShowsWorkdaysLeft() {
  #expect(MenuBarTitle.title(usage: makeUsage(creditsUsed: 7000), now: utcDate("2026-10-11T00:00:00Z"), days: utcWorkdays) == "42% · 5d")
}
```

- [ ] **Step 2: Run the test command.** Expected: build fails on the extra `days:` argument.

- [ ] **Step 3: Implement.** Replace `timeIntervalSince / secondsPerDay` in `averageDailyBurn` and `allowedDailyBurn` with `days.dayCount(from:to:)`, and `runOutDate` with `days.date(addingDays:to:)`. Keep `max(elapsed, 1)`. `allowedDailyBurn` stays non-optional; `dailyHeadroom` adds a guard that returns nil when `days.dayCount(from: now, to: resetDate) == 0`. Pass `days` through every function in the Interfaces list, including `RunwayHealth` and `MenuBarTitle`.

- [ ] **Step 4: Run the test command.** Expected: `** TEST SUCCEEDED **`, all existing tests unchanged.

- [ ] **Step 5: Commit**

```bash
git add Core/Runway.swift Core/RunwayHealth.swift Core/MenuBarTitle.swift CoreTests/RunwayTests.swift CoreTests/MenuBarTitleTests.swift
git commit -m "Count runway math in workdays when asked"
```

### Task 3: Core text in workday units

**Files:**
- Modify: `Core/RunwayInsight.swift`, `Core/RunwayNotice.swift`, `Core/QuotaSummary.swift`, `Core/PortkeyBudget.swift`
- Test: `CoreTests/RunwayInsightTests.swift`, `CoreTests/RunwayNoticeTests.swift`, `CoreTests/QuotaSummaryTests.swift`, `CoreTests/PortkeyBudgetTests.swift`

**Interfaces:**
- Consumes: Task 2 functions with `days:`, `RunwayDays.dayWord(count:)`.
- Produces: trailing `days: RunwayDays = .calendar` on `RunwayInsight.runOutSentence`, `requiredDailyBurn`, `headroomText`, `banner`, `popoverSentence`; `RunwayNotice.toSend(usage:now:sentKeys:locale:days:)`; `QuotaSummary.text(...gaugeMode:days:)`; `PortkeyBudget.status(spentUSD:budgetUSD:resetDate:now:locale:days:)`.

Copy (exact): "N credits/workday of headroom", "N credits/workday over budget", "To reach <reset>, keep the burn under N credits/workday.", "Runway is short: N workdays left", "Runway is critical: under 1 workday left", Copy summary "Average workday burn: N credits/workday", Portkey "..., N workdays". Every one uses `dayWord`, so `.calendar` text stays as it is ("Average daily burn: N credits/day").

- [ ] **Step 1: Write the failing tests** (`usLocale` already exists in RunwayInsightTests)

```swift
@Test func headroomTextUsesWorkdays() {
  let text = RunwayInsight.headroomText(usage: makeUsage(creditsUsed: 7000), now: utcDate("2026-10-11T00:00:00Z"), locale: usLocale, days: utcWorkdays)
  #expect(text == "667 credits/workday over budget")
}

@Test func bannerTargetUsesWorkdays() {
  let banner = RunwayInsight.banner(usage: makeUsage(creditsUsed: 7000), errorMessage: nil, categoryCredits: [], now: utcDate("2026-10-11T00:00:00Z"), locale: usLocale, days: utcWorkdays)
  #expect(banner.detail.hasPrefix("To reach Nov 1, keep the burn under 333 credits/workday. 667 credits/workday over budget."))
}
```

`RunwayNoticeTests`: `toSend(usage: makeUsage(creditsUsed: 7000), now: utcDate("2026-10-11T00:00:00Z"), sentKeys: [], days: utcWorkdays)` contains a notice with title `"Runway is short: 5 workdays left"`.
`QuotaSummaryTests`: the same usage gives a line `"Average workday burn: 1,000 credits/workday"`.
`PortkeyBudgetTests`: `status(spentUSD: 7, budgetUSD: 12, resetDate: utcDate("2026-11-01T00:00:00Z"), now: utcDate("2026-10-11T00:00:00Z"), locale: Locale(identifier: "en_US"), days: utcWorkdays)?.text` ends with `", 5 workdays"`.

- [ ] **Step 2: Run the test command.** Expected: build fails on `days:`.

- [ ] **Step 3: Implement.** Pass `days` into every `Runway` and `RunwayHealth` call in these four files. `requiredDailyBurn` returns nil when no workday time is left before the reset (no division by zero). Build the unit text with `days.dayWord(count:)`. Copy summary label: "Average daily burn" for `.calendar`, "Average workday burn" for `.workdays`.

- [ ] **Step 4: Run the test command.** Expected: `** TEST SUCCEEDED **`, existing text tests unchanged.

- [ ] **Step 5: Commit**

```bash
git add Core/RunwayInsight.swift Core/RunwayNotice.swift Core/QuotaSummary.swift Core/PortkeyBudget.swift CoreTests
git commit -m "Name workdays in runway text when asked"
```

### Task 4: Setting, App wiring and docs

**Files:**
- Modify: `App/UsageStore.swift`, `App/SettingsView.swift`, `App/PopoverView.swift`, `App/DashboardView.swift`, `App/RunwayNotifier.swift`, `App/AppDelegate.swift`, `README.md`, `Core/README.md`

**Interfaces:**
- Consumes: every `days:` parameter from Tasks 2 and 3.
- Produces: `UsageStore.countWeekdaysOnlyKey = "countWeekdaysOnly"` and `private(set) var runwayDays: RunwayDays` (`.workdays(.current)` when the Bool is true, else `.calendar`).

- [ ] **Step 1: UsageStore.** Read the key at start and on `UserDefaults.didChangeNotification`, next to the gauge mode reload. On change, rebuild `title` the same way `reloadGaugeMode` does. Pass `runwayDays` to `MenuBarTitle.title` and `QuotaSummary.text` (also in demo mode).

- [ ] **Step 2: Settings.** In the Gauge section, add `Toggle("Count only weekdays", ...)` bound to `@AppStorage(UsageStore.countWeekdaysOnlyKey)`, `.toggleStyle(.switch)`, disabled in demo mode like the gauge toggle. Add "Burn rate and run-out skip Saturdays and Sundays." to the section footer, after the current gauge text.

- [ ] **Step 3: Views and notifier.** Pass `usageStore.runwayDays` to every `Runway`, `RunwayHealth`, `RunwayInsight`, `PortkeyBudget` and `RunwayNotice` call in `PopoverView`, `DashboardView`, `AppDelegate` and `RunwayNotifier`. Text with a unit uses `dayWord`:
  - popover burn card detail "credits/workday", caption "workdays of runway" / "workday of runway";
  - Dashboard burn card unit, per-agent line "credits/workday.", Runway card "N workdays" / "1 workday";
  - daily burn chart label "GitHub average, N/workday" and accessibility value "N credits per workday". The bars, ghost line and "last cycle by this point" do not change.

- [ ] **Step 4: Docs.** README: the new Settings toggle and what it changes. Core/README: the `RunwayDays` math (workday time in the local time zone, the 1-workday minimum, nil headroom when only a weekend is left).

- [ ] **Step 5: Build, test, check by eye.** Run the test command. Expected: `** TEST SUCCEEDED **`. Then a Debug demo build with `-demo typical -countWeekdaysOnly YES`: the menu bar, popover, Dashboard and chart show workday units. Flip the toggle in a normal Debug build: the menu bar title changes without a refresh. Capture only the app window.

- [ ] **Step 6: Commit**

```bash
git add App/UsageStore.swift App/SettingsView.swift App/PopoverView.swift App/DashboardView.swift App/RunwayNotifier.swift App/AppDelegate.swift README.md Core/README.md
git commit -m "Add the Count only weekdays setting"
```
