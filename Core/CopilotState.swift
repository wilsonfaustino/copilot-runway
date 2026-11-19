import Foundation

public enum CopilotState: Equatable, Sendable {
  case copilot
  case portkeyOnly(CopilotAbsence)
  case noPortkeyData(CopilotAbsence)
}
