import Core
import Testing

@Test func unsetPreferenceFollowsSystemFlagOff() {
  #expect(TaskPalette.resolve(preference: .unset, systemDifferentiatesWithoutColor: false) == .standard)
}

@Test func unsetPreferenceFollowsSystemFlagOn() {
  #expect(TaskPalette.resolve(preference: .unset, systemDifferentiatesWithoutColor: true) == .colorblindSafe)
}

@Test func onPreferenceWinsOverSystemFlagOff() {
  #expect(TaskPalette.resolve(preference: .on, systemDifferentiatesWithoutColor: false) == .colorblindSafe)
}

@Test func onPreferenceWithSystemFlagOn() {
  #expect(TaskPalette.resolve(preference: .on, systemDifferentiatesWithoutColor: true) == .colorblindSafe)
}

@Test func offPreferenceWinsOverSystemFlagOn() {
  #expect(TaskPalette.resolve(preference: .off, systemDifferentiatesWithoutColor: true) == .standard)
}

@Test func offPreferenceWithSystemFlagOff() {
  #expect(TaskPalette.resolve(preference: .off, systemDifferentiatesWithoutColor: false) == .standard)
}
