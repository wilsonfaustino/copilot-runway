import SwiftUI

struct SettingsView: View {
  let usageStore: UsageStore
  @State private var organizationText = ""

  var body: some View {
    Form {
      // Saved on Return or when the window closes, not on each key, because every save runs GitHub searches.
      TextField("GitHub organization", text: $organizationText)
        .onSubmit { usageStore.setOrganization(organizationText) }
      Text("Counts your PRs and commits in this organization with gh. Press Return to save.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding()
    .frame(width: 380)
    .onAppear { organizationText = usageStore.organization ?? "" }
    .onDisappear { usageStore.setOrganization(organizationText) }
  }
}
