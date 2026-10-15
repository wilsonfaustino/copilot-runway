import AppKit
import Core
import Observation

@MainActor
@Observable
final class UsageStore {
  static let refreshInterval: Duration = .seconds(5 * 60)

  private(set) var title = MenuBarTitle.placeholder
  private(set) var errorMessage: String?
  private(set) var lastRefresh: Date?
  private(set) var usage: CopilotUsage?
  private(set) var averageDailyBurn: Double?
  private(set) var modelCredits: [ModelCredits] = []
  private(set) var sessionsWarning: String?

  @ObservationIgnored private var pollingTask: Task<Void, Never>?

  init() {
    pollingTask = Task { [weak self] in
      while !Task.isCancelled {
        await self?.refresh()
        try? await Task.sleep(for: Self.refreshInterval)
      }
    }
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { await self?.refresh() }
    }
  }

  func refresh() async {
    do {
      let usage = try await CopilotUsageClient.fetchCurrentUsage()
      title = MenuBarTitle.title(usage: usage, now: .now)
      errorMessage = nil
      lastRefresh = .now
      self.usage = usage
      averageDailyBurn = Runway.averageDailyBurn(usage: usage, now: .now)
    } catch let usageError as CopilotUsageError {
      title = MenuBarTitle.title(error: usageError)
      errorMessage = usageError.message
    } catch {
      title = MenuBarTitle.title(error: .invalidResponse)
      errorMessage = CopilotUsageError.invalidResponse.message
    }
    // The cycle start comes from the API, so session credits wait for at least one good response.
    guard let usage else { return }
    let cycleStart = Runway.cycleStart(resetDate: usage.resetDate)
    let (modelCredits, sessionsWarning) = await Task.detached(priority: .utility) {
      Self.loadSessionCredits(since: cycleStart)
    }.value
    self.modelCredits = modelCredits
    self.sessionsWarning = sessionsWarning
  }

  nonisolated static func loadSessionCredits(since cycleStart: Date) -> ([ModelCredits], String?) {
    var warnings: [String] = []
    let prices: [String: ModelPrice]
    do {
      prices = try PriceTable.load()
    } catch {
      prices = PriceTable.bundled
      warnings.append("prices.json is invalid. Using bundled prices.")
    }
    var records = PiSessionParser.records(since: cycleStart)
    do {
      records += try OpenCodeSessionParser.records(since: cycleStart)
    } catch {
      warnings.append("Cannot read OpenCode sessions.")
    }
    let modelCredits = Credits.byModel(records: records, prices: prices)
    return (modelCredits, warnings.isEmpty ? nil : warnings.joined(separator: " "))
  }
}
