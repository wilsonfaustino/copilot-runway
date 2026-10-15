cask "copilot-runway" do
  version "0.1.0"
  # Matches the zip from scripts/release.sh. Update it with each release.
  sha256 "690c19cc5947aa45717fedced1dc5d271940769f6a0e376ac20fc86b20d483be"

  # Placeholder host. Replace it with the real release URL before you publish the tap.
  url "https://example.com/REPLACE_ME/CopilotRunway-#{version}.zip"
  name "Copilot Runway"
  desc "Menu bar app that shows GitHub Copilot credit runway"
  homepage "https://example.com/REPLACE_ME"

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
