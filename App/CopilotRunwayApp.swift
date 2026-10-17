import SwiftUI

@main
struct CopilotRunwayApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    Window("Copilot Runway", id: DashboardView.windowId) {
      DashboardView(usageStore: appDelegate.usageStore)
    }
    .defaultSize(width: 760, height: 640)
    .defaultLaunchBehavior(Self.dashboardLaunchBehavior)
    Settings {
      SettingsView(usageStore: appDelegate.usageStore)
    }
  }

  #if DEBUG
  private static let dashboardLaunchBehavior: SceneLaunchBehavior = DemoLaunch.opensDashboard ? .presented : .suppressed
  #else
  private static let dashboardLaunchBehavior: SceneLaunchBehavior = .suppressed
  #endif
}
