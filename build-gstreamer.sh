#!/usr/bin/env bash
#
# build-gstreamer.sh — add game video support (GStreamer) to Wine CX.
#
# Wine plays in-game videos and cutscenes (Media Foundation, DirectShow, WMV)
# through its winegstreamer module, which needs GStreamer. build.sh leaves it
# out; this script adds it afterwards, the same way Gcenx's Wine Stable does:
#
#   1. installs the official GStreamer runtime in /Library/Frameworks
#      (asks for your password once; skipped if it is already installed)
#   2. downloads the official devel package (~800 MB) only for its headers,
#      and deletes it afterwards
#   3. reconfigures the existing build with GStreamer, compiles only
#      winegstreamer and copies it into Wine CX.app
#   4. registers it in the Steam prefix
#
# Run it after build.sh, with Steam closed. Takes 15 to 30 minutes, mostly
# the download.
#
# Configuration: WINE_CX_DIR, OUT_APP (same as build.sh), WINEPREFIX (default ~/.wine-steam)
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
fi

GST_VERSION="1.28.8"
GST_URL="https://gstreamer.freedesktop.org/data/pkg/osx/$GST_VERSION"
RUNTIME_PKG="gstreamer-1.0-$GST_VERSION-universal.pkg"
DEVEL_PKG="gstreamer-1.0-devel-$GST_VERSION-universal.pkg"
FW="/Library/Frameworks/GStreamer.framework"

BASE="${WINE_CX_DIR:-$HOME/Games/wine-cx}"
OUT_APP="${OUT_APP:-$BASE/Wine CX.app}"
OUT_WINE="$OUT_APP/Contents/Resources/wine"
PREFIX="${WINEPREFIX:-$HOME/.wine-steam}"
SRC="$BASE/src"
BUILD="$BASE/build"
WORK="$BASE/gstreamer"
LOGS="$BASE/logs"
JOBS="${JOBS:-$(sysctl -n hw.logicalcpu)}"

ts()   { date '+%H:%M:%S'; }
step() { printf '\n[%s] ==> %s\n' "$(ts)" "$*"; }
ok()   { printf '[%s]     ok: %s\n' "$(ts)" "$*"; }
die()  { printf '\n[%s] ERROR: %s\n' "$(ts)" "$*" >&2; exit 1; }
trap 'die "failed at line $LINENO: $BASH_COMMAND"' ERR

# Downloads a package and checks it against the SHA-256 published next to it.
fetch() {
    local f="$1"
    [[ -f "$WORK/$f" ]] && shasum -a 256 -c "$WORK/$f.sha256sum" >/dev/null 2>&1 && return 0
    curl -fsSL --retry 3 -o "$WORK/$f.sha256sum" "$GST_URL/$f.sha256sum"
    curl -fL --retry 3 --progress-bar -o "$WORK/$f.part" "$GST_URL/$f"
    mv "$WORK/$f.part" "$WORK/$f"
    (cd "$WORK" && shasum -a 256 -c "$f.sha256sum" >/dev/null) || die "checksum mismatch for $f"
}

# --- 0. Checks ----------------------------------------------------------------
step "Checks"
[[ -d "$OUT_WINE/lib/wine" ]] || die "Wine CX.app not found at $OUT_APP (run build.sh first)"
[[ -f "$BUILD/config.status" && -f "$SRC/configure" ]] || die "build folder not found in $BASE (run build.sh first and keep src/ and build/)"
[[ -d "$PREFIX/drive_c" ]] || die "Wine prefix not found at $PREFIX (set WINEPREFIX)"
if pgrep -qf 'Steam\\Steam\.exe|steamwebhelper'; then
    die "quit Steam first (Steam > Exit, or: ./cx stop)"
fi
mkdir -p "$WORK" "$LOGS"
ok "Wine CX and build folder found"

# --- 1. GStreamer runtime -----------------------------------------------------
step "GStreamer $GST_VERSION runtime"
if [[ -f "$FW/Versions/1.0/lib/libgstreamer-1.0.0.dylib" ]]; then
    ok "already installed in $FW"
else
    fetch "$RUNTIME_PKG"
    echo "Installing GStreamer into /Library/Frameworks. macOS will ask for your password."
    sudo installer -pkg "$WORK/$RUNTIME_PKG" -target /
    rm -f "$WORK/$RUNTIME_PKG"
    ok "installed"
fi
lipo -info "$FW/Versions/1.0/lib/libgstreamer-1.0.0.dylib" | grep -q x86_64 \
    || die "the installed GStreamer has no x86_64 code; reinstall the universal package"

# --- 2. Headers ---------------------------------------------------------------
step "Headers (from the devel package)"
INC="$WORK/include"
if [[ ! -f "$INC/gstreamer-1.0/gst/video/video.h" || ! -f "$INC/x86_64/glibconfig.h" ]]; then
    fetch "$DEVEL_PKG"
    rm -rf "$WORK/devel" "$INC"
    pkgutil --expand-full "$WORK/$DEVEL_PKG" "$WORK/devel"
    mkdir -p "$INC/x86_64"
    for d in "$WORK"/devel/*/Payload/include; do cp -R "$d/." "$INC/"; done
    # glibconfig.h comes in one copy per architecture; Wine is built for x86_64.
    glibconf="$(find "$WORK/devel" -path '*lib/glib-2.0/include/x86_64/glibconfig.h' | head -1)"
    [[ -n "$glibconf" ]] || die "x86_64 glibconfig.h not found in the devel package"
    cp "$glibconf" "$INC/x86_64/"
    rm -rf "$WORK/devel" "$WORK/$DEVEL_PKG"   # frees ~1.5 GB
fi
[[ -f "$INC/gstreamer-1.0/gst/gst.h" && -f "$INC/glib-2.0/glib.h" ]] || die "headers incomplete in $INC"
ok "$INC"

# --- 3. Configure -------------------------------------------------------------
step "Reconfiguring the build with GStreamer"
export PATH="/opt/homebrew/bin:$PATH"
BREW="$(brew --prefix)"
CLT_BIN="$(xcode-select -p)/usr/bin"
export SDKROOT="$(xcrun --show-sdk-path)"
export PATH="$BREW/opt/bison/bin:$BREW/opt/flex/bin:$CLT_BIN:$PATH"
export MACOSX_DEPLOYMENT_TARGET=14.0

GST_CFLAGS="-I$INC/x86_64 -I$INC/gstreamer-1.0 -I$INC/glib-2.0 -I$INC"
GST_LIBS="-L$FW/Versions/1.0/lib -lgstvideo-1.0 -lgstaudio-1.0 -lgsttag-1.0 -lgstbase-1.0 -lgstreamer-1.0 -lgobject-2.0 -lglib-2.0 -Wl,-rpath,$FW/Libraries"

cd "$BUILD"
cp -p include/config.h "$WORK/config.h.before"
eval "set -- $(./config.status --config)"
args=()
for a in "$@"; do
    case "$a" in
        --without-gstreamer) a="--with-gstreamer" ;;
        GSTREAMER_CFLAGS=*|GSTREAMER_LIBS=*) continue ;;
    esac
    args+=("$a")
done
args+=("GSTREAMER_CFLAGS=$GST_CFLAGS" "GSTREAMER_LIBS=$GST_LIBS")
/usr/bin/arch -x86_64 "$SRC/configure" "${args[@]}" >"$LOGS/configure-gstreamer.log" 2>&1 \
    || { tail -20 "$LOGS/configure-gstreamer.log"; die "configure failed; details in $BUILD/config.log"; }
grep -q '^GSTREAMER_LIBS = .*-lgstreamer' Makefile || die "configure did not enable GStreamer; see $BUILD/config.log"
# GStreamer doesn't change config.h. Keep its old date so nothing else recompiles.
if cmp -s "$WORK/config.h.before" include/config.h; then
    touch -r "$WORK/config.h.before" include/config.h
fi
rm -f "$WORK/config.h.before"
ok "GStreamer enabled"

# --- 4. Compile and install ---------------------------------------------------
step "Compiling winegstreamer"
make -j"$JOBS" dlls/winegstreamer/all >"$LOGS/make-gstreamer.log" 2>&1 \
    || { tail -30 "$LOGS/make-gstreamer.log"; die "make failed; full log in $LOGS/make-gstreamer.log"; }
cp dlls/winegstreamer/winegstreamer.so             "$OUT_WINE/lib/wine/x86_64-unix/"
cp dlls/winegstreamer/x86_64-windows/winegstreamer.dll "$OUT_WINE/lib/wine/x86_64-windows/"
cp dlls/winegstreamer/i386-windows/winegstreamer.dll   "$OUT_WINE/lib/wine/i386-windows/"
ok "copied into $OUT_APP"

# --- 5. Register in the prefix ------------------------------------------------
step "Registering in $PREFIX"
# regsvr32 instead of wineboot -u: wineboot also starts Steam (it is in the Run key).
export WINEPREFIX="$PREFIX" WINEMSYNC=1 WINEDEBUG=-all
/usr/bin/arch -x86_64 "$OUT_WINE/bin/wine" regsvr32 /s winegstreamer.dll
/usr/bin/arch -x86_64 "$OUT_WINE/bin/wine" 'C:\windows\syswow64\regsvr32.exe' /s winegstreamer.dll
/usr/bin/arch -x86_64 "$OUT_WINE/bin/wineserver" -w || true
ok "registered (64 and 32 bit)"

step "Done"
echo "Game videos now play through GStreamer. Launch Steam as usual."
