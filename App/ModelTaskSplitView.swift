import Core
import SwiftUI

// The dashboard By model rows: each model bar is full width and split by the task mix of that model.
// The row label keeps the share of all credits, so models compare in the labels.
struct ModelTaskSplitView: View {
  let breakdown: ShareBreakdown
  let taskSplit: ModelTaskSplit
  let taskPalette: TaskPalette
  // A line under the "Not in local sessions" item.
  var notInLocalSessionsNote: String?

  @State private var hoveredSegment: HoveredSegment?

  private struct HoveredSegment: Equatable {
    let itemID: ShareItem.ID
    let category: TaskCategory
  }

  private static let dimmedOpacity = 0.35
  private static let segmentSpacing: CGFloat = 2
  private static let barHeight: CGFloat = 10
  private static let swatchSize: CGFloat = 10
  private static let swatchRadius: CGFloat = 2
  private static let legendHoverScale: CGFloat = 1.15
  private static let legendHoverAnimation = Animation.easeOut(duration: 0.12)

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: Theme.Spacing.regular, alignment: .leading)], spacing: 4) {
        ForEach(taskSplit.categories, id: \.self) { category in
          HStack(spacing: Theme.Spacing.small) {
            RoundedRectangle(cornerRadius: Self.swatchRadius)
              .fill(Theme.taskColor(category, palette: taskPalette))
              .frame(width: Self.swatchSize, height: Self.swatchSize)
            Text(category.displayName)
          }
          .captionStyle()
          .lineLimit(1)
          .scaleEffect(hoveredSegment?.category == category ? Self.legendHoverScale : 1, anchor: .leading)
          .animation(Self.legendHoverAnimation, value: hoveredSegment?.category == category)
        }
      }
      VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
        ForEach(breakdown.items) { item in
          VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            HStack(spacing: Theme.Spacing.regular) {
              Text(item.name)
                .italic(item.kind == .notInLocalSessions)
                .foregroundStyle(item.kind == .notInLocalSessions ? .secondary : .primary)
              Spacer()
              Text(Credits.formatted(item.credits))
                .foregroundStyle(.secondary)
              Text("\(item.share)%")
                .foregroundStyle(.secondary)
                .frame(minWidth: 36, alignment: .trailing)
            }
            .font(.system(size: 12.5))
            .monospacedDigit()
            .lineLimit(1)
            bar(item)
              .accessibilityHidden(true)
          }
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(item.name)
          .accessibilityValue(taskSplit.rowSummary(for: item))
          if item.kind == .notInLocalSessions, let notInLocalSessionsNote {
            Text(notInLocalSessionsNote)
              .captionStyle()
          }
        }
      }
    }
  }

  @ViewBuilder
  private func bar(_ item: ShareItem) -> some View {
    let shape = RoundedRectangle(cornerRadius: Self.swatchRadius)
    if item.kind == .notInLocalSessions {
      DiagonalStripes(color: Theme.notInLocalSessionsStripe)
        .clipShape(shape)
        .frame(height: Self.barHeight)
    } else {
      let segments = taskSplit.segments[item.id] ?? []
      let segmentsTotal = segments.reduce(0) { $0 + $1.credits }
      let segmentPercents = taskSplit.segmentPercents[item.id] ?? []
      GeometryReader { proxy in
        let segmentsWidth = max(proxy.size.width - Self.segmentSpacing * CGFloat(segments.count - 1), 0)
        HStack(spacing: Self.segmentSpacing) {
          ForEach(Array(segments.enumerated()), id: \.element.category) { index, segment in
            let thisSegment = HoveredSegment(itemID: item.id, category: segment.category)
            // The other segments of the hovered bar dim, so the highlight does not rely on color alone.
            let isDimmed = hoveredSegment?.itemID == item.id && hoveredSegment != thisSegment
            shape
              .fill(Theme.taskColor(segment.category, palette: taskPalette))
              .opacity(isDimmed ? Self.dimmedOpacity : 1)
              .frame(width: segmentsWidth * CGFloat(segment.credits / segmentsTotal))
              .contentShape(Rectangle())
              .onHover { isHovering in
                if isHovering {
                  hoveredSegment = thisSegment
                } else if hoveredSegment == thisSegment {
                  hoveredSegment = nil
                }
              }
              .help(ModelTaskSplit.segmentSummary(segment, percent: segmentPercents[index]))
          }
        }
      }
      .frame(height: Self.barHeight)
    }
  }
}
