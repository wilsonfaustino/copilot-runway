#if DEBUG
import Core
import Foundation
import os

// Debug-only launch arguments: `-demo <scenario>` shows fixed fake data, `-openDashboard` opens the dashboard.
enum DemoLaunch {
  static let scenario: DemoScenario? = {
    guard let launchValue = DemoScenario.launchValue(arguments: ProcessInfo.processInfo.arguments) else { return nil }
    if DemoScenario.Name(rawValue: launchValue) == nil {
      let validNames = DemoScenario.Name.allCases.map(\.rawValue).joined(separator: ", ")
      Logger(subsystem: "dev.wilsonfaustino.CopilotRunway", category: "demo").error(
        "Unknown demo scenario \"\(launchValue, privacy: .public)\". Valid names: \(validNames, privacy: .public). Using typical."
      )
    }
    return DemoScenario(name: DemoScenario.Name(launchValue: launchValue), now: .now)
  }()

  static let isActive = scenario != nil

  static let opensDashboard = ProcessInfo.processInfo.arguments.contains("-openDashboard")
}
#endif
