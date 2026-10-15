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

## Prices (`PriceTable`)

Bundled rates, in USD per 1 million tokens, from GitHub's
[Models and pricing for GitHub Copilot](https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing):

| Model id | Tier | Input | Cached input | Cache write | Output |
|---|---|---|---|---|---|
| `gpt-6.1-sol` | Default, prompt <= 272K | 2.00 | 0.10 | 2.50 | 10.00 |
| `gpt-6.1-sol` | Long context, prompt > 272K | 4.00 | 0.20 | 5.00 | 15.00 |
| `gpt-6-luna` | Default, prompt <= 272K | 0.10 | 0.01 | 0.125 | 0.50 |
| `gpt-6-luna` | Long context, prompt > 272K | 0.20 | 0.02 | 0.25 | 0.75 |
| `gemini-3.8-flash` | Default, no tier | 0.75 | 0.075 | 0 | 3.75 |

- The same page says: "1 AI credit = $0.01 USD". So credits = USD x 100.
- GitHub lists a cache write rate for these models, so the table has one.
- Tier rule: the long context rates apply to the whole request when
  input + cached input + cache write > 272,000. Exactly 272,000 uses the default rates.
  The GitHub page labels the threshold "input tokens" and does not define it further.
  Pi stores per message costs that match this rule exactly.
- Credits are computed per message and then summed per model, because the tier depends on each request.
- The Gemini 3.8 Flash rate is promotional "through December 31, 2026" (footnote on the same page).
  GitHub lists no cache write rate for Google models, so it is 0. Pi records 0 cache write tokens for it.
- Models without a price show as "no price".

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
