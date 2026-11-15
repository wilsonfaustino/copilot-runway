import AppKit
import Core
import SwiftUI

// The update row's controls in the popover and in Settings > About. Copy brew command is never disabled.
struct UpdateControls: View {
  let appUpdater: AppUpdater

  var body: some View {
    HStack(spacing: Theme.Spacing.small) {
      switch appUpdater.state {
      case .unknown, .preparing, .unavailable:
        copyBrewCommandButton
      case .ready:
        updateButton
      case .checking:
        progress("Checking Homebrew...")
      case .updating:
        progress("Updating...")
      case .failed:
        Text("Update failed.")
        copyBrewCommandButton
        updateButton
      case .noNewVersion:
        Text("No new version yet.")
        copyBrewCommandButton
        updateButton
      }
    }
    .controlSize(.small)
    .task { await appUpdater.prepareIfNeeded() }
  }

  private var updateButton: some View {
    Button("Update") {
      Task { await appUpdater.update() }
    }
  }

  private var copyBrewCommandButton: some View {
    Button("Copy brew command") {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(ReleaseCheck.upgradeCommand, forType: .string)
    }
    .help(ReleaseCheck.upgradeCommand)
  }

  private func progress(_ text: String) -> some View {
    HStack(spacing: Theme.Spacing.small) {
      ProgressView()
        .controlSize(.small)
      Text(text)
    }
  }
}
