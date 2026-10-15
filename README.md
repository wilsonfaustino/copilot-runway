# Copilot Runway

Copilot Runway is a macOS menu bar app that shows your GitHub Copilot AI credit usage as
runway: how many credits are left, how fast you use them, and which models and kinds of
work use them. It is for developers on Copilot usage-based billing who code through
OpenCode or Pi Agent. The menu bar shows the percent of credits left and the days until
they run out at your current pace. The app reads your existing `gh` login and the local
OpenCode and Pi session files, so it needs no setup.

## Privacy

- The app is local only. It has no telemetry and no backend.
- The app sends network calls only to `api.github.com`:
  - One request for your credits used and limit, every 5 minutes and when the Mac wakes.
  - `gh search` calls for GitHub outcomes, only after you set an organization.
- The app reuses your `gh` login. For the credits request, it runs `gh auth token`, keeps the
  token in memory for that one request, and sends it only in the `Authorization` header.
  The app does not store the token on disk or in `UserDefaults`, and does not log it.
  For `gh search`, gh reads its own login, so the app never reads the token.
- Session files stay on your Mac. The OpenCode database opens read only, and the queries select
  only time, agent, model, token and tool call fields. The app does not decode or keep prompt or
  answer text.
- "Copy summary" holds only numbers, dates, model ids and category names. It has no login,
  organization, token, file path, prompt or command.

## Features

### Menu bar

The title shows the percent of credits left and the whole days of runway, for example
`48% · 12d`. A runway glyph next to the title changes color with the runway health:

| Health | Rule | Color |
|---|---|---|
| Healthy | The credits last past the reset date, or the plan has no limit, or no credits are used yet | Blue |
| Short | The credits run out before the reset date | Orange |
| Critical | Less than 1 day of runway | Red |
| Unavailable | No data yet | Gray |

Other titles:

| Title | Meaning |
|---|---|
| `--% · --d` | No data yet |
| `100% · --d` | No credits used yet this cycle, so there is no burn rate |
| `∞` | Unlimited plan |
| `gh missing` | The app cannot find the GitHub CLI |
| `gh login` | gh is not logged in |
| `offline` | The app cannot reach `api.github.com` |
| `error` | GitHub returned an error status or an unexpected response |

For the error states, the glyph changes to a neutral symbol.

### Popover

Click the title to open the popover:

- A ring with the percent of credits left, and the days of runway.
- A sentence about the run-out date, for example "At this pace you run out on Oct 21,
  10 days before the reset on Nov 1."
- Cards for credits used of the limit, the average daily burn, and credits per outcome.
- Credits per model from local sessions.
- The time of the last refresh.
- A one-line local-only notice on first launch. You can close it.
- After a fetch error, the error message shows and the last good numbers fade.

### Dashboard

"Open dashboard" in the popover opens a window with:

- The cycle dates and the reset date.
- A banner with the run-out sentence. When the credits run out before the reset, it gives the
  highest daily burn that still reaches the reset. It also gives the category with the largest
  share of local credits.
- Cards for days of runway, percent remaining, average daily burn and credits per outcome.
- A daily burn chart for the cycle, one bar per UTC day from local sessions, with a line at the
  GitHub average daily burn. Select a bar to see the credits for that day.
- Local credits by task category, by model and by agent (OpenCode or Pi).
- A note with the percent of GitHub credits that local sessions do not explain, and the number of
  models with no price.
- A "Copy summary" button. It puts a short plain-text report on the clipboard that you can paste
  into a quota request:

```
GitHub Copilot AI credits, cycle 2026-10-01 to 2026-10-31 (UTC)
Used: 6,000 of 12,000 credits (50% remaining)
Average daily burn: 600 credits/day
Projected run-out: 2026-10-21, before the reset on 2026-11-01
Outcomes: 10 PRs opened, 20 PRs reviewed, 45 commits; 200 credits per outcome (PRs opened plus reviewed)
Top models (share of 1,300 credits in local sessions):
- gpt-6.1-sol: 900 credits (69%)
- gpt-6-luna: 300 credits (23%)
- gemini-3.8-flash: 60 credits (5%)
Top categories (same local sessions):
- Implementation: 700 credits (54%)
- Investigation: 400 credits (31%)
- Planning: 150 credits (12%)
```

### Task categories

The app puts each turn of each local session in one category: Debugging, Implementation,
Review, Investigation, Planning or Uncategorized. Fixed rules on the tool calls of the turn
decide the category. No model call is made. See [Category rules](#category-rules).

### Credits per outcome

When you set a GitHub organization, the app counts your PRs opened, PRs reviewed and commits in
that organization for the current cycle, and divides the credits used by the outcomes.
See [Credits per outcome](#credits-per-outcome-1).

### Settings

Open Settings with the gear button in the popover:

- GitHub organization for outcomes. The status line under it shows if gh can search it.
- The GitHub account source ("From gh auth. No token stored.").
- The path of the price override file.

## Screenshots

[screenshot: menu bar title]

[screenshot: popover]

[screenshot: dashboard]

[screenshot: settings]

## Requirements

- macOS 14 (Sonoma) or later.
- The [GitHub CLI](https://cli.github.com) (`gh`), logged in with `gh auth login`. The app looks
  for gh in `/opt/homebrew/bin`, `/usr/local/bin` and `/usr/bin`, because apps opened from Finder
  do not get your shell `PATH`.
- A GitHub Copilot plan with usage-based billing (AI credits).
- Optional: OpenCode or Pi Agent with the `github-copilot` provider. Without them, the app shows
  the GitHub numbers but no per-model, per-category or daily data.

## Install

### From a Homebrew tap

The tap is not published yet. When it is, install with the fully qualified name:

```sh
brew install --cask <owner>/<tap>/copilot-runway
```

Since Homebrew 6.0.0, Homebrew loads code from a third-party tap only after you trust it.
A fully qualified install trusts this one cask and nothing else in the tap
([Tap Trust](https://docs.brew.sh/Tap-Trust)).

### First launch

Releases are ad-hoc signed and not notarized by Apple. Homebrew sets the quarantine
attribute on cask downloads, so Gatekeeper blocks the first launch:

1. Open Copilot Runway from `/Applications`. macOS shows a warning. Click Done.
2. Open System Settings > Privacy & Security, scroll down, and click "Open Anyway" next to
   the message about Copilot Runway. Confirm with your password.

You do this once per installed version. Alternative from the terminal:

```sh
xattr -dr com.apple.quarantine /Applications/CopilotRunway.app
```

### Build from source

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
./scripts/release.sh
```

The script builds the Release configuration, ad-hoc signs the app, verifies the signature
and writes `dist/CopilotRunway-<version>.zip`. It prints the zip's sha256 for
`packaging/Casks/copilot-runway.rb`. Unzip it and move `CopilotRunway.app` to
`/Applications`.

### Signing and Homebrew policy

The app is ad-hoc signed (`codesign --sign -`) and is not notarized. The release script
signs without the hardened runtime. With an ad-hoc signature, the hardened runtime's
library validation stops the app from loading its own `Core.framework`. With a Developer ID
certificate, the build can use the hardened runtime and be notarized, and the first-launch
step goes away.

Homebrew policy as of Homebrew 7.0.9 (October 2026):

- Homebrew 5.0.0 deprecated `--no-quarantine`
  ([release notes](https://brew.sh/2025/11/12/homebrew-5.0.0/)). The flag is not in
  Homebrew 6.0.0 or later. The source of `Library/Homebrew/cmd/install.rb` confirms this.
  The flag was removed in the "Homebrew 6 deprecations" commit. There is no replacement
  flag. Users must do the first-launch step above.
- Homebrew applies quarantine to cask downloads so that Gatekeeper checks them
  ([Security and Supply Chain](https://docs.brew.sh/Homebrew-Security-and-Supply-Chain)).
- Casks that fail Gatekeeper checks are not allowed in the official Homebrew/homebrew-cask
  repository ([Acceptable Casks](https://docs.brew.sh/Acceptable-Casks)). Homebrew planned to
  disable those casks in September 2026
  ([6.0.0 release notes](https://brew.sh/2026/06/11/homebrew-6.0.0/)). This rule applies to
  the official repository, not to third-party taps. That is why this app ships through its
  own tap.
- Apple's steps for "Open Anyway":
  [Safely open apps on your Mac](https://support.apple.com/en-us/102445).

## How the numbers work

### Runway

GitHub gives the credits used, the credits remaining, the limit and the reset date. The app
calculates the rest:

- Cycle start: the reset date minus one calendar month. The cycle starts and resets at
  midnight UTC.
- Average daily burn: credits used / days since the cycle start. The app counts at least 1 day,
  so the first hours of a cycle do not give a very high burn.
- Days left: credits remaining / average daily burn. The menu bar, the popover and the dashboard
  round it down to whole days. There is no value for an unlimited plan or when no credits are used.
- Run-out date: now plus the days left. It can fall after the reset date.
- Target burn: credits remaining / days until the reset, rounded down. The dashboard shows it when
  the run-out date is before the reset.

Example: 10 days after the cycle start, with 6,000 of 12,000 credits used, the average daily burn is
600 credits/day and the days left are 6,000 / 600 = 10.

### Local credits and the GitHub total

The two totals come from different sources, so they do not match:

- The GitHub total is all Copilot use on your account, from every client and every machine.
- Local credits come from the OpenCode and Pi session files on this Mac. The app keeps only
  assistant messages billed through the `github-copilot` provider since the cycle start, and
  prices the tokens of each message with the price table.

So the local total is lower when you also use Copilot in other clients or on other Macs. It can
also differ when the price table is not the same as the rates GitHub billed, or when a model has no
price. The dashboard shows the percent of GitHub credits that local sessions do not explain.
The runway always uses the GitHub numbers. The per-model, per-category, per-agent and daily
numbers use the local credits.

### Prices

Copilot bills AI credits at published per-model rates for input, cached input, cache write and
output tokens. 1 AI credit is $0.01 USD, so credits = USD x 100. The app has a bundled price table
for every model on GitHub's
[Models and pricing for GitHub Copilot](https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing)
page: OpenAI GPT-5 to GPT-6.1, Anthropic Claude Haiku, Sonnet, Opus and Fable, Google Gemini,
Microsoft MAI-Code, xAI Grok and Moonshot AI Kimi. Core/README.md has the full list of ids and rates.
For models with a long context tier, the long context rates apply to the whole request when the
prompt is more than the tier threshold (272,000 tokens for most models). The app prices each
message and then adds them per model. Claude Opus 4.8 (fast mode) is not in the table because its
model id is not known.

To change or add a price, write `~/.config/copilot-runway/prices.json`. Each entry replaces the
bundled entry with the same model id. Models not in the file keep the bundled price. All four
`standard` rates are required, in USD per 1 million tokens. `longContextThreshold` and
`longContext` are optional.

```json
{
  "gpt-6.1-sol": {
    "standard": { "input": 2.0, "cachedInput": 0.1, "cacheWrite": 2.5, "output": 10.0 },
    "longContextThreshold": 272000,
    "longContext": { "input": 4.0, "cachedInput": 0.2, "cacheWrite": 5.0, "output": 15.0 }
  },
  "example-model": {
    "standard": { "input": 0.5, "cachedInput": 0.05, "cacheWrite": 0, "output": 3.0 }
  }
}
```

The `example-model` rates only show the shape. They are not real prices. If the file is not
valid, the app uses the bundled prices and shows a warning.

### Category rules

A turn is one user message plus all assistant messages and tool calls until the next user
message. The app checks these rules in this order. The first match wins.

| Category | Rule |
|---|---|
| Debugging | An edit, then a shell call, then an edit of the same file path |
| Implementation | Any edit. Every edited file counts, docs included |
| Review | A shell command that contains `gh pr diff` or `gh pr view`, and no edits |
| Investigation | Any read or shell call, and no edits |
| Planning | No read, shell or edit calls, and the OpenCode `plan` agent or at least 1,000 output tokens |
| Uncategorized | None of the above |

[Core/README.md](Core/README.md) lists which tool names count as read, shell and edit calls.

### Credits per outcome

Credits per outcome = credits used (from GitHub) / (PRs opened + PRs reviewed). Commits show
next to it but do not count as outcomes. With 0 outcomes there is no value.

The app counts these for your `gh` user in one organization since the cycle start, with
`gh search`:

- PRs opened: PRs you created in the cycle, open, closed, merged or draft.
- PRs reviewed: GitHub search has no review date filter. The app counts PRs that you reviewed at
  any time and that were updated in the cycle. Your own PRs are left out.
- Commits: commit search covers only the default branch of each repo, so commits on branches
  that are not merged do not count. The date is the author date, not the push date.

Limits:

- Credits used is all Copilot use on the account, also work outside the organization.
- Search returns at most 1,000 results per query. A count at the cap shows as `1,000+`.
- The search rate limit is low, so outcomes refresh on launch, when the organization changes, and
  at most every 30 minutes. After an error the app keeps the last counts and tries again after
  30 minutes.

## Configuration

The app works with no configuration. Two settings are optional:

| Setting | Where | Default |
|---|---|---|
| GitHub organization for outcomes | Settings window. It saves on Return or when the window closes. | Not set. Outcomes are off. |
| Price overrides | `~/.config/copilot-runway/prices.json` | The bundled price table |

## Development

Requirements: Xcode with Swift 6, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
The Xcode project comes from `project.yml`. Do not edit the `.xcodeproj` by hand, and do not
commit it.

```sh
xcodegen generate
xcodebuild -scheme CopilotRunway build
xcodebuild test -scheme CopilotRunway -destination 'platform=macOS'
```

The tests use Swift Testing and cover the Core module.

### Repo layout

```
project.yml          XcodeGen project definition
App/                 SwiftUI app target: menu bar, popover, dashboard, settings
Core/                Pure logic: usage client, session parsers, prices, runway, categories, outcomes
CoreTests/           Unit tests, with sample sessions in CoreTests/Fixtures/
packaging/Casks/     Homebrew cask
scripts/release.sh   Release build: ad-hoc signed zip in dist/
```

The app target only renders. All parsing, pricing, runway math and categories live in `Core`.
[Core/README.md](Core/README.md) documents the session file paths and formats, the turn and
category rules, the dashboard totals, the summary format, the outcome searches and the price table.

### Release

`./scripts/release.sh` reads `MARKETING_VERSION` from `project.yml`, builds the Release
configuration, ad-hoc signs `Core.framework` and the app, verifies the signature, and writes
`dist/CopilotRunway-<version>.zip` with its sha256. Put the sha256 and the release URL in
`packaging/Casks/copilot-runway.rb`.

## Known limitations

- The app is not notarized. Each new version needs the first-launch step.
- The Homebrew tap is not published, and the cask has a placeholder download URL.
- The app has no app icon yet.
- The credits request uses `api.github.com/copilot_internal/user`, the same request as the
  OpenCode and Pi plugins. It is not part of the documented GitHub REST API, so GitHub can change it.
- Outcomes cover one organization.
- The bundled price table has the models on GitHub's pricing page. Other models show "no price" until
  you add them to `prices.json`. The Gemini 3.7 Flash and 3.8 Flash rates are promotional rates through
  December 31, 2026. The Gemini 4 Argon rate is promotional until December 1, 2026.
- The app does not read the older OpenCode JSON file store under
  `~/.local/share/opencode/storage/`.

## Roadmap

- Sign with a Developer ID, turn the hardened runtime back on, and notarize the release. Then the
  first-launch step goes away.
- Add an app icon.
- Publish the Homebrew tap.

## License

MIT. See [LICENSE](LICENSE).

## Credits

The session file formats for OpenCode and Pi follow the provider docs in
[codeburn](https://github.com/getagentseal/codeburn) (MIT):
[docs/providers/opencode.md](https://github.com/getagentseal/codeburn/blob/main/docs/providers/opencode.md)
and [docs/providers/pi.md](https://github.com/getagentseal/codeburn/blob/main/docs/providers/pi.md).
