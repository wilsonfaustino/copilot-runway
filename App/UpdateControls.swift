import AppKit
import Core
import SwiftUI

// The update row's controls in the popover and in Settings > About. Copy brew command is never disabled.
// After a failed or empty update, UpdateStatusRow shows the status and Copy brew command on a second line.
struct UpdateControls: View {
  let appUpdater: AppUpdater

  var body: some View {
    HStack(spacing: Theme.Spacing.small) {
      switch appUpdater.state {
      case .unknown, .preparing, .unavailable:
        CopyBrewCommandButton()
      case .ready, .failed, .noNewVersion:
        updateButton
      case .checking:
        progress("Checking Homebrew...")
      case .updating:
        progress("Updating...")
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

  private func progress(_ text: String) -> some View {
    HStack(spacing: Theme.Spacing.small) {
      ProgressView()
        .controlSize(.small)
      Text(text)
    }
  }
}

// The second line under the update row. Empty unless the last update failed or found no new version.
struct UpdateStatusRow: View {
  let appUpdater: AppUpdater

  var body: some View {
    if let statusMessage = appUpdater.statusMessage {
      HStack(spacing: Theme.Spacing.small) {
        Text(statusMessage)
          .font(.system(size: 12))
          .foregroundStyle(appUpdater.state == .failed ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
        Spacer()
        CopyBrewCommandButton()
          .controlSize(.small)
      }
    }
  }
}

private struct CopyBrewCommandButton: View {
  var body: some View {
    Button("Copy brew command") {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(ReleaseCheck.upgradeCommand, forType: .string)
    }
    .help(ReleaseCheck.upgradeCommand)
  }
}
