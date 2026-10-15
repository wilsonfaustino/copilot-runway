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
  }
}
