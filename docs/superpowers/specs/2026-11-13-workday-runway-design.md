# Workday runway (item 36, PR 2)

Status: draft for approval. Decisions from the 2026-11-13 grilling session. Builds on PR #58 ("Lasts the cycle").

## Intent

The credits/day figure looks too low, because quiet weekends dilute it. An opt-in setting makes the runway math
count only workdays, so the figure matches the burn of a real work day.

## Goals

- Settings toggle "Count only weekdays" in the Gauge section, default off, footnote "Burn rate and run-out skip
  Saturdays and Sundays." It changes the app live, with no relaunch (same as `gaugeMode`).
- One toggle for Copilot and the Portkey budget.
- When on, all four `Runway` numbers change together, in workday units:
  - average burn = all credits used (weekend spend included) / workday time elapsed in the cycle, at least 1
    workday;
  - allowed burn = credits left / workday time until the reset; headroom = allowed minus average;
  - days left = credits left / average burn, in workdays;
  - run-out date = now, stepped forward over that much workday time, skipping weekends.
- Word: "workday" everywhere text has full words:
  - "credits/workday" (popover burn card, Dashboard burn card and per-agent line, Copy summary, headroom text);
  - "workdays of runway" / "1 workday of runway" (popover caption);
  - "N workdays" / "1 workday" (Dashboard Runway card, Portkey status);
  - "Runway is short: N workdays left", "Runway is critical: under 1 workday left" (notifications);
  - Dashboard banner: "To reach <reset>, keep the burn under N credits/workday." (`requiredDailyBurn` per
    workday).
- Menu bar keeps `Nd`; N is workdays.
- Daily burn chart: bars stay one per calendar day; the GitHub average rule uses the workday average and its
  label says "/workday"; the last-cycle ghost line and "last cycle by this point" do not change.
- Demo builds take `-countWeekdaysOnly YES` for one launch (same pattern as `-gaugeMode spent`).

## Non-goals

- Holidays, custom work weeks, locale weekends.
- Changing `cycleStart`, `resetDate` or `lastCycleDay` (stay UTC).
- Run-out and reset dates keep showing as UTC days.
- The "N days before the reset" / "N days early" parts of the run-out sentences stay calendar days between two
  dates.
- Portkey reset handling (item 33).

## Constraints

- Weekend = Saturday and Sunday in the user's local time zone (`TimeZone.current`). Tests pass the time zone, so
  they run the same on every machine and in CI.
- Default off: no visible change for current users.
- `RunwayHealth`, `MenuBarTitle`, `RunwayInsight`, `RunwayNotice`, `QuotaSummary`, `PortkeyBudget` and
  `Runway.lastsTheCycle` must all use the same setting, or the menu bar, colours and text disagree.
- Only weekend time left before the reset: allowed burn has no workdays to divide by, so `dailyHeadroom` returns
  nil (no headroom text). Health follows the run-out date against the reset, as today.

## Approaches

1. **Chosen: a value type passed as a parameter.** New Core enum `RunwayDays` with `case calendar` and
   `case workdays(TimeZone)`. Every `Runway` function and each caller above gets a `days: RunwayDays = .calendar`
   parameter. The default keeps every existing call and test unchanged. `UsageStore` reads the toggle and hands
   the value to the views, like `gaugeMode`. Explicit and easy to test; the cost is one more parameter on about
   15 functions.
2. Put the setting on `QuotaUsage`. Fewer signatures, but it mixes a user setting into the GitHub API data type,
   and `PortkeyBudget` builds its own `QuotaUsage`, so both builders must remember it.
3. A static global read from `UserDefaults` inside Core. Rejected: Core stays pure and testable.

## Design

- `Core/RunwayDays.swift`:
  - `public enum RunwayDays: Equatable, Sendable { case calendar; case workdays(TimeZone) }`
  - `func dayCount(from: Date, to: Date) -> Double`: for `.calendar`, seconds / 86,400; for `.workdays`, the
    time between the two dates that falls on Monday to Friday in the time zone, in days. Fractional, so a partly
    elapsed workday counts in part.
  - `func date(addingDays: Double, to: Date) -> Date`: the inverse. For `.workdays`, steps forward over workday
    time only (a start on a weekend first moves to Monday 00:00 local).
  - `var unitWord` style helpers for "day"/"workday" copy, used by Core text and passed to views.
- `Runway`: replace the raw `timeIntervalSince / secondsPerDay` math in `averageDailyBurn`, `allowedDailyBurn`,
  `runOutDate` with `days.dayCount` and `days.date(addingDays:to:)`. Minimum 1 elapsed day stays.
- Callers take `days:` and pass it on. Text that names the unit uses the helper.
- App: `UsageStore.countWeekdaysOnlyKey = "countWeekdaysOnly"`, re-read on `UserDefaults.didChangeNotification`
  like `gaugeModeKey`, exposed as `runwayDays: RunwayDays`. Settings toggle in the Gauge section.

## Tests (CoreTests)

- `RunwayDays.dayCount`: a full week is 5 workdays; Friday 12:00 to Monday 12:00 is 1 workday; a range inside a
  weekend is 0; the same instant range gives different counts in UTC and in `America/Sao_Paulo` (UTC-3) across
  a weekend edge.
- `RunwayDays.date(addingDays:to:)`: Friday 12:00 + 1 workday = Monday 12:00; Saturday + 0.5 = Monday 12:00;
  round trip with `dayCount`.
- `Runway` with `.workdays`: average burn on the Nov 13 example (cycle from Sunday Nov 1); headroom nil when only
  a weekend is left; minimum 1 workday at a cycle that starts on a Saturday.
- Text: "credits/workday", "workdays of runway" via the helper, notification titles, Portkey status, Copy
  summary line.
- Existing tests unchanged (default `.calendar`).

## Left to the builder

- Exact name of the copy helper(s) on `RunwayDays`.
- Settings footnote layout, same style as the gauge toggle.
- README and Core/README updates for the setting and the new math.

## Release

Minor release (new setting). What's New line in the release PR.
