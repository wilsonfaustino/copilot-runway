import Core
import SwiftUI

struct PopoverView: View {
  let usageStore: UsageStore
  @AppStorage("localOnlyNoticeDismissed") private var localOnlyNoticeDismissed = false
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Copilot Runway")
        .font(.headline)
      if !localOnlyNoticeDismissed {
        HStack(alignment: .firstTextBaseline) {
          Text("Local only: no telemetry. The only network calls go to api.github.com.")
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
          Button("Dismiss") { localOnlyNoticeDismissed = true }
            .controlSize(.small)
        }
      }
      if let usage = usageStore.usage {
        LabeledContent(
          "Used",
          value: usage.isUnlimited
            ? "\(credits(usage.creditsUsed)) (unlimited)"
            : "\(credits(usage.creditsUsed)) / \(credits(usage.entitlement))"
        )
      }
      if let averageDailyBurn = usageStore.averageDailyBurn {
        LabeledContent("Daily burn", value: "\(credits(averageDailyBurn)) / day")
      }
      if !usageStore.modelCredits.isEmpty {
        Divider()
        Text("This cycle, from local sessions")
          .font(.caption)
          .foregroundStyle(.secondary)
        ForEach(usageStore.modelCredits, id: \.model) { modelCredits in
          LabeledContent(modelCredits.model, value: modelCredits.credits.map(credits) ?? "no price")
        }
      }
      if let sessionsWarning = usageStore.sessionsWarning {
        Text(sessionsWarning)
          .foregroundStyle(.orange)
      }
      if let errorMessage = usageStore.errorMessage {
        Text(errorMessage)
          .foregroundStyle(.red)
      }
      if let lastRefresh = usageStore.lastRefresh {
        Text("Updated \(lastRefresh.formatted(date: .omitted, time: .shortened))")
          .foregroundStyle(.secondary)
      }
      HStack {
        Button("Open dashboard") {
          openWindow(id: DashboardView.windowId)
          // The app has no Dock icon, so it must come forward or the window opens behind other apps.
          NSApplication.shared.activate()
        }
        Spacer()
        Button("Quit") {
          NSApplication.shared.terminate(nil)
        }
      }
    }
    .padding()
    .frame(width: 300)
  }

  private func credits(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0)))
  }
}
