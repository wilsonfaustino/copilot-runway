# "Lasts the cycle" cap (item 36, PR 1)

Status: approved decisions from the 2026-11-13 grilling session. PR 2 (workday toggle) builds on this.

## Intent

When the credits last past the reset, the app shows a days-left number that means little (for example "45d" in a
cycle that resets in 18 days). Replace that number with "Lasts the cycle". Copilot only, in the current
calendar-day mode now and in the workday mode later.

## Goals

- Menu bar: `62%` with no days part when the run-out date is at or after the reset.
- Popover days figure: "Lasts the cycle", caption "Resets <date>". The Share card renders `PopoverView`, so it
  follows.
- Dashboard Runway card: "Lasts the cycle", detail "Resets <date>".

## Non-goals

- Portkey budget runway. It keeps the raw days until item 33 (Portkey reset setting) is settled.
- Copy summary. `QuotaSummary.runOutLine` already says "Projected run-out: after the reset on <date>" and has no
  days number.
- Run-out sentence, headroom text, notifications. `RunwayInsight` already handles the past-reset case, and the
  short notification fires only when the run-out is before the reset.
- Health colours. A run-out at or after the reset is already `.healthy`.

## Constraints

- `Runway.wholeDaysLeft` stays unchanged. `PortkeyBudget.status` calls it and must keep the raw days.
- Core holds the rule, with unit tests. Views only render.

## Approaches

1. **Chosen:** one Core rule, `Runway.lastsTheCycle(usage:now:) -> Bool`: true when `now < resetDate` and
   `runOutDate >= resetDate`. `MenuBarTitle.title`, the popover and the Dashboard check it before they show days.
2. Change `wholeDaysLeft` to return nil past the reset. Rejected: Portkey uses it, and nil already means "no burn
   yet" ("--d"), so two states would share one value.
3. Cap the days at the days until the reset. Rejected: the user chose the "Lasts the cycle" text, and a capped
   number looks like runway when it is not.

## Design

- `Runway.lastsTheCycle(usage:now:)`. Unlimited plans and no burn yet return false (they keep "∞" and "--").
  `runOutDate == resetDate` counts as lasting the cycle, which matches `RunwayHealth` (short only when the run-out
  is before the reset).
- `MenuBarTitle.title`: when `lastsTheCycle`, return `"\(gaugePercent)%"`. `placeholder` stays `--% · --d`.
- `PopoverView.daysFigure` and `daysCaption`: "Lasts the cycle" and "Resets <date>", with the date in the format
  the popover already uses for days.
- `DashboardView.runwayCard`: the same text, in the same order as the other cards.

## Tests (CoreTests)

- `lastsTheCycle`: run-out before the reset (false), equal to the reset (true), after the reset (true), no burn
  (false), unlimited (false), now at or after the reset (false).
- `MenuBarTitle.title`: `"62%"` past the reset, existing `Nd` cases unchanged.

## Left to the builder

- Font size of "Lasts the cycle" in the popover figure and the Dashboard card, so it fits next to the other KPI
  figures.
- VoiceOver labels for the new text.

## Release

Patch release (visible change for all users). Add a What's New line (max 3 lines) in the release PR.
