import Core
import ServiceManagement
import SwiftUI

// One tab of the Settings window: a grid with right-aligned labels on the left and the controls on the right,
// with a divider line between groups.
private struct SettingsTabLayout<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    Grid(alignment: .topLeading, horizontalSpacing: Theme.Spacing.section, verticalSpacing: Theme.Spacing.section) {
      content
    }
    .padding(EdgeInsets(top: 20, leading: 16, bottom: 24, trailing: 28))
    .frame(width: 520, alignment: .topLeading)
    .fixedSize(horizontal: false, vertical: true)
  }
}

private struct SettingsRow<Content: View>: View {
  let label: String
  @ViewBuilder let content: Content

  var body: some View {
    GridRow {
      Text(label)
        .frame(width: 170, alignment: .trailing)
      VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
        content
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private struct SettingsDivider: View {
  var body: some View {
    Divider().gridCellColumns(2)
  }
}

private struct SettingsCaption: View {
  let text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    Text(text)
      .captionStyle()
      .fixedSize(horizontal: false, vertical: true)
  }
}

struct SettingsGeneralTab: View {
  let usageStore: UsageStore
  @AppStorage(RunwayNotifier.enabledKey) private var runwayNotificationsEnabled = true
  @AppStorage(Theme.taskPalettePreferenceKey) private var taskPalettePreference = TaskPalettePreference.unset
  @State private var loginItemStatus = SMAppService.mainApp.status
  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiatesWithoutColor

  var body: some View {
    SettingsTabLayout {
      SettingsRow(label: "Login") {
        Toggle("Open at login", isOn: opensAtLogin)
          #if DEBUG
          // Demo mode must not register a login item.
          .disabled(DemoLaunch.isActive)
          #endif
        if loginItemStatus == .requiresApproval {
          SettingsCaption("Approval needed in Login Items.")
          Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
            .controlSize(.small)
        }
        SettingsCaption("Starts Copilot Runway when you log in. You can also change this in System Settings > General > Login Items.")
      }
      SettingsDivider()
      SettingsRow(label: "Notifications") {
        Toggle("Runway notifications", isOn: $runwayNotificationsEnabled)
          #if DEBUG
          // Demo mode must not write the real preference.
          .disabled(DemoLaunch.isActive)
          #endif
        SettingsCaption(
          "One notice at 80% used, one when runway turns short, one when it turns critical and one when the limit is reached."
            + " Each is sent once per billing cycle. With a Portkey budget, the same notices also cover Portkey.")
        #if DEBUG
        if !DemoLaunch.isActive {
          Button("Send test notice") {
            Task { await usageStore.runwayNotifier.sendTestNotice(usage: usageStore.usage, days: usageStore.runwayDays) }
          }
          .controlSize(.small)
        }
        #endif
      }
      SettingsDivider()
      SettingsRow(label: "Task colors") {
        Toggle("Colorblind-safe task colors", isOn: colorblindSafeTaskColors)
          #if DEBUG
          // Demo mode must not write the real preference.
          .disabled(DemoLaunch.isActive)
          #endif
        SettingsCaption("Swaps the task colors for a palette tested for color blindness. Until you set it, it follows Differentiate without color.")
      }
    }
    .toggleStyle(.checkbox)
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      loginItemStatus = SMAppService.mainApp.status
    }
    .onAppear { loginItemStatus = SMAppService.mainApp.status }
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

  // Shows the effective palette while the preference is unset, so the checkbox matches the charts.
  private var colorblindSafeTaskColors: Binding<Bool> {
    Binding(
      get: {
        TaskPalette.resolve(preference: taskPalettePreference, systemDifferentiatesWithoutColor: differentiatesWithoutColor)
          == .colorblindSafe
      },
      set: { taskPalettePreference = $0 ? .on : .off }
    )
  }
}

struct SettingsRunwayTab: View {
  let usageStore: UsageStore
  @AppStorage(UsageStore.gaugeModeKey) private var gaugeMode = GaugeMode.left
  @AppStorage(UsageStore.countWeekdaysOnlyKey) private var countWeekdaysOnly = false

  var body: some View {
    SettingsTabLayout {
      SettingsRow(label: "Gauge shows") {
        HStack(spacing: Theme.Spacing.section) {
          gaugeTileButton(mode: .left, title: "Credits left")
          gaugeTileButton(mode: .spent, title: "Credits spent")
        }
        #if DEBUG
        // Demo mode must not write the real preference.
        .disabled(DemoLaunch.isActive)
        #endif
        .padding(.bottom, Theme.Spacing.tight)
        SettingsCaption("Applies to the menu bar, the popover ring, the dashboard and Copy summary. The color still follows the runway.")
      }
      SettingsDivider()
      SettingsRow(label: "Days") {
        Toggle("Count only weekdays", isOn: $countWeekdaysOnly)
          .toggleStyle(.checkbox)
          #if DEBUG
          .disabled(DemoLaunch.isActive)
          #endif
        SettingsCaption("Burn rate and run-out skip Saturdays and Sundays.")
      }
      SettingsDivider()
      SettingsRow(label: "Days off") {
        Group {
          if let resetDate = usageStore.usage?.resetDate {
            DaysOffCalendar(resetDate: resetDate)
          }
          SettingsCaption(
            countWeekdaysOnly
              ? "Click a workday to mark it off. Shift-click marks a range. Days off do not count toward burn rate or runway. Resets with the cycle."
              : "Turn on Count only weekdays to mark days off.")
        }
        .disabled(!daysOffEditable)
        .opacity(daysOffEditable ? 1 : 0.5)
      }
    }
  }

  private var daysOffEditable: Bool {
    #if DEBUG
    // Demo mode must not write the real preference.
    if DemoLaunch.isActive { return false }
    #endif
    return countWeekdaysOnly
  }

  private func gaugeTileButton(mode: GaugeMode, title: String) -> some View {
    // Reading lastRefresh redraws the tiles on each poll, so the health color follows the clock like the popover.
    _ = usageStore.lastRefresh
    let tile = GaugeTile.make(usage: usageStore.usage, hasError: usageStore.usageError != nil, mode: mode)
    let health = RunwayHealth(usage: usageStore.usage, hasError: usageStore.usageError != nil, now: .now, days: usageStore.runwayDays)
    let isSelected = gaugeMode == mode
    return Button {
      gaugeMode = mode
    } label: {
      VStack(spacing: Theme.Spacing.small) {
        GaugeTileRing(tile: tile, color: tile.isSample ? .secondary : Theme.accent(health))
          .frame(width: 112, height: 76)
          .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
          .overlay(
            RoundedRectangle(cornerRadius: 8)
              .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: isSelected ? 2 : 1)
          )
        Text(title)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(title), \(tile.percent) percent\(tile.isSample ? ", sample" : "")")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

// The cycle month as a 7-column calendar. Click marks or unmarks a workday, shift-click marks a range.
private struct DaysOffCalendar: View {
  let resetDate: Date
  @State private var markedDays: Set<LocalDay> = []
  @State private var lastClicked: LocalDay?

  private static let cellWidth: CGFloat = 32
  private static let cellHeight: CGFloat = 24
  private static let cellSpacing: CGFloat = 4

  private static let gregorianCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = .current
    return calendar
  }()

  var body: some View {
    let grid = DaysOffGrid(resetDate: resetDate, firstWeekday: Calendar.current.firstWeekday)
    let today = LocalDay(date: .now, timeZone: .autoupdatingCurrent)
    VStack(alignment: .leading, spacing: Theme.Spacing.small) {
      HStack {
        Text(header(grid: grid))
          .font(.system(size: 12, weight: .semibold))
        Spacer()
        Button("Clear") { save([]) }
          .controlSize(.small)
          .disabled(markedDays.isEmpty)
      }
      .frame(width: Self.cellWidth * 7 + Self.cellSpacing * 6)
      VStack(alignment: .leading, spacing: Self.cellSpacing) {
        HStack(spacing: Self.cellSpacing) {
          ForEach(Array(weekdayInitials.enumerated()), id: \.offset) { _, initial in
            Text(initial)
              .captionStyle()
              .frame(width: Self.cellWidth, height: Self.cellHeight)
          }
        }
        ForEach(Array(weeks(grid: grid).enumerated()), id: \.offset) { _, week in
          HStack(spacing: Self.cellSpacing) {
            ForEach(Array(week.enumerated()), id: \.offset) { _, cell in
              if let cell {
                dayButton(cell: cell, today: today)
              } else {
                Color.clear.frame(width: Self.cellWidth, height: Self.cellHeight)
              }
            }
          }
        }
      }
    }
    .onChange(of: resetDate, initial: true) {
      markedDays = DaysOffGrid.inCycle(UsageStore.savedDaysOff(), resetDate: resetDate)
      lastClicked = nil
    }
  }

  private func header(grid: DaysOffGrid) -> String {
    let firstDay = grid.cells[0].day
    let monthName = Self.gregorianCalendar.monthSymbols[firstDay.month - 1]
    return "\(monthName) \(firstDay.year) · \(markedDays.count) \(markedDays.count == 1 ? "day" : "days") off"
  }

  private var weekdayInitials: [String] {
    let symbols = Calendar.current.veryShortWeekdaySymbols
    let firstIndex = Calendar.current.firstWeekday - 1
    return Array(symbols[firstIndex...] + symbols[..<firstIndex])
  }

  // Leading blanks and trailing blanks are nil, so every week has 7 slots.
  private func weeks(grid: DaysOffGrid) -> [[DaysOffGrid.Cell?]] {
    var slots: [DaysOffGrid.Cell?] = Array(repeating: nil, count: grid.leadingBlanks) + grid.cells
    slots += Array(repeating: nil, count: (7 - slots.count % 7) % 7)
    return stride(from: 0, to: slots.count, by: 7).map { Array(slots[$0..<$0 + 7]) }
  }

  private func dayButton(cell: DaysOffGrid.Cell, today: LocalDay) -> some View {
    let isDayOff = markedDays.contains(cell.day)
    return Button {
      let isShift = NSEvent.modifierFlags.contains(.shift)
      save(DaysOffGrid.clicking(cell.day, in: markedDays, isShift: isShift, lastClicked: lastClicked))
      lastClicked = cell.day
    } label: {
      Text("\(cell.day.day)")
        .font(.system(size: 11))
        .monospacedDigit()
        .foregroundStyle(isDayOff ? Color.white : (cell.isWeekend ? Color.secondary.opacity(0.5) : Color.primary))
        .frame(width: Self.cellWidth, height: Self.cellHeight)
        .background(isDayOff ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        .overlay {
          if cell.day == today {
            RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor, lineWidth: 1)
          }
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(cell.isWeekend)
    .accessibilityLabel(accessibilityLabel(cell: cell, isDayOff: isDayOff))
    .accessibilityAddTraits(isDayOff ? .isSelected : [])
  }

  // "November 20, day off", "November 21, weekend", or the date alone for a plain workday.
  private func accessibilityLabel(cell: DaysOffGrid.Cell, isDayOff: Bool) -> String {
    let date = "\(Self.gregorianCalendar.monthSymbols[cell.day.month - 1]) \(cell.day.day)"
    if cell.isWeekend { return "\(date), weekend" }
    return isDayOff ? "\(date), day off" : date
  }

  // Keeps only marks in this cycle, so marks from past cycles drop on the next write.
  private func save(_ days: Set<LocalDay>) {
    #if DEBUG
    if DemoLaunch.isActive { return }
    #endif
    markedDays = days
    if days.isEmpty {
      UserDefaults.standard.removeObject(forKey: UsageStore.daysOffKey)
    } else {
      UserDefaults.standard.set(days.sorted().map(\.string), forKey: UsageStore.daysOffKey)
    }
  }
}

// The popover ring's horseshoe at tile size, with the percent in the middle.
private struct GaugeTileRing: View {
  let tile: GaugeTile
  let color: Color

  private static let lineWidth: CGFloat = 6

  private func horseshoe(fraction: Double, color: Color) -> some View {
    Circle()
      .trim(from: 0, to: RunwayGlyph.trackSweepDegrees / 360 * fraction)
      .stroke(color, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
      .rotationEffect(.degrees(RunwayGlyph.trackStartDegrees))
  }

  var body: some View {
    ZStack {
      horseshoe(fraction: 1, color: color.opacity(RunwayGlyph.trackOpacity))
      if tile.fraction > 0 {
        horseshoe(fraction: tile.fraction, color: color)
      }
      Text("\(tile.percent)%")
        .font(.system(size: 12, weight: .semibold))
        .monospacedDigit()
    }
    .padding(Self.lineWidth / 2)
    .frame(width: 56, height: 56)
  }
}

struct SettingsSourcesTab: View {
  let usageStore: UsageStore
  @AppStorage(UsageStore.portkeyBudgetKey) private var portkeyBudgetUSD: Double?
  @State private var organizationText = ""
  @State private var portkeyBudgetText = ""
  @State private var portkeyBudgetRefused = false

  private var priceOverridePath: String {
    (PriceTable.overrideURL.path as NSString).abbreviatingWithTildeInPath
  }

  var body: some View {
    SettingsTabLayout {
      SettingsRow(label: "GitHub account") {
        Text("From gh auth. No token stored.")
          .foregroundStyle(.secondary)
      }
      SettingsDivider()
      SettingsRow(label: "Organization") {
        // Saved on Return or when the tab or window closes, not on each key, because every save runs GitHub searches.
        TextField("Organization", text: $organizationText, prompt: Text("your-org"))
          .textFieldStyle(.roundedBorder)
          .labelsHidden()
          .onSubmit { usageStore.setOrganization(organizationText) }
        statusRow
        SettingsCaption("Optional. Counts your PRs, reviews and commits in this organization through gh.")
      }
      SettingsDivider()
      SettingsRow(label: "Portkey budget") {
        HStack(spacing: Theme.Spacing.small) {
          TextField("Portkey budget", text: $portkeyBudgetText, prompt: Text("No budget"))
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .frame(width: 120)
            .onSubmit { savePortkeyBudget() }
            #if DEBUG
            // Demo mode must not write the real preference.
            .disabled(DemoLaunch.isActive)
            #endif
          Text("USD per month")
            .foregroundStyle(.secondary)
        }
        if portkeyBudgetRefused {
          Label("Enter an amount from 0 to 1,000,000, or leave the field empty.", systemImage: "exclamationmark.triangle")
            .font(.callout)
            .foregroundStyle(Theme.accent(.critical))
            .fixedSize(horizontal: false, vertical: true)
        }
        SettingsCaption("Optional. With a budget, the Portkey block shows the dollars left and the days of runway. Empty means no budget.")
      }
      SettingsDivider()
      SettingsRow(label: "Portkey prices") {
        PortkeySetupPromptButton(records: usageStore.portkeySpend.records)
        SettingsCaption("Paste it into Pi, OpenCode or omp. The agent asks you for each model price and adds it to its config, so new Portkey requests get a cost.")
        SettingsCaption(PortkeySetupPrompt.disclaimer)
      }
      SettingsDivider()
      SettingsRow(label: "Price overrides") {
        Text(priceOverridePath)
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }
      GridRow {
        Label("Local only. Session files stay on this Mac. The only network calls go to api.github.com.", systemImage: "lock")
          .captionStyle()
          .fixedSize(horizontal: false, vertical: true)
          .gridCellColumns(2)
          .padding(.top, Theme.Spacing.tight)
      }
    }
    .onAppear {
      organizationText = usageStore.organization ?? ""
      portkeyBudgetText = portkeyBudgetUSD.map { $0.formatted(.number.grouping(.never)) } ?? ""
      portkeyBudgetRefused = false
    }
    .onDisappear {
      usageStore.setOrganization(organizationText)
      savePortkeyBudget()
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

  private var statusRow: some View {
    let status = SettingsOrganizationStatus(usageStore: usageStore, enteredText: organizationText)
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
        .fixedSize(horizontal: false, vertical: true)
      if status == .unsaved {
        Spacer()
        Button("Save") { usageStore.setOrganization(organizationText) }
          .controlSize(.small)
      }
    }
  }
}

struct SettingsAboutTab: View {
  let usageStore: UsageStore

  private static let authorURL = URL(string: "https://github.com/wilsonfaustino")!
  private static let repositoryURL = URL(string: "https://github.com/wilsonfaustino/copilot-runway")!
  private static let licenseURL = URL(string: "https://github.com/wilsonfaustino/copilot-runway/blob/main/LICENSE")!

  private var versionText: String {
    let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    return "Version \(shortVersion) (\(buildNumber))"
  }

  var body: some View {
    SettingsTabLayout {
      SettingsRow(label: "Copilot Runway") {
        Text(versionText)
          .foregroundStyle(.secondary)
        if let availableVersion = usageStore.availableVersion {
          VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack(spacing: Theme.Spacing.small) {
              Text("Version \(availableVersion) is available.")
              UpdateControls(appUpdater: usageStore.appUpdater)
            }
            // fixedSize collapses the row's Spacer, so Copy sits after the status text like Update sits after the version text.
            UpdateStatusRow(appUpdater: usageStore.appUpdater)
              .fixedSize()
          }
        }
      }
      SettingsDivider()
      SettingsRow(label: "Made by") {
        Link("Wilson Faustino", destination: Self.authorURL)
      }
      SettingsRow(label: "Source") {
        Link(destination: Self.repositoryURL) {
          Label("Star on GitHub", systemImage: "star")
        }
      }
      SettingsRow(label: "License") {
        Link("MIT License", destination: Self.licenseURL)
      }
    }
  }
}
