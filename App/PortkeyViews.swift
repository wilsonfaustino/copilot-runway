import Core
import SwiftUI

// Portkey is USD against its own monthly budget. Nothing here feeds a Copilot number.
enum PortkeyText {
  // The agents that can send Portkey traffic, in the column order of the design.
  static let sources: [SessionSource] = [.pi, .opencode, .omp]

  static let costSourceNote = "Portkey cost comes from the price each agent recorded in its session files. No call goes to Portkey."

  static func requests(_ count: Int) -> String {
    count == 1 ? "1 request" : "\(count) requests"
  }
}

struct PortkeyCard: View {
  let spend: PortkeySpend
  let budgetStatus: PortkeyBudget.Status?
  var showsCostSourceNote = true

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
      VStack(alignment: .leading, spacing: 12) {
        header
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(PortkeySpend.formatted(spend.totalUSD))
            .bigFigureStyle()
          Text("this cycle, \(PortkeyText.requests(spend.requestCount))")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        if let budgetStatus {
          Text(budgetStatus.text)
            .font(.system(size: 12.5, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(Theme.accent(budgetStatus.health))
        }
        if spend.totalUSD > 0 {
          PortkeyModelShareBar(spend: spend)
        }
        if !spend.byModel.isEmpty {
          modelRows
          agentTiles
        }
        if let insight = spend.insightSentence() {
          Text(insight)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        if let unpricedNote = spend.unpricedNote {
          Text(unpricedNote)
            .captionStyle()
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .cardStyle(padding: Theme.Spacing.section)
      if showsCostSourceNote {
        Text(PortkeyText.costSourceNote)
          .captionStyle()
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var header: some View {
    HStack(spacing: 8) {
      Image(systemName: "arrow.triangle.branch")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Theme.portkeyModelColor(rank: 0))
        .accessibilityHidden(true)
      Text("Portkey")
        .font(.system(size: 13, weight: .semibold))
      Spacer()
      Text("USD, not credits")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.16)))
    }
  }

  private var modelRows: some View {
    let models = spend.byModel
    let percents = Credits.sharePercents(models.map(\.usd), of: spend.totalUSD)
    return VStack(alignment: .leading, spacing: 8) {
      sectionTitle("By model")
      ForEach(Array(models.enumerated()), id: \.element.model) { rank, modelSpend in
        HStack(spacing: 8) {
          RoundedRectangle(cornerRadius: 2)
            .fill(Theme.portkeyModelColor(rank: rank))
            .frame(width: 8, height: 8)
          Text(ModelDisplayName.portkeyName(for: modelSpend.model))
            .lineLimit(1)
          Spacer()
          Text("\(percents[rank])%")
            .foregroundStyle(.secondary)
          Text(PortkeySpend.formatted(modelSpend.usd))
            .frame(minWidth: 52, alignment: .trailing)
        }
        .font(.system(size: 13))
        .monospacedDigit()
        .accessibilityElement(children: .combine)
      }
    }
  }

  private var agentTiles: some View {
    let spendBySource = Dictionary(uniqueKeysWithValues: spend.bySource.map { ($0.source, $0.usd) })
    return VStack(alignment: .leading, spacing: 8) {
      sectionTitle("By agent")
      HStack(spacing: 8) {
        ForEach(PortkeyText.sources, id: \.self) { source in
          let usd = spendBySource[source] ?? 0
          VStack(alignment: .leading, spacing: 2) {
            Text(source.displayName)
              .captionStyle()
            Text(PortkeySpend.formatted(usd))
              .font(.system(size: 13, weight: .semibold))
              .monospacedDigit()
              .foregroundStyle(usd > 0 ? .primary : .secondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(8)
          .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
          .accessibilityElement(children: .combine)
        }
      }
    }
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(.secondary)
  }
}

// One part per model, in byModel order, sized by USD.
private struct PortkeyModelShareBar: View {
  let spend: PortkeySpend

  var body: some View {
    let models = spend.byModel
    GeometryReader { proxy in
      HStack(spacing: 0) {
        ForEach(Array(models.enumerated()), id: \.element.model) { rank, modelSpend in
          Rectangle()
            .fill(Theme.portkeyModelColor(rank: rank))
            .frame(width: proxy.size.width * modelSpend.usd / spend.totalUSD)
        }
      }
    }
    .frame(height: 8)
    .background(Color.primary.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 4))
    .accessibilityHidden(true)
  }
}

struct PortkeyDashboardSection: View {
  let spend: PortkeySpend
  let budgetStatus: PortkeyBudget.Status?
  let dateRange: String

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
      HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.regular) {
        Text("Portkey")
          .font(.system(size: 20, weight: .semibold))
        Text("\(dateRange), USD. Not part of the Copilot runway.")
          .captionStyle()
        Spacer()
      }
      HStack(alignment: .top, spacing: Theme.Spacing.regular) {
        summaryCard("Spend this cycle", value: PortkeySpend.formatted(spend.totalUSD)) {
          if let budgetStatus {
            Text(budgetStatus.text)
              .font(.system(size: 12))
              .monospacedDigit()
              .foregroundStyle(Theme.accent(budgetStatus.health))
          }
        }
        summaryCard("Requests", value: "\(spend.requestCount)") { EmptyView() }
        summaryCard("Average per request", value: spend.averageUSDPerRequest.map { PortkeySpend.formatted($0) } ?? "--") {
          EmptyView()
        }
      }
      .fixedSize(horizontal: false, vertical: true)
      if spend.byModel.isEmpty {
        Text("No Portkey requests in this cycle.")
          .captionStyle()
      } else {
        modelSourceTable
        agentBars
      }
      Text("\(PortkeyText.costSourceNote) A message without a cost counts as a request and adds \(PortkeySpend.formatted(0)).")
        .captionStyle()
        .fixedSize(horizontal: false, vertical: true)
      if let unpricedNote = spend.unpricedNote {
        Text(unpricedNote)
          .captionStyle()
      }
    }
  }

  private func summaryCard<Detail: View>(_ title: String, value: String, @ViewBuilder detail: () -> Detail) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.small) {
      Text(title)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
      Text(value)
        .bigFigureStyle(size: 26)
      detail()
    }
    .lineLimit(1)
    .minimumScaleFactor(0.6)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .cardStyle(padding: Theme.Spacing.panel)
  }

  private var modelSourceTable: some View {
    let sourceTotals = Dictionary(uniqueKeysWithValues: spend.bySource.map { ($0.source, $0.usd) })
    return VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
      Text("By model and agent")
        .font(DashboardView.cardTitleFont)
      Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 8) {
        GridRow {
          Text("Model")
            .gridColumnAlignment(.leading)
          ForEach(PortkeyText.sources, id: \.self) { source in
            Text(source.displayName)
          }
          Text("Total")
        }
        .captionStyle()
        Divider()
        ForEach(Array(spend.byModel.enumerated()), id: \.element.model) { rank, modelSpend in
          GridRow {
            HStack(spacing: 8) {
              RoundedRectangle(cornerRadius: 2)
                .fill(Theme.portkeyModelColor(rank: rank))
                .frame(width: 8, height: 8)
              Text(ModelDisplayName.portkeyName(for: modelSpend.model))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(PortkeyText.sources, id: \.self) { source in
              if let cell = spend.cell(model: modelSpend.model, source: source) {
                VStack(alignment: .trailing, spacing: 2) {
                  Text(PortkeySpend.formatted(cell.usd))
                  Text("\(cell.requestCount) req")
                    .captionStyle()
                }
              } else {
                Text("none")
                  .foregroundStyle(.secondary)
              }
            }
            Text(PortkeySpend.formatted(modelSpend.usd))
              .fontWeight(.semibold)
          }
        }
        Divider()
        GridRow {
          Text("All models")
          ForEach(PortkeyText.sources, id: \.self) { source in
            let usd = sourceTotals[source] ?? 0
            Text(PortkeySpend.formatted(usd))
              .foregroundStyle(usd > 0 ? .primary : .secondary)
          }
          Text(PortkeySpend.formatted(spend.totalUSD))
        }
        .fontWeight(.semibold)
      }
      .font(.system(size: 12.5))
      .monospacedDigit()
      .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardStyle(padding: Theme.Spacing.panel)
  }

  private var agentBars: some View {
    let sources = spend.bySource.filter { $0.usd > 0 }
    let percents = Credits.sharePercents(sources.map(\.usd), of: spend.totalUSD)
    return VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
      Text("By agent")
        .font(DashboardView.cardTitleFont)
      ForEach(Array(sources.enumerated()), id: \.element.source) { index, sourceSpend in
        HStack(spacing: Theme.Spacing.regular) {
          Text(sourceSpend.source.displayName)
            .frame(width: 80, alignment: .leading)
          RoundedRectangle(cornerRadius: 5)
            .fill(Color.primary.opacity(0.08))
            .frame(height: 10)
            .overlay(alignment: .leading) {
              GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 5)
                  .fill(Theme.agentColor(sourceSpend.source))
                  .frame(width: proxy.size.width * sourceSpend.usd / spend.totalUSD)
              }
            }
          Text("\(percents[index])%")
            .frame(width: 48, alignment: .trailing)
        }
        .font(.system(size: 12.5))
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sourceSpend.source.displayName)
        .accessibilityValue("\(percents[index]) percent of Portkey spend, \(PortkeySpend.formatted(sourceSpend.usd))")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardStyle(padding: Theme.Spacing.panel)
  }
}
