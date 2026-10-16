import AppKit
import Core
import Observation

@MainActor
@Observable
final class UsageStore {
  static let refreshInterval: Duration = .seconds(5 * 60)
  static let organizationKey = "githubOrganization"
  static let releaseCheckInterval: TimeInterval = 24 * 60 * 60

  private(set) var title = MenuBarTitle.placeholder
  private(set) var errorMessage: String?
  private(set) var usageError: CopilotUsageError?
  private(set) var lastRefresh: Date?
  private(set) var usage: CopilotUsage?
  private(set) var averageDailyBurn: Double?
  private(set) var modelCredits: [ModelCredits] = []
  private(set) var categoryCredits: [CategoryCredits] = []
  private(set) var sourceCredits: [SourceCredits] = []
  private(set) var dailyCredits: [DailyCredits] = []
  private(set) var sessionsWarning: String?
  private(set) var organization = UserDefaults.standard.string(forKey: organizationKey)
    .flatMap(GitHubOutcomesClient.normalizedOrganization)
  private(set) var outcomes: GitHubOutcomes?
  private(set) var outcomesErrorKind: GitHubOutcomesError?
  var outcomesError: String? { outcomesErrorKind?.message }
  private(set) var availableVersion: String?

  @ObservationIgnored private var pollingTask: Task<Void, Never>?
  @ObservationIgnored private var lastOutcomesFetch: OutcomesFetch?
  @ObservationIgnored private var lastReleaseCheck: Date?
  // The poll and the wake observer can both call refresh() at wake.
  @ObservationIgnored private var isRefreshing = false

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
    guard !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }
    Task { await refreshReleaseIfDue() }
    do throws(CopilotUsageError) {
      let usage = try await CopilotUsageClient.fetchCurrentUsage()
      title = MenuBarTitle.title(usage: usage, now: .now)
      errorMessage = nil
      usageError = nil
      lastRefresh = .now
      self.usage = usage
      averageDailyBurn = Runway.averageDailyBurn(usage: usage, now: .now)
    } catch {
      title = MenuBarTitle.title(error: error)
      errorMessage = error.message
      usageError = error
    }
    // The cycle start comes from the API, so session credits wait for at least one good response.
    guard let usage else { return }
    Task { await refreshOutcomesIfDue() }
    let cycleStart = Runway.cycleStart(resetDate: usage.resetDate)
    let sessionCredits = await Task.detached(priority: .utility) {
      Self.loadSessionCredits(since: cycleStart, now: .now)
    }.value
    modelCredits = sessionCredits.byModel
    categoryCredits = sessionCredits.byCategory
    sourceCredits = sessionCredits.bySource
    dailyCredits = sessionCredits.byDay
    sessionsWarning = sessionCredits.warning
  }

  func summaryText() -> String? {
    usage.map {
      QuotaSummary.text(usage: $0, now: .now, modelCredits: modelCredits, categoryCredits: categoryCredits, outcomes: outcomes)
    }
  }

  func setOrganization(_ text: String) {
    let newOrganization = GitHubOutcomesClient.normalizedOrganization(text)
    guard newOrganization != organization else { return }
    UserDefaults.standard.set(newOrganization, forKey: Self.organizationKey)
    organization = newOrganization
    outcomes = nil
    outcomesErrorKind = nil
    lastOutcomesFetch = nil
    Task { await refreshOutcomesIfDue() }
  }

  // Runs on launch, on an organization change, and at most every 30 minutes, because the search
  // rate limit is low. The cycle start comes from the usage API, so it waits for a good response.
  private func refreshOutcomesIfDue() async {
    guard let organization, let usage else { return }
    let cycleStart = Runway.cycleStart(resetDate: usage.resetDate)
    guard OutcomesFetch.isDue(lastFetch: lastOutcomesFetch, organization: organization, cycleStart: cycleStart, now: .now) else {
      return
    }
    let fetch = OutcomesFetch(organization: organization, cycleStart: cycleStart, startDate: .now)
    lastOutcomesFetch = fetch
    let result = await Task.detached(priority: .utility) { () -> Result<GitHubOutcomes, GitHubOutcomesError> in
      do throws(GitHubOutcomesError) {
        return .success(try await GitHubOutcomesClient.fetchOutcomes(organization: organization, since: cycleStart))
      } catch {
        return .failure(error)
      }
    }.value
    // The organization changed or a newer fetch started, so this result is stale.
    guard lastOutcomesFetch == fetch else { return }
    switch result {
    case .success(let newOutcomes):
      outcomes = newOutcomes
      outcomesErrorKind = nil
    case .failure(let outcomesFailure):
      outcomesErrorKind = outcomesFailure
    }
  }

  // Runs on launch and then at most once a day. A failure keeps the last result and shows nothing.
  private func refreshReleaseIfDue() async {
    if let lastReleaseCheck, Date.now.timeIntervalSince(lastReleaseCheck) < Self.releaseCheckInterval { return }
    // Set before the request, so a wake refresh during the request does not start a second one.
    lastReleaseCheck = .now
    guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return }
    do {
      availableVersion = try await ReleaseCheck.fetchNewerVersion(currentVersion: currentVersion)
    } catch {
      // Offline, rate limited or no release yet: keep the last result.
    }
  }

  struct SessionCredits: Sendable {
    let byModel: [ModelCredits]
    let byCategory: [CategoryCredits]
    let bySource: [SourceCredits]
    let byDay: [DailyCredits]
    let warning: String?
  }

  // Every aggregate comes from the same turns, so all dashboard totals add up.
  nonisolated static func loadSessionCredits(since cycleStart: Date, now: Date) -> SessionCredits {
    var warnings: [String] = []
    let prices: [String: ModelPrice]
    do {
      prices = try PriceTable.load()
    } catch {
      prices = PriceTable.bundled
      warnings.append("prices.json is invalid. Using bundled prices.")
    }
    var turns = PiSessionParser.turns(since: cycleStart)
    do {
      turns += try OpenCodeSessionParser.turns(since: cycleStart)
    } catch {
      warnings.append("Cannot read OpenCode sessions.")
    }
    let records = turns.flatMap(\.records)
    return SessionCredits(
      byModel: Credits.byModel(records: records, prices: prices),
      byCategory: Credits.byCategory(turns: turns, prices: prices),
      bySource: Credits.bySource(turns: turns, prices: prices),
      byDay: Credits.byDay(records: records, prices: prices, cycleStart: cycleStart, now: now, calendar: Runway.utcCalendar),
      warning: warnings.isEmpty ? nil : warnings.joined(separator: " ")
    )
  }
}
