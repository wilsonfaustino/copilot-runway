import Core
import Foundation
import Testing

@Test func localDayRoundTripsItsString() {
  let localDay = LocalDay(string: "2026-11-20")
  #expect(localDay?.year == 2026)
  #expect(localDay?.month == 11)
  #expect(localDay?.day == 20)
  #expect(localDay?.string == "2026-11-20")
}

@Test func localDayRejectsInvalidStrings() {
  #expect(LocalDay(string: "2026-13-01") == nil)
  #expect(LocalDay(string: "abc") == nil)
}

@Test func localDayFollowsTheTimeZone() {
  let saoPaulo = TimeZone(identifier: "America/Sao_Paulo")!
  #expect(LocalDay(date: utcDate("2026-12-01T01:00:00Z"), timeZone: saoPaulo) == LocalDay(string: "2026-11-30"))
}
