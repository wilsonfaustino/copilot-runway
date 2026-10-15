import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent"
import { truncateToWidth } from "@earendil-works/pi-tui"
import { execFile } from "node:child_process"
import { readFile, writeFile } from "node:fs/promises"
import { homedir } from "node:os"
import { basename, join } from "node:path"
import { promisify } from "node:util"
import { type CopilotCredits, formatOmpLine, formatStatusLines } from "./format.ts"

const execFileAsync = promisify(execFile)
const AUTH_FILE = join(homedir(), ".pi/agent/auth.json")
// Outside extensions/ so the extension loader never scans it.
const STYLE_FILE = join(homedir(), ".pi/agent/statusline-style")
const STYLES = ["custom", "omp"] as const
type Style = (typeof STYLES)[number]
const USAGE_URL = "https://api.github.com/copilot_internal/user"
const COPILOT_REFRESH_INTERVAL_MS = 5 * 60 * 1000
const FAILED_COPILOT_LABEL = "Copilot ?"
const GIT_NO_FSMONITOR = ["-c", "core.useBuiltinFSMonitor=false", "-c", "core.fsmonitor=false"]

// Same request as ~/.config/opencode/cli-plugins/copilot-credits, but with Pi's own token.
async function fetchCopilotCredits(): Promise<CopilotCredits> {
  const auth = JSON.parse(await readFile(AUTH_FILE, "utf8"))
  const githubToken = auth["github-copilot"]?.refresh
  if (!githubToken) throw new Error("no github-copilot token in auth.json")
  const response = await fetch(USAGE_URL, {
    headers: { Authorization: `token ${githubToken}`, Accept: "application/json", "Editor-Version": "vscode/1.99.0" },
  })
  if (!response.ok) throw new Error(`copilot usage HTTP ${response.status}`)
  const body = await response.json()
  const premium = body.quota_snapshots?.premium_interactions
  if (!premium) throw new Error("no premium_interactions in copilot usage response")
  // Unlimited plans report entitlement 0, so there is no quota to divide by.
  const hasEntitlement = premium.entitlement > 0
  const usagePercentage = hasEntitlement ? Math.round((premium.credits_used / premium.entitlement) * 100) : 0
  const usageLabel = hasEntitlement
    ? `Copilot: ${premium.credits_used}/${premium.entitlement} (${usagePercentage}%)`
    : `Copilot: ${premium.credits_used} used`
  if (!body.quota_reset_date) return { usageLabel, usagePercentage, resetLabel: "" }
  const millisecondsPerDay = 24 * 60 * 60 * 1000
  const daysUntilReset = Math.ceil((Date.parse(body.quota_reset_date) - Date.now()) / millisecondsPerDay)
  return { usageLabel, usagePercentage, resetLabel: ` · Reset in ${daysUntilReset} day${daysUntilReset === 1 ? "" : "s"}` }
}

// Exit code 1 from `git diff --quiet` means "has changes", so a rejected promise is the dirty signal.
async function readGitFlags(cwd: string): Promise<string> {
  const git = (...args: string[]) => execFileAsync("git", [...GIT_NO_FSMONITOR, ...args], { cwd })
  const isDirty = (...args: string[]) => git(...args).then(() => false, () => true)
  const [unstaged, staged, untracked] = await Promise.all([
    isDirty("diff", "--quiet"),
    isDirty("diff", "--cached", "--quiet"),
    git("ls-files", "--others", "--exclude-standard").then(({ stdout }) => stdout.length > 0, () => false),
  ])
  return `${unstaged ? "!" : ""}${staged ? "+" : ""}${untracked ? "?" : ""}`
}

async function readStyle(): Promise<Style> {
  const saved = await readFile(STYLE_FILE, "utf8").then((text) => text.trim(), () => "")
  return saved === "omp" ? "omp" : "custom"
}

function sessionCostUsd(ctx: ExtensionContext): number {
  let costUsd = 0
  // ponytail: full branch scan per render, cache on message_end if long sessions lag
  for (const entry of ctx.sessionManager.getBranch()) {
    if (entry.type === "message" && entry.message.role === "assistant") costUsd += entry.message.usage?.cost?.total ?? 0
  }
  return costUsd
}

export default function (pi: ExtensionAPI) {
  let sessionStartedAt = Date.now()
  let gitFlags = ""
  let copilot: CopilotCredits | undefined
  let requestRender = () => {}
  let style: Style = "custom"

  const refreshGitFlags = (cwd: string) =>
    readGitFlags(cwd).then((flags) => {
      gitFlags = flags
      requestRender()
    })

  const refreshCopilot = () =>
    fetchCopilotCredits()
      .catch((error) => {
        console.error("[statusline]", error.message)
        return { usageLabel: FAILED_COPILOT_LABEL, usagePercentage: 0, resetLabel: "" }
      })
      .then((credits) => {
        copilot = credits
        requestRender()
      })

  pi.on("session_start", async (_event, ctx) => {
    if (ctx.hasUI === false) return
    style = await readStyle()
    sessionStartedAt = Date.now()
    refreshGitFlags(ctx.cwd)
    refreshCopilot()

    ctx.ui.setFooter((tui, _theme, footerData) => {
      requestRender = () => tui.requestRender()
      const unsubscribeBranch = footerData.onBranchChange(requestRender)
      const durationTicker = setInterval(requestRender, 1000)
      const copilotTicker = setInterval(refreshCopilot, COPILOT_REFRESH_INTERVAL_MS)

      return {
        dispose() {
          unsubscribeBranch()
          clearInterval(durationTicker)
          clearInterval(copilotTicker)
          requestRender = () => {}
        },
        invalidate() {},
        render(width: number): string[] {
          const usage = ctx.getContextUsage()
          if (style === "omp") {
            const ompLine = formatOmpLine({
              contextPercent: Math.round(usage?.percent ?? 0),
              contextWindow: ctx.model?.contextWindow,
              model: ctx.model?.name ?? ctx.model?.id ?? "Unknown",
              thinkingLevel: pi.getThinkingLevel(),
              dirName: basename(ctx.cwd),
              branch: footerData.getGitBranch() ?? undefined,
              gitFlags,
              copilot,
            })
            return [truncateToWidth(ompLine, width)]
          }
          const lines = formatStatusLines({
            contextPercent: Math.round(usage?.percent ?? 0),
            contextTokens: usage?.tokens ?? 0,
            model: ctx.model?.name ?? ctx.model?.id ?? "Unknown",
            durationMs: Date.now() - sessionStartedAt,
            costUsd: sessionCostUsd(ctx),
            dirName: basename(ctx.cwd),
            branch: footerData.getGitBranch() ?? undefined,
            gitFlags,
            copilot,
          })
          return lines.map((line) => truncateToWidth(line, width))
        },
      }
    })
  })

  pi.registerCommand("statusline", {
    description: "Switch footer style: custom or omp (no argument toggles)",
    getArgumentCompletions: (prefix) =>
      STYLES.filter((name) => name.startsWith(prefix)).map((name) => ({ value: name, label: name })),
    handler: async (args, ctx) => {
      const requested = args.trim()
      if (requested && !STYLES.includes(requested as Style)) {
        ctx.ui.notify(`Unknown style "${requested}". Use: ${STYLES.join(", ")}`, "error")
        return
      }
      style = requested ? (requested as Style) : style === "custom" ? "omp" : "custom"
      await writeFile(STYLE_FILE, style)
      requestRender()
      ctx.ui.notify(`Statusline: ${style}`, "info")
    },
  })

  pi.on("tool_execution_end",(_event, ctx) => refreshGitFlags(ctx.cwd))
  pi.on("agent_end", (_event, ctx) => {
    refreshGitFlags(ctx.cwd)
    refreshCopilot()
  })
}
