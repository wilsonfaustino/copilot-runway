import Core
import ServiceManagement
import SwiftUI

struct SettingsView: View {
  let usageStore: UsageStore
  @State private var organizationText = ""
  @AppStorage(RunwayNotifier.enabledKey) private var runwayNotificationsEnabled = true
  @AppStorage(Theme.taskPalettePreferenceKey) private var taskPalettePreference = TaskPalettePreference.unset
  @AppStorage(UsageStore.gaugeModeKey) private var gaugeMode = GaugeMode.left
  @AppStorage(UsageStore.portkeyBudgetKey) private var portkeyBudgetUSD: Double?
  @State private var portkeyBudgetText = ""
  @State private var portkeyBudgetRefused = false
  @State private var loginItemStatus = SMAppService.mainApp.status
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
      generalSection
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
      gaugeSection
      chartsSection
      portkeySection
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
    .frame(minHeight: 320, maxHeight: .infinity)
    .background(HeightResizableWindow())
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      loginItemStatus = SMAppService.mainApp.status
    }
    .onAppear {
      loginItemStatus = SMAppService.mainApp.status
      organizationText = usageStore.organization ?? ""
      portkeyBudgetText = portkeyBudgetUSD.map { $0.formatted(.number.grouping(.never)) } ?? ""
      portkeyBudgetRefused = false
    }
    .onDisappear {
      usageStore.setOrganization(organizationText)
      savePortkeyBudget()
    }
  }

  private var opensAtLogin: Binding<Bool> {
    Binding(
      get: { loginItemStatus == .enabled },
      set: { shouldOpen in
        do {
          if shouldOpen {
            try SMAppService.mainApp.register()
          } else {
            try SMAppService.mainApp.unregister()
          }
        } catch {}
        loginItemStatus = SMAppService.mainApp.status
      }
    )
  }

  private var generalSection: some View {
    Section {
      Toggle("Open at login", isOn: opensAtLogin)
        .toggleStyle(.switch)
        #if DEBUG
        // Demo mode must not register a login item.
        .disabled(DemoLaunch.isActive)
        #endif
      if loginItemStatus == .requiresApproval {
        Text("Approval needed in Login Items.")
          .captionStyle()
        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
          .controlSize(.small)
      }
    } header: {
      Text("General")
    } footer: {
      Text("Starts Copilot Runway when you log in. You can also change this in System Settings > General > Login Items.")
        .captionStyle()
        .padding(.top, Theme.Spacing.small)
    }
  }

  private var portkeySection: some View {
    Section {
      TextField("Portkey monthly budget (USD)", text: $portkeyBudgetText, prompt: Text("No budget"))
        .textFieldStyle(.roundedBorder)
        .onSubmit { savePortkeyBudget() }
        #if DEBUG
        // Demo mode must not write the real preference.
        .disabled(DemoLaunch.isActive)
        #endif
      if portkeyBudgetRefused {
        Label("Enter an amount from 0 to 1,000,000, or leave the field empty.", systemImage: "exclamationmark.triangle")
          .font(.callout)
          .foregroundStyle(Theme.accent(.critical))
      }
    } header: {
      Text("Portkey")
    } footer: {
      Text("Optional. With a budget, the Portkey block shows the dollars left and the days of runway. Empty means no budget.")
        .captionStyle()
        .padding(.top, Theme.Spacing.small)
    }
  }

  // A refused entry keeps the saved budget.
  private func savePortkeyBudget() {
    #if DEBUG
    if DemoLaunch.isActive { return }
    #endif
    switch PortkeyBudget.entry(from: portkeyBudgetText) {
    case .noBudget:
      portkeyBudgetUSD = nil
      portkeyBudgetRefused = false
    case .budget(let amount):
      portkeyBudgetUSD = amount
      portkeyBudgetRefused = false
    case .refused:
      portkeyBudgetRefused = true
    }
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

  private var showsCreditsSpent: Binding<Bool> {
    Binding(get: { gaugeMode == .spent }, set: { gaugeMode = $0 ? .spent : .left })
  }

  private var gaugeSection: some View {
    Section {
      Toggle("Show credits spent instead of left", isOn: showsCreditsSpent)
        .toggleStyle(.switch)
        #if DEBUG
        // Demo mode must not write the real preference.
        .disabled(DemoLaunch.isActive)
        #endif
    } header: {
      Text("Gauge")
    } footer: {
      Text("Applies to the menu bar, the popover ring, the dashboard and Copy summary. The color still follows the runway.")
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
      Text("Swaps the task colors for a palette tested for color blindness. Until you set it, it follows Differentiate without color.")
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

// The Settings scene creates a window without .resizable, so the frame range alone does not let the user resize it.
// SwiftUI clears the style bit again right after attach, so it is added in the async pass that also fits the window
// once to the Form content. Later content changes and manual resizes are left alone. Screen changes only pull the
// frame back inside the visible frame.
private struct HeightResizableWindow: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView { WindowConfiguringView() }

  func updateNSView(_ nsView: NSView, context: Context) {}

  private final class WindowConfiguringView: NSView {
    private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
      stopObserving()
      guard let window else { return }
      let center = NotificationCenter.default
      observers = [
        center.addObserver(forName: NSWindow.didChangeScreenNotification, object: window, queue: .main) { [weak self, weak window] _ in
          self?.keepInsideVisibleFrame(window)
        },
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self, weak window] _ in
          self?.keepInsideVisibleFrame(window)
        },
      ]
      DispatchQueue.main.async { [weak self, weak window] in
        guard let self, let window, self.window === window else { return }
        self.fitToContent(window)
      }
    }

    deinit { stopObserving() }

    private func stopObserving() {
      observers.forEach(NotificationCenter.default.removeObserver)
      observers = []
    }

    private func fitToContent(_ window: NSWindow) {
      window.styleMask.insert(.resizable)
      window.contentView?.layoutSubtreeIfNeeded()
      if let scrollView = window.contentView?.firstDescendant(ofType: NSScrollView.self), let contentView = scrollView.documentView {
        var fittedFrame = window.frame
        fittedFrame.size.height += contentView.frame.height + scrollView.contentInsets.top + scrollView.contentInsets.bottom - scrollView.contentView.bounds.height
        fittedFrame.origin.y = window.frame.maxY - fittedFrame.height
        window.setFrame(fittedFrame, display: false)
      }
      keepInsideVisibleFrame(window)
    }

    // Checks the origin as well as the height, because a short enough window can still hang below the screen.
    private func keepInsideVisibleFrame(_ window: NSWindow?) {
      guard let window, self.window === window, let visibleFrame = window.screen?.visibleFrame else { return }
      var fittedFrame = window.frame
      fittedFrame.size.height = min(fittedFrame.height, visibleFrame.height)
      fittedFrame.origin.y = min(max(fittedFrame.origin.y, visibleFrame.minY), visibleFrame.maxY - fittedFrame.height)
      fittedFrame.origin.x = min(max(fittedFrame.origin.x, visibleFrame.minX), visibleFrame.maxX - fittedFrame.width)
      if fittedFrame != window.frame { window.setFrame(fittedFrame, display: true) }
    }
  }
}

private extension NSView {
  func firstDescendant<ViewType: NSView>(ofType type: ViewType.Type) -> ViewType? {
    for subview in subviews {
      if let match = subview as? ViewType ?? subview.firstDescendant(ofType: type) { return match }
    }
    return nil
  }
}
