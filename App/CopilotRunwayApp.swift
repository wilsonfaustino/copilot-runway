import Core
import SwiftUI

@main
struct CopilotRunwayApp: App {
  @State private var usageStore = UsageStore()

  var body: some Scene {
    MenuBarExtra {
      VStack(alignment: .leading, spacing: 8) {
        Text("Copilot Runway")
          .font(.headline)
        if let errorMessage = usageStore.errorMessage {
          Text(errorMessage)
            .foregroundStyle(.red)
        }
        if let lastRefresh = usageStore.lastRefresh {
          Text("Updated \(lastRefresh.formatted(date: .omitted, time: .shortened))")
            .foregroundStyle(.secondary)
        }
        Button("Quit") {
          NSApplication.shared.terminate(nil)
        }
      }
      .padding()
    } label: {
      Text(usageStore.title)
    }
    .menuBarExtraStyle(.window)
  }
}
