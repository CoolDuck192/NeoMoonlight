#!/bin/bash
#
# Builds the Vision Pro app signed with your own Apple developer team and
# installs it on your headset.
#
# Run it in Terminal on the Mac itself. Signing needs your login keychain,
# which is locked in an SSH session.
#
# Before the first run:
#   1. Xcode is installed with the visionOS platform, and your Apple ID is
#      added under Xcode > Settings > Accounts.
#   2. On the Vision Pro: Settings > Privacy & Security > Developer Mode is on.
#   3. The Vision Pro is paired with this Mac: in Xcode open
#      Window > Devices and Simulators, then on the headset open
#      Settings > General > Remote Devices and pick this Mac. Both must be on
#      the same network.
#
# Usage:
#   BuildScripts/install-on-vision-pro.sh [options]
#
#   --team ID           10-character Apple Developer Team ID. Only needed the
#                       first time, and only if it cannot be worked out.
#   --bundle-id ID      Bundle identifier for your build. Only used the first
#                       time. Default: com.<mac user name>.neomoonlight
#   --device ID         Identifier or name of the headset, if more than one is
#                       paired.
#   --configuration C   Release (default) or Debug.
#   --build-only        Build and sign, do not install.
#   --launch            Start the app on the headset after installing.
#
# The team and bundle identifier are stored in Config/Signing.local.xcconfig,
# which git ignores. Delete that file to choose them again.
#
set -euo pipefail

TEAM=""
BUNDLE_ID=""
DEVICE=""
CONFIGURATION="Release"
BUILD_ONLY=0
LAUNCH=0

while [ $# -gt 0 ]; do
    case "$1" in
        --team)          TEAM="${2:?--team needs a value}"; shift 2 ;;
        --bundle-id)     BUNDLE_ID="${2:?--bundle-id needs a value}"; shift 2 ;;
        --device)        DEVICE="${2:?--device needs a value}"; shift 2 ;;
        --configuration) CONFIGURATION="${2:?--configuration needs a value}"; shift 2 ;;
        --build-only)    BUILD_ONLY=1; shift ;;
        --launch)        LAUNCH=1; shift ;;
        -h|--help)       sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)               echo "error: unknown option $1 (see --help)" >&2; exit 2 ;;
    esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="Moonlight.xcodeproj"
SCHEME="Moonlight XrOS"
DERIVED="$ROOT/DerivedData"
LOCAL_CONFIG="$ROOT/Config/Signing.local.xcconfig"
LOG="$ROOT/DerivedData/install-on-vision-pro.log"

fail() {
    echo "error: $*" >&2
    exit 1
}

echo "== Toolchain"
command -v xcodebuild >/dev/null 2>&1 || fail "xcodebuild not found. Install Xcode from the App Store and open it once."
xcodebuild -version || fail "Xcode is not set up. Open Xcode once, or run: sudo xcode-select -s /Applications/Xcode.app"
sdks="$(xcodebuild -showsdks 2>/dev/null || true)"
case "$sdks" in
    *"-sdk xros"*) ;;
    *) fail "the visionOS platform is not installed. Add it in Xcode > Settings > Components (or Platforms)." ;;
esac
if [ -n "${SSH_CONNECTION:-}" ]; then
    echo "warning: this is an SSH session. Signing usually fails here (errSecInternalComponent)" >&2
    echo "         because the login keychain is locked. Run the script in Terminal on the Mac." >&2
fi

# Prints the team IDs of the paid teams Xcode knows about, one per line.
xcode_team_ids() {
    defaults read com.apple.dt.Xcode IDEProvisioningTeams 2>/dev/null | awk '
        /isFreeProvisioningTeam/ { free = ($0 ~ /= *1;/) }
        /teamID/ {
            id = $0
            sub(/.*= *"?/, "", id)
            sub(/"?;.*/, "", id)
            if (!free) { print id }
            free = 0
        }' | sort -u
}

# Prints the team IDs of the Apple Development signing certificates in the keychain.
certificate_team_ids() {
    security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | sort -u \
        | while IFS= read -r name; do
            security find-certificate -c "$name" -p 2>/dev/null \
                | openssl x509 -noout -subject -nameopt multiline 2>/dev/null \
                | sed -n 's/^ *organizationalUnitName *= *//p'
        done | sort -u
}

echo "== Signing"
if [ -f "$LOCAL_CONFIG" ]; then
    echo "Using $LOCAL_CONFIG"
    if [ -n "$TEAM" ] || [ -n "$BUNDLE_ID" ]; then
        echo "note: --team and --bundle-id are ignored because that file exists. Delete it to choose again."
    fi
else
    if [ -z "$TEAM" ]; then
        candidates="$(xcode_team_ids || true)"
        if [ -z "$candidates" ]; then
            candidates="$(certificate_team_ids || true)"
        fi
        count="$(printf '%s\n' "$candidates" | grep -c . || true)"
        if [ "$count" = "1" ]; then
            TEAM="$candidates"
            echo "Found developer team $TEAM"
        elif [ "$count" = "0" ]; then
            fail "could not find your developer team. Add your Apple ID under Xcode > Settings > Accounts, or pass --team with the Team ID from https://developer.apple.com/account (Membership details)."
        else
            echo "More than one developer team was found:" >&2
            printf '  %s\n' $candidates >&2
            fail "run again with --team and the one to use."
        fi
    fi
    case "$TEAM" in
        [A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9]) ;;
        *) fail "'$TEAM' is not a Team ID. It is 10 capital letters and digits, not your name or Apple ID." ;;
    esac
    if [ -z "$BUNDLE_ID" ]; then
        user="$(id -un | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"
        BUNDLE_ID="com.${user:-me}.neomoonlight"
    fi
    {
        echo "// Written by BuildScripts/install-on-vision-pro.sh. Git ignores this file."
        echo "DEVELOPMENT_TEAM = $TEAM"
        echo "PRODUCT_BUNDLE_IDENTIFIER = $BUNDLE_ID"
    } > "$LOCAL_CONFIG"
    echo "Wrote $LOCAL_CONFIG (team $TEAM, bundle identifier $BUNDLE_ID)"
fi
APP_BUNDLE_ID="$(sed -n 's/^ *PRODUCT_BUNDLE_IDENTIFIER *= *//p' "$LOCAL_CONFIG" | tail -1 | tr -d '[:space:]')"

mkdir -p "$DERIVED"

DESTINATION="generic/platform=visionOS"
if [ "$BUILD_ONLY" = "0" ]; then
    echo "== Looking for the Vision Pro"
    if [ -z "$DEVICE" ]; then
        # Lines look like: { platform:visionOS, arch:arm64, id:00008112-0012345678901234, name:Apple Vision Pro }
        found="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations 2>/dev/null \
            | grep 'platform:visionOS,' | grep -v 'placeholder' \
            | sed -n 's/.*[{ ,]id:\([^,} ]*\).*/\1/p' | sort -u || true)"
        count="$(printf '%s\n' "$found" | grep -c . || true)"
        if [ "$count" = "1" ]; then
            DEVICE="$found"
        elif [ "$count" = "0" ]; then
            echo "Xcode does not see a Vision Pro. Devices it knows about:" >&2
            xcrun devicectl list devices >&2 || true
            fail "pair the headset first (steps 2 and 3 at the top of this script), keep it awake and on the same network, then run again."
        else
            echo "More than one Vision Pro is paired:" >&2
            xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations 2>/dev/null | grep 'platform:visionOS,' | grep -v 'placeholder' >&2
            fail "run again with --device and the id of the one to use."
        fi
    fi
    echo "Headset: $DEVICE"
    case "$DEVICE" in
        *[!0-9A-Fa-f-]*) DESTINATION="platform=visionOS,name=$DEVICE" ;;
        *)               DESTINATION="platform=visionOS,id=$DEVICE" ;;
    esac
fi

echo "== Building ($CONFIGURATION). This takes a few minutes; the log is $LOG"
if ! xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -destination "$DESTINATION" \
        -derivedDataPath "$DERIVED" \
        -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
        build > "$LOG" 2>&1; then
    grep -E "error:|errSec|Provisioning|provisioning profile|No Account|requires a development team" "$LOG" | sort -u | head -40 >&2 || true
    echo >&2
    echo "The build failed. The lines above are the errors; the full log is $LOG" >&2
    echo "Common causes:" >&2
    echo "  - 'No Account for Team' or 'No profiles': add your Apple ID under Xcode > Settings > Accounts." >&2
    echo "  - 'bundle identifier ... is not available': delete $LOCAL_CONFIG and run again with another --bundle-id." >&2
    echo "  - 'errSecInternalComponent': run the script in Terminal on the Mac, not over SSH." >&2
    exit 1
fi

APP="$(find "$DERIVED/Build/Products/$CONFIGURATION-xros" -maxdepth 1 -name '*.app' -type d 2>/dev/null | head -1 || true)"
[ -n "$APP" ] || fail "the build succeeded but no .app was found in $DERIVED/Build/Products/$CONFIGURATION-xros"
echo "Built $APP"

if [ "$BUILD_ONLY" = "1" ]; then
    echo "== Done (not installed: --build-only)"
    exit 0
fi

echo "== Installing on the headset"
xcrun devicectl device install app --device "$DEVICE" "$APP" \
    || fail "the install failed. Wake the headset, check that it is unlocked and on the same network, then run again (the build is kept, so the second run is quick)."

if [ "$LAUNCH" = "1" ] && [ -n "$APP_BUNDLE_ID" ]; then
    echo "== Starting the app"
    xcrun devicectl device process launch --device "$DEVICE" "$APP_BUNDLE_ID" \
        || echo "warning: could not start the app; open it from the Home View." >&2
fi

echo "== Done. The app is in the Home View on the headset."
