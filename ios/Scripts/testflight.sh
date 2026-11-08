#!/bin/bash
# Archive Volant for iPhone with the App Store profiles, check the signed result, and export an
# .ipa for TestFlight:  Scripts/testflight.sh
# The build number is the current time (yyyymmddHHMM) unless VOLANT_BUILD is set; the version is
# MARKETING_VERSION in project.yml. With ASC_KEY_ID and ASC_ISSUER_ID set (the key at
# ~/.appstoreconnect/private_keys/AuthKey_<id>.p8) the .ipa is uploaded; otherwise open it in
# Transporter. Profile names default to "Volant App Store", "Volant Widgets App Store" and
# "Volant Share App Store"; override with VOLANT_APP_PROFILE, VOLANT_WIDGETS_PROFILE, VOLANT_SHARE_PROFILE.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD="${VOLANT_BUILD:-$(date +%Y%m%d%H%M)}"
OUT="build/testflight/$BUILD"
APP_PROFILE="${VOLANT_APP_PROFILE:-Volant App Store}"
WIDGETS_PROFILE="${VOLANT_WIDGETS_PROFILE:-Volant Widgets App Store}"
SHARE_PROFILE="${VOLANT_SHARE_PROFILE:-Volant Share App Store}"
mkdir -p "$OUT"
echo "Volant for iPhone build $BUILD -> ios/$OUT"
xcodegen generate --quiet
if ! xcodebuild -project VolantMobile.xcodeproj -scheme VolantMobile -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath build/release -archivePath "$OUT/Volant.xcarchive" \
    CURRENT_PROJECT_VERSION="$BUILD" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Distribution" \
    VOLANT_APP_PROFILE="$APP_PROFILE" VOLANT_WIDGETS_PROFILE="$WIDGETS_PROFILE" VOLANT_SHARE_PROFILE="$SHARE_PROFILE" \
    archive > "$OUT/archive.log" 2>&1; then
  grep -E "error:" "$OUT/archive.log" | sort -u
  echo "Archive failed; full log in ios/$OUT/archive.log" >&2
  exit 1
fi
sed -e "s/VOLANT_APP_PROFILE/$APP_PROFILE/" -e "s/VOLANT_WIDGETS_PROFILE/$WIDGETS_PROFILE/" \
    -e "s/VOLANT_SHARE_PROFILE/$SHARE_PROFILE/" ExportOptions-AppStore.plist > "$OUT/ExportOptions.plist"
if ! xcodebuild -exportArchive -archivePath "$OUT/Volant.xcarchive" -exportPath "$OUT/export" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" > "$OUT/export.log" 2>&1; then
  grep -E "error" "$OUT/export.log" | sort -u
  echo "Export failed; full log in ios/$OUT/export.log" >&2
  exit 1
fi
IPA="$OUT/export/Volant.ipa"
mkdir -p "$OUT/check"
ditto -x -k "$IPA" "$OUT/check"
python3 - "$OUT/check/Payload/Volant.app" <<'PY'
import plistlib, subprocess, sys
app = sys.argv[1]
def entitlements(path):
    out = subprocess.run(["codesign", "-d", "--entitlements", "-", "--xml", path], capture_output=True).stdout
    return plistlib.loads(out) if out else {}
group, container = "group.com.mysticcoders.volant", "iCloud.com.mysticcoders.volant"
for path, wants_icloud in [(app, True), (f"{app}/PlugIns/VolantWidgets.appex", False), (f"{app}/PlugIns/VolantShare.appex", True)]:
    ent = entitlements(path)
    assert not ent.get("get-task-allow"), f"{path} is a debug signature"
    assert ent.get("com.apple.security.application-groups") == [group], f"{path} lacks {group}"
    if wants_icloud:
        assert ent.get("com.apple.developer.icloud-container-identifiers") == [container], f"{path} lacks {container}"
        assert ent.get("com.apple.developer.icloud-container-environment") == "Production", f"{path} is not on the Production iCloud environment"
print("Signed entitlements check passed")
PY
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
  xcrun altool --upload-app -f "$IPA" -t ios --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  echo "Uploaded build $BUILD; it appears in TestFlight after Apple finishes processing."
else
  echo "Exported ios/$IPA. Upload it with Transporter, or set ASC_KEY_ID and ASC_ISSUER_ID to upload from here."
fi
