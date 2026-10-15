// Mirrors ~/.claude/statusline-command.sh so Pi and Claude Code look the same.
const CYAN = "\x1b[36m"
const MAGENTA = "\x1b[35m"
const YELLOW = "\x1b[33m"
const GREEN = "\x1b[32m"
const RED = "\x1b[31m"
const DIM = "\x1b[2m"
const RESET = "\x1b[0m"
const BRANCH_ICON = ""

// Same thresholds as the Claude statusline: context fills fast past a quarter.
const CONTEXT_GREEN_MAX_PERCENT = 11
const CONTEXT_YELLOW_MAX_PERCENT = 25
// Same thresholds as the OpenCode copilot-credits plugin.
const COPILOT_WARNING_PERCENT = 70
const COPILOT_ERROR_PERCENT = 90

export type CopilotCredits = { usageLabel: string; usagePercentage: number; resetLabel: string }

export type StatusInput = {
  contextPercent: number
  contextTokens: number
  model: string
  durationMs: number
  costUsd: number
  dirName: string
  branch?: string
  gitFlags: string
  copilot?: CopilotCredits
}

export function formatTokens(tokens: number): string {
  if (tokens >= 1_000_000) return `${(tokens / 1_000_000).toFixed(1)}M`
  if (tokens >= 1000) return `${Math.floor(tokens / 1000)}k`
  return `${tokens}`
}

export function formatDuration(durationMs: number): string {
  const minutes = Math.floor(durationMs / 60000)
  const seconds = Math.floor((durationMs % 60000) / 1000)
  return `${minutes}m${String(seconds).padStart(2, "0")}s`
}

export function contextColor(contextPercent: number): string {
  if (contextPercent <= CONTEXT_GREEN_MAX_PERCENT) return GREEN
  if (contextPercent <= CONTEXT_YELLOW_MAX_PERCENT) return YELLOW
  return RED
}

export function copilotColor(credits: CopilotCredits): string {
  if (credits.usagePercentage >= COPILOT_ERROR_PERCENT) return RED
  if (credits.usagePercentage >= COPILOT_WARNING_PERCENT) return YELLOW
  return GREEN
}

export function formatStatusLines(status: StatusInput): [string, string] {
  const color = contextColor(status.contextPercent)
  let line1 =
    `${color}${status.contextPercent}%${RESET} | ${color}${formatTokens(status.contextTokens)}${RESET} | ` +
    `${MAGENTA}${status.model}${RESET} ${GREEN}${formatDuration(status.durationMs)}${RESET} ` +
    `${YELLOW}$${status.costUsd.toFixed(2)}${RESET}`
  if (status.copilot?.usageLabel) {
    line1 += ` ${DIM}|${RESET} ${copilotColor(status.copilot)}${status.copilot.usageLabel}${RESET}${DIM}${status.copilot.resetLabel}${RESET}`
  }

  let line2 = `${CYAN}${status.dirName}${RESET}`
  if (status.branch) {
    const flags = status.gitFlags ? ` [${status.gitFlags}]` : ""
    line2 += ` ${DIM}on${RESET} ${RED}${BRANCH_ICON} ${MAGENTA}${status.branch}${RESET}${RED}${flags}${RESET}`
  }
  return [line1, line2]
}

// Approximates the omp composer band (model, dir, branch, context) plus Copilot credits. Nerd font glyphs as omp uses.
const OMP_SEPARATOR = ` ${DIM}\ue0b1${RESET} `
const OMP_MODEL_ICON = "\u{f0238}"
const OMP_DIR_ICON = "\u{f0645}"
const OMP_BRANCH_ICON = "\ue0a0"
const COPILOT_ICON = "\uf4b8"
const COPILOT_WARNING_ICON = "\uf4ba"
const COPILOT_ERROR_ICON = "\uf4b9"

export function copilotIcon(credits: CopilotCredits): string {
  if (credits.usagePercentage >= COPILOT_ERROR_PERCENT) return COPILOT_ERROR_ICON
  if (credits.usagePercentage >= COPILOT_WARNING_PERCENT) return COPILOT_WARNING_ICON
  return COPILOT_ICON
}

export type OmpStatusInput = Pick<StatusInput, "contextPercent" | "model" | "dirName" | "branch" | "gitFlags" | "copilot"> & {
  contextWindow?: number
  thinkingLevel?: string
}

export function formatOmpLine(status: OmpStatusInput): string {
  const thinking = status.thinkingLevel && status.thinkingLevel !== "off" ? `${DIM} · ${status.thinkingLevel}${RESET}` : ""
  const segments = [`${CYAN}${OMP_MODEL_ICON} ${status.model}${RESET}${thinking}`, `${OMP_DIR_ICON} ${status.dirName}`]
  if (status.branch) {
    const flags = status.gitFlags ? ` ${status.gitFlags}` : ""
    segments.push(`${YELLOW}${OMP_BRANCH_ICON} ${status.branch}${flags}${RESET}`)
  }
  const window = status.contextWindow ? ` ${DIM}of ${formatTokens(status.contextWindow)}${RESET}` : ""
  segments.push(`${contextColor(status.contextPercent)}${status.contextPercent}%${RESET}${window}`)
  if (status.copilot?.usageLabel) {
    // The icon replaces the "Copilot:" text prefix, including the "Copilot ?" failure label.
    const usage = status.copilot.usageLabel.replace(/^Copilot:? /, "")
    const icon = copilotIcon(status.copilot)
    segments.push(`${copilotColor(status.copilot)}${icon} ${usage}${RESET}${DIM}${status.copilot.resetLabel}${RESET}`)
  }
  return segments.join(OMP_SEPARATOR)
}
