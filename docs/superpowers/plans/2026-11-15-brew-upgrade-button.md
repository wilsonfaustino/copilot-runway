# Brew upgrade button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An "Update" button that runs `brew update --force` and `brew upgrade --cask wilsonfaustino/tap/copilot-runway`, then relaunches the app, in the popover update notice and in Settings > About.

**Architecture:** Core `BrewUpgrade` holds the pure parts (brew lookup, arguments, environment, output parsing, installed version check, relaunch script) and runs brew through the existing `GhRunner`, which gets an `extraEnvironment` parameter, a null stdin and an opt-in SIGINT at the time limit. App `AppUpdater` (@Observable, owned by `UsageStore`) holds the button state. One shared view, `UpdateControls`, replaces both "Copy brew command" buttons. After the upgrade exits 0 and the bundle on disk has a newer version, a detached `/bin/sh` waits for the app's PID to exit and runs `open` on the bundle path, and the app terminates.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, XcodeGen, Homebrew 7.

**Spec:** Roadmap item 38 in `.serena/memories/roadmap-candidates.md` (option b), plus these decisions from the 2026-11-15 session:
- Update button in both places; "Copy brew command" only as the fallback (no brew, not a cask install, or after a failure).
- While brew runs: a small spinner with "Checking Homebrew..." (update step), then "Updating..." (upgrade step). On failure: one line plus "Copy brew command". No brew output shown.
- Trust state dropped (user, 2026-11-15): `brew upgrade` with the full cask name records trust by itself, so a trust failure shows the generic failure line.
- Copy buttons stay enabled after every failure.
- One click, not automatic. What's New needs no change (it already shows after a version change).

**Spike evidence (2026-11-15, side chat, no repo changes):** a throwaway Developer ID signed, notarized app (`UpgradeProbe.app`, code in the session scratchpad `upgrade-probe/Probe.swift`) installed from a local tap upgraded itself 1.0 -> 1.1 from a button, on brew 7.0.13 and macOS 26, with the command and environment this plan uses. Confirmed: no `[y/n]` hang (exit 0); brew did not quit the running app; no App Management dialog; relaunch in the same second the old process quit; the new bundle has `com.apple.quarantine` (brew 7 has no `--no-quarantine`) but the notarized app opened with no dialog; brew not found showed the fallback (the probe left its button disabled; this plan must not). About 10 s (update 8 s, upgrade 2 s). Not covered: a git fetch of a tap with a remote. Probe cleaned up; source still in the scratchpad.

**Codex adversarial review (gpt-6.1-sol high, 2026-11-15):** 13 findings, checked against local Homebrew source (`trust.rb:634`, `trust.rb:653`, `cask/upgrade.rb` no-op warning, `cmd/update.sh` SIGINT trap). Second pass (same model): 3 findings, all folded in. It verified the first-pass fixes (SIGINT reaches `update.sh` through brew's `exec`; plist read and version compare; `.preparing`; trust fixtures; full name accepted by `brew trust --cask`). Its key fact, checked in `cmd/upgrade.rb:215` and `trust.rb` `explicitly_allowed?`: `brew upgrade` with a fully qualified cask name records trust by itself, so the upgrade step does not fail on trust. The trust message stays as a cheap defensive path (unit tested with fixtures), not a rehearsed case. First pass: all folded in below, except finding 6 (running copy is not the cask's copy): the installed version check from finding 2 already stops a relaunch of a stale copy, so no separate artifact check.

## Global Constraints

- Branch `wilsonfaustino/brew-upgrade-button` from `main`. Commit only on the user's "commit"; push only on `/ship`.
- No em dashes anywhere. 2-space indent, LF, final newline.
- No new network host. Brew talks to GitHub; the app itself makes no new call.
- Brew paths, in order: `/opt/homebrew/bin/brew`, `/usr/local/bin/brew`.
- Cask full name: `wilsonfaustino/tap/copilot-runway`. Every brew command uses the full name. Fallback copy text stays `ReleaseCheck.upgradeCommand` (unchanged).
- Commands, in order: `brew update --force`, then `brew upgrade --cask <cask full name>`. Skip the upgrade when the update step does not succeed.
- Environment added to the inherited one: `HOMEBREW_NO_ASK=1`, `HOMEBREW_NO_UPGRADE_QUIT_CASKS=1`, `HOMEBREW_NO_AUTO_UPDATE=1` (the explicit update step replaces auto update), `PATH=<brew dir>:/usr/bin:/bin:/usr/sbin:/sbin`. Use variables, not flags: an older brew rejects an unknown flag but ignores an unknown variable.
- Brew stdin is `/dev/null`. Read stdout and stderr. Time limit 300 s for each step; at the limit brew gets SIGINT (its `update.sh` cleans up on SIGINT, not SIGTERM). `brew list` time limit: `GhRunner.defaultTimeout`.
- Do not rename `GhRunner` or its file (a rename makes Sonar count every line as new code; 80% new coverage gate).
- Test command (whole suite): `xcodebuild test -scheme CopilotRunway -destination 'platform=macOS' -derivedDataPath build/brew` -> `** TEST SUCCEEDED **`.

## Review Focus

1. Brew exits 0 but did not upgrade ("Not upgrading ..., the latest version is already installed"), for example when GitHub Latest moves before the tap job finishes, or the running copy is not the cask's copy. Expect: no relaunch, "No new version in Homebrew yet" state. Pinned by Task 2 tests `installedVersionIsNewer...` and the Task 3 check before relaunch.
2. Brew fails for a reason that is not ours (another tap's fetch fails during `brew update --force`, a future trust rule). Expect: generic failure line with Copy brew command and retry. Accepted per the plan's policy; covered by `upgradeIsFailedOnNonZeroExit`.
3. Brew prompts for anything (sudo password, a future new prompt). Expect: fails at once on EOF or at the time limit, shows the failure line, never hangs. Pinned by Task 1 test `runnerGivesTheProcessAnEmptyStdin`.
4. Double click, or both controls on screen. Expect: one preparation and one brew run. Pinned by the Task 3 `.preparing` state and the guard in `update()`.
5. A failure that leaves the copy button disabled (the spike probe did this). Expect: copy buttons enabled in every state. Pinned by the Task 3 view rule and checked in Task 4 by click and paste.

---

### Task 1: GhRunner environment, empty stdin, SIGINT at the time limit

**Files:**
- Modify: `Core/GhRunner.swift` (`run` signature, process setup, timeout task)
- Test: `CoreTests/GhRunnerTests.swift`

**Interfaces:**
- Produces: `GhRunner.run(path: String, arguments: [String], readsStandardError: Bool, timeout: Duration = defaultTimeout, extraEnvironment: [String: String] = [:], interruptsAtTimeLimit: Bool = false) async throws(Failure) -> Output`.
  - `extraEnvironment` merges over `ProcessInfo.processInfo.environment`; empty means today's behavior.
  - stdin is always `FileHandle.nullDevice` (GUI apps already get `/dev/null` from launchd, so gh behavior does not change).
  - `interruptsAtTimeLimit: true` sends `process.interrupt()` (SIGINT) instead of `process.terminate()` at the time limit. Default keeps gh behavior.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func runnerAddsExtraEnvironmentToTheInheritedOne() async throws {
  let inheritedHome = try #require(ProcessInfo.processInfo.environment["HOME"])
  let output = try await GhRunner.run(
    path: "/bin/sh", arguments: ["-c", "echo \"$RUNWAY_TEST_VALUE:$HOME\""],
    readsStandardError: false, extraEnvironment: ["RUNWAY_TEST_VALUE": "set"]
  )
  #expect(String(decoding: output.standardOutput, as: UTF8.self) == "set:\(inheritedHome)\n")
}

@Test func runnerExtraEnvironmentOverridesAnInheritedKey() async throws {
  let output = try await GhRunner.run(
    path: "/bin/sh", arguments: ["-c", "echo \"$HOME\""],
    readsStandardError: false, extraEnvironment: ["HOME": "/runway-test-home"]
  )
  #expect(String(decoding: output.standardOutput, as: UTF8.self) == "/runway-test-home\n")
}

@Test func runnerGivesTheProcessAnEmptyStdin() async throws {
  // read fails on EOF at once; with an open stdin it would wait until the time limit.
  let output = try await GhRunner.run(
    path: "/bin/sh", arguments: ["-c", "read answer; echo \"exit $?\""],
    readsStandardError: false, timeout: .seconds(5)
  )
  #expect(String(decoding: output.standardOutput, as: UTF8.self) == "exit 1\n")
}

@Test func runnerSendsInterruptAtTheTimeLimitWhenAsked() async throws {
  // The script traps INT, writes a marker file and exits, like brew update's own cleanup.
  // Expect: throws .timedOut, and the marker file exists within 2 s after the throw.
}
```

- [ ] **Step 2: Run tests, expect FAIL** (new parameters do not exist; compile error).
- [ ] **Step 3: Implement** in `Core/GhRunner.swift`. Set `process.environment` only when `extraEnvironment` is not empty. One comment on `interruptsAtTimeLimit` naming why (brew cleans up its fetch children on SIGINT only).
- [ ] **Step 4: Run the whole suite, expect `** TEST SUCCEEDED **`.**
- [ ] **Step 5: On the user's "commit":** `git add Core/GhRunner.swift CoreTests/GhRunnerTests.swift`, message "Let GhRunner add environment, close stdin and interrupt at the time limit".

### Task 2: Core BrewUpgrade

**Files:**
- Create: `Core/BrewUpgrade.swift`
- Modify: `Core/ReleaseCheck.swift` (only if needed: reuse `compareVersions` from `BrewUpgrade`; it is internal and in the same module, so no change expected)
- Test: `CoreTests/BrewUpgradeTests.swift`

**Interfaces:**
- Consumes: Task 1 `GhRunner.run(..., extraEnvironment:, interruptsAtTimeLimit:)`.
- Produces:
  - `public enum BrewUpgrade`
  - `public enum Outcome: Equatable, Sendable { case succeeded, failed }`
  - `static let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]`
  - `public static let caskFullName = "wilsonfaustino/tap/copilot-runway"`
  - `public static let stepTimeout: Duration = .seconds(300)` (public: public defaults use it)
  - `static func environment(brewPath: String) -> [String: String]` (the four Global Constraints values; PATH starts with the directory of `brewPath`)
  - `public static func findBrew(isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)) -> String?`
  - `public static func isInstalledByCask(brewPath: String, caskFullName: String) async -> Bool` (runs `list --cask <full name>`; true only on exit 0; any `GhRunner.Failure` is false)
  - `public static func updateHomebrew(brewPath: String, timeout: Duration = stepTimeout) async -> Outcome` (runs `update --force`, `interruptsAtTimeLimit: true`)
  - `public static func upgrade(brewPath: String, caskFullName: String, timeout: Duration = stepTimeout) async -> Outcome` (runs `upgrade --cask <full name>`, `interruptsAtTimeLimit: true`)
  - Outcome: `.succeeded` only on exit 0. Non-zero exit, launch failure and timeout are `.failed`.
  - `public static func installedVersionIsNewer(bundleURL: URL, currentVersion: String) -> Bool`: reads `Contents/Info.plist` from disk with `NSDictionary(contentsOf:)` (not `Bundle`, which caches), takes `CFBundleShortVersionString`, true only when `ReleaseCheck.compareVersions(currentVersion, installed) == .orderedAscending`. Missing file or key is false.
  - `public static func relaunchArguments(processIdentifier: Int32, bundlePath: String) -> [String]` returns `["-c", relaunchScript, "sh", String(processIdentifier), bundlePath]` where `relaunchScript` is exactly:

```sh
while kill -0 "$1" 2>/dev/null; do sleep 0.2; done; exec /usr/bin/open "$2"
```

- [ ] **Step 1: Write the failing tests**

Use a fake brew: a temp `#!/bin/sh` script in its own temp directory (same helper style as `makeHangingGh` in `GhRunnerTests.swift`) that writes `"$@"`, `$HOMEBREW_NO_ASK`, `$HOMEBREW_NO_UPGRADE_QUIT_CASKS`, `$HOMEBREW_NO_AUTO_UPDATE`, `$PATH` to a temp log file, prints given text to stdout or stderr, and exits with a given code.

```swift
@Test func findBrewPrefersAppleSiliconPath() {
  #expect(BrewUpgrade.findBrew { _ in true } == "/opt/homebrew/bin/brew")
  #expect(BrewUpgrade.findBrew { $0 == "/usr/local/bin/brew" } == "/usr/local/bin/brew")
  #expect(BrewUpgrade.findBrew { _ in false } == nil)
}

@Test func upgradeSendsCaskArgumentsAndNoPromptEnvironment() async throws {
  // fake brew exits 0
  #expect(await BrewUpgrade.upgrade(brewPath: fakeBrew.path, caskFullName: "wilsonfaustino/tap/copilot-runway") == .succeeded)
  #expect(try String(contentsOf: logURL, encoding: .utf8)
    == "upgrade --cask wilsonfaustino/tap/copilot-runway|1|1|1|\(fakeBrewDirectory):/usr/bin:/bin:/usr/sbin:/sbin\n")
}

@Test func updateHomebrewRunsUpdateForce() async  // log starts with "update --force|", result .succeeded
@Test func upgradeIsFailedOnNonZeroExit() async  // fake exits 1, prints "Error: Download failed" -> .failed
@Test func upgradeIsFailedAtTheTimeLimit() async  // fake traps INT and exits 130, else sleeps; timeout .seconds(1) -> .failed
@Test func upgradeIsFailedWhenBrewCannotLaunch() async  // path "/nonexistent/brew" -> .failed
@Test func installedByCaskIsTrueWhenBrewListSucceeds() async  // fake exits 0, log "list --cask wilsonfaustino/tap/copilot-runway|..."
@Test func installedByCaskIsFalseWhenBrewListFails() async  // fake exits 1 -> false

@Test func installedVersionIsNewerReadsThePlistOnDisk() throws {
  // temp Foo.app/Contents/Info.plist with CFBundleShortVersionString
  // "1.3.0" vs current "1.2.1" -> true; "1.2.1" vs "1.2.1" -> false; "1.0.0" vs "1.2.1" -> false
}
@Test func installedVersionIsNewerIsFalseWithoutAPlist()  // URL with no Contents/Info.plist -> false

@Test func relaunchArgumentsPassPathAsArgument() {
  let arguments = BrewUpgrade.relaunchArguments(processIdentifier: 42, bundlePath: "/Applications/CopilotRunway Rehearsal.app")
  #expect(arguments.count == 5)
  #expect(arguments[0] == "-c")
  #expect(!arguments[1].contains("Rehearsal"))
  #expect(Array(arguments[2...]) == ["sh", "42", "/Applications/CopilotRunway Rehearsal.app"])
}

@Test func relaunchScriptWaitsForTheProcessToExit() async throws {
  let clock = ContinuousClock()
  let start = clock.now  // before run(), so scheduling delay cannot shorten the measured wait
  let sleeper = Process()
  sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
  sleeper.arguments = ["1"]
  try sleeper.run()
  // open fails on a path that does not exist, so the script ends right after the wait loop.
  let output = try await GhRunner.run(
    path: "/bin/sh",
    arguments: BrewUpgrade.relaunchArguments(processIdentifier: sleeper.processIdentifier, bundlePath: "/nonexistent/Runway.app"),
    readsStandardError: false, timeout: .seconds(5)
  )
  #expect(clock.now - start >= .seconds(1))
  #expect(output.exitStatus != 0)
}
```

- [ ] **Step 2: Run tests, expect FAIL** (`BrewUpgrade` does not exist).
- [ ] **Step 3: Implement `Core/BrewUpgrade.swift`** with the Interfaces above. One comment on `environment(brewPath:)` that names why each variable exists (brew 7 asks `[y/n]` and quits running cask apps by default; the explicit `update --force` replaces auto update; apps opened from Finder have no shell PATH).
- [ ] **Step 4: Run the whole suite, expect `** TEST SUCCEEDED **`.**
- [ ] **Step 5: On the user's "commit":** `git add Core/BrewUpgrade.swift CoreTests/BrewUpgradeTests.swift`, message "Add BrewUpgrade to run brew upgrade for the cask".

### Task 3: AppUpdater and the Update button

**Files:**
- Create: `App/AppUpdater.swift`, `App/UpdateControls.swift`
- Modify: `App/UsageStore.swift` (one property), `App/PopoverView.swift` (`updateNotice`), `App/SettingsTabs.swift` (`SettingsAboutTab` version row), `App/DemoLaunch.swift` (Debug arg), `README.md` (update line)

**Interfaces:**
- Consumes: Task 2 `BrewUpgrade.findBrew`, `isInstalledByCask`, `updateHomebrew`, `upgrade`, `installedVersionIsNewer`, `relaunchArguments`, `caskFullName`, `Outcome`.
- Produces:
  - `@MainActor @Observable final class AppUpdater` with `enum State { case unknown, preparing, unavailable, ready, checking, updating, failed, noNewVersion }`, `private(set) var state: State = .unknown`.
  - `var caskFullName: String`: `DemoLaunch.upgradeCaskFullName ?? BrewUpgrade.caskFullName` in Debug, `BrewUpgrade.caskFullName` in Release.
  - `func prepareIfNeeded() async`: only from `.unknown`; sets `.preparing` before the first await (so a second control cannot start a second preparation or overwrite a later state); finds brew, checks the cask, sets `.ready` or `.unavailable`.
  - `func update() async`: only from `.ready`, `.failed` or `.noNewVersion`. Sets `.checking`, runs `updateHomebrew`; on `.failed` sets `.failed` and stops. Then `.updating`, runs `upgrade`; same mapping. On `.succeeded`, if `installedVersionIsNewer(bundleURL: Bundle.main.bundleURL, currentVersion: <CFBundleShortVersionString>)` is false, sets `.noNewVersion` and stops. Else starts `/bin/sh` with `relaunchArguments(processIdentifier: ProcessInfo.processInfo.processIdentifier, bundlePath: Bundle.main.bundlePath)` and calls `NSApplication.shared.terminate(nil)`; if that launch throws, sets `.failed`.
  - `UsageStore`: `let appUpdater = AppUpdater()`.
  - `DemoLaunch.upgradeCaskFullName: String?` (Debug only): the value after `-upgradeCask`, a full name like `wilsonfaustino/runway-rehearsal/copilot-runway-rehearsal`.
  - `struct UpdateControls: View` (`let appUpdater: AppUpdater`), `.task { await appUpdater.prepareIfNeeded() }`. Copy, exact:
    - `.unknown`, `.preparing`, `.unavailable`: "Copy brew command" button (today's behavior, `.help(ReleaseCheck.upgradeCommand)`).
    - `.ready`: "Update" button.
    - `.checking`: `ProgressView().controlSize(.small)` + "Checking Homebrew...", no button.
    - `.updating`: `ProgressView().controlSize(.small)` + "Updating...", no button.
    - `.failed`: "Update failed. Run the brew command in Terminal." + "Copy brew command" + "Update" (retry).
    - `.noNewVersion`: "Homebrew has no new version yet. Try again later." + "Copy brew command" + "Update" (retry).
    - All buttons `.controlSize(.small)`.
    - "Copy brew command" is never disabled in any state. No `.disabled` modifier on them, and none on a container that holds them.

- [ ] **Step 1: Add `App/AppUpdater.swift`, `App/UpdateControls.swift`, the `UsageStore` property and the `DemoLaunch` arg.** No unit tests: the logic it calls is tested in Task 2, and the App target has no test target.
- [ ] **Step 2: Replace the two "Copy brew command" buttons** in `PopoverView.updateNotice` and `SettingsAboutTab` with `UpdateControls(appUpdater: usageStore.appUpdater)`. Keep the "Version X is available." text as it is.
- [ ] **Step 3: README.** In the section that describes updates, say the Update button runs `brew update --force` and `brew upgrade --cask wilsonfaustino/tap/copilot-runway`, then relaunches; Copy brew command is the fallback.
- [ ] **Step 4: Build and run the whole suite, expect `** TEST SUCCEEDED **`.**
- [ ] **Step 5: On the user's "commit":** selective `git add` of the files above, message "Add an Update button that runs brew upgrade and relaunches".

### Task 4: Local rehearsal with a real brew upgrade (user present)

No code. The spike already proved the no-prompt run, no quit, no App Management block, quarantine, relaunch and brew not found on a notarized app. This rehearsal checks the real app code and a tap with a git remote. Ask the user before each step that installs, quits, trusts or untaps anything. Never run a copied production command (`wilsonfaustino/tap/...`) during the rehearsal; copied text is inspect only.

Rehearsal names: tap `wilsonfaustino/runway-rehearsal`, cask full name `wilsonfaustino/runway-rehearsal/copilot-runway-rehearsal`, app target `CopilotRunway Rehearsal.app`, bundle id `dev.wilsonfaustino.CopilotRunway.rehearsal` (separate preferences, so the user's real defaults and What's New baseline stay untouched). Launch command for every case:

```sh
open "/Applications/CopilotRunway Rehearsal.app" --args -upgradeCask wilsonfaustino/runway-rehearsal/copilot-runway-rehearsal
```

Rehearsal rules:
- The automatic relaunch runs `open` without `-upgradeCask`, so the relaunched process falls back to the production cask name. Never click Update in a relaunched instance. Check its version, then quit it (`osascript -e 'quit app id "dev.wilsonfaustino.CopilotRunway.rehearsal"'`) and reopen with the launch command.
- Quit the rehearsal app before every uninstall, reinstall or reset. The cask has no `uninstall quit:`, so replacing files does not replace a running process.
- The Debug builds are ad-hoc signed and not notarized, and brew quarantines the download. Gatekeeper blocks the first launch of each version and the automatic relaunch. The user approves with Privacy & Security > Open Anyway. A Gatekeeper block right after the old process quits counts as proof that the helper ran `open`; the spike already proved an unattended relaunch with a notarized build.

- [ ] **Step 1: Prepare.** Build the branch in Debug with `PRODUCT_BUNDLE_IDENTIFIER=dev.wilsonfaustino.CopilotRunway.rehearsal` three times: `MARKETING_VERSION=1.0.0` (old), `1.1.0` and `1.2.1` (the real GitHub Latest is 1.2.1, so any installed version below it shows the notice). Zip each `CopilotRunway.app` with `ditto -c -k --keepParent` into the session scratchpad. The user's real app may keep running (different bundle id).
- [ ] **Step 2: Local tap with a git remote.** `brew tap-new wilsonfaustino/runway-rehearsal` (with git). Make a bare repo in the scratchpad, add it as the tap's `origin` and push. Cask `copilot-runway-rehearsal` at 1.0.0 with `url "file://<scratchpad>/1.0.0.zip"`, its sha256, `app "CopilotRunway.app", target: "CopilotRunway Rehearsal.app"`. Trust only the cask: `brew trust --cask wilsonfaustino/runway-rehearsal/copilot-runway-rehearsal`; check `~/.homebrew/trust.json` has no tap-wide entry for the rehearsal tap. `brew install --cask wilsonfaustino/runway-rehearsal/copilot-runway-rehearsal`.
- [ ] **Step 3: Happy path.** In a separate clone of the bare repo, bump the cask to 1.2.1 (url, sha256), commit, push; the tap clone stays at 1.0.0, so only `brew update --force` can find it. Launch. Expect: "Version 1.2.1 is available." with Update. Click Update in the popover and at once in Settings. Expect: one `brew update` then one `brew upgrade` in `ps`; "Checking Homebrew..." then "Updating..."; app quits; Gatekeeper block or relaunch follows (approve with Open Anyway); Settings > About shows 1.2.1; What's New banner shows; `brew list --cask --versions` says 1.2.1.
- [ ] **Step 4: No new version.** Restore: quit the app, `brew uninstall --cask` the rehearsal cask, set the remote cask back to 1.0.0, `brew update --force`, reinstall. Launch, click Update without a remote bump. Expect: "Homebrew has no new version yet. Try again later.", no relaunch, Copy brew command enabled (click, paste, check text).
- [ ] **Step 5: Untrusted cask upgrades anyway.** Quit the app. With 1.0.0 installed, bump the remote to 1.1.0. `brew untrust --cask wilsonfaustino/runway-rehearsal/copilot-runway-rehearsal`. Launch, click Update. Expect: upgrade to 1.1.0 works (brew records trust for the full name), no trust message. This confirms the app needs no trust handling.
- [ ] **Step 6: Failure.** Restore 1.0.0 as in Step 4. Bump the remote to 1.2.1 with a wrong sha256. Launch, click Update. Expect: "Update failed. Run the brew command in Terminal." + Copy brew command enabled (click, paste). Time limit uses the same state; not rehearsed (300 s), covered by the Task 1 and Task 2 timeout tests.
- [ ] **Step 7: Not a cask install.** Unzip 1.0.0 into the scratchpad, launch that copy with `--args -upgradeCask wilsonfaustino/runway-rehearsal/copilot-runway-missing`. Expect: Copy brew command only, enabled (click, paste).
- [ ] **Step 8: Clean up (ask first).** Quit the app, `brew uninstall --cask` the rehearsal cask, `brew untrust --cask` it, `brew untap wilsonfaustino/runway-rehearsal`, `defaults delete dev.wilsonfaustino.CopilotRunway.rehearsal`, delete scratchpad zips, unzipped copy and the bare repo. Check `~/.homebrew/trust.json` has no rehearsal entry left.
- [ ] **Step 9: Ship** on the user's "commit" and `/ship`. After merge, 1.3.0 What's New gets an Update button line; real proof against the GitHub tap is the 1.3.0 to 1.3.1 upgrade.

## Unresolved questions

- Popover width: the failure and no new version lines plus buttons may wrap. Shorten them ("Update failed.", "No new version yet.") if they do. Decided (user): yes, shorten if they wrap.
- `brew list --cask wilsonfaustino/tap/copilot-runway` exits 0 on the user's machine (checked 2026-11-15).
