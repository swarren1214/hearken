#!/usr/bin/env bash
#
# Marketing screenshots.
#
# Builds Hearken (Debug) for the Simulator, opens each screen in screenshot mode (demo content,
# no iCloud, see Hearken/App/ScreenshotMode.swift) and saves:
#
#   screenshots/<device>/<appearance>/NN-<screen>.png   full size, for the App Store and press
#   website/assets/screens/<screen>.png                 light mode, resized, for the website
#
# Usage:
#   scripts/screenshots.sh                    every screen, light and dark
#   scripts/screenshots.sh today quiz group   just these screens
#
# Options (environment variables):
#   DEVICE_TYPE="iPhone 17 Pro Max"   Simulator model. Default: one with the 6.9" screen App Store
#                                     Connect asks for (1320 × 2868), or else the biggest iPhone screen.
#   APPEARANCES="light"               "light", "dark" or "light dark" (default).
#   SKIP_BUILD=1                      Reuse the last build.
#   WEB_WIDTH=720                     Width of the website copies, in pixels.
#
# Needs Xcode and its command line tools. Uses its own Simulator ("Hearken Screenshots"), so
# your other simulators and their data are untouched.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/Hearken.xcodeproj"
SCHEME="Hearken"
BUNDLE_ID="com.stephenwarren.hearken"
DERIVED="$ROOT/build/screenshots"
APP="$DERIVED/Build/Products/Debug-iphonesimulator/Hearken.app"
OUT="$ROOT/screenshots"
WEB="$ROOT/website/assets/screens"
SIM_NAME="Hearken Screenshots"
APPEARANCES="${APPEARANCES:-light dark}"
WEB_WIDTH="${WEB_WIDTH:-720}"

# Screens in the order they're numbered, and how long each needs to settle (seconds).
ALL_SCREENS=(today reader listen group play path badges quiz mapquest library notebook plans)
settle_time() {
  case "$1" in
    listen) echo 6 ;;           # the player sheet opens after speech starts
    quiz) echo 5 ;;             # answers the third question, then scrolls to the explanation
    mapquest) echo 6 ;;         # map tiles load
    reader|group|path) echo 5 ;;
    *) echo 4 ;;
  esac
}

if [[ $# -gt 0 ]]; then SCREENS=("$@"); else SCREENS=("${ALL_SCREENS[@]}"); fi
for screen in "${SCREENS[@]}"; do
  [[ " ${ALL_SCREENS[*]} " == *" $screen "* ]] || { echo "Unknown screen: $screen (choose from: ${ALL_SCREENS[*]})" >&2; exit 1; }
done

log() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# MARK: Simulator

json() { xcrun simctl list "$1" -j; }

# Helpers in Python, written to files rather than inline: macOS's bash 3.2 misreads Python
# (comments, quotes, parentheses) inside $( ... ).
HELPERS="$(mktemp -d)"
trap 'rm -rf "$HELPERS"' EXIT

cat > "$HELPERS/pick.py" <<'PY'
import json, os, plistlib, re, sys

# Picks the Simulator runtime and model. Every installed iOS runtime is considered, newest first,
# because a runtime made for one new device (an iOS x.1 built only for a new model) may support
# nothing else. Choice: DEVICE_TYPE if given; otherwise a model with the 6.9-inch App Store screen
# (1320 x 2868) or the biggest tall iPhone screen, when Xcode reports sizes; otherwise the
# highest-numbered Pro Max.
runtimes_text, types_text = sys.stdin.read().split("<<SPLIT>>")
runtimes = [r for r in json.loads(runtimes_text)["runtimes"] if r.get("platform") == "iOS" and r.get("isAvailable")]
if not runtimes:
    print("ERROR\tNo iOS Simulator runtime is installed. Add one in Xcode > Settings > Components.")
    sys.exit()
runtimes.sort(key=lambda r: [int(p) for p in re.findall(r"\d+", r.get("version", "0"))], reverse=True)
listed = {t["identifier"]: t for t in json.loads(types_text)["devicetypes"]}


def models(runtime):
    supported = runtime.get("supportedDeviceTypes")
    if supported is None:
        return [t for t in listed.values() if "iPhone" in t.get("name", "")]
    return [listed.get(t["identifier"], t) for t in supported if "iPhone" in t.get("name", "")]


def screen(t):
    try:
        with open(os.path.join(t.get("bundlePath", ""), "Contents/Resources/profile.plist"), "rb") as f:
            profile = plistlib.load(f)
        w, h = int(profile["mainScreenWidth"]), int(profile["mainScreenHeight"])
        return (min(w, h), max(w, h))
    except Exception:
        return (0, 0)


def tall(t):
    w, h = screen(t)
    return w > 0 and h / w > 2.0


def number(t):
    return [int(n) for n in re.findall(r"\d+", t["name"])] or [0]


def choose():
    wanted = os.environ.get("DEVICE_TYPE")
    if wanted:
        for runtime in runtimes:
            for t in models(runtime):
                if t["name"] == wanted:
                    return runtime, t
        return None
    # By screen size, where Xcode tells us: the 6.9-inch App Store size, else the biggest tall screen.
    for runtime in runtimes:
        exact = [t for t in models(runtime) if screen(t) == (1320, 2868)]
        if exact:
            return runtime, exact[-1]
    for runtime in runtimes:
        candidates = sorted([t for t in models(runtime) if tall(t)], key=lambda t: screen(t)[0] * screen(t)[1])
        if candidates:
            return runtime, candidates[-1]
    # Otherwise by name: the highest-numbered Pro Max (the largest regular iPhone each year).
    for runtime in runtimes:
        candidates = sorted([t for t in models(runtime) if t["name"].endswith("Pro Max")], key=number)
        if candidates:
            return runtime, candidates[-1]
    return None

picked = choose()
if picked:
    runtime, model = picked
    size = screen(model)
    print("OK\t" + runtime["identifier"] + "\t" + model["identifier"] + "\t" + model["name"] + "\t"
          + ("%d x %d" % size if size[0] else "size unknown"))
else:
    lines = []
    for runtime in runtimes:
        names = ", ".join(sorted({t["name"] for t in models(runtime)})) or "none"
        lines.append("  iOS " + runtime.get("version", "?") + ": " + names)
    wanted = os.environ.get("DEVICE_TYPE")
    print("ERROR\t" + ((wanted + " isn't available") if wanted else "No regular iPhone model found")
          + " in your installed Simulator runtimes:\n" + "\n".join(lines)
          + "\nAdd an iOS runtime in Xcode > Settings > Components, or pass DEVICE_TYPE=\"<one of these>\".")
PY

cat > "$HELPERS/udid.py" <<'PY'
import json, os, sys
devices = json.load(sys.stdin)["devices"].get(os.environ["RUNTIME"], [])
print(next((d["udid"] for d in devices if d["name"] == os.environ["SIM"] and d.get("isAvailable")), ""))
PY

# The runtime and model to run on (see pick.py above).
PICK="$( (json runtimes; echo; echo '<<SPLIT>>'; json devicetypes) | DEVICE_TYPE="${DEVICE_TYPE:-}" /usr/bin/python3 "$HELPERS/pick.py")"
if [[ "$PICK" != OK$'\t'* ]]; then echo "${PICK#*$'\t'}" >&2; exit 1; fi
PICK="${PICK#OK$'\t'}"
RUNTIME="${PICK%%$'\t'*}"
DEVICE_TYPE_ID="${PICK#*$'\t'}"
DEVICE_NAME="${DEVICE_TYPE_ID#*$'\t'}"
DEVICE_TYPE_ID="${DEVICE_TYPE_ID%%$'\t'*}"
DEVICE_SIZE="${DEVICE_NAME#*$'\t'}"
DEVICE_NAME="${DEVICE_NAME%%$'\t'*}"
echo "Using $DEVICE_NAME ($DEVICE_SIZE) on ${RUNTIME##*.}"
SIM="$SIM_NAME ($DEVICE_NAME)"

UDID="$(json devices | SIM="$SIM" RUNTIME="$RUNTIME" /usr/bin/python3 "$HELPERS/udid.py")"
if [[ -z "$UDID" ]]; then
  log "Creating the \"$SIM\" Simulator"
  UDID="$(xcrun simctl create "$SIM" "$DEVICE_TYPE_ID" "$RUNTIME")"
fi

log "Booting $SIM"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
open -a Simulator --args -CurrentDeviceUDID "$UDID" || true

# MARK: Build and install

if [[ -z "${SKIP_BUILD:-}" || ! -d "$APP" ]]; then
  log "Building Hearken (Debug, Simulator)"
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$DERIVED" \
    -quiet \
    build
fi

log "Installing"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

# The status bar Apple uses in its own screenshots.
xcrun simctl status_bar "$UDID" override \
  --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --operatorName "" \
  --batteryState charged --batteryLevel 100

# MARK: Capture

device_dir="$(echo "$DEVICE_NAME" | tr ' ' '-')"
mkdir -p "$WEB"

for appearance in $APPEARANCES; do
  log "Capturing ($appearance)"
  xcrun simctl ui "$UDID" appearance "$appearance"
  dir="$OUT/$device_dir/$appearance"
  mkdir -p "$dir"

  for screen in "${SCREENS[@]}"; do
    number=0
    for i in "${!ALL_SCREENS[@]}"; do [[ "${ALL_SCREENS[$i]}" == "$screen" ]] && number=$((i + 1)); done
    file="$dir/$(printf '%02d' "$number")-$screen.png"

    xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl launch "$UDID" "$BUNDLE_ID" -HearkenScreenshots -HearkenScreen "$screen" >/dev/null
    sleep "$(settle_time "$screen")"
    xcrun simctl io "$UDID" screenshot --type=png "$file" >/dev/null 2>&1
    echo "  $screen  →  ${file#$ROOT/}"

    if [[ "$appearance" == "light" ]]; then
      sips --resampleWidth "$WEB_WIDTH" "$file" --out "$WEB/$screen.png" >/dev/null
    fi
  done
done

xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl status_bar "$UDID" clear || true

log "Done"
echo "Full size:  ${OUT#$ROOT/}/$device_dir/"
echo "Website:    ${WEB#$ROOT/}/"
