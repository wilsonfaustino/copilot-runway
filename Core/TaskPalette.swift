import Foundation

public enum TaskPalettePreference: String, Sendable {
  case unset
  case on
  case off
}

public enum TaskPalette: Equatable, Sendable {
  case standard
  case colorblindSafe

  // The stored choice wins. Until the user sets one, the palette follows the macOS "Differentiate without color" setting.
  public static func resolve(preference: TaskPalettePreference, systemDifferentiatesWithoutColor: Bool) -> TaskPalette {
    switch preference {
    case .on: .colorblindSafe
    case .off: .standard
    case .unset: systemDifferentiatesWithoutColor ? .colorblindSafe : .standard
    }
  }
}
