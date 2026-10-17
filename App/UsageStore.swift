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
  private(set) var modelCredits: [ModelCredits] = []
  private(set) var categoryCredits: [CategoryCredits] = []
  private(set) var sourceCredits: [SourceCredits] = []
  private(set) var dailyCredits: [DailyCredits] = []
  private(set) var cacheHits: [ModelCacheHit] = []
  private(set) var lowCacheSentences: [String] = []
  private(set) var modelEfficiencyNote: String?
  private(set) var sessionsWarning: String?
  private(set) var organization = UserDefaults.standard.string(forKey: organizationKey)
    .flatMap(GitHubOutcomesClient.normalizedOrganization)
  private(set) var outcomes: GitHubOutcomes?
  private(set) var outcomesErrorKind: GitHubOutcomesError?
  var outcomesError: String? { outcomesErrorKind?.message }
  // nil while loading and after an error, so the dashboard shows nothing instead of a wrong number.
  private(set) var copilotReviewCount: Int?
  private(set) var availableVersion: String?
  // The notification center keeps only a weak reference to its delegate, so the store owns the notifier.
  @ObservationIgnored let runwayNotifier = RunwayNotifier()

  @ObservationIgnored private var pollingTask: Task<Void, Never>?
  @ObservationIgnored private var lastOutcomesFetch: OutcomesFetch?
  // reviews(author:) needs the login. It is fetched once and kept in memory only, until the app quits.
  @ObservationIgnored private var login: String?
  @ObservationIgnored private var lastReleaseCheck: Date?
  // The poll and the wake observer can both call refresh() at wake.
  @ObservationIgnored private var isRefreshing = false
  #if DEBUG
  // Fixed fake data from -demo. Demo mode makes no network calls, reads no session files and writes no settings.
  @ObservationIgnored private let demoScenario = DemoLaunch.scenario
  #endif

  init() {
    #if DEBUG
    // Set before the first render, so the real organization never shows in demo mode.
    if demoScenario != nil { organization = DemoScenario.organization }
    #endif
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
    #if DEBUG
    if let demoScenario {
      applyDemo(demoScenario)
      return
    }
    #endif
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
      // Not awaited, because a permission prompt can stay open and must not stop the poll.
      Task { await runwayNotifier.sendDueNotices(usage: usage) }
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
      SessionCredits.load(since: cycleStart, now: .now)
    }.value
    apply(sessionCredits)
  }

  private func apply(_ sessionCredits: SessionCredits) {
    modelCredits = sessionCredits.byModel
    categoryCredits = sessionCredits.byCategory
    sourceCredits = sessionCredits.bySource
    dailyCredits = sessionCredits.byDay
    cacheHits = sessionCredits.cacheHits
    lowCacheSentences = sessionCredits.lowCacheSentences
    modelEfficiencyNote = sessionCredits.modelEfficiencyNote
    sessionsWarning = sessionCredits.warning
  }

  #if DEBUG
  // No usage poll, release check, outcomes fetch, session files or run-out notices.
  private func applyDemo(_ demoScenario: DemoScenario) {
    usage = demoScenario.usage
    title = MenuBarTitle.title(usage: demoScenario.usage, now: .now)
    lastRefresh = .now
    outcomes = demoScenario.outcomes
    copilotReviewCount = demoScenario.copilotReviewCount
    apply(demoScenario.sessionCredits)
  }
  #endif

  func summaryText() -> String? {
    usage.map {
      QuotaSummary.text(usage: $0, now: .now, modelCredits: modelCredits, categoryCredits: categoryCredits, outcomes: outcomes)
    }
  }

  func setOrganization(_ text: String) {
    #if DEBUG
    // Demo mode keeps the demo organization and never writes the real setting.
    if demoScenario != nil { return }
    #endif
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
  // One fetch loads the outcomes and the Copilot review count. The review count needs no organization:
  // Copilot code review bills the PR author on any repo. An error hides the review count and keeps the
  // last outcomes, and gh stderr never reaches the UI.
  private func refreshOutcomesIfDue() async {
    guard let usage else { return }
    let cycleStart = Runway.cycleStart(resetDate: usage.resetDate)
    guard OutcomesFetch.isDue(lastFetch: lastOutcomesFetch, organization: organization, cycleStart: cycleStart, now: .now) else {
      return
    }
    let fetch = OutcomesFetch(organization: organization, cycleStart: cycleStart, startDate: .now)
    lastOutcomesFetch = fetch
    let organization = organization
    let login = login
    let result = await Task.detached(priority: .utility) { () -> Result<GitHubActivity, GitHubOutcomesError> in
      do throws(GitHubOutcomesError) {
        return .success(try await GitHubOutcomesClient.fetchActivity(organization: organization, login: login, since: cycleStart))
      } catch {
        return .failure(error)
      }
    }.value
    // The organization changed or a newer fetch started, so this result is stale.
    guard lastOutcomesFetch == fetch else { return }
    let outcomesResult: Result<GitHubOutcomes, GitHubOutcomesError>?
    switch result {
    case .success(let activity):
      self.login = activity.login ?? self.login
      copilotReviewCount = activity.copilotReviewCount
      outcomesResult = activity.outcomes
    case .failure(let fetchFailure):
      copilotReviewCount = nil
      outcomesResult = organization == nil ? nil : .failure(fetchFailure)
    }
    switch outcomesResult {
    case .success(let newOutcomes)?:
      outcomes = newOutcomes
      outcomesErrorKind = nil
    case .failure(let outcomesFailure)?:
      outcomesErrorKind = outcomesFailure
    case nil:
      break
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
}
