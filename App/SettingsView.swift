import SwiftUI

enum SettingsTab: Hashable {
  case general
  case runway
  case sources
  case about
}

struct SettingsView: View {
  @Bindable var usageStore: UsageStore

  var body: some View {
    TabView(selection: $usageStore.settingsTab) {
      SettingsGeneralTab(usageStore: usageStore)
        .tabItem { Label("General", systemImage: "gearshape") }
        .tag(SettingsTab.general)
      SettingsRunwayTab(usageStore: usageStore)
        .tabItem { Label("Runway", systemImage: "gauge.with.needle") }
        .tag(SettingsTab.runway)
      SettingsSourcesTab(usageStore: usageStore)
        .tabItem { Label("Sources", systemImage: "tray.2") }
        .tag(SettingsTab.sources)
      SettingsAboutTab(usageStore: usageStore)
        .tabItem { Label("About", systemImage: "info.circle") }
        .tag(SettingsTab.about)
    }
  }
}
