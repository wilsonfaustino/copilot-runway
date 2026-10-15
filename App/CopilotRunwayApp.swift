import Core
import SwiftUI

@main
struct CopilotRunwayApp: App {
  @State private var usageStore = UsageStore()

  var body: some Scene {
    MenuBarExtra {
      PopoverView(usageStore: usageStore)
    } label: {
      Text(usageStore.title)
    }
    .menuBarExtraStyle(.window)
    Window("Copilot Runway", id: DashboardView.windowId) {
      DashboardView(usageStore: usageStore)
    }
    .defaultSize(width: 760, height: 640)
    Settings {
      SettingsView(usageStore: usageStore)
    }
  }
}
