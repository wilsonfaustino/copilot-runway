import Core
import Foundation
import UserNotifications

// Posts the run-out notices from RunwayNotice. Only the Core title and body reach a notice.
@MainActor
final class RunwayNotifier: NSObject, UNUserNotificationCenterDelegate {
  static let enabledKey = "runwayNotificationsEnabled"
  static let sentKeysKey = "runwayNoticeSentKeys"
  static let portkeySentKeysKey = "portkeyNoticeSentKeys"

  // A permission prompt can stay open for a long time, so a second refresh must not post the same notices.
  private var sendingSubjects: Set<RunwayNotice.Subject> = []

  override init() {
    super.init()
    // Setting the delegate does not ask for permission.
    UNUserNotificationCenter.current().delegate = self
  }

  func sendDueNotices(usage: QuotaUsage, days: RunwayDays, subject: RunwayNotice.Subject = .copilot) async {
    // The @AppStorage default is true, and a missing key reads as false through bool(forKey:).
    guard UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true, !sendingSubjects.contains(subject) else { return }
    // Each subject keeps its own keys, because the save below drops every key outside its current cycle.
    let sentKeysKey = subject == .portkey ? Self.portkeySentKeysKey : Self.sentKeysKey
    let sentKeys = Set(UserDefaults.standard.stringArray(forKey: sentKeysKey) ?? [])
    let notices = RunwayNotice.toSend(usage: usage, now: .now, sentKeys: sentKeys, days: days, subject: subject)
    guard !notices.isEmpty else { return }
    sendingSubjects.insert(subject)
    defer { sendingSubjects.remove(subject) }
    if await isAuthorized() {
      for notice in notices {
        await post(identifier: notice.key, title: notice.title, body: notice.body)
      }
    }
    // Saved also when permission is denied, so the notices do not retry every 5 minutes.
    let currentCycleKeys = Set(
      RunwayNotice.Kind.allCases.map { RunwayNotice.key(kind: $0, resetDate: usage.resetDate, subject: subject) })
    let keptKeys = sentKeys.union(notices.map(\.key)).intersection(currentCycleKeys)
    UserDefaults.standard.set(keptKeys.sorted(), forKey: sentKeysKey)
  }

  #if DEBUG
  func sendTestNotice(usage: QuotaUsage?, days: RunwayDays) async {
    // Demo mode asks for no permission and posts no notice.
    guard !DemoLaunch.isActive, await isAuthorized() else { return }
    let notice = usage.flatMap { RunwayNotice.toSend(usage: $0, now: .now, sentKeys: [], days: days).first }
    let runOutSentence = usage.flatMap { RunwayInsight.runOutSentence(usage: $0, now: .now, days: days) }
    await post(
      identifier: "test",
      title: notice?.title ?? "Test notice",
      body: notice?.body ?? runOutSentence ?? "Sample body. No usage yet."
    )
  }

  // Posts the Portkey notices of PortkeyNoticeDrill, one step every few seconds. The sent keys stay in memory,
  // so the real sent keys and the toggle do not change, and each launch runs the full drill again.
  func runPortkeyNoticeDrill() async {
    guard !DemoLaunch.isActive, await isAuthorized() else { return }
    let stepInterval: Duration = .seconds(8)
    let now = Date.now
    var sentKeys: Set<String> = []
    for usage in PortkeyNoticeDrill.usages(now: now) {
      for notice in RunwayNotice.toSend(usage: usage, now: now, sentKeys: sentKeys, subject: .portkey) {
        await post(identifier: "drill-\(notice.key)", title: notice.title, body: notice.body)
        sentKeys.insert(notice.key)
      }
      try? await Task.sleep(for: stepInterval)
    }
  }
  #endif

  // Asks only the first time. Later calls return the stored answer.
  private func isAuthorized() async -> Bool {
    (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
  }

  private func post(identifier: String, title: String, body: String) async {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
  }

  // Shows banners while the app is active, for example when the popover is open.
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list]
  }
}
