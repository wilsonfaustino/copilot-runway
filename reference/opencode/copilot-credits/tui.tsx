import { Plugin } from "@opencode/plugin/tui"
import { createSignal } from "solid-js"
import { readFile } from "node:fs/promises"
import { homedir } from "node:os"
import { join } from "node:path"

const AUTH_FILE = join(homedir(), ".local/share/opencode/auth.json")
const USAGE_URL = "https://api.github.com/copilot_internal/user"
const REFRESH_INTERVAL_MS = 5 * 60 * 1000
const WARNING_USAGE_PERCENTAGE = 70
const ERROR_USAGE_PERCENTAGE = 90
const FAILED_LABEL = "PR ?"

async function fetchPremiumCredits() {
  const auth = JSON.parse(await readFile(AUTH_FILE, "utf8"))
  const githubToken = auth["github-copilot"]?.refresh
  if (!githubToken) throw new Error("no github-copilot token in auth.json")
  const response = await fetch(USAGE_URL, {
    headers: {
      Authorization: `token ${githubToken}`,
      Accept: "application/json",
      "Editor-Version": "vscode/1.99.0",
    },
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
  const resetLabel = ` · Reset in ${daysUntilReset} day${daysUntilReset === 1 ? "" : "s"}`
  return { usageLabel, usagePercentage, resetLabel }
}

export default Plugin.define({
  id: "local.copilot-credits",
  setup(context) {
    const [credits, setCredits] = createSignal({ usageLabel: "", usagePercentage: 0, resetLabel: "" })

    const refresh = () =>
      fetchPremiumCredits()
        .then(setCredits)
        .catch((error) => {
          console.error("[copilot-credits]", error.message)
          setCredits({ usageLabel: FAILED_LABEL, usagePercentage: 0, resetLabel: "" })
        })

    refresh()
    const timer = setInterval(refresh, REFRESH_INTERVAL_MS)
    const stopListening = context.data.on("session.execution.succeeded", refresh)

    const usageColor = () => {
      if (credits().usageLabel === FAILED_LABEL) return context.theme.text.muted
      const feedback = context.theme.text.feedback
      if (credits().usagePercentage >= ERROR_USAGE_PERCENTAGE) return feedback.error.base
      if (credits().usagePercentage >= WARNING_USAGE_PERCENTAGE) return feedback.warning.base
      return feedback.success.base
    }

    context.ui.slot({
      append: "prompt.footer",
      render: () => (
        <text fg={context.theme.text.muted}>
          <span style={{ fg: usageColor() }}>{credits().usageLabel}</span>
          {credits().resetLabel}
        </text>
      ),
    })

    return () => {
      clearInterval(timer)
      stopListening()
    }
  },
})
