# Copilot Runway

A macOS menu bar app that shows your GitHub Copilot AI credit usage as runway: how much is
left, how fast you use it, and the date it runs out. It reads your existing `gh` login and
the local OpenCode and Pi session files.

Local only. The app has no telemetry and no backend. It sends network calls only to the
GitHub API.

Requires macOS 14 (Sonoma) or later.

## Install

### From a Homebrew tap

The tap does not exist yet. When it exists, install with the fully qualified name:

```sh
brew install --cask <owner>/<tap>/copilot-runway
```

Since Homebrew 6.0.0, Homebrew loads code from a third-party tap only after you trust it.
A fully qualified install trusts this one cask and nothing else in the tap
([Tap Trust](https://docs.brew.sh/Tap-Trust)).

### First launch

Releases are ad-hoc signed and not notarized by Apple. Homebrew sets the quarantine
attribute on cask downloads, so Gatekeeper blocks the first launch:

1. Open Copilot Runway from `/Applications`. macOS shows a warning. Click Done.
2. Open System Settings > Privacy & Security, scroll down, and click "Open Anyway" next to
   the message about Copilot Runway. Confirm with your password.

You do this once per installed version. Alternative from the terminal:

```sh
xattr -dr com.apple.quarantine /Applications/CopilotRunway.app
```

### Build from source

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
./scripts/release.sh
```

The script builds the Release configuration, ad-hoc signs the app, verifies the signature
and writes `dist/CopilotRunway-<version>.zip`. It prints the zip's sha256 for
`packaging/Casks/copilot-runway.rb`. You can also unzip it and move `CopilotRunway.app`
to `/Applications`.

## Signing and Homebrew policy

The app is ad-hoc signed (`codesign --sign -`) and is not notarized. The release script
signs without the hardened runtime. With an ad-hoc signature, the hardened runtime's
library validation stops the app from loading its own `Core.framework`. A Developer ID
certificate is the open item. With one, the build can use the hardened runtime and be
notarized, and the first-launch step goes away.

Homebrew policy as of Homebrew 7.0.9 (October 2026):

- Homebrew 5.0.0 deprecated `--no-quarantine`
  ([release notes](https://brew.sh/2025/11/12/homebrew-5.0.0/)). The flag is not in
  Homebrew 6.0.0 or later. The source of `Library/Homebrew/cmd/install.rb` confirms this.
  The flag was removed in the "Homebrew 6 deprecations" commit. There is no replacement
  flag. Users must do the first-launch step above.
- Homebrew applies quarantine to cask downloads so that Gatekeeper checks them
  ([Security and Supply Chain](https://docs.brew.sh/Homebrew-Security-and-Supply-Chain)).
- Casks that fail Gatekeeper checks are not allowed in the official Homebrew/homebrew-cask
  repository ([Acceptable Casks](https://docs.brew.sh/Acceptable-Casks)). Homebrew planned to
  disable those casks in September 2026
  ([6.0.0 release notes](https://brew.sh/2026/06/11/homebrew-6.0.0/)). This rule applies to
  the official repository, not to third-party taps. That is why this app ships through its
  own tap.
- Apple's steps for "Open Anyway":
  [Safely open apps on your Mac](https://support.apple.com/en-us/102445).
