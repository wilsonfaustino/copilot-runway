import AppKit
import Core
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
  let usageStore = UsageStore()
  private var statusItem: NSStatusItem?
  private let popover = NSPopover()
  private let sharePicker = SharePicker()
  #if DEBUG
  var openDashboard: (() -> Void)?
  // The autosave name that SwiftUI gives the Settings window.
  private static let settingsWindowAutosaveName = "com_apple_SwiftUI_Settings_window"
  #endif

  func applicationDidFinishLaunching(_ notification: Notification) {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.autosaveName = "CopilotRunwayStatusItem"
    if let button = statusItem.button {
      button.target = self
      button.action = #selector(togglePopover(_:))
      button.imagePosition = .imageLeading
    }
    self.statusItem = statusItem
    updateLabel()

    let hostingController = NSHostingController(
      rootView: PopoverView(
        usageStore: usageStore,
        closePopover: { [weak popover] in popover?.performClose(nil) },
        share: { [weak self] anchorView in self?.share(from: anchorView) }
      ))
    hostingController.sizingOptions = [.preferredContentSize]
    popover.behavior = .transient
    popover.contentViewController = hostingController
    popover.delegate = self

    #if DEBUG
    if DemoLaunch.opensDashboard {
      // Async, because an argument that AppKit opens as a file makes SwiftUI skip .presented, and that happens in this launch pass.
      DispatchQueue.main.async { [weak self] in self?.openDashboard?() }
    }
    if DemoLaunch.scenario != nil {
      NotificationCenter.default.addObserver(
        self, selector: #selector(clearSettingsWindowAutosaveName(_:)), name: NSWindow.didUpdateNotification, object: nil)
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
        let health = RunwayHealth(usage: usageStore.usage, hasError: false, now: .now)
        let remainingFraction = MenuBarTitle.remainingFraction(usage: usageStore.usage)
        button.image = RunwayGlyph.menuBarImage(remainingFraction: remainingFraction, health: health)
      }
      button.title = usageStore.title
    } onChange: {
      Task { @MainActor in self.updateLabel() }
    }
  }

  @objc private func togglePopover(_ sender: Any?) {
    guard let button = statusItem?.button else { return }
    if popover.isShown {
      popover.performClose(sender)
      return
    }
    NSApp.activate()
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    // show does not make the popover key, and the system declines activate() for a status item click, so
    // without this the popover looks inactive and the first click in it only makes it key.
    popover.contentViewController?.view.window?.makeKey()
    button.highlight(true)
  }

  private func share(from anchorView: NSView) {
    guard let image = ShareCardRenderer.image(usageStore: usageStore), let summary = usageStore.summaryText() else { return }
    sharePicker.show(image: image, summary: summary, relativeTo: anchorView)
  }

  #if DEBUG
  // Demo mode does not save the Settings frame, so a later real run keeps its own frame. SwiftUI sets the
  // name when it creates the window. didUpdate also fires for inactive windows, so a Settings window that is
  // opened and moved before it becomes key never saves its frame. It runs for every window update, so keep it a cheap compare.
  @objc private func clearSettingsWindowAutosaveName(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, window.frameAutosaveName == Self.settingsWindowAutosaveName else { return }
    window.setFrameAutosaveName("")
  }
  #endif

  func popoverDidClose(_ notification: Notification) {
    statusItem?.button?.highlight(false)
  }
}
