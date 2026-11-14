import Core
import Foundation
import Testing

private let novemberResetDate = utcDate("2026-12-01T00:00:00Z")

private func day(_ string: String) -> LocalDay { LocalDay(string: string)! }

@Test func gridHasOneCellPerDayOfTheCycleMonth() {
  let grid = DaysOffGrid(resetDate: novemberResetDate, firstWeekday: 1)
  #expect(grid.cells.count == 30)
  #expect(grid.cells.first?.day == day("2026-11-01"))
  #expect(grid.cells.last?.day == day("2026-11-30"))
}

@Test func leadingBlanksFollowTheFirstWeekday() {
  #expect(DaysOffGrid(resetDate: novemberResetDate, firstWeekday: 1).leadingBlanks == 0)
  #expect(DaysOffGrid(resetDate: novemberResetDate, firstWeekday: 2).leadingBlanks == 6)
}

@Test func gridMarksWeekendCells() {
  let cells = DaysOffGrid(resetDate: novemberResetDate, firstWeekday: 1).cells
  #expect(cells.first { $0.day == day("2026-11-07") }?.isWeekend == true)
  #expect(cells.first { $0.day == day("2026-11-08") }?.isWeekend == true)
  #expect(cells.first { $0.day == day("2026-11-09") }?.isWeekend == false)
}

@Test func inCycleDropsOtherMonthsAndWeekends() {
  let marked: Set<LocalDay> = [day("2026-10-30"), day("2026-11-21"), day("2026-11-24")]
  #expect(DaysOffGrid.inCycle(marked, resetDate: novemberResetDate) == [day("2026-11-24")])
}

@Test func rangeReturnsWorkdaysInEitherOrder() {
  let expected: Set<LocalDay> = [day("2026-11-23"), day("2026-11-24"), day("2026-11-25"), day("2026-11-26"), day("2026-11-27")]
  #expect(DaysOffGrid.range(from: day("2026-11-27"), to: day("2026-11-23")) == expected)
  #expect(DaysOffGrid.range(from: day("2026-11-23"), to: day("2026-11-27")) == expected)
}

@Test func rangeSkipsWeekendsAndKeepsSingleDay() {
  #expect(DaysOffGrid.range(from: day("2026-11-20"), to: day("2026-11-23")) == [day("2026-11-20"), day("2026-11-23")])
  #expect(DaysOffGrid.range(from: day("2026-11-24"), to: day("2026-11-24")) == [day("2026-11-24")])
  #expect(DaysOffGrid.range(from: day("2026-11-21"), to: day("2026-11-22")).isEmpty)
}

@Test func plainClickTogglesTheDay() {
  let marked: Set<LocalDay> = [day("2026-11-20")]
  #expect(DaysOffGrid.clicking(day("2026-11-24"), in: marked, isShift: false, lastClicked: day("2026-11-20"))
    == [day("2026-11-20"), day("2026-11-24")])
  #expect(DaysOffGrid.clicking(day("2026-11-20"), in: marked, isShift: false, lastClicked: nil).isEmpty)
}

@Test func shiftClickAddsTheWorkdaysFromTheLastClickedDay() {
  let marked: Set<LocalDay> = [day("2026-11-20")]
  #expect(DaysOffGrid.clicking(day("2026-11-24"), in: marked, isShift: true, lastClicked: day("2026-11-20"))
    == [day("2026-11-20"), day("2026-11-23"), day("2026-11-24")])
}

@Test func shiftClickKeepsMarkedDaysInTheRange() {
  let marked: Set<LocalDay> = [day("2026-11-23"), day("2026-11-24")]
  #expect(DaysOffGrid.clicking(day("2026-11-25"), in: marked, isShift: true, lastClicked: day("2026-11-23"))
    == [day("2026-11-23"), day("2026-11-24"), day("2026-11-25")])
}

@Test func shiftClickWithNoLastClickedDayToggles() {
  #expect(DaysOffGrid.clicking(day("2026-11-24"), in: [], isShift: true, lastClicked: nil) == [day("2026-11-24")])
}
