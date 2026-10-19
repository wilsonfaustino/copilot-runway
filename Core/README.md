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
- A line that does not decode is skipped, because Pi can be writing the last line. A file that has
  lines but no line that decodes sets `hasUndecodableFile`, for example after a Pi format change.
  `SessionCredits.load` then adds the warning "Cannot read some Pi sessions.", and the app shows it
  where it shows the OpenCode warning.

### omp (`PiSessionParser`, source `omp`)

omp (oh-my-pi) is a Pi fork. Checked on omp 18.12.3 in October 2026.

- Path: `~/.omp/agent/sessions/<encoded cwd>/<ISO timestamp>_<session id>.jsonl`, one file per session.
- Same format as Pi, so `PiSessionParser` reads it with `source: .omp`. Provider, `responseId`,
  `timestamp` and `usage` match the Pi fields above.
- Extra entry types, all skipped: `title` (before `session`), `custom`, `custom_message`, `title_change`.
- Records are unique by `responseId` across both roots. `SessionCredits.load` reads Pi first and passes one set to both reads,
  so a response found in both `~/.pi` and `~/.omp` counts once, as Pi.
- A missing `~/.omp` folder gives no turns and no warning, as for Pi. A file with no line that
  decodes adds the warning "Cannot read some omp sessions."

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
  2.x stops writing this table but keeps the old rows. The parser does not read this table.
- `tokens.input` excludes cached tokens. `tokens.output` excludes reasoning, so the parser adds
  `tokens.reasoning` to output.
- 2.x copies 1.x messages into `session_message` under the same id, so reading only
  `session_message` counts each copied message once.
- Child (subagent) sessions have their own rows, so the parser reads all rows and needs no session walk.
- The queries select only time, agent, model, token and tool call fields (tool name, file path,
  shell command) with `json_extract`, so prompt and answer text never leaves the database.
- Not read: the file based JSON store under `~/.local/share/opencode/storage/`
  (only older sessions on our machines).

## Turns and task categories

### Turns (`Turn`)

A turn is one user message plus all assistant messages and tool calls until the next user message.
Each turn keeps its timestamp, source (`pi`, `opencode` or `omp`), agent (OpenCode only), tool calls
(name, file path for read and edit tools, command for shell tools), and the Copilot `UsageRecord`s
of its assistant messages. The parsers keep only the records that pass the filters in
[Session files](#session-files), and keep only turns with at least one record. So every record is in exactly one turn, and `Credits.byCategory` adds up
to the priced models in `Credits.byModel`.

- Pi: only `message.role = "user"` starts a turn. `system` and `toolResult` messages do not.
  Tool calls are the `content` items with `type: "toolCall"`: `name`, `arguments.path`,
  `arguments.command`, and the optional `arguments.input` (only for its `[<path>#<hash>]` header, see omp). Only these fields are decoded. Message text is not.
  Assistant messages before the first user message form a turn of their own.
- omp: same as Pi. The omp `edit` tool has no `arguments.path`. Its `arguments.input` starts with a
  `[<path>#<hash>]` header, so when `path` is missing and `input` starts with `[`, the file path is
  the text between the first `[` and the first `#` of the first line. This rule applies to Pi too.
  An `input` that is not a string is ignored.
- OpenCode: rows of `session_message` in `session_id, seq` order. Only `type = 'user'` starts a turn.
  `synthetic`, `system`, `shell`, `agent-switched` and other rows do not. The agent is
  `data.agent` of the first assistant message. Tool calls are the `data.content` items with
  `type: "tool"`: `name`, `state.input.path` (2.x) or `state.input.filePath` (1.x copies), and
  `state.input.command`. A `patch` call becomes one tool call per file in `state.metadata.files[].file`.
  A patch without metadata (16 of 217 in our data, all with `state.status = "error"`) has no file path.
- OpenCode turns read only the 2.x table. The 158 legacy `message` rows that 2.x did not copy end in
  April 2026, so they cannot be in a current cycle.
- A turn that starts before the cycle keeps only its messages in the cycle. OpenCode also drops its
  tool calls from before the cycle. Pi keeps them.
- `SessionCredits.load` reads every parser from the last cycle start (see Last cycle comparison), so
  the cut above happens one cycle earlier. To keep this cycle's turns unchanged, OpenCode gets
  `splitAt: cycleStart`: rows before it build their own turns, so the turns from the reset on equal a
  read that starts at the reset. Pi and omp need no split, because a read from the reset already keeps the
  earlier tool calls. One edge stays: a row whose `seq` order disagrees with its time order.

### Tool names

| Kind | Pi | omp | OpenCode |
|---|---|---|---|
| Read (read, search, fetch) | `read`, `grep`, `find`, `ls` | Pi names plus `glob`, `ast_grep` | `read`, `grep`, `glob`, `list`, `webfetch`, `websearch` |
| Shell | `bash` | `bash` | `shell`, `bash` (1.x) |
| Edit | `edit`, `write` | `edit`, `write`, `ast_edit` | `patch`, `apply_patch`, `edit`, `write`, `multiedit` (1.x) |
| Neutral | all others, for example `codemode`, `tool_search`, `mcp__*` | all others, for example `task` | all others, for example `execute`, `skill`, `question`, `subagent`, `todowrite` |

Neutral tools do not change the category. `execute` and `codemode` run code that can call other
tools, and the session does not record which ones, so they stay neutral.

A call whose file path starts with `xd://` is neutral, except `read`, for every source. omp runs
a mounted tool with a `write` to `xd://<tool>`, and that changes no file. A `read` of `xd://<tool>`
reads the tool, so it stays a read. A staged `ast_edit` that a later `write` to `xd://resolve`
applies is not counted as an edit.

### Categories (`TaskCategorizer`)

Rules, checked in this order. The first match wins.

| Category | Rule |
|---|---|
| Debugging | An edit, then a shell call, then an edit of the same file path |
| Implementation | Any edit. Every edited file counts as a source file, docs included |
| Review | A shell command that contains `gh pr diff` or `gh pr view`, no edits. Substring match, so `rtk gh pr view` also counts |
| Planning | The OpenCode `plan` agent, no edits and no review command. Read and shell calls do not change this |
| Investigation | Any read or shell call, no edits |
| Planning | No read, shell or edit calls, and at least 1,000 output tokens (reasoning included) |
| Uncategorized | None of the above |

## Dashboard aggregates

All dashboard numbers come from the same turns, so they add up to the same local total.
`SessionCredits.load` reads the Pi, omp and OpenCode turns once, picks the prices, and builds every
aggregate. It takes the records for `Credits.byModel` and `Credits.byDay` from the current cycle turns
after the split at the cycle start (see Last cycle comparison).
Messages from models without a price add 0, as in `Credits.byCategory`.

- `Credits.byDay`: one entry per day from the cycle start through now, days without messages at 0.
  The caller passes the calendar. The app uses `Runway.utcCalendar` (UTC days), because the cycle
  starts and resets at midnight UTC: every bucket is a whole day inside the cycle. With local days,
  a user at UTC-3 gets a first bucket of 3 hours (September 30, 21:00 to midnight) and loses the
  last 3 hours of the cycle. The chart labels days in UTC too.
- `Credits.bySource`: priced credits per `Turn.source` (OpenCode, Pi, omp). `UsageRecord` has no source.
- `Credits.byModelAndCategory`: priced credits per model and task. A turn can mix models, so each record
  goes to its own model and the category of its turn. The totals per model equal `byModel` and the
  totals per category equal `byCategory`.
- `Runway.runOutDate`: now plus `daysLeft` days. It can fall after the reset date.
  `nil` for unlimited plans and when no credits are used.
- `Runway.dailyHeadroom`: `allowedDailyBurn` minus `averageDailyBurn`. `allowedDailyBurn` is the credits
  remaining divided by the real fractional days until the reset, with no minimum, so the sign always
  agrees with `runOutDate` against the reset date. `nil` for unlimited plans, with no credits used or
  left, and at or after the reset. `RunwayInsight.headroomText` shows it as "N credits/day of
  headroom" or "N credits/day over budget", on the second line under the popover runway figure and at
  the end of the dashboard banner run-out sentences.
- `ShareBreakdown`: the items of the By task, By model and By agent split bars, with whole-percent shares.
  `Credits.sharePercents(_:of:)` allocates them with the largest remainder method, so the shares of one
  breakdown add up to 100 (for example 34, 33 and 33 for three equal parts). On a tie the first item wins.
  - `local(entries:)` keeps the order of the entries. Shares are of the local total.
  - `tasks(_:)` is `local(entries:)` for the By task card. It always has an Uncategorized item, at 0
    credits when no turn falls in it. The card shows an item with credits and a 0% share as "<1%"
    (`Credits.shareLabel(percent:of:)`). The other cards show the share.
  - `models(_:githubCredits:namedModelLimit:)` skips models without a price and sorts by credits. With more
    than `namedModelLimit` models (3 in the popover, 5 in the dashboard), the top ones keep their names and
    the rest fold into one "Other models" item. When GitHub
    credits are more than local credits, a last "Not in local sessions" item holds the difference and
    shares are of the GitHub total. A gap under 1% is left out. When local credits are more than GitHub
    credits, shares and `shareTotal` are of the local total and `unit` is "local credits". With no local
    credits there are no items, `shareTotal` is the GitHub total and the card shows its empty text.
  - `copilotReviewNote(reviewCount:modelCredits:)` is the line under the "Not in local sessions" item.
    See Copilot code reviews.
  - `unpricedModelsNote(_:)` is the dashboard By model note: "1 model has no price: <name>" or
    "2 models have no price: <name1>, <name2>", sorted by id. `nil` when every model has a price.
  - `unit` names what `shareTotal` counts ("local credits" or "GitHub credits"). `isEmpty` is true when
    there is no bar to draw.
- `ModelTaskSplit`: the dashboard By model card draws one full-width bar per model item, split by task.
  The segments of a bar are the `byModelAndCategory` credits of that model, so they show its task mix.
  "Other models" sums the folded models. "Not in local sessions" has no task and keeps its striped bar.
  Every bar draws its segments in one order, highest category total first, and leaves out categories at 0.
  `segmentPercents` holds the whole percent of each segment, allocated like the `ShareBreakdown` shares so
  the segments of a bar add up to 100. The hover text and the VoiceOver summary read these values.

## Last cycle comparison (`CycleComparison`)

The Daily burn chart draws the last cycle as a dashed line next to this cycle's bars, plus one sentence.
Both use local credits only. They are not in the GitHub numbers, the popover or Copy summary.

- Parse window: `SessionCredits.load(since: cycleStart)` reads Pi, omp and OpenCode from
  `Runway.cycleStart(resetDate: cycleStart)`, one cycle earlier. On our data this adds about 20 ms
  per refresh (33 ms OpenCode, Pi flat), so there is no cache.
- Split: `SessionCredits.aggregate` keeps only records at or after `cycleStart` in each turn and drops
  turns with no record left. Every current aggregate (`byModel`, `byCategory`, `byModelAndCategory`,
  `bySource`, `byDay`, `cacheHits`, the notes) reads these turns. The earlier records feed only
  `previousByDay`: `Credits.byDay` from the last cycle start through the day before `cycleStart`.
  OpenCode turns that cross the reset are split in the parser, see Turns.
- Pairing: days pair by index from each cycle start (day 1 with day 1). The chart x axis is "Day N"
  up to the longer of this cycle's length (`Runway.cycleDayCount`) and the last cycle's.
- `CycleComparison.compare(current:previous:)` compares totals so far, through yesterday. The last
  `byDay` entry is today, which is not over, so it is left out. The last cycle total runs through the
  same day index. Past the last cycle's final day (day 31 against a 30-day cycle), it is the whole last
  cycle. The percent is `(current - previous) / previous * 100`, rounded.
- Minimum data: `nil` without a full day in this cycle, with fewer than 5 days above 0 credits in the
  paired last cycle days, or with a paired last cycle total of 0. Missing old sessions (OpenCode
  pruning, deleted Pi folders) look like quiet days, so the minimum also guards the "below" sentence.
- `sentence(locale:)`: "Local credits through Oct 17 are 35% above the same days of last cycle.",
  "... 12% below ..." or, when the percent rounds to 0, "Local credits through Oct 17 are about the
  same as last cycle." The day is the UTC day (`RunwayInsight.day`). `SessionCredits` keeps it as
  `cycleComparisonSentence`.
- Prices load once per refresh and apply to both cycles, so the comparison is token volume at the
  current rates, not what GitHub billed.
- The chart hides the line and its legend when the last cycle has 0 credits.

## Model display names (`ModelDisplayName`)

`ModelDisplayName.bundled` maps each id in `PriceTable.bundled` to the name GitHub writes on the
[models and pricing page](https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing),
for example `gpt-6.1-sol` to "GPT-6.1 Sol". `name(for:)` returns the id itself for an id not in the map.
Display names appear in text and legends: the By model rows, the unpriced models note, the low cache hit
note, the model efficiency note and "Copy summary". Keys, sorting, pricing and grouping use raw ids. The map
has no override file. A new price table entry needs a new name, and a test checks that the two have the same ids.

## Model efficiency (`ModelEfficiency`)

- An edit turn is a turn that `TaskCategorizer` puts in Implementation or Debugging. A retry is a
  Debugging turn. Retry rate is retries divided by edit turns.
- The model of a turn is the model of its records. Turns with no records, turns with records from 2 or
  more models, and models without a price are left out.
- Credits per edit turn is `Credits.byModel` over the model's edit turn records, divided by its edit turns.
- A model needs at least `ModelEfficiency.minimumEditTurns` (10) edit turns. Under that, one turn moves
  the retry rate by 10 or more points.
- `note(_:locale:)` is the dashboard By model note. With 2 or more models, it compares the 2 with the
  most edit turns (ties by model id), the cheaper one first: "GPT-6 Luna costs 40% less per edit turn
  than GPT-6.1 Sol. Retry rate 22% against 18%." A difference that rounds to 0% gives "cost the same".
  With 1 model, it gives its credits per edit turn and retry rate. Under 1 credit, the credits show 2
  significant digits, so a cheap model does not show 0. With no model, there is no note.
- The codeburn "One-shot rate" (docs/how-it-works.md in github.com/getagentseal/codeburn, MIT) gave the
  idea. No code or thresholds come from it.

## Cache hit and run-out notices

### Cache hit (`CacheHit`)

- Rate per model: `cachedInput / promptTokens`, summed over the model's records in the cycle.
  `promptTokens = input + cachedInput + cacheWrite`. Our `input` excludes cached tokens, so the
  codeburn formula `cacheRead / (input + cacheRead)` does not apply as is. A model with 0 prompt
  tokens has no rate.
- A rate under `CacheHit.lowThreshold` (0.5) is low. Exactly 50% is not low. A low rate that
  rounds to 50% shows as 49%.
- `SessionCredits.load` builds `cacheHits` (same order as `byModel`) and `lowCacheSentences`
  (one per low model, highest credits first) from the same records and prices.
- The sentence names the standard price ratio `cachedInput / input`: one twentieth, one tenth,
  one quarter, half, else "P% of the price". A model with no price or no cached price gets the
  rate sentence only.

### Run-out notices (`RunwayNotice`)

- `RunwayNotice.toSend(usage:now:sentKeys:)` gives the notices to send now, in this order:
  `used80` (80% of the entitlement used), `short` and `critical` (from `RunwayHealth`, critical
  only while credits remain), `limitReached` (no credits remain).
- The key is the kind plus the reset date as an ISO 8601 UTC day, for example
  `used80-2026-11-01`. The app stores sent keys. A key in `sentKeys` does not fire again, and
  the next cycle has a new reset date, so each kind fires once per billing cycle.
- Each kind is independent. A more severe notice does not cancel a less severe one that was
  never sent. `critical` and `limitReached` never fire together, because one needs credits left
  and the other needs none.
- Missing usage, an unlimited plan, and usage from a past cycle (now at or after the reset)
  give no notices.

## Quota summary (`QuotaSummary`)

"Copy summary" puts this plain text on the clipboard. It holds only numbers, dates, model names and
category names: no login, org, token, file path, prompt or command. At most 13 lines.

```
GitHub Copilot AI credits, cycle 2026-10-01 to 2026-10-31 (UTC)
Used: 6,000 of 12,000 credits (50% remaining)
Average daily burn: 600 credits/day
Projected run-out: 2026-10-21, before the reset on 2026-11-01
Outcomes: 10 PRs (8 merged, 2 open), 20 PRs reviewed; 600 credits per PR authored
Top models (share of 1,300 credits in local sessions):
- GPT-6.1 Sol: 900 credits (69%)
- GPT-6 Luna: 300 credits (23%)
- Gemini 3.8 Flash: 60 credits (5%)
Top categories (same local sessions):
- Implementation: 700 credits (54%)
- Investigation: 400 credits (31%)
- Planning: 150 credits (11%)
```

- Cycle dates, reset and run-out dates are UTC days in ISO 8601. Numbers use `en_US` grouping,
  so the text is the same on every machine.
- Used, remaining and the average daily burn come from the GitHub API. Shares are of the priced
  local session total, allocated over all models or categories before the top 3 are listed (see
  `Credits.sharePercents`), so the category percents equal the By task card. Models without a price are left out.
- When the run-out falls on or after the reset, the line says "after the reset on <date>".
  Unlimited plans have no limit and no run-out line. Sections with no local credits are left out.
- The outcomes line holds only the PR and PR reviewed counts and credits per PR authored, no
  organization or repo name. It has no commits. It is left out until an organization is set and the
  first search succeeds. "PRs" is open plus merged PRs (see GitHub outcomes). With no PRs it says
  "credits per PR authored: none, no PRs yet".

## GitHub outcomes (`GitHubOutcomesClient`)

Outcomes are counted for the `gh` user (`@me`) in one organization, set in Settings and stored in
`UserDefaults` under `githubOrganization`. With no organization the app works as before and the
dashboard asks for one.

The client runs `gh api graphql` and `gh api search/commits` through `Process`, with gh found the same
way as for `gh auth token`. gh reads its own login, so the app never reads or passes the token for these
calls. `<cycle start>` is `Runway.cycleStart` in ISO 8601 UTC, for example `2026-10-01T00:00:00Z`.

One refresh (`GitHubOutcomesClient.fetchActivity`) runs these gh processes, in this order:

| Request | Runs | Command |
|---|---|---|
| Commits | Organization set | `gh api --method=GET search/commits -f q=<commit search> -f per_page=1` |
| Login | Organization set, first refresh of the app session | `gh api graphql -f query={ viewer { login } }` |
| First page of every search | Every refresh | `gh api graphql -f query=<document> -f openQuery=<search> -f mergedQuery=<search> -f reviewedQuery=<search> -f login=<login> -f copilotQuery=<search>` |
| Later pages | Only for a search that has more pages, one search per request | `gh api graphql -f query=<document> -f q=<search> [-f login=<login>] -f after=<cursor>` |

The searches in the GraphQL request, one alias each:

| Alias | Search | Reads |
|---|---|---|
| `openPullRequests` | `org:<org> is:pr author:@me is:open created:>=<cycle start>` | `issueCount`, with `first: 0` |
| `mergedPullRequests` | `org:<org> is:pr author:@me is:merged created:>=<cycle start>` | `issueCount`, with `first: 0` |
| `reviewed` | `org:<org> is:pr reviewed-by:@me -author:@me updated:>=<cycle start>` | Your last review on each PR, 100 PRs per page |
| `copilotReviews` | `author:@me is:pr updated:>=<cycle start>` | The reviews on each PR, 100 PRs per page |

The commit search is `author:@me author-date:>=<cycle start> user:<org>`. These are the qualifiers that
`gh search commits --owner` sent before. GraphQL search has no commit type, so commits use REST.

- Without an organization the GraphQL request holds only `copilotReviews`, and the commits and login
  requests do not run. GraphQL rejects a declared variable that the document does not use, so
  `outcomesDocument(includesOrganization:)` gives one document for each case.
- Request count: 1 gh process per refresh without an organization. With an organization, 2 per refresh,
  and 3 on the first refresh, which also gets the login. Each later page adds 1. Before, a refresh with
  an organization ran at least 5 (`gh search prs`, the login, the reviewed pages, `gh search commits`
  and the Copilot review pages), and `gh search prs` and `gh search commits` downloaded up to 1,000
  results each. In October 2026 one account had 33 candidates in each paged search, so a refresh went
  from 5 processes to 2.
- Only counts leave Core. The PR counts read only `issueCount`, the commit count reads only
  `total_count`, and the paged searches decode only review dates and reviewer logins. No PR title, repo
  name or commit message is kept.
- Each value goes in as a `-f` field (a GraphQL string variable, or a REST query field), never into the
  query document. A `-f` value has the form `name=value`, so an organization that starts with `-` stays
  a value. `--method=GET` puts the REST fields in the URL query. Without it gh sends a POST.
- The organization must be a GitHub login (ASCII letters, digits and hyphens, not starting with a
  hyphen). Any other value gives "Organization not found" before an organization request runs, because
  the organization goes into search strings, where a space or `:` could add qualifiers.
- PRs: the PRs created in the cycle that are open or merged, so PRs = `openPullRequests` +
  `mergedPullRequests`. A PR closed without a merge does not count. A draft is open, so it counts. The
  values are in `GitHubOutcomes.prsMerged` and `GitHubOutcomes.prsOpen`, and `prs` is their sum.
  `issueCount` is the exact total, also above 1,000. In October 2026 one account
  had 2 open and 17 merged PRs, the same 19 as the old list search.
- PRs reviewed: search has no review date qualifier. `reviewed-by:@me` matches a PR that you reviewed
  at any time, and `updated:` filters on any PR activity. So the search
  `org:<org> is:pr reviewed-by:@me -author:@me updated:>=<cycle start>` only finds candidates. For each
  candidate the query reads your last submitted review (`reviews(author: $login, last: 1, states:
  [APPROVED, CHANGES_REQUESTED, COMMENTED, DISMISSED])`), and the PR counts only if its `submittedAt`
  is at or after the cycle start. A pending review has no `submittedAt`, and the states filter leaves
  it out. Search gives one node per PR, so each PR counts once. In October 2026 this changed one
  account's count from 32 to 23: 9 PRs had their last review before the cycle and only changed in it.
- `reviews(author:)` needs the login, and GraphQL cannot pass `viewer.login` into it in the same query,
  so the login comes from a separate call. `UsageStore` gets it on the first refresh with an
  organization and keeps it in memory until the app quits. It is not written to disk. A `gh auth switch`
  to another account takes effect after the app restarts. `viewerLatestReview` needs no login, but it
  has no states filter and its behavior with a pending review is not documented, so it is not used.
- `-author:@me` removes your own PRs: without it, `reviewed-by:@me` also matches your PRs where you
  replied to a review.
- gh exits with 1 when the response has an `errors` list, and stderr is classified as for search. The
  parser also rejects an `errors` list, so a response with exit 0 never counts as 0. The messages are
  classified like stderr and never go to the UI.
- An unknown organization gives 0 results in GraphQL search, not an error. REST search gives HTTP 422
  with "cannot be searched", so the commits request runs first and reports it.
- A failed organization request (an invalid name, the commits request or the login request) fails only
  the outcomes. The GraphQL request then runs without the organization searches, so the Copilot review
  count still loads. A failed GraphQL request fails both.
- Commits: commit search covers only the default branch of each repo, so commits on branches that are
  not merged do not count. `author-date` is the date the commit was written, not pushed.
  `total_count` is the exact total, also above 1,000.
- Credits per PR authored = `credits_used` from the usage API / PRs. PRs reviewed and commits are
  shown as counts but are not in the divisor. With 0 PRs there is no value. `credits_used` is all Copilot use on
  the account, also outside the organization.

### Copilot code reviews

This count is separate from PRs reviewed. It counts Copilot code reviews on your own PRs.

- What it counts: reviews by `copilot-pull-request-reviewer` with `submittedAt` at or after the cycle
  start, on PRs where you are the author.
- The query: the `copilotReviews` alias in the outcomes request, with search type `ISSUE` and the search
  `author:@me is:pr updated:>=<cycle start>`. It reads `reviews(first: 100)` for each PR. Later pages
  use `copilotReviewDocument` with `-f q=<search> -f after=<cursor>`. There is no organization
  qualifier, because automatic reviews bill the PR author on any repo. The count does not need the
  organization setting: without one, the request holds only this search.
- Only the reviewer login and `submittedAt` are decoded. No PR title, repo name or review text is kept.
- The app refreshes this count in the same request as the outcomes, on the 30 minute schedule. An error
  hides the count, and the count is nil until the first request succeeds.
- The popover and the dashboard By model card show the count in a line under the "Not in local sessions"
  item (`ShareBreakdown.copilotReviewNote`), for example "Likely 14 Copilot reviews, ~95 each". The
  credits per review are that item's credits divided by the count. The line is hidden without reviews,
  without that item, and when a local model has no price, because the item then holds that model's use too.
- Limits:
  - It does not count reviews that you requested on other people's PRs. Those reviews also bill you.
  - It counts reviews on PRs where the organization pays. Those reviews do not use your credits.
  - It counts reviews, not credits. The API the app can read has no per-feature credit split. Exact
    credits need the billing `ai_credit/usage` endpoint with the user token scope (rows with model
    `Code Review model`). The app does not use that endpoint.

### Limits

- The search API allows 30 requests per minute, and GitHub also has a secondary rate limit.
  In October 2026, 8 fast searches after a few others hit the secondary limit.
- Search returns at most 1,000 results per query. The PR and commit counts are totals, so they are
  exact. The reviewed and Copilot review counts stop after 1,000 candidates, and show the matches among
  them. Such a count is then a lower bound, but it shows no `+`.
- So outcomes refresh on launch (after the first good usage response, which gives the cycle start),
  when the organization changes, and when a credits refresh finds the last search 30 minutes old or
  more (`OutcomesFetch.isDue`). A new cycle start also refreshes. The organization saves on Return or
  when Settings closes, not on each key. The searches run off the main thread.

### Errors

gh stderr can hold the organization and the query, so it never reaches the UI. `GitHubOutcomesClient.error`
maps it to one short line. For a REST error gh writes only the status, for example
`gh: Validation Failed (HTTP 422)`, to stderr, and the response body to stdout. So after a failed exit
the client classifies stderr and stdout together. The samples are what gh 2.102 printed in October 2026.

| Error | Signal |
|---|---|
| gh missing | No gh in the install folders, or it does not start |
| Not logged in | Exit status 4 ("please run: gh auth login"), or `401` / `Bad credentials` in the output |
| Organization not found or no access | "cannot be searched either because the resources do not exist or you do not have permission" |
| Rate limited | "rate limit" in the output, for example "HTTP 403: You have exceeded a secondary rate limit" |
| Other | Any other failure, gh still running after 30 seconds, a commit response without `total_count`, or a GraphQL response that does not decode |

After an error the app keeps the last outcome counts, hides the Copilot review count, and tries again
after 30 minutes.

## Release check (`ReleaseCheck`)

- The app requests `https://api.github.com/repos/wilsonfaustino/copilot-runway/releases/latest` with the
  `Accept: application/vnd.github+json` header. The request has no `Authorization` header and no `gh` call.
- The check reads `tag_name` and removes a leading `v`.
- The numeric dot components are compared. Missing components count as 0, so `0.2` equals `0.2.0`.
  A version that does not parse never counts as an update.
- The app runs the check on launch and at most once every 24 hours. A failure keeps the last result
  and shows no error.
- When a newer version exists, the UI offers "Copy brew command", which copies `brew upgrade --cask copilot-runway`.

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
