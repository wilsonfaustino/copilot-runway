import Foundation

// What the gauges and their percent show: the credits left in the cycle, or the credits spent.
public enum GaugeMode: String, Sendable {
  case left
  case spent

  // The popover ring sweeps from this fraction to the gauge fraction: down from full for left, up from empty for spent.
  public var sweepStartFraction: Double {
    switch self {
    case .left: 1
    case .spent: 0
    }
  }
}
