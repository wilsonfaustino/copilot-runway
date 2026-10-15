import Core
import SwiftUI

@main
struct CopilotRunwayApp: App {
  @State private var usageStore = UsageStore()

  var body: some Scene {
    MenuBarExtra {
      PopoverView(usageStore: usageStore)
    } label: {
      HStack {
        if let usageError = usageStore.usageError {
          Image(systemName: RunwayGlyph.menuBarSymbolName(error: usageError))
        } else {
          let health = RunwayHealth(usage: usageStore.usage, hasError: false, now: .now)
          Image(nsImage: RunwayGlyph.menuBarImage(health: health))
        }
        Text(usageStore.title)
      }
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
