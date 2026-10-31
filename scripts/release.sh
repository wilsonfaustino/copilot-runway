#!/bin/zsh
# Build a signed Release zip of Copilot Runway in dist/.
# Ad-hoc signed by default. Set DEVELOPER_ID_IDENTITY (codesign identity) and
# NOTARY_KEYCHAIN_PROFILE (notarytool keychain profile) to sign with a Developer ID and notarize.
set -euo pipefail

repo_root="${0:A:h:h}"
cd "$repo_root"

developer_id_identity="${DEVELOPER_ID_IDENTITY:-}"
notary_keychain_profile="${NOTARY_KEYCHAIN_PROFILE:-}"
if [[ -n "$developer_id_identity" && -n "$notary_keychain_profile" ]]; then
  signing_mode="developer-id"
elif [[ -z "$developer_id_identity" && -z "$notary_keychain_profile" ]]; then
  signing_mode="ad-hoc"
else
  echo "error: set both DEVELOPER_ID_IDENTITY and NOTARY_KEYCHAIN_PROFILE, or neither for an ad-hoc build" >&2
  exit 1
fi

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
# Ad-hoc: no hardened runtime. Its library validation needs a Team ID, which an ad-hoc
# signature lacks, so dyld refuses to load Core.framework.
# Developer ID: hardened runtime and a secure timestamp, both required for notarization.
if [[ "$signing_mode" == "ad-hoc" ]]; then
  echo "signing: ad-hoc, not notarized"
  for framework_path in "$app_path"/Contents/Frameworks/*.framework(N); do
    codesign --force --sign - --timestamp=none "$framework_path"
  done
  codesign --force --sign - --timestamp=none "$app_path"
  codesign --verify --strict --verbose=2 "$app_path"
else
  echo "signing: Developer ID, notarized"
  for framework_path in "$app_path"/Contents/Frameworks/*.framework(N); do
    codesign --force --options runtime --timestamp --sign "$developer_id_identity" "$framework_path"
  done
  codesign --force --options runtime --timestamp --sign "$developer_id_identity" "$app_path"
  codesign --verify --strict --verbose=2 "$app_path"

  notary_zip_path="$dist_dir/CopilotRunway-$version-notary.zip"
  rm -f "$notary_zip_path"
  ditto -c -k --keepParent "$app_path" "$notary_zip_path"
  notary_exit_code=0
  notary_json="$(xcrun notarytool submit "$notary_zip_path" \
    --keychain-profile "$notary_keychain_profile" --wait --output-format json)" || notary_exit_code=$?
  rm -f "$notary_zip_path"

  # notarytool can exit 0 for a rejected submission, so check the status too.
  notary_status="$(plutil -extract status raw -o - - <<< "$notary_json" 2>/dev/null || true)"
  if [[ "$notary_exit_code" -ne 0 || "$notary_status" != "Accepted" ]]; then
    notary_submission_id="$(plutil -extract id raw -o - - <<< "$notary_json" 2>/dev/null || true)"
    echo "error: notarization failed (status: ${notary_status:-unknown}, exit code: $notary_exit_code)" >&2
    echo "submission id: ${notary_submission_id:-unknown}" >&2
    echo "log: xcrun notarytool log ${notary_submission_id:-<submission-id>} --keychain-profile \"$notary_keychain_profile\"" >&2
    exit 1
  fi

  xcrun stapler staple "$app_path"
  xcrun stapler validate "$app_path"
  spctl_exit_code=0
  spctl_output="$(spctl -a -vv -t exec "$app_path" 2>&1)" || spctl_exit_code=$?
  echo "$spctl_output"
  if [[ "$spctl_exit_code" -ne 0 || "$spctl_output" != *"source=Notarized Developer ID"* ]]; then
    echo "error: Gatekeeper did not accept the app as Notarized Developer ID" >&2
    exit 1
  fi
fi

rm -f "$zip_path"
ditto -c -k --keepParent "$app_path" "$zip_path"

echo "zip: $zip_path"
echo "sha256: $(shasum -a 256 "$zip_path" | cut -d ' ' -f 1)"
