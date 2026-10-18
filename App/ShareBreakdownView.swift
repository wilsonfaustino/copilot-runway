import Core
import SwiftUI

// The split bar and legend of a ShareBreakdown, shared by the dashboard cards and the popover.
struct ShareBreakdownView: View {
  let breakdown: ShareBreakdown
  // Items without a color are the folded "Other models" item.
  let colors: [ShareItem.ID: Color]
  // Low cache hit percent by model item.
  var lowCachePercents: [ShareItem.ID: Int] = [:]
  // Models with no price get a legend row and no bar part.
  var unpricedModels: [(id: String, name: String)] = []
  // Shows a share above 0 that rounds to 0% as "<1%".
  var marksSmallShares = false
  // A line under the "Not in local sessions" item.
  var notInLocalSessionsNote: String?

  private static let partSpacing: CGFloat = 2
  private static let swatchSize: CGFloat = 10
  private static let swatchRadius: CGFloat = 2

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
      if !breakdown.isEmpty {
        splitBar
      }
      VStack(alignment: .leading, spacing: 7) {
        ForEach(breakdown.items) { item in
          legendRow(id: item.id, name: item.name, italic: item.kind == .notInLocalSessions, swatch: itemFill(item)) {
            Text(Credits.formatted(item.credits))
              .foregroundStyle(.secondary)
            Text(marksSmallShares ? Credits.shareLabel(item.credits, of: breakdown.shareTotal) : "\(item.share)%")
              .foregroundStyle(.secondary)
              .frame(minWidth: 36, alignment: .trailing)
          }
          if item.kind == .notInLocalSessions, let notInLocalSessionsNote {
            Text(notInLocalSessionsNote)
              .captionStyle()
              .padding(.leading, Self.swatchSize + Theme.Spacing.regular)
          }
        }
        ForEach(unpricedModels, id: \.id) { model in
          legendRow(
            id: .entry(model.id), name: model.name, italic: false,
            swatch: RoundedRectangle(cornerRadius: Self.swatchRadius).strokeBorder(Color.secondary)
          ) {
            Text("no price")
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  // One part per item with credits, 2 pt apart, each as wide as its share of the credits.
  private var splitBar: some View {
    let barItems = breakdown.items.filter { $0.credits > 0 }
    return GeometryReader { proxy in
      let partsWidth = max(proxy.size.width - Self.partSpacing * CGFloat(barItems.count - 1), 0)
      HStack(spacing: Self.partSpacing) {
        ForEach(barItems) { item in
          itemFill(item)
            .frame(width: partsWidth * CGFloat(item.credits / breakdown.shareTotal))
        }
      }
    }
    .frame(height: Self.swatchSize)
  }

  @ViewBuilder
  private func itemFill(_ item: ShareItem) -> some View {
    let shape = RoundedRectangle(cornerRadius: Self.swatchRadius)
    if item.kind == .notInLocalSessions {
      DiagonalStripes(color: Theme.notInLocalSessionsStripe)
        .clipShape(shape)
    } else {
      shape.fill(colors[item.id] ?? Theme.otherModelsColor)
    }
  }

  private func legendRow<Swatch: View, Values: View>(
    id: ShareItem.ID, name: String, italic: Bool, swatch: Swatch, @ViewBuilder values: () -> Values
  ) -> some View {
    HStack(spacing: Theme.Spacing.regular) {
      swatch
        .frame(width: Self.swatchSize, height: Self.swatchSize)
      Text(name)
        .italic(italic)
        .foregroundStyle(italic ? .secondary : .primary)
      if let lowCachePercent = lowCachePercents[id] {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Image(systemName: "exclamationmark.circle")
            .accessibilityHidden(true)
          Text("cache hit \(lowCachePercent)%")
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Theme.accent(.short))
      }
      Spacer()
      values()
    }
    .font(.system(size: 12.5))
    .monospacedDigit()
    .lineLimit(1)
    .accessibilityElement(children: .combine)
  }
}

// Stripes at 135 degrees, 2 pt wide with 2 pt of space, like the gap in the mockup.
struct DiagonalStripes: View {
  let color: Color

  var body: some View {
    Canvas { context, size in
      // A 4 pt period across the stripes is 4 * sqrt(2) pt along the x axis.
      let horizontalPeriod = 4 * 2.0.squareRoot()
      var stripes = Path()
      var stripeStart = -size.height
      while stripeStart < size.width {
        stripes.move(to: CGPoint(x: stripeStart, y: size.height))
        stripes.addLine(to: CGPoint(x: stripeStart + size.height, y: 0))
        stripeStart += horizontalPeriod
      }
      context.stroke(stripes, with: .color(color), lineWidth: 2)
    }
  }
}
