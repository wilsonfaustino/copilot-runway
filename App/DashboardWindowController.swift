import AppKit
import Core
import Observation
import SwiftUI

@MainActor
@Observable
final class DashboardSelection {
  var tab = DashboardTab.general
  // The last tab the user picked. The shown tab falls back to General while that row is missing or disabled.
  var chosenTab: DashboardTab?
}

// Gives the View menu item its Show Sidebar or Hide Sidebar title.
@MainActor
@Observable
final class DashboardSidebarMenuState {
  static let shared = DashboardSidebarMenuState()
  var isSidebarVisible = true
}

// The Dashboard state that survives a relaunch. A demo run reads and writes none of it.
@MainActor
enum DashboardDefaults {
  static let tabKey = "dashboardTab"
  static let sidebarVisibleKey = "dashboardSidebarVisible"
  static let sidebarWidthKey = "dashboardSidebarWidth"

  static var isEnabled: Bool {
    #if DEBUG
    !DemoLaunch.isActive
    #else
    true
    #endif
  }

  static var tab: DashboardTab? {
    guard isEnabled else { return nil }
    return UserDefaults.standard.string(forKey: tabKey).flatMap(DashboardTab.init(rawValue:))
  }

  static var isSidebarVisible: Bool {
    guard isEnabled else { return true }
    return UserDefaults.standard.object(forKey: sidebarVisibleKey) as? Bool ?? true
  }

  static var sidebarWidth: Double? {
    guard isEnabled else { return nil }
    return UserDefaults.standard.object(forKey: sidebarWidthKey) as? Double
  }

  static func save(_ value: Any, forKey key: String) {
    guard isEnabled else { return }
    UserDefaults.standard.set(value, forKey: key)
  }
}

// An AppKit split view, because NavigationSplitView cannot keep the sidebar button out of the toolbar overflow.
@MainActor
final class DashboardWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
  private static var shared: DashboardWindowController?
  private static let copySummaryItemId = NSToolbarItem.Identifier("copySummary")
  private static let contentMinWidth: CGFloat = 720
  private static let contentMinHeight: CGFloat = 560

  private let usageStore: UsageStore
  private let selection: DashboardSelection
  private let splitViewController = DashboardSplitViewController()
  private let copySummaryButton = NSButton()
  private let sidebarController: NSViewController

  static func show(usageStore: UsageStore) {
    let controller = shared ?? DashboardWindowController(usageStore: usageStore)
    shared = controller
    NSApp.setActivationPolicy(.regular)
    // The app has no Dock icon, so it must come forward or the window opens behind other apps.
    NSApp.activate()
    controller.showWindow(nil)
    controller.focusSidebarList()
  }

  private init(usageStore: UsageStore) {
    self.usageStore = usageStore
    let selection = DashboardSelection()
    selection.chosenTab = DashboardDefaults.tab
    selection.tab = selection.chosenTab ?? .general
    self.selection = selection
    let sidebarHostingController = NSHostingController(
      rootView: DashboardSidebarView(usageStore: usageStore, selection: selection))
    sidebarHostingController.sizingOptions = []
    sidebarController = sidebarHostingController
    super.init(window: nil)

    let contentController = NSHostingController(
      rootView: DashboardView(
        usageStore: usageStore, selection: selection,
        chromeDidChange: { [weak self] title, subtitle, canCopy in
          self?.updateChrome(title: title, subtitle: subtitle, canCopy: canCopy)
        }))
    contentController.sizingOptions = []

    let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
    sidebarItem.minimumThickness = DashboardSidebar.openWidthRange.lowerBound
    sidebarItem.maximumThickness = DashboardSidebar.openWidthRange.upperBound
    sidebarItem.canCollapse = true
    sidebarItem.canCollapseFromWindowResize = false
    let contentItem = NSSplitViewItem(viewController: contentController)
    contentItem.minimumThickness = Self.contentMinWidth
    splitViewController.addSplitViewItem(sidebarItem)
    splitViewController.addSplitViewItem(contentItem)

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.title = "Copilot Runway"
    window.isReleasedWhenClosed = false
    window.isRestorable = false
    // Before the content, because the first render sends the title bar text to this window.
    self.window = window
    window.contentViewController = splitViewController
    window.setContentSize(NSSize(width: 980, height: 640))
    window.contentMinSize = NSSize(width: Self.contentMinWidth, height: Self.contentMinHeight)
    // Set before the window is shown, so a demo run writes no Dashboard frame.
    if DashboardDefaults.isEnabled {
      window.setFrameAutosaveName(DashboardView.windowId)
    }
    if window.frameAutosaveName.isEmpty || !window.setFrameUsingName(DashboardView.windowId) {
      window.center()
    }

    let toolbar = NSToolbar(identifier: "dashboardToolbar")
    toolbar.delegate = self
    toolbar.displayMode = .iconOnly
    toolbar.allowsUserCustomization = false
    toolbar.autosavesConfiguration = false
    window.toolbar = toolbar
    window.toolbarStyle = .unified

    copySummaryButton.title = "Copy summary"
    copySummaryButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
    copySummaryButton.imagePosition = .imageLeading
    copySummaryButton.bezelStyle = .toolbar
    copySummaryButton.target = self
    copySummaryButton.action = #selector(copySummary)

    window.delegate = self
    // The hosting controllers report no size, so the split view starts the sidebar at 0 pt without this.
    window.layoutIfNeeded()
    splitViewController.splitView.setPosition(
      DashboardSidebar.restoredWidth(saved: DashboardDefaults.sidebarWidth), ofDividerAt: 0)
    sidebarItem.isCollapsed = !DashboardDefaults.isSidebarVisible
    DashboardSidebarMenuState.shared.isSidebarVisible = !sidebarItem.isCollapsed
    splitViewController.isCollapsed = sidebarItem.isCollapsed
    splitViewController.isRestoring = false
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  // Like Mail, the sidebar list takes the arrow keys as soon as the window opens.
  private func focusSidebarList() {
    guard let window, window.firstResponder === window, let sidebarList = tableView(in: sidebarController.view) else {
      return
    }
    window.makeFirstResponder(sidebarList)
  }

  private func tableView(in view: NSView) -> NSTableView? {
    if let tableView = view as? NSTableView { return tableView }
    return view.subviews.lazy.compactMap { self.tableView(in: $0) }.first
  }

  func windowWillClose(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }

  private func updateChrome(title: String, subtitle: String, canCopy: Bool) {
    window?.title = title
    window?.subtitle = subtitle
    copySummaryButton.isEnabled = canCopy
  }

  @objc private func copySummary() {
    guard let summaryText = usageStore.summaryText() else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(summaryText, forType: .string)
    copySummaryButton.title = "Copied"
  }

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    // The flexible space before the toggle puts the button at the sidebar's trailing edge when open, as in Mail.
    [.flexibleSpace, .toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, Self.copySummaryItemId]
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    toolbarDefaultItemIdentifiers(toolbar)
  }

  func toolbar(
    _ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool
  ) -> NSToolbarItem? {
    guard itemIdentifier == Self.copySummaryItemId else { return nil }
    let item = NSToolbarItem(itemIdentifier: itemIdentifier)
    item.view = copySummaryButton
    item.label = "Copy summary"
    return item
  }
}

@MainActor
final class DashboardSplitViewController: NSSplitViewController {
  // True until the window controller applies the saved width and visibility, so the restore saves nothing.
  var isRestoring = true
  var isCollapsed = false

  override func splitViewDidResizeSubviews(_ notification: Notification) {
    super.splitViewDidResizeSubviews(notification)
    guard !isRestoring, let sidebarItem = splitViewItems.first else { return }
    if sidebarItem.isCollapsed != isCollapsed {
      isCollapsed = sidebarItem.isCollapsed
      DashboardSidebarMenuState.shared.isSidebarVisible = !isCollapsed
      DashboardDefaults.save(!isCollapsed, forKey: DashboardDefaults.sidebarVisibleKey)
    }
    // Only a divider drag holds the mouse down. The collapse and expand animations pass through widths under 200 pt.
    guard !sidebarItem.isCollapsed, NSEvent.pressedMouseButtons != 0 else { return }
    let width = Double(sidebarItem.viewController.view.frame.width)
    DashboardDefaults.save(DashboardSidebar.restoredWidth(saved: width), forKey: DashboardDefaults.sidebarWidthKey)
  }
}

struct DashboardSidebarView: View {
  let usageStore: UsageStore
  @Bindable var selection: DashboardSelection

  private var rows: [DashboardSidebarRow] {
    DashboardSidebar.rows(
      DashboardSidebarInput(
        copilotState: usageStore.copilotState, copilotUsage: usageStore.usage, hasCopilotError: usageStore.hasUsageError,
        combined: usageStore.combinedBudget, portkeySpentUSD: usageStore.portkeySpend.totalUSD,
        portkeyRequestCount: usageStore.portkeySpend.requestCount, portkeyBudgetUSD: usageStore.portkeyBudgetUSD,
        resetDate: usageStore.cycleResetDate, mode: usageStore.gaugeMode, days: usageStore.runwayDays),
      now: .now)
  }

  var body: some View {
    let rows = rows
    List(
      selection: Binding<DashboardTab?>(
        get: { selection.tab },
        set: { newTab in
          guard let newTab, rows.contains(where: { $0.tab == newTab && $0.isEnabled }) else { return }
          selection.tab = newTab
          selection.chosenTab = newTab
          DashboardDefaults.save(newTab.rawValue, forKey: DashboardDefaults.tabKey)
        })
    ) {
      ForEach(rows, id: \.tab) { row in
        rowView(row)
          .tag(row.tab)
          .selectionDisabled(!row.isEnabled)
          .disabled(!row.isEnabled)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(row.accessibilityLabel)
      }
    }
    .listStyle(.sidebar)
    .onChange(of: rows, initial: true) { _, newRows in
      selection.tab = DashboardSidebar.resolvedTab(saved: selection.chosenTab, rows: newRows)
    }
  }

  private func rowView(_ row: DashboardSidebarRow) -> some View {
    HStack(spacing: 8) {
      SidebarIconTint { rowIcon(row.tab) }
        .frame(width: 18)
      VStack(alignment: .leading, spacing: 1) {
        Text(row.tab.title)
        Text(row.status)
          .font(.caption)
          .foregroundStyle(Theme.accent(row.health))
          .lineLimit(1)
      }
      Spacer(minLength: 4)
      if let gauge = row.gauge {
        HorseshoeRing(tile: gauge, color: Theme.accent(row.health), diameter: 22, lineWidth: 3, showsPercent: false)
      }
    }
    .padding(.vertical, 2)
  }

  @ViewBuilder
  private func rowIcon(_ tab: DashboardTab) -> some View {
    switch tab {
    case .general: Image(systemName: "chart.pie")
    case .copilot: markIcon("CopilotMark")
    case .portkey: markIcon("PortkeyMark")
    }
  }

  private func markIcon(_ assetName: String) -> some View {
    Image(assetName)
      .resizable()
      .scaledToFit()
      // 15 pt matches the optical size of the chart.pie symbol inside the 18 pt icon column.
      .frame(width: 15, height: 15)
  }
}

private struct SidebarIconTint<Content: View>: View {
  @Environment(\.backgroundProminence) private var backgroundProminence
  @Environment(\.isEnabled) private var isEnabled
  @ViewBuilder let content: Content

  var body: some View {
    content.foregroundStyle(iconStyle)
  }

  private var iconStyle: AnyShapeStyle {
    if !isEnabled { return AnyShapeStyle(.secondary) }
    return backgroundProminence == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint)
  }
}
