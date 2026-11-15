import AppKit
import SwiftUI

enum SettingsTab: Hashable, CaseIterable {
  case general
  case runway
  case sources
  case about
}

// An AppKit window, because a SwiftUI Settings scene cannot animate its height when the tab changes.
// NSTabViewController does not animate the window to a new preferredContentSize, so this controller
// sets the window frame itself from the measured height of each tab.
@MainActor
final class SettingsWindowController: NSWindowController {
  private static var shared: SettingsWindowController?

  private let usageStore: UsageStore
  private let tabViewController = SettingsTabViewController()
  private var contentSizes: [SettingsTab: CGSize] = [:]

  static func show(usageStore: UsageStore) {
    let controller = shared ?? SettingsWindowController(usageStore: usageStore)
    shared = controller
    controller.tabViewController.selectedTabViewItemIndex = SettingsTab.allCases.firstIndex(of: usageStore.settingsTab) ?? 0
    // The app has no Dock icon, so it must come forward or the window opens behind other apps.
    NSApp.activate()
    controller.showWindow(nil)
  }

  private init(usageStore: UsageStore) {
    self.usageStore = usageStore
    super.init(window: nil)

    tabViewController.tabStyle = .toolbar
    tabViewController.didSelectTab = { [weak self] index in
      guard let self else { return }
      usageStore.settingsTab = SettingsTab.allCases[index]
      fitWindowToSelectedTab()
    }
    addTab(.general, label: "General", systemImage: "gearshape", content: SettingsGeneralTab(usageStore: usageStore))
    addTab(.runway, label: "Runway", systemImage: "gauge.with.needle", content: SettingsRunwayTab(usageStore: usageStore))
    addTab(.sources, label: "Sources", systemImage: "tray.2", content: SettingsSourcesTab(usageStore: usageStore))
    addTab(.about, label: "About", systemImage: "info.circle", content: SettingsAboutTab(usageStore: usageStore))

    let window = NSWindow(contentViewController: tabViewController)
    window.styleMask = [.titled, .closable]
    window.toolbarStyle = .preference
    window.isReleasedWhenClosed = false
    window.center()
    #if DEBUG
    // Demo mode does not save the window position, so a later real run keeps its own position.
    if !DemoLaunch.isActive {
      window.setFrameAutosaveName("SettingsWindow")
    }
    #else
    window.setFrameAutosaveName("SettingsWindow")
    #endif
    self.window = window
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  private func addTab(_ tab: SettingsTab, label: String, systemImage: String, content: some View) {
    // The ScrollView lets a tab taller than the screen scroll. It has no ideal height of its own, so the
    // content measures itself and the window follows.
    let hostingController = NSHostingController(
      rootView: ScrollView(.vertical) {
        content.onGeometryChange(for: CGSize.self) { $0.size } action: { [weak self] contentSize in
          guard let self else { return }
          contentSizes[tab] = contentSize
          if usageStore.settingsTab == tab {
            fitWindowToSelectedTab()
          }
        }
      }
      .scrollBounceBehavior(.basedOnSize)
    )
    // Without this, constraints from the SwiftUI size resize the window at once, without animation.
    hostingController.sizingOptions = []
    // NSTabViewController shows the title of the selected tab as the window title.
    hostingController.title = label
    let item = NSTabViewItem(viewController: hostingController)
    item.label = label
    item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: label)
    tabViewController.addTabViewItem(item)
  }

  // Keeps the top edge in place, and keeps the window inside the visible frame of its screen.
  private func fitWindowToSelectedTab() {
    guard let window, let contentSize = contentSizes[usageStore.settingsTab] else { return }
    let chromeHeight = window.frame.height - window.contentLayoutRect.height
    let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame
    let height = min(contentSize.height + chromeHeight, visibleFrame?.height ?? .greatestFiniteMagnitude)
    var frame = window.frame
    frame.origin.y += frame.height - height
    frame.size = NSSize(width: contentSize.width, height: height)
    if let visibleFrame, frame.minY < visibleFrame.minY {
      frame.origin.y = visibleFrame.minY
    }
    guard frame != window.frame else { return }
    window.setFrame(frame, display: true, animate: window.isVisible)
  }
}

private final class SettingsTabViewController: NSTabViewController {
  var didSelectTab: ((Int) -> Void)?

  override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
    super.tabView(tabView, didSelect: tabViewItem)
    // selectedTabViewItemIndex still holds the previous tab here, so read the index of the new item.
    if let tabViewItem {
      didSelectTab?(tabView.indexOfTabViewItem(tabViewItem))
    }
  }
}
