import Core
import SwiftUI

// The popover ring's horseshoe at tile size, with the percent in the middle.
struct HorseshoeRing: View {
  let tile: GaugeTile
  let color: Color
  var diameter: CGFloat = 56
  var lineWidth: CGFloat = 6
  var showsPercent = true

  private func horseshoe(fraction: Double, color: Color) -> some View {
    Circle()
      .trim(from: 0, to: RunwayGlyph.trackSweepDegrees / 360 * fraction)
      .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
      .rotationEffect(.degrees(RunwayGlyph.trackStartDegrees))
  }

  var body: some View {
    ZStack {
      horseshoe(fraction: 1, color: color.opacity(RunwayGlyph.trackOpacity))
      if tile.parts.portkey > 0 {
        horseshoe(fraction: tile.parts.total, color: color.opacity(RunwayGlyph.portkeyOpacity))
      }
      if tile.parts.copilot > 0 {
        horseshoe(fraction: tile.parts.copilot, color: color)
      }
      if showsPercent {
        Text("\(tile.percent)%")
          .font(.system(size: 12, weight: .semibold))
          .monospacedDigit()
      }
    }
    .padding(lineWidth / 2)
    .frame(width: diameter, height: diameter)
  }
}
