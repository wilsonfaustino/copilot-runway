#!/bin/zsh
# Copy the repo cask into the local Homebrew tap clone and commit it there. Never pushes.
set -euo pipefail

repo_root="${0:A:h:h}"
cd "$repo_root"

# Must be under ~/www so the includeIf rule applies the personal git identity and credentials.
tap_dir="$HOME/www/dot/homebrew-tap"

version="$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' project.yml)"
if [[ -z "$version" ]]; then
  echo "error: MARKETING_VERSION not found in project.yml" >&2
  exit 1
fi

cask_source="$repo_root/packaging/Casks/copilot-runway.rb"
cask_version="$(sed -n 's/^ *version *"\([^"]*\)".*/\1/p' "$cask_source" | head -n 1)"
cask_sha256="$(sed -n 's/^ *sha256 *"\([^"]*\)".*/\1/p' "$cask_source" | head -n 1)"
if [[ "$cask_version" != "$version" ]]; then
  echo "error: cask version $cask_version differs from project.yml version $version" >&2
  exit 1
fi

tap_cask_path="Casks/copilot-runway.rb"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

zip_url="https://github.com/wilsonfaustino/copilot-runway/releases/download/v$version/CopilotRunway-$version.zip"
zip_path="$work_dir/download/CopilotRunway-$version.zip"
mkdir "$work_dir/download"
curl -fsSL -o "$zip_path" "$zip_url"

downloaded_sha256="$(shasum -a 256 "$zip_path" | cut -d ' ' -f 1)"
if [[ "$downloaded_sha256" != "$cask_sha256" ]]; then
  echo "error: sha256 mismatch for $zip_url" >&2
  echo "  cask:       $cask_sha256" >&2
  echo "  downloaded: $downloaded_sha256" >&2
  exit 1
fi
echo "sha256 ok: $downloaded_sha256"

if [[ ! -e "$tap_dir" ]]; then
  git clone --quiet https://github.com/wilsonfaustino/homebrew-tap.git "$tap_dir"
else
  if ! git -C "$tap_dir" rev-parse --git-dir > /dev/null 2>&1; then
    echo "error: $tap_dir exists but is not a git repo" >&2
    exit 1
  fi
  tap_origin_url="$(git -C "$tap_dir" remote get-url origin)"
  if [[ "$tap_origin_url" != *wilsonfaustino/homebrew-tap(|.git) ]]; then
    echo "error: origin of $tap_dir is $tap_origin_url, not the homebrew-tap repo" >&2
    exit 1
  fi
  if [[ -n "$(git -C "$tap_dir" status --porcelain)" ]]; then
    echo "error: $tap_dir has uncommitted changes" >&2
    exit 1
  fi
  git -C "$tap_dir" pull --quiet --ff-only
fi

cp "$cask_source" "$tap_dir/$tap_cask_path"
if [[ -z "$(git -C "$tap_dir" status --porcelain -- "$tap_cask_path")" ]]; then
  echo "tap is already up to date"
  exit 0
fi

if [[ -z "$(git -C "$tap_dir" config user.email)" ]]; then
  echo "error: git user.email is empty in $tap_dir; the folder must be under an includeIf rule" >&2
  exit 1
fi
git -C "$tap_dir" add "$tap_cask_path"
git -C "$tap_dir" commit --quiet -m "copilot-runway $version" -- "$tap_cask_path"

git -C "$tap_dir" log -1 --oneline
echo "push with:"
echo "  git -C $tap_dir push"
