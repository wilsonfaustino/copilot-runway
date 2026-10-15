# Core

Pure logic for Copilot Runway. The app target only renders what this module returns.

## Session files

The parsers keep only assistant messages billed through GitHub Copilot (provider `github-copilot`)
with a timestamp at or after the cycle start (`Runway.cycleStart`). Each message becomes a
`UsageRecord`: model id, timestamp, and tokens (input, cached input, cache write, output).
Output always includes reasoning tokens, because reasoning bills at the output rate.

Format reference: codeburn (MIT)
[docs/providers/opencode.md](https://github.com/getagentseal/codeburn/blob/main/docs/providers/opencode.md) and
[docs/providers/pi.md](https://github.com/getagentseal/codeburn/blob/main/docs/providers/pi.md).
The details below are what we found on disk in October 2026.

### Pi (`PiSessionParser`)

- Path: `~/.pi/agent/sessions/<encoded cwd>/<ISO timestamp>_<session id>.jsonl`, one file per session.
- Each line is one JSON entry with `type`. Types seen: `session`, `message`, `model_change`,
  `thinking_level_change`, `context_edit`, `compaction`.
- Usage lives on `type: "message"` entries whose `message.role` is `assistant`:
  - `message.provider`, for example `github-copilot`
  - `message.model`, for example `gpt-6.1-sol`, `gpt-6-luna`
  - `message.responseId`
  - `message.timestamp`: Unix time in milliseconds
  - `message.usage`: `input`, `output`, `cacheRead`, `cacheWrite`, `reasoning`, `totalTokens`, `cost`
- `usage.input` excludes cached tokens. `usage.output` already includes reasoning:
  `totalTokens = input + output + cacheRead + cacheWrite`.
- Missing token fields count as 0.
- A forked session repeats earlier entries, so records are unique by `responseId` across all files.
- Files last modified before the cycle start are skipped.
- `compaction` entries also carry `usage` but no model, so they are not counted.

### OpenCode (`OpenCodeSessionParser`)

- Path: `~/.local/share/opencode/opencode*.db` (SQLite, WAL mode). Opened read only.
  Backups such as `opencode.db.bak-*` do not match and are ignored.
- OpenCode 2.x table `session_message`: `id`, `session_id`, `type`, `seq`, `time_created` (ms), `data` (JSON).
  Rows with `type = 'assistant'` carry:
  - `data.model.id`, `data.model.providerID`
  - `data.tokens.input`, `data.tokens.output`, `data.tokens.reasoning`,
    `data.tokens.cache.read`, `data.tokens.cache.write`
- OpenCode 1.x table `message`: `id`, `session_id`, `time_created` (ms), `data` (JSON) with
  `data.role = 'assistant'`, `data.providerID`, `data.modelID`, and the same `data.tokens` shape.
  2.x stops writing this table but keeps the old rows.
- `tokens.input` excludes cached tokens. `tokens.output` excludes reasoning, so the parser adds
  `tokens.reasoning` to output.
- 2.x copies 1.x messages into `session_message` under the same id. The parser reads the legacy
  table first and skips current rows with an id it already has.
- Child (subagent) sessions have their own rows, so the parser reads all rows and needs no session walk.
- The queries select only time, agent, model, token and tool call fields (tool name, file path,
  shell command) with `json_extract`, so prompt and answer text never leaves the database.
- Not read: the file based JSON store under `~/.local/share/opencode/storage/`
  (only older sessions on our machines).

## Turns and task categories

### Turns (`Turn`)

A turn is one user message plus all assistant messages and tool calls until the next user message.
Each turn keeps its timestamp, source (`pi` or `opencode`), agent (OpenCode only), tool calls
(name, file path for read and edit tools, command for shell tools), and the Copilot `UsageRecord`s
of its assistant messages. The parsers use the same filters as for records, and keep only turns
with at least one record. So every record is in exactly one turn, and `Credits.byCategory` adds up
to the priced models in `Credits.byModel`.

- Pi: only `message.role = "user"` starts a turn. `system` and `toolResult` messages do not.
  Tool calls are the `content` items with `type: "toolCall"`: `name`, `arguments.path`,
  `arguments.command`. Only these three fields are decoded. Message text is not.
  Assistant messages before the first user message form a turn of their own.
- OpenCode: rows of `session_message` in `session_id, seq` order. Only `type = 'user'` starts a turn.
  `synthetic`, `system`, `shell`, `agent-switched` and other rows do not. The agent is
  `data.agent` of the first assistant message. Tool calls are the `data.content` items with
  `type: "tool"`: `name`, `state.input.path` (2.x) or `state.input.filePath` (1.x copies), and
  `state.input.command`. A `patch` call becomes one tool call per file in `state.metadata.files[].file`.
  A patch without metadata (16 of 217 in our data, all with `state.status = "error"`) has no file path.
- OpenCode turns read only the 2.x table. The 158 legacy `message` rows that 2.x did not copy end in
  April 2026, so they cannot be in a current cycle. They still count in `records`.
- A turn that starts before the cycle keeps only its messages in the cycle. OpenCode also drops its
  tool calls from before the cycle. Pi keeps them.

### Tool names

| Kind | Pi | OpenCode |
|---|---|---|
| Read (read, search, fetch) | `read`, `grep`, `find`, `ls` | `read`, `grep`, `glob`, `list`, `webfetch`, `websearch` |
| Shell | `bash` | `shell`, `bash` (1.x) |
| Edit | `edit`, `write` | `patch`, `apply_patch`, `edit`, `write`, `multiedit` (1.x) |
| Neutral | all others, for example `codemode`, `tool_search`, `mcp__*` | all others, for example `execute`, `skill`, `question`, `subagent`, `todowrite` |

Neutral tools do not change the category. `execute` and `codemode` run code that can call other
tools, and the session does not record which ones, so they stay neutral.

### Categories (`TaskCategorizer`)

Rules, checked in this order. The first match wins.

| Category | Rule |
|---|---|
| Debugging | An edit, then a shell call, then an edit of the same file path |
| Implementation | Any edit. Every edited file counts as a source file, docs included |
| Review | A shell command that contains `gh pr diff` or `gh pr view`, no edits. Substring match, so `rtk gh pr view` also counts |
| Investigation | Any read or shell call, no edits |
| Planning | No read, shell or edit calls, and the OpenCode `plan` agent or at least 1,000 output tokens (reasoning included) |
| Uncategorized | None of the above |

## Dashboard aggregates

All dashboard numbers come from the same turns, so they add up to the same local total.
The app takes the records for `Credits.byModel` and `Credits.byDay` from `turns.flatMap(\.records)`.
In October 2026 this gave the same records and the same total as the parser `records` functions.
Messages from models without a price add 0, as in `Credits.byCategory`.

- `Credits.byDay`: one entry per day from the cycle start through now, days without messages at 0.
  The caller passes the calendar. The app uses `Runway.utcCalendar` (UTC days), because the cycle
  starts and resets at midnight UTC: every bucket is a whole day inside the cycle. With local days,
  a user at UTC-3 gets a first bucket of 3 hours (September 30, 21:00 to midnight) and loses the
  last 3 hours of the cycle. The chart labels days in UTC too.
- `Credits.bySource`: priced credits per `Turn.source` (OpenCode, Pi). `UsageRecord` has no source.
- `Runway.runOutDate`: now plus `daysLeft` days. It can fall after the reset date.
  `nil` for unlimited plans and when no credits are used.

## Quota summary (`QuotaSummary`)

"Copy summary" puts this plain text on the clipboard. It holds only numbers, dates, model ids and
category names: no login, org, token, file path, prompt or command. At most 13 lines.

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

- Cycle dates, reset and run-out dates are UTC days in ISO 8601. Numbers use `en_US` grouping,
  so the text is the same on every machine.
- Used, remaining and the average daily burn come from the GitHub API. Shares are of the priced
  local session total. Models without a price are left out.
- When the run-out falls on or after the reset, the line says "after the reset on <date>".
  Unlimited plans have no limit and no run-out line. Sections with no local credits are left out.
- The outcomes line holds only the three counts and credits per outcome, no organization or repo name.
  It is left out until an organization is set and the first search succeeds. With no PRs opened or
  reviewed it says "credits per outcome: none, no PRs opened or reviewed yet".

## GitHub outcomes (`GitHubOutcomesClient`)

Outcomes are counted for the `gh` user (`@me`) in one organization, set in Settings and stored in
`UserDefaults` under `githubOrganization`. With no organization the app works as before and the
dashboard asks for one.

The client runs `gh search` through `Process`, with gh found the same way as for `gh auth token`.
gh reads its own login, so the app never reads or passes the token for these calls.
`<cycle start>` is `Runway.cycleStart` in ISO 8601 UTC, for example `2026-10-01T00:00:00Z`.

| Count | Command |
|---|---|
| PRs opened | `gh search prs --owner=<org> --author=@me --created=>=<cycle start> --json=number --limit=1000` |
| PRs reviewed | `gh search prs --owner=<org> --reviewed-by=@me --updated=>=<cycle start> --json=number --limit=1000 -- -author:@me` |
| Commits | `gh search commits --owner=<org> --author=@me --author-date=>=<cycle start> --json=sha --limit=1000` |

- Only the length of each JSON list leaves Core. Each result decodes no fields, so no PR title,
  repo name or commit message is kept. PR numbers repeat across repos, so results are not deduplicated.
- Every value uses the `--flag=value` form, so an organization that starts with `-` stays a value.
- PRs opened counts every PR created in the cycle: open, closed, merged and draft.
- PRs reviewed: search has no review date qualifier. `--updated` counts PRs that you reviewed at any
  time and that changed in the cycle. `-author:@me` removes your own PRs: without it,
  `reviewed-by:@me` also matches your PRs where you replied to a review.
- Commits: commit search covers only the default branch of each repo, so commits on branches that are
  not merged do not count. `--author-date` is the date the commit was written, not pushed.
- Credits per outcome = `credits_used` from the usage API / (PRs opened + PRs reviewed). Commits are
  shown but are not outcomes. With 0 outcomes there is no value. `credits_used` is all Copilot use on
  the account, also outside the organization.

### Limits

- The search API allows 30 requests per minute, and GitHub also has a secondary rate limit.
  In October 2026, 8 fast searches after a few others hit the secondary limit.
- gh fetches 100 results per request, so one refresh costs 3 requests, and up to 30 at the cap.
- Search returns at most 1,000 results per query. A count at 1,000 shows as `1,000+`.
- So outcomes refresh on launch (after the first good usage response, which gives the cycle start),
  when the organization changes, and when a credits refresh finds the last search 30 minutes old or
  more (`OutcomesFetch.isDue`). A new cycle start also refreshes. The organization saves on Return or
  when Settings closes, not on each key. The searches run off the main thread.

### Errors

gh stderr can hold the organization and the query, so it never reaches the UI. `GitHubOutcomesClient.error`
maps it to one short line. The samples are what gh 2.102 printed in October 2026.

| Error | Signal |
|---|---|
| gh missing | No gh in the install folders, or it does not start |
| Not logged in | Exit status 4 ("please run: gh auth login"), or `401` / `Bad credentials` in stderr |
| Organization not found or no access | "cannot be searched either because the resources do not exist or you do not have permission" |
| Rate limited | "rate limit" in stderr, for example "HTTP 403: You have exceeded a secondary rate limit" |
| Other | Any other failure, or output that is not a JSON list |

After an error the app keeps the last counts and tries again after 30 minutes.

## Prices (`PriceTable`)

Bundled rates, in USD per 1 million tokens, from GitHub's
[Models and pricing for GitHub Copilot](https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing):

| Model id | Tier | Input | Cached input | Cache write | Output |
|---|---|---|---|---|---|
| `gpt-5-mini` | Default, no tier | 0.25 | 0.025 | 0 | 2.00 |
| `gpt-5.3-codex` | Default, no tier | 1.75 | 0.175 | 0 | 14.00 |
| `gpt-5.4` | Default, prompt <= 272K | 2.50 | 0.25 | 0 | 15.00 |
| `gpt-5.4` | Long context, prompt > 272K | 5.00 | 0.50 | 0 | 22.50 |
| `gpt-5.4-mini` | Default, no tier | 0.75 | 0.075 | 0 | 4.50 |
| `gpt-5.4-nano` | Default, no tier | 0.20 | 0.02 | 0 | 1.25 |
| `gpt-5.5` | Default, prompt <= 272K | 5.00 | 0.50 | 0 | 30.00 |
| `gpt-5.5` | Long context, prompt > 272K | 10.00 | 1.00 | 0 | 45.00 |
| `gpt-5.6-luna` | Default, prompt <= 200K | 0.20 | 0.02 | 0.25 | 1.20 |
| `gpt-5.6-luna` | Long context, prompt > 200K | 0.40 | 0.04 | 0.50 | 1.80 |
| `gpt-5.6-sol` | Default, prompt <= 272K | 4.00 | 0.40 | 5.00 | 20.00 |
| `gpt-5.6-sol` | Long context, prompt > 272K | 8.00 | 0.80 | 10.00 | 30.00 |
| `gpt-5.6-terra` | Default, prompt <= 272K | 2.00 | 0.20 | 2.50 | 12.00 |
| `gpt-5.6-terra` | Long context, prompt > 272K | 4.00 | 0.40 | 5.00 | 18.00 |
| `gpt-6-astra` | Default, prompt <= 272K | 10.00 | 1.00 | 12.50 | 50.00 |
| `gpt-6-astra` | Long context, prompt > 272K | 20.00 | 2.00 | 25.00 | 75.00 |
| `gpt-6-luna` | Default, prompt <= 272K | 0.10 | 0.01 | 0.125 | 0.50 |
| `gpt-6-luna` | Long context, prompt > 272K | 0.20 | 0.02 | 0.25 | 0.75 |
| `gpt-6-sol` | Default, prompt <= 272K | 2.00 | 0.20 | 2.50 | 10.00 |
| `gpt-6-sol` | Long context, prompt > 272K | 4.00 | 0.40 | 5.00 | 15.00 |
| `gpt-6.1-sol` | Default, prompt <= 272K | 2.00 | 0.10 | 2.50 | 10.00 |
| `gpt-6.1-sol` | Long context, prompt > 272K | 4.00 | 0.20 | 5.00 | 15.00 |
| `claude-haiku-4.5` | Default, no tier | 1.00 | 0.10 | 1.25 | 5.00 |
| `claude-haiku-5.5` | Default, prompt <= 100K | 0.10 | 0.01 | 0.125 | 0.50 |
| `claude-haiku-5.5` | Long context, prompt > 100K | 0.50 | 0.05 | 0.625 | 2.50 |
| `claude-sonnet-4` | Default, no tier | 3.00 | 0.30 | 3.75 | 15.00 |
| `claude-sonnet-4.6` | Default, no tier | 3.00 | 0.30 | 3.75 | 15.00 |
| `claude-opus-4.8` | Default, no tier | 5.00 | 0.50 | 6.25 | 25.00 |
| `claude-opus-5` | Default, no tier | 5.00 | 0.50 | 6.25 | 25.00 |
| `claude-opus-5.5` | Default, no tier | 4.00 | 0.20 | 5.00 | 20.00 |
| `claude-sonnet-5` | Default, no tier | 2.00 | 0.20 | 2.50 | 10.00 |
| `claude-sonnet-5.5` | Default, no tier | 2.00 | 0.10 | 2.50 | 10.00 |
| `claude-fable-5` | Default, no tier | 10.00 | 1.00 | 12.50 | 50.00 |
| `claude-fable-5.1` | Default, no tier | 10.00 | 0.25 | 12.50 | 50.00 |
| `gemini-3.7-flash` | Default, no tier | 0.75 | 0.075 | 0 | 3.75 |
| `gemini-3.8-flash` | Default, no tier | 0.75 | 0.075 | 0 | 3.75 |
| `gemini-4-argon` | Default, no tier | 2.00 | 0.10 | 0 | 10.00 |
| `mai-code-1.1-flash` | Default, no tier | 0.20 | 0.02 | 0 | 1.20 |
| `grok-4.5` | Default, prompt <= 200K | 2.00 | 0.50 | 0 | 6.00 |
| `grok-4.5` | Long context, prompt > 200K | 4.00 | 1.00 | 0 | 12.00 |
| `grok-4.6` | Default, prompt <= 200K | 2.00 | 0.50 | 0 | 6.00 |
| `grok-4.6` | Long context, prompt > 200K | 4.00 | 1.00 | 0 | 12.00 |
| `grok-4.7` | Default, prompt <= 200K | 2.00 | 0.50 | 0 | 6.00 |
| `grok-4.7` | Long context, prompt > 200K | 4.00 | 1.00 | 0 | 12.00 |
| `kimi-k3` | Default, no tier | 3.00 | 0.30 | 0 | 15.00 |

- The same page says: "1 AI credit = $0.01 USD". So credits = USD x 100.
- GitHub lists a cache write rate for GPT-5.6 and later OpenAI models and for all Anthropic models.
  For all other models the page shows "Not applicable" or has no cache write column, so the table has 0.
- The table has every model on that page except Claude Opus 4.8 (fast mode), which has a price but no
  known model id. Add it to `prices.json` when you know the id OpenCode or Pi writes.
- Model ids are the page names in lowercase with hyphens, for example `claude-opus-5.5`. Ids seen in
  OpenCode and Pi session files follow this form. Ids for models not yet seen in a session file
  (for example `grok-4.5` and `kimi-k3`) come from the same rule and are not checked.
- The tier threshold uses the page value with 1K = 1,000 tokens. Most tiers are 272K. GPT-5.6 Luna and
  the Grok models use 200K. Claude Haiku 5.5 uses 100K.
- Tier rule: the long context rates apply to the whole request when
  input + cached input + cache write > the model threshold (272,000 for most models).
  A prompt of exactly the threshold uses the default rates.
  The GitHub page labels the threshold "input tokens" and does not define it further.
  Pi stores per message costs that match this rule exactly.
- Credits are computed per message and then summed per model, because the tier depends on each request.
- The Gemini 3.7 Flash and Gemini 3.8 Flash rates are promotional "through December 31, 2026"
  (footnote on the same page). The Gemini 4 Argon rate is promotional "until December 1, 2026".
  GitHub lists no cache write rate for Google models, so it is 0. Pi records 0 cache write tokens for Gemini 3.8 Flash.
- Models without a price show as "no price". The parsers keep only `github-copilot` records, so models
  that you call with your own provider key never reach the price table.

### Override

Optional file: `~/.config/copilot-runway/prices.json`. Each entry replaces the bundled entry with
the same model id. Models not in the file keep the bundled price. All four rates are required.
`longContextThreshold` and `longContext` are optional. If the file is not valid, the app uses the
bundled prices and shows a warning.

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

(The `example-model` rates above only show the shape. They are not real prices.)
