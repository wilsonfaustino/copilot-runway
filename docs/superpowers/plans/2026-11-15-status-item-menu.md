# Status item menu (roadmap item 43)

Right-click or control-click on the menu bar item opens a menu. Left-click still toggles the popover.
App only, no Core change. Live check instead of unit tests.
Canvas (option B chosen): https://claude.ai/artifact/XDHJNCFvtDgV5soLU7RaQi

## Menu

```
Refresh               ⌘R
Copy Summary         ⇧⌘C
─────────────────────────
Open Dashboard        ⌘D
Settings…             ⌘,
Check for Updates…    ⌘U
─────────────────────────
Quit Copilot Runway   ⌘Q
```

Shortcuts work only while the menu is open.

## Steps

1. `App/CopilotRunwayApp.swift`, `App/AppDelegate.swift`: take `openDashboard` out of `#if DEBUG`, so release builds can open the Dashboard from AppKit. Keep the `DemoLaunch.opensDashboard` block in `#if DEBUG`.
   -> verify: Release build compiles; the `DemoLaunch.opensDashboard` launch argument still opens the Dashboard in Debug.
2. `App/UsageStore.swift`: add `checkForUpdatesNow() async -> UpdateCheckResult` (`.newer(String)`, `.upToDate(String)`, `.failed`). It skips the once-a-day gate, sets `lastReleaseCheck` and `availableVersion`, and shares the fetch with `refreshReleaseIfDue`.
   -> verify: build; scheduled check unchanged.
3. `App/AppDelegate.swift`:
   - `button.sendAction(on: [.leftMouseUp, .rightMouseUp])`.
   - In `togglePopover`: right mouse up, or left mouse up with Control held, closes the popover and shows the menu. Show it with `statusItem.menu = menu; button.performClick(nil); statusItem.menu = nil`, so the system places it.
   - Build the menu on each open. Copy Summary is disabled when `usageStore.summaryText()` is nil.
   - Actions: Refresh `Task { await usageStore.refresh() }`; Copy Summary writes to `NSPasteboard.general`; Open Dashboard `openDashboard?()` then `NSApp.activate()`; Settings `SettingsWindowController.show(usageStore:)`; Check for Updates runs step 2; Quit `NSApp.terminate(nil)`.
   - Check for Updates result: `.upToDate` shows an `NSAlert` ("Copilot Runway is up to date." / "Version X is the newest version."); `.newer` opens the popover, which shows the existing update notice with the Update button; `.failed` shows an `NSAlert` ("Could not check for updates." / "Check your connection and try again.").
   - `button.setAccessibilityHelp("Click for usage. Right-click for more actions.")`.
   -> verify: build; all tests pass (`xcodebuild test`).
4. `README.md`: one line about the right-click menu.
5. Live check (user): right-click, control-click, left-click still toggles, each item, each shortcut with the menu open, Copy Summary disabled with no usage (`-demo` error scenario), up-to-date alert, failure alert offline, VoiceOver reads the help text, light and dark.

## Assumptions

- `.newer` opens the popover instead of an alert, because the popover already has the Update button.
- The help text goes to VoiceOver only, not a hover tooltip (menu bar items rarely show tooltips).

## Unresolved questions

- None blocking.
