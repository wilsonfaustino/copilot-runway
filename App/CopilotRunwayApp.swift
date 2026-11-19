import SwiftUI

@main
struct CopilotRunwayApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  // The Dashboard is an AppKit window (DashboardWindowController), so this scene only carries the menu commands.
  var body: some Scene {
    Settings { EmptyView() }
    .commands {
      // The same toggleSidebar(_:) as the toolbar button, sent to the Dashboard split view controller.
      CommandGroup(before: .toolbar) {
        Button(DashboardSidebarMenuState.shared.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
          NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
        }
        .keyboardShortcut("s", modifiers: [.command, .control])
      }
      CommandGroup(replacing: .appSettings) {
        Button("Settings…") { SettingsWindowController.show(usageStore: appDelegate.usageStore) }
          .keyboardShortcut(",")
      }
    }
  }
}
