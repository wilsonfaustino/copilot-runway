import AppKit
import Core
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
  let usageStore = UsageStore()
  private var statusItem: NSStatusItem?
  private let popover = NSPopover()
  private let sharePicker = SharePicker()
  // Room for the popover arrow below the menu bar and a small gap above the Dock.
  private static let popoverScreenMargin: CGFloat = 24
  var openDashboard: (() -> Void)?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.autosaveName = "CopilotRunwayStatusItem"
    if let button = statusItem.button {
      button.target = self
      button.action = #selector(togglePopover(_:))
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
      button.imagePosition = .imageLeading
      button.setAccessibilityHelp("Click for usage. Right-click for more actions.")
    }
    self.statusItem = statusItem
    updateLabel()

    let hostingController = NSHostingController(
      rootView: PopoverScrollView(
        usageStore: usageStore,
        content: PopoverView(
          usageStore: usageStore,
          closePopover: { [weak popover] in popover?.performClose(nil) },
          share: { [weak self] anchorView in self?.share(from: anchorView) }
        )))
    hostingController.sizingOptions = [.preferredContentSize]
    popover.behavior = .transient
    popover.contentViewController = hostingController
    popover.delegate = self

    #if DEBUG
    if DemoLaunch.opensDashboard {
      // Async, because an argument that AppKit opens as a file makes SwiftUI skip .presented, and that happens in this launch pass.
      DispatchQueue.main.async { [weak self] in self?.openDashboard?() }
    }
    if DemoLaunch.runsPortkeyNoticeDrill {
      Task { await usageStore.runwayNotifier.runPortkeyNoticeDrill() }
    }
    #endif
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  // onChange fires once, before the store changes, so the Task re-reads the new values and re-arms tracking.
  private func updateLabel() {
    withObservationTracking {
      guard let button = statusItem?.button else { return }
      if let usageError = usageStore.usageError {
        let image = NSImage(
          systemSymbolName: RunwayGlyph.menuBarSymbolName(error: usageError), accessibilityDescription: nil)
        image?.isTemplate = true
        button.image = image
      } else {
        let health = RunwayHealth(usage: usageStore.gaugeUsage, hasError: false, now: .now, days: usageStore.runwayDays)
        button.image = RunwayGlyph.menuBarImage(parts: usageStore.gaugeParts, health: health)
      }
      button.title = usageStore.title
    } onChange: {
      Task { @MainActor in self.updateLabel() }
    }
  }

  @objc private func togglePopover(_ sender: Any?) {
    guard let button = statusItem?.button else { return }
    if let currentEvent = NSApp.currentEvent,
      currentEvent.type == .rightMouseUp || currentEvent.modifierFlags.contains(.control)
    {
      popover.performClose(sender)
      showMenu(from: button)
      return
    }
    if popover.isShown {
      popover.performClose(sender)
      return
    }
    showPopover(from: button)
  }

  private func showPopover(from button: NSStatusBarButton) {
    NSApp.activate()
    if let visibleFrame = button.window?.screen?.visibleFrame {
      usageStore.popoverMaxHeight = visibleFrame.height - Self.popoverScreenMargin
    }
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    // show does not make the popover key, and the system declines activate() for a status item click, so
    // without this the popover looks inactive and the first click in it only makes it key.
    popover.contentViewController?.view.window?.makeKey()
    button.highlight(true)
  }

  // Setting the menu for one click lets the system place it like any other menu bar menu.
  private func showMenu(from button: NSStatusBarButton) {
    // Key equivalents in an open menu reach it only while the app is active.
    NSApp.activate()
    statusItem?.menu = makeMenu()
    button.performClick(nil)
    statusItem?.menu = nil
  }

  private func makeMenu() -> NSMenu {
    let menu = NSMenu()
    // Copy Summary sets its own enabled state.
    menu.autoenablesItems = false
    menu.addItem(menuItem("Refresh", symbolName: "arrow.clockwise", action: #selector(refreshNow), keyEquivalent: "r"))
    let copySummaryItem = menuItem("Copy Summary", symbolName: "doc.on.doc", action: #selector(copySummary), keyEquivalent: "c")
    copySummaryItem.keyEquivalentModifierMask = [.command, .shift]
    copySummaryItem.isEnabled = usageStore.summaryText() != nil
    menu.addItem(copySummaryItem)
    menu.addItem(.separator())
    menu.addItem(menuItem("Open Dashboard", symbolName: "chart.bar.xaxis", action: #selector(openDashboardWindow), keyEquivalent: "d"))
    menu.addItem(menuItem("Settings…", symbolName: "gearshape", action: #selector(openSettings), keyEquivalent: ","))
    menu.addItem(menuItem("Check for Updates…", symbolName: "arrow.down.circle", action: #selector(checkForUpdates), keyEquivalent: "u"))
    menu.addItem(.separator())
    menu.addItem(menuItem("Quit Copilot Runway", symbolName: "power", action: #selector(quit), keyEquivalent: "q"))
    return menu
  }

  private func menuItem(_ title: String, symbolName: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
    item.target = self
    item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    return item
  }

  @objc private func refreshNow() {
    Task { await usageStore.refresh() }
  }

  @objc private func copySummary() {
    guard let summaryText = usageStore.summaryText() else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(summaryText, forType: .string)
  }

  @objc private func openDashboardWindow() {
    openDashboard?()
    NSApp.activate()
  }

  @objc private func openSettings() {
    SettingsWindowController.show(usageStore: usageStore)
  }

  @objc private func checkForUpdates() {
    Task {
      switch await usageStore.checkForUpdatesNow() {
      case .newer:
        guard let button = statusItem?.button, !popover.isShown else { return }
        showPopover(from: button)
      case .upToDate(let currentVersion):
        showAlert(message: "Copilot Runway is up to date.", information: "Version \(currentVersion) is the newest version.")
      case .failed:
        showAlert(message: "Could not check for updates.", information: "Check your connection and try again.")
      }
    }
  }

  private func showAlert(message: String, information: String) {
    let alert = NSAlert()
    alert.messageText = message
    alert.informativeText = information
    NSApp.activate()
    alert.runModal()
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }

  private func share(from anchorView: NSView) {
    guard let image = ShareCardRenderer.image(usageStore: usageStore), let summary = usageStore.summaryText() else { return }
    sharePicker.show(image: image, summary: summary, relativeTo: anchorView)
  }

  func popoverDidClose(_ notification: Notification) {
    statusItem?.button?.highlight(false)
  }
}
