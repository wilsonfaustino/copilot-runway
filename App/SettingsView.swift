import Core
import SwiftUI

struct SettingsView: View {
  let usageStore: UsageStore
  @State private var organizationText = ""
  @AppStorage(RunwayNotifier.enabledKey) private var runwayNotificationsEnabled = true
  @AppStorage(Theme.taskPalettePreferenceKey) private var taskPalettePreference = TaskPalettePreference.unset
  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiatesWithoutColor

  private var organizationStatus: SettingsOrganizationStatus {
    SettingsOrganizationStatus(usageStore: usageStore, enteredText: organizationText)
  }

  private var priceOverridePath: String {
    (PriceTable.overrideURL.path as NSString).abbreviatingWithTildeInPath
  }

  private static let authorURL = URL(string: "https://github.com/wilsonfaustino")!
  private static let repositoryURL = URL(string: "https://github.com/wilsonfaustino/copilot-runway")!
  private static let licenseURL = URL(string: "https://github.com/wilsonfaustino/copilot-runway/blob/main/LICENSE")!

  private var versionText: String {
    let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    return "Version \(shortVersion) (\(buildNumber))"
  }

  var body: some View {
    Form {
      Section {
        // Saved on Return or when the window closes, not on each key, because every save runs GitHub searches.
        TextField("GitHub organization", text: $organizationText, prompt: Text("your-org"))
          .textFieldStyle(.roundedBorder)
          .onSubmit { usageStore.setOrganization(organizationText) }
        statusRow
      } header: {
        Text("Outcomes")
      } footer: {
        Text("Optional. Counts your PRs, reviews and commits in this organization through gh.")
          .captionStyle()
          .padding(.top, Theme.Spacing.small)
      }
      notificationsSection
      chartsSection
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
      aboutSection
    }
    .formStyle(.grouped)
    .frame(width: 480)
    .fixedSize(horizontal: false, vertical: true)
    .onAppear { organizationText = usageStore.organization ?? "" }
    .onDisappear { usageStore.setOrganization(organizationText) }
  }

  private var notificationsSection: some View {
    Section {
      Toggle("Runway notifications", isOn: $runwayNotificationsEnabled)
        .toggleStyle(.switch)
        #if DEBUG
        // Demo mode must not write the real preference.
        .disabled(DemoLaunch.isActive)
        #endif
      #if DEBUG
      if !DemoLaunch.isActive {
        Button("Send test notice") {
          Task { await usageStore.runwayNotifier.sendTestNotice(usage: usageStore.usage) }
        }
        .controlSize(.small)
      }
      #endif
    } header: {
      Text("Notifications")
    } footer: {
      Text(
        "One notice at 80% used, one when runway turns short, one when it turns critical and one when the limit is reached."
          + " Each is sent once per billing cycle."
      )
      .captionStyle()
      .padding(.top, Theme.Spacing.small)
    }
  }

  // Shows the effective palette while the preference is unset, so the switch matches the charts.
  private var colorblindSafeTaskColors: Binding<Bool> {
    Binding(
      get: {
        TaskPalette.resolve(preference: taskPalettePreference, systemDifferentiatesWithoutColor: differentiatesWithoutColor)
          == .colorblindSafe
      },
      set: { taskPalettePreference = $0 ? .on : .off }
    )
  }

  private var chartsSection: some View {
    Section {
      Toggle("Colorblind-safe task colors", isOn: colorblindSafeTaskColors)
        .toggleStyle(.switch)
        #if DEBUG
        // Demo mode must not write the real preference.
        .disabled(DemoLaunch.isActive)
        #endif
    } header: {
      Text("Charts")
    } footer: {
      Text("Colors the task bars by hue instead of shades of blue. Until you set it, it follows Differentiate without color.")
        .captionStyle()
        .padding(.top, Theme.Spacing.small)
    }
  }

  private var aboutSection: some View {
    Section("About") {
      LabeledContent("Copilot Runway") {
        Text(versionText)
          .foregroundStyle(.secondary)
      }
      if let availableVersion = usageStore.availableVersion {
        HStack(spacing: Theme.Spacing.small) {
          Text("Version \(availableVersion) is available.")
          Spacer()
          Button("Copy brew command") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(ReleaseCheck.upgradeCommand, forType: .string)
          }
          .controlSize(.small)
          .help(ReleaseCheck.upgradeCommand)
        }
      }
      LabeledContent("Made by") {
        Link("Wilson Faustino", destination: Self.authorURL)
      }
      LabeledContent("Source") {
        Link(destination: Self.repositoryURL) {
          Label("Star on GitHub", systemImage: "star")
        }
      }
      LabeledContent("License") {
        Link("MIT License", destination: Self.licenseURL)
      }
    }
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
      if status == .unsaved {
        Spacer()
        Button("Save") { usageStore.setOrganization(organizationText) }
          .controlSize(.small)
      }
    }
  }
}
