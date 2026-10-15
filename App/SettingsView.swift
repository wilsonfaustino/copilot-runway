import Core
import SwiftUI

struct SettingsView: View {
  let usageStore: UsageStore
  @State private var organizationText = ""

  private var organizationStatus: SettingsOrganizationStatus {
    SettingsOrganizationStatus(usageStore: usageStore, enteredText: organizationText)
  }

  private var priceOverridePath: String {
    (PriceTable.overrideURL.path as NSString).abbreviatingWithTildeInPath
  }

  var body: some View {
    Form {
      Section {
        // Saved on Return or when the window closes, not on each key, because every save runs GitHub searches.
        TextField("GitHub organization", text: $organizationText)
          .onSubmit { usageStore.setOrganization(organizationText) }
        statusRow
      }
      Section {
        LabeledContent("GitHub account") {
          Label("From gh auth. No token stored.", systemImage: "text.alignleft")
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.secondary)
        }
        LabeledContent("Price overrides") {
          Text(priceOverridePath)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
      } footer: {
        Label("Local only. Session files stay on this Mac. The only network calls go to api.github.com.", systemImage: "lock")
          .captionStyle()
          .padding(.top, Theme.Spacing.small)
      }
    }
    .formStyle(.grouped)
    .frame(width: 480)
    .fixedSize(horizontal: false, vertical: true)
    .onAppear { organizationText = usageStore.organization ?? "" }
    .onDisappear { usageStore.setOrganization(organizationText) }
  }

  private var statusRow: some View {
    let status = organizationStatus
    return HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small) {
      if let symbolName = status.symbolName {
        Image(systemName: symbolName)
          .foregroundStyle(status.tint)
          .accessibilityHidden(true)
      } else {
        ProgressView().controlSize(.small)
      }
      Text(status.text)
        .font(.callout)
        .foregroundStyle(.secondary)
    }
  }
}
