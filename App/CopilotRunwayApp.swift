import SwiftUI

@main
struct CopilotRunwayApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @Environment(\.openWindow) private var openWindow

  var body: some Scene {
    let _ = appDelegate.openDashboard = { [openWindow] in openWindow(id: DashboardView.windowId) }
    Window("Copilot Runway", id: DashboardView.windowId) {
      DashboardView(usageStore: appDelegate.usageStore)
    }
    .defaultSize(width: 760, height: 640)
    .defaultLaunchBehavior(.suppressed)
    .commands {
      CommandGroup(replacing: .appSettings) {
        Button("Settings…") { SettingsWindowController.show(usageStore: appDelegate.usageStore) }
          .keyboardShortcut(",")
      }
    }
  }
}
