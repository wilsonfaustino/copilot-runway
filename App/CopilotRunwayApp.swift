import Core
import SwiftUI

@main
struct CopilotRunwayApp: App {
  var body: some Scene {
    MenuBarExtra(MenuBarTitle.placeholder) {
      VStack(alignment: .leading, spacing: 8) {
        Text("Copilot Runway")
          .font(.headline)
        Button("Quit") {
          NSApplication.shared.terminate(nil)
        }
      }
      .padding()
    }
    .menuBarExtraStyle(.window)
  }
}
