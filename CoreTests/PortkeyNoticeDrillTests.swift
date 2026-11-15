#if DEBUG
import Core
import Foundation
import Testing

// The days since the cycle start are 25 to 28, from the month length, so the drill covers a February cycle and a
// 31-day cycle.
@Test(arguments: ["2027-02-26T09:00:00Z", "2026-11-14T09:00:00Z", "2026-12-28T23:00:00Z"])
func portkeyDrillSendsOneNewNoticePerStep(now: String) {
  let nowDate = utcDate(now)
  var sentKeys: Set<String> = []
  var kindsPerStep: [[RunwayNotice.Kind]] = []
  for usage in PortkeyNoticeDrill.usages(now: nowDate) {
    let notices = RunwayNotice.toSend(usage: usage, now: nowDate, sentKeys: sentKeys, subject: .portkey)
    sentKeys.formUnion(notices.map(\.key))
    kindsPerStep.append(notices.map(\.kind))
  }
  #expect(kindsPerStep == [[.used80], [.short], [.critical], [.limitReached]])
}
#endif
