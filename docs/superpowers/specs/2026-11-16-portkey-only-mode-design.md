# Portkey-only mode (roadmap item 45)

Date: 2026-11-16. Layout canvas (private): https://claude.ai/artifact/PUWxSWHedPPqi5Q3saVgEm

## Intent

Some users route their agents through Portkey and have no usable Copilot: `gh` is missing, `gh` is logged out, or
the org gives their GitHub account no Copilot seat. Today they see only an error. `UsageStore.refresh` returns
before the session scan when the Copilot call fails (`App/UsageStore.swift:179`, "The cycle start comes from the
API"), so the Portkey card never loads, even with Portkey requests and a budget on disk.

This mode gives those users a working app: the menu bar, popover and Dashboard show their Portkey runway or spend.

## Goals

- A no-Copilot user with Portkey data sees Portkey runway (budget set) or Portkey spend (no budget).
- The user can tell at a glance why the Copilot cards are gone, and what to do about it.
- A no-Copilot user with no Portkey data sees the error from today plus a short explanation of this mode.
- Copilot users see no change. A Copilot outage keeps the current behavior.

## Non-goals

- Portkey task categories, projects or top sessions. Those cards read Copilot records only and stay hidden.
- A Portkey summary for Copy summary.
- Any new network call. Portkey data stays local session files.

## Anti-goals

- A Copilot outage (offline, GitHub 5xx) must never flip a Copilot user into Portkey-only mode.
- No setting or toggle for this mode. It is automatic.

## Decisions (user, 2026-11-16)

1. **"No Copilot" errors:** `ghNotFound`, `notLoggedIn` (401), any other 4xx except 429 (this covers an org
   that gives no seat; the exact status is unverified, so all 4xx count), and `invalidResponse` (for example a 200
   without the premium snapshot). **Outage:** `network`, 5xx and 429. An outage keeps today's behavior.
2. **Cycle:** the calendar month. Cycle start is the 1st at 00:00 UTC; the reset date is the 1st of the next
   month at 00:00 UTC (the Portkey monthly reset).
3. **Menu bar:**
   - Budget set: the normal title from the Portkey budget usage, for example "58% · 11d". The gauge is the
     Portkey part, full opacity.
   - No budget: the amount spent this month, for example "$10.17" (`PortkeySpend.formatted`), with an empty gauge
     track.
   - No Portkey data: today's error title ("gh missing", "gh login", "error").
4. **Popover**, see the canvas artboards:
   - Header gets a "Portkey only" chip (kept in the Share image).
   - The red error label is replaced by a grey info line that names the cause:
     - `ghNotFound`: "GitHub CLI not found, so Copilot data is off."
     - `notLoggedIn`: "GitHub CLI not logged in, so Copilot data is off."
     - other 4xx and `invalidResponse`: "No Copilot seat for this GitHub account, so Copilot data is off."
     - then, budget set: "The runway shows your Portkey budget." No budget: "Showing Portkey spend only."
     The Share image leaves the info line out, like other non-share rows.
   - Budget set: the ring, days figure and insight sentence come from the Portkey budget usage.
   - No budget: empty ring track with "--", the big figure is the amount spent, caption "spent this month", and a
     link "Set a monthly budget to see runway" that opens Settings on the Sources tab.
   - Stat cards: budget set: Spent ($ of budget), Daily burn (USD/day), Requests. No budget: Daily burn,
     Requests. The Copilot cards (Used, Daily burn in credits, Per PR) are hidden.
   - By model (credits), the combined box and the Copilot review note are hidden.
   - The Portkey card stays, without its budget status line (the ring already shows it).
5. **Popover, no Copilot and no Portkey data** (no Portkey request this cycle and no budget): today's red error
   label, plus a card "Using Portkey without Copilot?" that says the app also shows Portkey spend from OpenCode,
   Pi and omp sessions, found none this month, and that a budget in Settings shows runway. An "Open Settings"
   button opens the Sources tab. Only for no-Copilot errors, never for an outage.
6. **Dashboard:**
   - Subtitle: "Portkey only · <cycle start> to <last cycle day> · resets <reset date>".
   - Insight banner from the Portkey budget usage, plus the cause line.
   - KPI row: Runway, Left (of budget, percent), Average daily burn (USD per day), Requests (USD each).
   - Daily burn chart: the existing USD form (`CombinedDailyBurn`; Copilot days are all 0 because `Credits.byDay`
     zero-fills every cycle day). In this mode Portkey bars use the full bar color, not `portkeyBarColor`
     (0.45 opacity). The average line uses the Portkey budget usage; with no budget, spend divided by elapsed
     days. The last-cycle line and comparison sentence use `previousPortkeySpend`, as in the combined form.
   - Portkey section stays. Its caption "Not part of the Copilot runway." drops that sentence in this mode.
   - Hidden: Outcomes, By task, By model (credits), By agent (credits), By project, Top sessions.
   - Copy summary is disabled.
7. **Demo scenario:** yes (Debug `-demo`).
9. **Cycle per mode:** each mode keeps its own cycle. Copilot mode (and the item 42 combined gauge) keeps the
   Copilot cycle for Portkey; Portkey-only mode uses the calendar month. A Portkey notice can fire twice after a
   mode switch; accepted, because switches are rare.
10. **Gauge tone (plan review, 2026-11-16):** the Portkey-only gauge is one full-tone part in the health accent,
    like a Copilot-only gauge, not the canvas teal.
11. **Share (plan review B2, 2026-11-16):** in Portkey only, Share sends the image only, with no summary text.
8. **README:** a section that explains the behavior without Copilot, and the "Zero setup" wording.

## Approaches

- **A. One mode flag in the store (chosen).** A small Core type decides which errors mean no Copilot, the
  calendar month reset date and the no-budget title. `UsageStore` gets a Portkey-only state; in it `gaugeUsage`
  comes from `PortkeyBudget.usage` and the session scan runs from the month start. Views hide Copilot cards behind
  one check. Reuses the `gaugeUsage` path from item 42 (ring, menu bar, notices, `Runway`). Cost: about ten view
  branches.
- **B. Separate Portkey-only views.** Clean views, but the header, ring, footer, Share and chart code copied
  twice (about 300 lines), and every later popover change made in two places. Not chosen.
- **Dropped: a generic budget-source protocol.** A large refactor this feature does not need.

## Behavior details (my calls, correct if wrong)

- **State:** `UsageStore` holds one value for the mode: Copilot, Portkey only (with the cause), or no Copilot with
  no Portkey data (with the cause). The cause drives the info line text.
- **Enter:** a no-Copilot error makes refresh skip the early return, run the session scan from the month start,
  then pick Portkey only (any Portkey request this cycle, or a budget above 0, as in `PortkeyBudget.showsBlock`)
  or no data.
- **Stale Copilot data:** entering either no-Copilot state clears `usage`, `combinedBudget` and the Copilot
  aggregates. A user who logs out should not see last cycle's Copilot numbers as current.
- **Debounce:** a 403 can be a GitHub secondary rate limit, a locked keychain after wake makes `gh auth token`
  fail (`notLoggedIn`), and a bad body gives `invalidResponse`. So: with no good Copilot response yet in this
  run, the first no-Copilot response enters the mode at once. After a good Copilot response, it takes a second
  no-Copilot response at least 240 s after the first (final review, 2026-11-16: the wake refresh and the poll can
  run seconds apart); until then the app keeps today's behavior (error title, last data dimmed).
- **Leave:** the next good Copilot response returns to Copilot mode.
- **Not saved:** the mode is not saved across launches. A Portkey-only user who launches offline sees today's
  error until GitHub answers. An outage with no mode known yet keeps today's early return.
- **Outage while in Portkey-only:** keep Portkey-only and refresh the Portkey data. The Portkey data is local, and
  the next good or no-Copilot response settles the mode.
- **Notices:** Copilot notices do not run (no Copilot usage). Portkey notices run with the month reset date and
  the same toggle.
- **Outcomes fetch:** skipped in both no-Copilot states (it needs the Copilot cycle).
- **Workdays and days off:** apply to the Portkey runway as they do to the combined runway; days-off marks use the
  month reset date for cycle filtering.
- **Settings gauge tiles:** follow `gaugeUsage`, like the popover.
- **Health and accent:** computed from the Portkey budget usage with no error, so the ring is not dimmed and not
  red. No budget: neutral accent.

## Tests

Core unit tests for: the error classification (each case, 429, 5xx, 403, 404, `invalidResponse`); the month reset
date (mid month, the 1st at 00:00 UTC, December to January, a leap year February); the no-budget menu bar title;
the info line text per cause and budget; the demo scenario values. Views stay thin.

## Left to the builder

- The names of the new Core type and the store state.
- How the views branch, as long as each Copilot card hides behind one check.
- The exact no-budget KPI texts on the Dashboard, following the popover's no-budget pattern.
- How many demo scenarios (at least budget set; no budget is useful too) and their numbers.
- README wording, in ASD-STE100.
