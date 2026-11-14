# Days off in workday mode: design

Roadmap item 40. Approved 2026-11-14. Canvas (private): https://claude.ai/artifact/CLRxB8bMntJGmvnN1NphPe, artboards "Item 40: Runway tab with Days off" and "Item 40: popover marker".

## Intent

With "Count only weekdays" on, the runway already skips Saturdays and Sundays. A holiday or a vacation week is the same kind of day: the user does not code, so no credits burn. Today those days still count as workdays. A past day off lowers the average burn per workday, and a future day off makes the run-out date too early. The user marks those days, and the runway skips them like weekends.

## Goals

- In the Settings Runway tab, a "Days off" row with a calendar grid of the current cycle. Click a workday to mark or unmark it. Shift-click marks every workday between the last clicked day and this one. A Clear button removes all marks.
- Days off count like weekend days in all workday math: burn rate, headroom, days left, run-out date, health, "Lasts the cycle", Portkey days of runway and notifications.
- A marker in the popover: "Excludes N days off" under the runway sentence, only when N > 0.

## Non-goals

- Days off in calendar mode (toggle off). The row shows but is faded, with the caption "Turn on Count only weekdays to mark days off."
- Future cycles. Only the current cycle has a grid. Marks outside the current cycle are ignored, so the list is empty after each reset.
- A holiday calendar or any holiday API (a network host other than api.github.com breaks the local-only rule).
- Dashboard burn chart marker, Copy summary and Share card. They stay unchanged. (The user approved the canvas without the chart marker; a later item if wanted.)
- Half days.

## Anti-goals

- With no days off marked, every output must stay byte for byte the same as today, in both modes.
- No new network call, no token use.

## Constraints

- A day off is a local calendar date in the user's time zone (`TimeZone.autoupdatingCurrent`), the same rule as weekends in `RunwayDays.workdays`. `cycleStart`, `resetDate` and date display stay UTC.
- Stored in UserDefaults under the key `daysOff` as an array of `yyyy-MM-dd` strings. Demo mode must not write it.
- A weekend date is never a day off (not clickable; ignored if stored).
- `RunwayDays.date(addingDays:to:)` has a whole-week jump that counts 5 workdays per week. Days off break that count, so the jump must not cross a day off.
- Copy, verbatim: row label `Days off`; header `<Month> <Year> · N days off` (`1 day off` for one); button `Clear`; caption on: `Click a workday to mark it off. Shift-click marks a range. Days off do not count toward burn rate or runway. Resets with the cycle.`; caption off: `Turn on Count only weekdays to mark days off.`; popover: `Excludes N days off` (`Excludes 1 day off`).

## Approaches

1. **Calendar grid (picked by the user).** A custom 7-column SwiftUI Grid of the cycle month. One click per holiday, the whole cycle visible at once. Cost: a custom view, because macOS has no multi-date picker (`MultiDatePicker` is iOS only, `DatePicker .graphical` picks one date, `NSDatePicker .range` picks one range).
2. **List with From/To pickers.** Standard controls, less work, but 4 clicks per holiday and no view of the marked days. Not picked.

A vacation range and a single holiday are stored the same way, as dates. A range is only a picking shortcut.

## Decisions

- Only active with "Count only weekdays" on (user).
- Current cycle only (user).
- Popover marker (user). Placement and wording from the canvas.
- Range by shift-click (user, "select a range of out of office").
- Week starts on the system's first weekday (`Calendar.current.firstWeekday`) (builder call, canvas shows Sunday first).

## Left to the builder

- The grid shows the calendar days of the cycle's UTC month (the cycle runs from the 1st 00:00 UTC to the next 1st). Days are labeled by date. A day off is matched in the user's time zone, so in UTC-3 a day off on the 30th still covers its local hours, and the math clips it at the reset as for any day.
- How `RunwayDays` carries the dates (an associated value on `.workdays` is the obvious fit; `Equatable` then makes `UsageStore` refresh when the marks change).
