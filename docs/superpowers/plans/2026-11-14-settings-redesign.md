# Settings redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the one long Settings Form with 4 toolbar tabs (General, Runway, Sources, About) in a Shottr-style layout: right-aligned labels, checkboxes, dividers, and picture tiles for the gauge mode. Layout only.

**Architecture:** `Settings { SettingsView }` holds a `TabView` with one small view per tab. Each tab is a `Form` with `.formStyle(.columns)`. The macOS Settings scene draws the tabs as toolbar icons and sizes the window to each tab. A new Core type `GaugeTile` gives the percent, fraction and sample flag for each tile, so the tile math has unit tests.

**Tech Stack:** Swift, SwiftUI (macOS 15), Swift Testing, XcodeGen.

**Spec:** roadmap item 39 in `.serena/memories/roadmap-candidates.md` (decisions 2026-11-14) and the approved canvas https://claude.ai/artifact/CLRxB8bMntJGmvnN1NphPe (artboards Main = General, Runway, Sources, About).

## Global Constraints

- Layout only. Same controls, same UserDefaults keys (`RunwayNotifier.enabledKey`, `Theme.taskPalettePreferenceKey`, `UsageStore.gaugeModeKey`, `UsageStore.countWeekdaysOnlyKey`, `UsageStore.portkeyBudgetKey`, organization through `usageStore.setOrganization`), same behavior.
- Window width 520 pt. Label column right-aligned. Divider lines between groups, no boxed sections.
- Checkboxes (`.toggleStyle(.checkbox)`), not switches.
- Tab names and SF Symbols: General `gearshape`, Runway `gauge.with.needle`, Sources `tray.2`, About `info.circle`.
- Left-column labels, verbatim: General: `Login`, `Notifications`, `Task colors`. Runway: `Gauge shows`, `Days`. Sources: `GitHub account`, `Organization`, `Portkey budget`, `Price overrides`. About: `Copilot Runway`, `Made by`, `Source`, `License`.
- Copy changes, verbatim: tile captions `Credits left` / `Credits spent`; Gauge caption `Applies to the menu bar, the popover ring, the dashboard and Copy summary. The color still follows the runway.`; Days caption `Burn rate and run-out skip Saturdays and Sundays.`; Portkey field with prompt `No budget` and trailing text `USD per month`. All other captions stay as today.
- Every control that is `.disabled(DemoLaunch.isActive)` today stays disabled in demo mode, tiles included.
- No em dashes. 2-space indent. Comments only for non-obvious rules.
- Test command: `xcodebuild test -scheme CopilotRunway -destination 'platform=macOS'`.

## Review Focus

1. Organization or Portkey text typed, then the user switches tab (not closes the window): the value must save, as it does today on close. Sources tab keeps the `onAppear`/`onDisappear` load and save; check by hand in Task 4.
2. Open at login in `.requiresApproval`: the caption and `Open Login Items` button still show under the checkbox in General.
3. No usage yet, an unlimited plan, or a usage error: the tiles must not show `--%` or an empty ring. `GaugeTile` falls back to a sample (tests in Task 1).
4. Small screen (visible height about 700 pt): the tallest tab (Sources) must fit with no clipped control. The item 34 bug was a clipped window.
5. Demo mode (`-demo typical`): no control, tiles included, writes a real preference.

---

### Task 1: GaugeTile in Core

**Files:**
- Create: `Core/GaugeTile.swift`
- Test: `CoreTests/GaugeTileTests.swift`

**Interfaces:**
- Produces: `public struct GaugeTile: Equatable, Sendable { public let fraction: Double; public let percent: Int; public let isSample: Bool }` and `public static func make(usage: QuotaUsage?, hasError: Bool, mode: GaugeMode) -> GaugeTile`.

Rule: with usage, no error and not unlimited, `fraction = MenuBarTitle.gaugeFraction(usage:mode:)`, `percent = Runway.wholeGaugePercent(usage:mode:)`, `isSample = false`. Else a sample: left `0.62` / `62`, spent `0.38` / `38`, `isSample = true`.

- [ ] **Step 1: Write the failing tests** (reuse `makeUsage` from the test helpers):

```swift
@Test func tileUsesRealUsage() {
  let usage = makeUsage(creditsUsed: 6100)
  #expect(GaugeTile.make(usage: usage, hasError: false, mode: .left) == GaugeTile(fraction: MenuBarTitle.gaugeFraction(usage: usage, mode: .left), percent: 49, isSample: false))
  #expect(GaugeTile.make(usage: usage, hasError: false, mode: .spent).percent == 51)
}
@Test func tileFallsBackToSampleWithoutUsage() {
  #expect(GaugeTile.make(usage: nil, hasError: false, mode: .left) == GaugeTile(fraction: 0.62, percent: 62, isSample: true))
  #expect(GaugeTile.make(usage: nil, hasError: false, mode: .spent) == GaugeTile(fraction: 0.38, percent: 38, isSample: true))
}
@Test func tileFallsBackToSampleOnError() { /* makeUsage(creditsUsed: 6100), hasError: true -> isSample true, percent 62 for .left */ }
@Test func tileFallsBackToSampleForUnlimitedPlan() { /* unlimited QuotaUsage as in GaugeModeTests -> isSample true for both modes */ }
@Test func spentTileIsFullAtOverage() { /* makeUsage(creditsUsed: 13000), .spent -> fraction 1, percent 100, isSample false */ }
```

The memberwise init must be public (tests build it).

- [ ] **Step 2: Run `xcodegen generate`, then the test command.** Expected: build fails, `GaugeTile` not found.
- [ ] **Step 3: Implement `GaugeTile` in `Core/GaugeTile.swift`.** One comment on the sample values (they only show the shape of the choice).
- [ ] **Step 4: Run the test command.** Expected: `** TEST SUCCEEDED **`.
- [ ] **Step 5: Commit** `git add Core/GaugeTile.swift CoreTests/GaugeTileTests.swift` (plus `CopilotRunway.xcodeproj` if xcodegen changed it), message `Add GaugeTile for the Settings gauge picture tiles`.

### Task 2: Tabs and column layout

**Files:**
- Modify: `App/SettingsView.swift` (whole body; remove `HeightResizableWindow` and the `firstDescendant` extension)
- Create: `App/SettingsTabs.swift` with `SettingsGeneralTab`, `SettingsRunwayTab`, `SettingsSourcesTab`, `SettingsAboutTab` (private helpers move with the tab that uses them)

**Interfaces:**
- `SettingsView(usageStore:)` keeps its signature, so `CopilotRunwayApp` does not change.
- Each tab: `struct SettingsXTab: View { let usageStore: UsageStore }` (About and General need it for `availableVersion` and the test notice).

Layout per tab: `Form { ... }.formStyle(.columns).padding(20).frame(width: 520).fixedSize(horizontal: false, vertical: true)`. Each row is a control with the label in its title (columns style puts it in the right-aligned left column), caption as `Text(...).captionStyle()` under it in the same `LabeledContent` or row. `Divider()` between groups. Toggles get `.toggleStyle(.checkbox)` and a label from Global Constraints with the control text as the checkbox title (`LabeledContent("Login") { Toggle("Open at login", ...) }`).

Content per tab (from the canvas):
- General: Login (Open at login + approval caption/button), Notifications (Runway notifications + DEBUG Send test notice), Task colors (Colorblind-safe task colors).
- Runway: Gauge shows (plain `Picker` with `.radioGroup` style as a stand-in until Task 3), Days (Count only weekdays). Split captions per Global Constraints.
- Sources: GitHub account, Organization (field + `statusRow` + caption), Portkey budget (field 120 pt + `USD per month` + refused label + caption), Price overrides, then the lock `Local only...` label. Owns the organization and Portkey `@State`, `onAppear` load and `onDisappear` save, unchanged.
- About: same rows as today's `aboutSection`.

`SettingsView` body: `TabView { SettingsGeneralTab(...).tabItem { Label("General", systemImage: "gearshape") } ... }`. Keep the `didBecomeActive` login status refresh in the General tab.

- [ ] **Step 1: Build the 4 tabs and the TabView; delete `HeightResizableWindow` and `firstDescendant`** (the window now fits each tab; Review Focus 4 checks small screens).
- [ ] **Step 2: Run the test command.** Expected: `** TEST SUCCEEDED **` (no Core change; proves the App target builds).
- [ ] **Step 3: Launch a Debug build with `-demo typical`, open Settings, capture only the Settings window rect** (per memory: no full-screen captures). Expected: 4 toolbar tabs, right-aligned labels, checkboxes, every control from today present.
- [ ] **Step 4: Commit** `App/SettingsView.swift App/SettingsTabs.swift` (plus project file if regenerated), message `Split Settings into General, Runway, Sources and About tabs`.

### Task 3: Gauge picture tiles

**Files:**
- Modify: `App/SettingsTabs.swift` (Runway tab)
- Modify: `App/PopoverView.swift` only if needed to share the horseshoe shape (make `RunwayRing.horseshoe` reachable, no behavior change)

**Interfaces:**
- Consumes: `GaugeTile.make(usage:hasError:mode:)`, `RunwayHealth(usage:hasError:now:days:)`, `Theme.accent(_:)`, `RunwayGlyph.trackSweepDegrees`, `trackStartDegrees`, `trackOpacity`.

Two buttons in a row (`role` radio for VoiceOver: `.accessibilityAddTraits(.isSelected)` on the chosen one), each a 112x76 rounded thumb with a 56 pt horseshoe ring and the percent in the middle, caption under it. Selected thumb: 2 pt accent-color border; other: 1 pt separator border. Ring color: `Theme.accent(health)` for real data, `.secondary` when `isSample`. Click writes `gaugeMode`. Accessibility label: `"Credits left, 62 percent"` style, plus `", sample"` when `isSample`.

- [ ] **Step 1: Replace the radio-group stand-in with the tiles.**
- [ ] **Step 2: Run the test command.** Expected: `** TEST SUCCEEDED **`.
- [ ] **Step 3: Demo check:** `-demo typical` shows real percents matching the popover ring; `-demo` with no usage (or an error scenario from `DemoScenario`) shows the gray sample tiles. Capture the Settings window rect for each, light and dark.
- [ ] **Step 4: Commit** message `Show the gauge mode as picture tiles in Settings`.

### Task 4: README and hand checks

**Files:**
- Modify: `README.md:159-172` (Settings list grouped by tab; same facts) and the Settings screenshot at line 186 (user replaces the image; leave a note in the PR).

- [ ] **Step 1: Update the README Settings list:** one bullet group per tab, same settings and wording of behavior.
- [ ] **Step 2: Hand checks** (Review Focus 1, 2, 5, 4): type an org, switch tab, reopen: saved. Type a refused Portkey amount: red label shows. Demo mode: all controls disabled. Move window to the smallest display: Sources fits.
- [ ] **Step 3: Run the test command.** Expected: `** TEST SUCCEEDED **`.
- [ ] **Step 4: Commit** `README.md`, message `Describe the Settings tabs in the README`.

## Unresolved questions

1. Sample tiles: gray 62% / 38% when no usage, error or unlimited plan. OK, or hide the percent text?
2. Drop item 34 `HeightResizableWindow` (plan says yes, tabs are short). OK?
3. README screenshot: you take the new one, or skip until release?
