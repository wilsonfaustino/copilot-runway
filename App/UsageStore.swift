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
    } catch let usageError as CopilotUsageError {
      title = MenuBarTitle.title(error: usageError)
      errorMessage = usageError.message
    } catch {
      title = MenuBarTitle.title(error: .invalidResponse)
      errorMessage = CopilotUsageError.invalidResponse.message
    }
  }
}
