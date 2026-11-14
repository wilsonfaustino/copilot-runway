# Portkey pricing setup prompt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A "Copy setup prompt" button gives the user a prompt for their AI agent that adds Portkey model prices to the Pi, OpenCode and omp configs.

**Architecture:** Core `PortkeySetupPrompt` finds the models whose newest record has no cost and builds the prompt text from them. The App gets one small button view that copies the text. The popover Portkey card shows it only when a model is unpriced. Settings > Sources always shows it.

**Tech Stack:** Swift, SwiftUI (macOS 15), Swift Testing, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-11-14-portkey-pricing-prompt-design.md`

**Design:** canvas https://claude.ai/artifact/CLRxB8bMntJGmvnN1NphPe, row "Item 37" (artboards `SourcesPortkeyPrompt`, `PopoverPortkeyPrompt`).

## Global Constraints

- Branch `wilsonfaustino/portkey-pricing-prompt` from `main`.
- The prompt text has no company names, hosts, key paths or prices. Gateway is always `<your.portkey.gateway.com>`.
- Disclaimer copy, verbatim: "This prompt asks your AI agent to change its config files. Copilot Runway is not responsible for what the agent does. Check each change before you accept it."
- No network call, no file read or write. The button only writes to `NSPasteboard.general`.
- Hide the button in the share image (`forShare`).
- No README change. What's New entry comes with the 1.3.0 release, not here.
- No em dashes. 2-space indent. Comments only for non-obvious rules. No `Co-Authored-By` in commits. Stage files by name.
- Test command: `xcodebuild test -scheme CopilotRunway -destination 'platform=macOS'`.

## Review Focus

1. A model priced now but unpriced earlier in the cycle: the button must not show (newest record wins). Task 1 test `unpricedModelsUsesNewestRecordPerAgentAndModel`.
2. The same model id unpriced in two agents: it must show in both agent lines and both sections. Task 1 test `textListsTheSameModelUnderEachAgent`.
3. Model ids with `/`, `@` and `.` (Fireworks style): they must appear verbatim in backticks. Task 1 test `textListsOnlyAgentsWithUnpricedModels` uses a Fireworks-style id.
4. No Portkey records at all: Settings still copies the generic prompt with all three sections. Task 1 test `textWithoutUnpricedModelsHasEveryAgentSection`.
5. Share image: the button and disclaimer must not appear. Task 2 hand check.

---

### Task 1: Core prompt builder

**Files:**
- Create: `Core/PortkeySetupPrompt.swift`
- Test: `CoreTests/PortkeySetupPromptTests.swift`

**Interfaces:**
- Consumes: `PortkeyRecord` (`model`, `timestamp`, `source`, `costUSD: Double?`) from `Core/PortkeySpend.swift`. `SessionSource` from `Core/Turn.swift`.
- Produces:
  - `public enum PortkeySetupPrompt`
  - `public static func unpricedModels(in records: [PortkeyRecord]) -> [SessionSource: [String]]`: for each (source, model), take the record with the latest `timestamp`; keep the model when its `costUSD` is nil. Ids sorted ascending. Sources with no unpriced model are absent.
  - `public static func text(records: [PortkeyRecord]) -> String`
  - `public static let disclaimer: String` (the Global Constraints copy).

- [ ] **Step 1: Write the failing tests**

Helper: `record(_ model: String, _ source: SessionSource, _ cost: Double?, at seconds: TimeInterval) -> PortkeyRecord` with `Date(timeIntervalSince1970: seconds)`. Use `fireworks = "@fireworks-ai-global/accounts/fireworks/models/glm-5p3-flash"` as one id.

```swift
@Test func unpricedModelsUsesNewestRecordPerAgentAndModel() {
  let records = [
    record("a", .pi, nil, at: 1), record("a", .pi, 0.01, at: 2),
    record("b", .pi, nil, at: 1),
    record("a", .opencode, 0.01, at: 1), record("a", .opencode, nil, at: 2),
  ]
  #expect(PortkeySetupPrompt.unpricedModels(in: records) == [.pi: ["b"], .opencode: ["a"]])
}

@Test func unpricedModelsIsEmptyWhenEveryNewestRecordHasACost() {
  #expect(PortkeySetupPrompt.unpricedModels(in: []).isEmpty)
  #expect(PortkeySetupPrompt.unpricedModels(in: [record("a", .omp, 0.02, at: 1)]).isEmpty)
}

@Test func textWithoutUnpricedModelsHasEveryAgentSection() {
  let text = PortkeySetupPrompt.text(records: [record("a", .pi, 0.01, at: 1)])
  for heading in ["## Pi", "## OpenCode", "## omp"] { #expect(text.contains(heading)) }
  #expect(text.contains("<model id>"))
  #expect(text.contains("<your.portkey.gateway.com>"))
  #expect(text.contains("I do not know which models need a price."))
  #expect(text == PortkeySetupPrompt.text(records: []))
}

@Test func textListsOnlyAgentsWithUnpricedModels() {
  let text = PortkeySetupPrompt.text(records: [record(fireworks, .pi, nil, at: 1)])
  #expect(text.contains("- Pi: `\(fireworks)`"))
  #expect(text.contains("## Pi"))
  #expect(!text.contains("## OpenCode"))
  #expect(!text.contains("## omp"))
  #expect(!text.contains("I do not know which models need a price."))
}

@Test func textListsEachModelOnce() {
  let text = PortkeySetupPrompt.text(records: [record("m", .pi, nil, at: 1), record("m", .pi, nil, at: 2)])
  #expect(text.components(separatedBy: "`m`").count == 2)
}

@Test func textListsTheSameModelUnderEachAgent() {
  let text = PortkeySetupPrompt.text(records: [record("m", .pi, nil, at: 1), record("m", .opencode, nil, at: 1)])
  #expect(text.contains("- Pi: `m`"))
  #expect(text.contains("- OpenCode: `m`"))
}

@Test func textOrdersSectionsPiOpenCodeOmp() {
  let text = PortkeySetupPrompt.text(records: [])
  let pi = text.range(of: "## Pi")!.lowerBound
  let openCode = text.range(of: "## OpenCode")!.lowerBound
  let omp = text.range(of: "## omp")!.lowerBound
  #expect(pi < openCode && openCode < omp)
}

@Test func textAlwaysHasSafetyAndPriceRules() {
  for text in [PortkeySetupPrompt.text(records: []), PortkeySetupPrompt.text(records: [record("m", .omp, nil, at: 1)])] {
    #expect(text.contains("Before you save any change, show me the diff and wait for my approval."))
    #expect(text.contains("Never print, log, copy or echo an API key."))
    #expect(text.contains("Do not search the web or fill in a price yourself, unless I explicitly ask you to."))
    #expect(text.contains("wait for my confirmation"))
  }
}

@Test func genericTextHasNoCompanyDetails() {
  let text = PortkeySetupPrompt.text(records: [])
  for banned in ["fireworks", "~/.secrets", "x-portkey-api-key", "https://"] { #expect(!text.lowercased().contains(banned)) }
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run: `xcodebuild test -scheme CopilotRunway -destination 'platform=macOS' -only-testing:CoreTests/PortkeySetupPromptTests`
Expected: build fails, `PortkeySetupPrompt` not found.

- [ ] **Step 3: Implement `Core/PortkeySetupPrompt.swift`**

`text(records:)` joins these parts with a blank line: intro, rules, prices, model list, then the agent sections, then check. Agent order `[.pi, .opencode, .omp]`; names "Pi", "OpenCode", "omp". With an empty `unpricedModels`, every agent section shows; else only the agents in it. The model list is one line per agent `- <Name>: ` + ids as `` `id` `` joined by `, `. When empty, the model list is the generic sentence below. Copy verbatim:

````text
Configure my AI agents so that each Portkey message in my sessions stores a correct USD cost. Copilot Runway reads that cost from the session files to show Portkey spend. Portkey has no price API, so each agent needs the price of each model in its own config. Without a price, the agent stores a cost of 0 and Copilot Runway shows the request as unpriced.

## Rules

- Before you save any change, show me the diff and wait for my approval.
- Never print, log, copy or echo an API key. Do not `cat` a key file. When you show a config file, replace each key value with `REDACTED`.
- Back up each file before you change it: `cp <file> <file>.bak-portkey-pricing-$(date +%Y%m%d-%H%M%S)`.
- Merge the changes into my existing files. Do not remove other providers, models or settings.
- Do not change the base URL, headers or key of a provider that already works. Change only the `cost` blocks.
- If a model already has a cost above 0, tell me and do not change it.
- If something below does not match what you find, stop and ask me. Do not guess.

## Prices

- Ask me for the price of each model in USD per 1 million tokens: input, output, cache read and cache write.
- You can tell me where to look, for example the Portkey model catalog or the pricing page of the model provider.
- Do not search the web or fill in a price yourself, unless I explicitly ask you to. If I ask, show the source URL next to each price.
- Before you write, show me a table of each model and its four prices, and wait for my confirmation.

## Models without a price

<one line per agent, or:>
I do not know which models need a price. Find the models under the Portkey provider in each config below and ask me about each one.

## Pi

- Config: `~/.pi/agent/models.json`. Pi reads it when it starts.
- Find the provider in `providers` whose `baseUrl` points to my Portkey gateway, for example `<your.portkey.gateway.com>`. Copilot Runway counts a message as Portkey only when the provider id contains `portkey` (any letter case). If it does not, ask me before you rename it. A rename also changes the `<provider>/<model id>` strings in `~/.pi/agent/settings.json`, and you must update those too.
- Add a `cost` block to each model in the `models` list of that provider:

  ```json
  { "id": "<model id>", "cost": { "input": <input>, "output": <output>, "cacheRead": <cache read>, "cacheWrite": <cache write> } }
  ```

## OpenCode

- Config: `~/.config/opencode/opencode.json`. OpenCode reads it when it starts.
- Find the provider in `providers` whose `settings.baseURL` points to my Portkey gateway, for example `<your.portkey.gateway.com>`. Its id must contain `portkey`, for example `portkey-openai-compatible`. If it does not, ask me before you rename it.
- Add a `cost` object to each model under `providers.<provider id>.models`:

  ```json
  "<model id>": { "cost": { "input": <input>, "output": <output>, "cache": { "read": <cache read>, "write": <cache write> } } }
  ```

## omp

- Config: `~/.omp/agent/models.yml` (YAML). omp is a Pi fork and uses the same `cost` keys as Pi.
- Copilot Runway has not tested this file end to end. If the file is missing, or the Portkey provider does not look like this example, stop and ask me.
- Find the provider whose `baseUrl` points to my Portkey gateway. Its id must contain `portkey` (any letter case). If it does not, ask me before you rename it.

  ```yaml
  providers:
    portkey:
      baseUrl: <your.portkey.gateway.com>
      models:
        - id: <model id>
          cost: { input: <input>, output: <output>, cacheRead: <cache read>, cacheWrite: <cache write> }
  ```

## Check

1. Check that each changed JSON file is valid: `python3 -m json.tool <file> > /dev/null`.
2. Tell me to quit and start each changed agent again, then send one short message with a Portkey model.
3. In Copilot Runway, the new request shows a USD amount. Older requests stay unpriced, because agents do not recalculate old messages.
````

- [ ] **Step 4: Run the tests and see them pass**

Run: the Step 2 command. Expected: all `PortkeySetupPromptTests` pass. Then the full test command: all pass.

- [ ] **Step 5: Commit**

```bash
git add Core/PortkeySetupPrompt.swift CoreTests/PortkeySetupPromptTests.swift
git commit -m "Build the Portkey pricing setup prompt from unpriced models"
```

(Run `xcodegen generate` first if new files are not picked up; `project.yml` globs the folders, so the `.pbxproj` change is generated, never hand edited.)

### Task 2: Copy buttons in the popover and Settings

**Files:**
- Modify: `App/PortkeyViews.swift` (new `PortkeySetupPromptButton`, `PortkeyCard` gets `showsSetupPrompt`)
- Modify: `App/PopoverView.swift:345-356` (`portkeyCard(now:)`)
- Modify: `App/SettingsTabs.swift:422` (new row after "Portkey budget")

**Interfaces:**
- Consumes: `PortkeySetupPrompt.text(records:)`, `.unpricedModels(in:)`, `.disclaimer` from Task 1. `UsageStore.portkeySpend.records`.
- Produces: `struct PortkeySetupPromptButton: View { let records: [PortkeyRecord] }`, a `Button` with `Label("Copy setup prompt", systemImage: "doc.on.doc")`, `.controlSize(.small)`, that runs `NSPasteboard.general.clearContents()` then `setString(PortkeySetupPrompt.text(records: records), forType: .string)` (the same pattern as "Copy brew command"). It shows no disclaimer; each caller adds it in its own caption style.

- [ ] **Step 1: Add `PortkeySetupPromptButton` and `var showsSetupPrompt = true` to `PortkeyCard`**

In `PortkeyCard.body`, right after the `unpricedNote` text: when `showsSetupPrompt && !PortkeySetupPrompt.unpricedModels(in: spend.records).isEmpty`, show `PortkeySetupPromptButton(records: spend.records)` and `Text(PortkeySetupPrompt.disclaimer).captionStyle().fixedSize(horizontal: false, vertical: true)`.

- [ ] **Step 2: Pass `showsSetupPrompt: !forShare` in `PopoverView.portkeyCard(now:)`**

- [ ] **Step 3: Add the "Portkey prices" row in `SettingsSourcesTab`**

After the Portkey budget row and its `SettingsDivider()`:

```swift
SettingsRow(label: "Portkey prices") {
  PortkeySetupPromptButton(records: usageStore.portkeySpend.records)
  SettingsCaption("Paste it into Pi, OpenCode or omp. The agent asks you for each model price and adds it to its config, so new Portkey requests get a cost.")
  SettingsCaption(PortkeySetupPrompt.disclaimer)
}
SettingsDivider()
```

- [ ] **Step 4: Build and run all tests**

Run: the full test command. Expected: all pass, no new warnings.

- [ ] **Step 5: Hand check (user)**

Build a Debug app and check:
1. Settings > Sources shows the row, the button and both captions. Click the button, paste into a text editor: the generic prompt with all three sections (your models are priced).
2. Popover: no button (every newest Portkey record has a cost).
3. To see the popover button: temporarily remove the `cost` block of one model in a backup copy of your Pi config, send one message, refresh. The button and disclaimer show under the unpriced note, and the copied prompt lists that model under Pi only. Restore the config.
4. Share image: no button, no disclaimer.
5. Light mode and VoiceOver read "Copy setup prompt".

- [ ] **Step 6: Commit**

```bash
git add App/PortkeyViews.swift App/PopoverView.swift App/SettingsTabs.swift
git commit -m "Add the Copy setup prompt button to the Portkey card and Settings"
```
