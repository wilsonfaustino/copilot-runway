import Foundation

extension SessionSource {
  public var displayName: String {
    switch self {
    case .pi: "Pi"
    case .opencode: "OpenCode"
    }
  }
}

extension TaskCategory {
  public var displayName: String { rawValue.capitalized }
}
