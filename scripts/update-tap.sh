#!/bin/zsh
# Copy the repo cask into a fresh clone of the Homebrew tap and commit it there. Never pushes.
set -euo pipefail

repo_root="${0:A:h:h}"
cd "$repo_root"

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

clone_dir="$work_dir/homebrew-tap"
git clone --quiet https://github.com/wilsonfaustino/homebrew-tap.git "$clone_dir"

cp "$cask_source" "$clone_dir/$tap_cask_path"
if [[ -z "$(git -C "$clone_dir" status --porcelain -- "$tap_cask_path")" ]]; then
  echo "tap is already up to date"
  exit 0
fi

# The clone sits outside the includeIf folders, so take the identity from the last tap commit.
author_name="$(git -C "$clone_dir" log -1 --format=%an)"
author_email="$(git -C "$clone_dir" log -1 --format=%ae)"
git -C "$clone_dir" add "$tap_cask_path"
git -C "$clone_dir" -c user.name="$author_name" -c user.email="$author_email" \
  commit --quiet -m "copilot-runway $version" -- "$tap_cask_path"

# Keep the clone: the push command below runs from it.
trap - EXIT
git -C "$clone_dir" log -1 --oneline
echo "push with:"
echo "  git -C $clone_dir push"
