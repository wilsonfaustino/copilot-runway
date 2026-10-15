#!/bin/zsh
# Build an ad-hoc signed Release zip of Copilot Runway in dist/.
set -euo pipefail

repo_root="${0:A:h:h}"
cd "$repo_root"

version="$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' project.yml)"
if [[ -z "$version" ]]; then
  echo "error: MARKETING_VERSION not found in project.yml" >&2
  exit 1
fi

dist_dir="$repo_root/dist"
derived_data_dir="$dist_dir/DerivedData"
app_path="$derived_data_dir/Build/Products/Release/CopilotRunway.app"
zip_path="$dist_dir/CopilotRunway-$version.zip"

xcodegen generate
xcodebuild -scheme CopilotRunway -configuration Release \
  -derivedDataPath "$derived_data_dir" build -quiet

# Sign nested code first, then the app. Apple advises against --deep for signing.
# No hardened runtime here: its library validation needs a Team ID, which an ad-hoc
# signature lacks, so dyld refuses to load Core.framework. Hardened runtime only matters
# for notarization, which needs a Developer ID anyway.
for framework_path in "$app_path"/Contents/Frameworks/*.framework(N); do
  codesign --force --sign - --timestamp=none "$framework_path"
done
codesign --force --sign - --timestamp=none "$app_path"
codesign --verify --strict --verbose=2 "$app_path"

rm -f "$zip_path"
ditto -c -k --keepParent "$app_path" "$zip_path"

echo "zip: $zip_path"
echo "sha256: $(shasum -a 256 "$zip_path" | cut -d ' ' -f 1)"
