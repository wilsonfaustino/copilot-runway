import SwiftUI

@main
struct CopilotRunwayApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @Environment(\.openWindow) private var openWindow

  var body: some Scene {
    #if DEBUG
    let _ = appDelegate.openDashboard = { [openWindow] in openWindow(id: DashboardView.windowId) }
    #endif
    Window("Copilot Runway", id: DashboardView.windowId) {
      DashboardView(usageStore: appDelegate.usageStore)
    }
    .defaultSize(width: 760, height: 640)
    .defaultLaunchBehavior(.suppressed)
    Settings {
      SettingsView(usageStore: appDelegate.usageStore)
    }
  }
}
