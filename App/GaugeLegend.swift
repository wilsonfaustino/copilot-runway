import Core
import SwiftUI

// Two swatches under a combined gauge: Copilot in the full tone, Portkey in the 0.6 tone.
struct GaugeLegend: View {
  let amountsUSD: GaugeParts
  let color: Color

  var body: some View {
    HStack(spacing: Theme.Spacing.regular) {
      item(label: "Copilot", amountUSD: amountsUSD.copilot, opacity: 1)
      item(label: "Portkey", amountUSD: amountsUSD.portkey, opacity: RunwayGlyph.portkeyOpacity)
    }
  }

  private func item(label: String, amountUSD: Double, opacity: Double) -> some View {
    HStack(spacing: Theme.Spacing.tight) {
      Circle()
        .fill(color.opacity(opacity))
        .frame(width: 8, height: 8)
      Text("\(label) \(PortkeySpend.formatted(amountUSD))")
        .captionStyle()
        .monospacedDigit()
    }
    .accessibilityElement(children: .combine)
  }
}
