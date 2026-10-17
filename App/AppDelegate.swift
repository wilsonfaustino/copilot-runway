import AppKit
import Core
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
  let usageStore = UsageStore()
  private var statusItem: NSStatusItem?
  private let popover = NSPopover()

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
      rootView: PopoverView(usageStore: usageStore, closePopover: { [weak popover] in popover?.performClose(nil) }))
    hostingController.sizingOptions = [.preferredContentSize]
    popover.behavior = .transient
    popover.contentViewController = hostingController
    popover.delegate = self
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
    button.highlight(true)
  }

  func popoverDidClose(_ notification: Notification) {
    statusItem?.button?.highlight(false)
  }
}
