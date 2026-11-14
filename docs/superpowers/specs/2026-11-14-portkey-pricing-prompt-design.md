# Portkey pricing setup prompt design

Roadmap item 37. Decisions confirmed by the user on 2026-11-14.

## Problem

Portkey has no API that gives model prices. Pi, omp and OpenCode store a USD cost on each Portkey message only
when their own config has a price for the model. Without it, the agent writes a cost of 0 and Copilot Runway
shows the request as unpriced. Users must add prices by hand. The user wrote a private prompt that does this for
Pi on one company gateway. This feature ships a generic version of it in the app.

## Behavior

- A "Copy setup prompt" button copies a prompt that the user pastes into their AI agent. The agent then adds
  `cost` blocks to the agent configs.
- Popover Portkey card: the button shows only when at least one model has an unpriced newest record (per agent
  and model). It is hidden in the share image.
- Settings > Sources: a "Portkey prices" row with the same button, always shown.
- Both places show this caption under the button, verbatim:
  "This prompt asks your AI agent to change its config files. Copilot Runway is not responsible for what the
  agent does. Check each change before you accept it."
- In app only. No README section.

## Prompt content

- One prompt. One section for each agent: Pi, OpenCode, omp.
- With unpriced models: only the sections of agents that have them, each listing its real model ids. The ids come
  from the user's own session files and stay on the Mac until the user pastes them.
- With no unpriced models: all three sections, with `<model id>` placeholders.
- Gateway host is always the placeholder `<your.portkey.gateway.com>`. No company names, hosts, key paths or
  prices in the text.
- Rules (shared): never print, log or copy an API key; redact keys as `REDACTED` when showing a file; back up each
  file before a change; merge, never remove other providers or models; never change the base URL, headers or key
  of a working provider; stop and ask when the files do not match the prompt; show each diff and wait for approval
  before saving.
- Prices: the agent asks the user for each price in USD per 1M tokens (input, output, cache read, cache write).
  It can suggest where to look (the Portkey model catalog, the provider's pricing page). It does not search the
  web or fill in a price itself, unless the user explicitly asks; then it shows the source URL with each value.
  Before it writes, it shows a table of all prices and waits for confirmation.
- If a listed model already has a cost above 0, the agent tells the user and does not change it.
- No step that sets `defaultProvider`, `defaultModel` or `enabledModels`.
- Ends with: restart the agent, send one message, check that Copilot Runway shows a USD amount for it. Old
  messages stay unpriced, because agents do not recalculate them.

## Agent config facts

- Pi: `~/.pi/agent/models.json`, `providers.<provider id>.models[]`, each model `cost: { input, output, cacheRead,
  cacheWrite }`. Proven by the user's private prompt. A provider rename also changes the `<provider>/<model id>`
  strings in `~/.pi/agent/settings.json`.
- omp: `~/.omp/agent/models.yml` (YAML), same `cost` keys as Pi. Read from the omp 18.12.3 binary, not tested end
  to end. The prompt tells the agent to stop and ask when the file differs.
- OpenCode: `~/.config/opencode/opencode.json`, `providers.<provider id>.models.<model id>.cost: { input, output,
  cache: { read, write } }`. Read from the user's config.
- Copilot Runway counts a message as Portkey when the provider id contains `portkey` (any case).
