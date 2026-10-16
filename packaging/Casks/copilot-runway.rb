cask "copilot-runway" do
  version "0.2.1"
  # Matches the zip from scripts/release.sh. Update it with each release.
  sha256 "dea8b2b6579a1dc457226eaf1b3969d7f890d556904143b8ec41ee81946beb55"

  url "https://github.com/wilsonfaustino/copilot-runway/releases/download/v#{version}/CopilotRunway-#{version}.zip"
  name "Copilot Runway"
  desc "Menu bar app that shows GitHub Copilot credit runway"
  homepage "https://github.com/wilsonfaustino/copilot-runway"

  depends_on macos: :sonoma

  app "CopilotRunway.app"

  zap trash: [
    "~/.config/copilot-runway",
    "~/Library/Preferences/dev.wilsonfaustino.CopilotRunway.plist",
  ]

  caveats <<~EOS
    Copilot Runway is ad-hoc signed and not notarized by Apple, so macOS
    blocks the first launch.

    To open it the first time:
      1. Open Copilot Runway from /Applications. macOS shows a warning.
         Click Done.
      2. Open System Settings > Privacy & Security, scroll down, and click
         "Open Anyway" next to the message about Copilot Runway. Confirm
         with your password.

    Alternative from the terminal:
      xattr -dr com.apple.quarantine /Applications/CopilotRunway.app
  EOS
end
