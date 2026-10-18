# Copilot Runway (working name)

A native macOS menu bar app that shows GitHub Copilot AI credit usage as **runway**:
how much is left, how fast it burns, and where it goes. Built for a team of Mac users
on Copilot usage-based billing who code through OpenCode and Pi Agent with
GPT-6.1 Sol, GPT-6 Luna and Gemini 3.8 Flash.

Codeburn already covers spend across agents. This app covers what codeburn does not:
the Copilot limit as the primary view, burn rate, projected run-out date, and
credits spent per kind of task.

## Principles (non-negotiable)

- **Zero setup.** Install, open, see numbers. Reuse the user's existing `gh` auth.
  Auto-detect OpenCode and Pi session files. No config file required to start.
- **Local only.** No telemetry, no backend. The only network calls go to the GitHub API.
  The app must say this on its first screen.
- **Insights over numbers.** Prefer a sentence that changes behavior over another table.
- **Thin UI, tested core.** All parsing, pricing, runway math and categorization live in a
  pure Swift module with unit tests. Views only render.

## Stack

- XcodeGen (`project.yml`) so the project is plain text. Never hand-edit `.pbxproj`.
- Not sandboxed (distributed via Homebrew cask, not the App Store), so shelling out to `gh` is allowed

## Data sources

1. **Credits used and limit.** Wilson's existing OpenCode/Pi plugin already polls this every
   5 minutes with his `gh` account. Its code is in `reference/`. Port that exact call.
   Do not guess a different endpoint. Get the token with `gh auth token`.
   Note: the reference plugins send the Copilot OAuth token from `auth.json`, not the `gh` token.
   Confirm the endpoint accepts the `gh` token before you build on it.
   Token handling: keep the token in memory only, for the length of one request. Send it only in the
   `Authorization` header to `api.github.com`. Never log it, print it, write it to disk or
   `UserDefaults`, put it in a URL, or include it in error messages or "Copy summary" output.
2. **Per-model token usage.** OpenCode and Pi write local session files. Locate and parse them.
   Codeburn (MIT) documents both formats: `docs/providers/opencode.md` and `docs/providers/pi.md`
   in github.com/getagentseal/codeburn. Document the paths you find in `Core/README.md`.
3. **Pricing.** Copilot credits are consumed at published API rates per model (input, output,
   cached tokens). Ship a small bundled price table for Sol, Luna and Gemini 3.8 Flash and allow a JSON override
   at `~/.config/copilot-runway/prices.json`.
4. **GitHub outcomes (later milestone).** `gh search prs/commits` scoped to `@me` and one org.

## Milestones

Do **one milestone per session**. Stop at the end of each, summarize what changed and how
to verify it, and wait for review. Do not start the next milestone on your own.

### M3. Task categories
Deterministic rules from tool calls in each session turn. No model calls.

| Category | Signal |
|---|---|
| Investigation | reads, greps, shell commands, no edits |
| Planning | OpenCode plan agent, or long turns with no tool calls |
| Implementation | edits or writes to source files |
| Debugging | edit, run, edit the same file again |
| Review | `gh pr diff` / `gh pr view` in shell, no edits |

Each rule gets unit tests with fixture sessions in `CoreTests/Fixtures/`.

### M6. Distribution
- Homebrew tap with a cask, signed and notarized build.
- Decision (2026-10-15): releases are ad-hoc signed for now, not notarized. No Developer ID yet.
- `scripts/release.sh` signs without hardened runtime. Library validation needs a Team ID, and dyld refuses `Core.framework` under an ad-hoc signature.
- When a Developer ID is available: turn hardened runtime back on in `scripts/release.sh` and add notarization. Ask the user before choosing or using any identity.
- Creating repos or releases is outward-facing, so ask first.

## Out of scope

Jira integration, team or org-wide aggregation, Windows or Linux, any backend, telemetry.
If a task seems to need one of these, stop and ask.

## Code style

- Never use em dashes anywhere, including comments, strings and docs
- 2-space indent, LF line endings, UTF-8, trim trailing whitespace, final newline
- Small types with clear names. No protocols or abstractions until a second implementation exists.
