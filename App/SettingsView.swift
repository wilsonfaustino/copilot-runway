import SwiftUI

struct SettingsView: View {
  let usageStore: UsageStore

  var body: some View {
    TabView {
      SettingsGeneralTab(usageStore: usageStore)
        .tabItem { Label("General", systemImage: "gearshape") }
      SettingsRunwayTab(usageStore: usageStore)
        .tabItem { Label("Runway", systemImage: "gauge.with.needle") }
      SettingsSourcesTab(usageStore: usageStore)
        .tabItem { Label("Sources", systemImage: "tray.2") }
      SettingsAboutTab(usageStore: usageStore)
        .tabItem { Label("About", systemImage: "info.circle") }
    }
  }
}
