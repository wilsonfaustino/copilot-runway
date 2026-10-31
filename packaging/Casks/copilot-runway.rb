cask "copilot-runway" do
  version "0.4.0"
  # CI replaces version and sha256 when it copies this file into the tap.
  sha256 "c5435d809ee70bb3486197564575afe3ec992d7d99bccce29955c18fb914fc5e"

  url "https://github.com/wilsonfaustino/copilot-runway/releases/download/v#{version}/CopilotRunway-#{version}.zip"
  name "Copilot Runway"
  desc "Menu bar app that shows GitHub Copilot credit runway"
  homepage "https://github.com/wilsonfaustino/copilot-runway"

  depends_on macos: :sequoia

  app "CopilotRunway.app"

  zap trash: [
    "~/.config/copilot-runway",
    "~/Library/Preferences/dev.wilsonfaustino.CopilotRunway.plist",
  ]
end
