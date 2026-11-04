#!/bin/zsh
# Build the notarized zip with scripts/release.sh and upload it to the draft GitHub release.
# Run it from the commit that the tag vX.Y.Z points to, after CI made the draft release.
# Needs DEVELOPER_ID_IDENTITY and NOTARY_KEYCHAIN_PROFILE in the environment.
# It does not edit notes, publish or touch tags.
set -euo pipefail

repo_root="${0:A:h:h}"
cd "$repo_root"

github_repo="wilsonfaustino/copilot-runway"

require_draft_release() {
  local is_draft
  if ! is_draft="$(gh release view "$tag" --repo "$github_repo" --json isDraft --jq .isDraft)"; then
    echo "error: could not read the GitHub release $tag in $github_repo" >&2
    exit 1
  fi
  if [[ "$is_draft" != "true" ]]; then
    echo "error: the GitHub release $tag is not a draft" >&2
    exit 1
  fi
}

if [[ -z "${DEVELOPER_ID_IDENTITY:-}" || -z "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  echo "error: set both DEVELOPER_ID_IDENTITY and NOTARY_KEYCHAIN_PROFILE in the environment" >&2
  exit 1
fi

version="$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' project.yml)"
if [[ -z "$version" ]]; then
  echo "error: MARKETING_VERSION not found in project.yml" >&2
  exit 1
fi
tag="v$version"

if ! status_output="$(git status --porcelain --untracked-files=all)"; then
  echo "error: git status failed" >&2
  exit 1
fi
if [[ -n "$status_output" ]]; then
  echo "error: the working tree is not clean" >&2
  exit 1
fi

if ! tag_commit="$(git rev-parse --verify --quiet "refs/tags/$tag^{commit}")"; then
  echo "error: tag $tag does not exist locally" >&2
  exit 1
fi
head_commit="$(git rev-parse HEAD)"
if [[ "$head_commit" != "$tag_commit" ]]; then
  echo "error: HEAD ($head_commit) is not the commit of $tag ($tag_commit)" >&2
  exit 1
fi

require_draft_release

scripts/release.sh

zip_path="$repo_root/dist/CopilotRunway-$version.zip"
if [[ ! -f "$zip_path" ]]; then
  echo "error: $zip_path was not built" >&2
  exit 1
fi
local_sha256="$(shasum -a 256 "$zip_path" | cut -d ' ' -f 1)"

# The build and notarization take minutes, so check again that nobody published the release.
require_draft_release
gh release upload "$tag" "$zip_path" --clobber --repo "$github_repo"

asset_name="${zip_path:t}"
asset_digest="$(gh release view "$tag" --repo "$github_repo" --json assets \
  --jq ".assets[] | select(.name == \"$asset_name\") | .digest")"
if [[ "$asset_digest" != "sha256:$local_sha256" ]]; then
  echo "error: asset digest mismatch for $asset_name" >&2
  echo "local:  sha256:$local_sha256" >&2
  echo "remote: ${asset_digest:-none}" >&2
  exit 1
fi

echo "uploaded: $asset_name to $tag"
echo "sha256: $local_sha256"
echo "next:"
echo "  1. set the release notes with this sha256"
echo "  2. gh release edit $tag --draft=false --latest --repo $github_repo"
