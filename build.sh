#!/usr/bin/env bash
#
# build.sh — build the Wine from CodeWeavers' CrossOver open-source release
# (LGPL) for Apple Silicon Macs and package it as "Wine CX.app".
#
# The result is a drop-in replacement for Gcenx's "Wine Stable.app", meant to
# be used with steam-on-m1-wine (see README.md).
#
# - Uses the x86_64 libraries already bundled in Wine Stable.app (freetype,
#   gnutls, SDL2, MoltenVK). Homebrew only provides build tools and headers.
# - Never modifies Wine Stable.app or any Wine prefix.
# - Safe to re-run: every step skips work that is already done, and an
#   existing build folder makes rebuilds incremental.
#
# Configuration (environment variables):
#   WINE_CX_DIR  work folder for sources, build and logs  (default: ~/Games/wine-cx)
#   OUT_APP      where to create the app                  (default: $WINE_CX_DIR/Wine CX.app)
#   GCENX_APP    Gcenx Wine Stable.app to base the app on (default: /Applications/Wine Stable.app)
#   JOBS         parallel compile jobs                    (default: number of CPU cores)
#
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
fi

CX_VERSION="26.3.0"
CX_URL="https://media.codeweavers.com/pub/crossover/source/crossover-sources-${CX_VERSION}.tar.gz"
CX_SHA256="ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872"

HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="${WINE_CX_DIR:-$HOME/Games/wine-cx}"
SRC="$BASE/src"
BUILD="$BASE/build"
STAGE="$BASE/stage"
LOGS="$BASE/logs"
GCENX_APP="${GCENX_APP:-/Applications/Wine Stable.app}"
GCENX_LIB="$BASE/gcenx-lib"   # symlink without spaces, for the linker
OUT_APP="${OUT_APP:-$BASE/Wine CX.app}"
OUT_WINE="$OUT_APP/Contents/Resources/wine"
JOBS="${JOBS:-$(sysctl -n hw.logicalcpu)}"
X86=(/usr/bin/arch -x86_64)

ts()   { date '+%H:%M:%S'; }
step() { printf '\n[%s] ==> %s\n' "$(ts)" "$*"; }
ok()   { printf '[%s]     ok: %s\n' "$(ts)" "$*"; }
die()  { printf '\n[%s] ERROR: %s\n' "$(ts)" "$*" >&2; exit 1; }
trap 'die "failed at line $LINENO: $BASH_COMMAND"' ERR

# --- 0. Checks ----------------------------------------------------------------
step "Checks"
[[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]] || die "this script is for Apple Silicon Macs"
[[ -d "$GCENX_APP/Contents/Resources/wine/lib" ]] \
    || die "Wine Stable.app not found at $GCENX_APP (install steam-on-m1-wine first, or set GCENX_APP)"
[[ -x /opt/homebrew/bin/brew ]] || die "Homebrew not found in /opt/homebrew"
"${X86[@]}" /usr/bin/true 2>/dev/null || die "Rosetta 2 is not installed: softwareupdate --install-rosetta"
xcode-select -p >/dev/null 2>&1 || die "Command Line Tools missing: xcode-select --install"
mkdir -p "$BASE" "$LOGS"
avail_gb="$(df -g "$BASE" | awk 'NR==2 {print $4}')"
(( avail_gb >= 6 )) || die "only ${avail_gb} GB free; the build needs about 6 GB"
ok "macOS $(sw_vers -productVersion), ${JOBS} jobs, ${avail_gb} GB free"

# --- 1. Build tools and headers (Homebrew, arm64) -----------------------------
step "Build tools"
export PATH="/opt/homebrew/bin:$PATH"
export HOMEBREW_NO_ENV_HINTS=1
BREW="$(brew --prefix)"
need=()
for f in bison flex freetype gnutls sdl2 mingw-w64; do
    brew list --versions "$f" >/dev/null 2>&1 || need+=("$f")
done
if (( ${#need[@]} )); then
    echo "Installing: ${need[*]}"
    brew install "${need[@]}"
fi
CLT_BIN="$(xcode-select -p)/usr/bin"
[[ -x "$CLT_BIN/clang" && -x "$CLT_BIN/make" ]] || die "clang/make not found in $CLT_BIN"
# macOS 27 ships the Command Line Tools as arm64 only, so the /usr/bin shims
# (xcrun, clang, make...) break under Rosetta. Resolve everything natively and
# call the tools from the CLT folder directly.
SDK="$(xcrun --show-sdk-path)"
export SDKROOT="$SDK"
# Homebrew's bison/flex must come before the CLT, which ship bison 2.3.
export PATH="$BREW/opt/bison/bin:$BREW/opt/flex/bin:$CLT_BIN:$PATH"
bison_major="$(bison --version | head -1 | grep -oE '[0-9]+' | head -1)"
(( bison_major >= 3 )) || die "bison >= 3 is not first in PATH"
command -v x86_64-w64-mingw32-gcc >/dev/null || die "mingw-w64 (x86_64) not found"
command -v i686-w64-mingw32-gcc   >/dev/null || die "mingw-w64 (i686) not found"
[[ -f "$BREW/opt/freetype/include/freetype2/ft2build.h" ]] || die "freetype headers not found"
[[ -f "$BREW/opt/gnutls/include/gnutls/gnutls.h" ]]       || die "gnutls headers not found"
[[ -f "$BREW/include/SDL2/SDL.h" ]]                       || die "SDL2 headers not found"
ok "bison $(bison --version | head -1 | awk '{print $NF}'), $(x86_64-w64-mingw32-gcc --version | head -1)"

# --- 2. CrossOver sources -----------------------------------------------------
step "CrossOver $CX_VERSION sources"
if [[ ! -f "$SRC/configure" ]]; then
    tarball="$BASE/crossover-sources-${CX_VERSION}.tar.gz"
    if [[ ! -f "$tarball" ]]; then
        curl -fL --retry 3 --progress-bar -o "$tarball.part" "$CX_URL"
        mv "$tarball.part" "$tarball"
    fi
    echo "$CX_SHA256  $tarball" | shasum -a 256 -c - >/dev/null || die "source checksum mismatch"
    tmp="$BASE/extract-tmp"
    rm -rf "$tmp"; mkdir -p "$tmp"
    tar -xzf "$tarball" -C "$tmp" sources/wine
    rm -rf "$SRC"; mv "$tmp/sources/wine" "$SRC"; rm -rf "$tmp"
    rm -f "$tarball"
fi
grep -q '^Wine version 11.0' "$SRC/VERSION" || die "unexpected source version: $(cat "$SRC/VERSION")"
ok "$(cat "$SRC/VERSION") (CrossOver $CX_VERSION)"

# Our own fixes on top of CrossOver's code (see patches/).
for p in "$HERE"/patches/*.patch; do
    name="$(basename "$p")"
    if patch -d "$SRC" -p1 -R -s -f --dry-run <"$p" >/dev/null 2>&1; then
        ok "$name already applied"
    elif patch -d "$SRC" -p1 -N -s --dry-run <"$p" >/dev/null 2>&1; then
        patch -d "$SRC" -p1 -N -s <"$p"
        ok "$name applied"
    else
        die "$name does not apply to these sources"
    fi
done

# --- 3. x86_64 libraries from Wine Stable -------------------------------------
step "x86_64 libraries from Wine Stable"
ln -sfn "$GCENX_APP/Contents/Resources/wine/lib" "$GCENX_LIB"
for lib in libfreetype.6.dylib libgnutls.30.dylib libSDL2-2.0.0.dylib libMoltenVK.dylib; do
    [[ -f "$GCENX_LIB/$lib" ]] || die "$lib not found in $GCENX_APP"
done
ok "freetype, gnutls, SDL2 and MoltenVK found"

# --- 4. Configure -------------------------------------------------------------
step "Configure"
mkdir -p "$BUILD" "$BASE/empty-pkgconfig"
if [[ ! -f "$BUILD/Makefile" ]]; then
    (
        cd "$BUILD"
        export MACOSX_DEPLOYMENT_TARGET=14.0
        # Options mirror Gcenx's wine-stable build (macports-wine).
        # Only configure runs as x86_64, so it detects an x86_64 host; the
        # compiler is the native arm64 clang emitting x86_64 code via -arch.
        # The ac_cv_lib_soname_* values are passed explicitly because the
        # Gcenx dylibs have unversioned install names, which confuses
        # configure's SONAME detection.
        "${X86[@]}" "$SRC/configure" \
            --prefix="$STAGE" \
            --enable-archs=i386,x86_64 \
            --disable-tests --disable-winebth_sys --disable-winemenubuilder \
            --without-alsa --without-capi --with-coreaudio --without-dbus \
            --without-ffmpeg --without-fontconfig --with-freetype --without-gettext \
            --without-gettextpo --without-gphoto --with-gnutls --without-gssapi \
            --without-gstreamer --without-inotify --without-krb5 --without-netapi \
            --without-opengl --without-oss --without-pcap --without-pulse \
            --without-sane --with-sdl --without-udev --without-usb --without-v4l2 \
            --with-vulkan --without-wayland --without-x \
            CC="$CLT_BIN/clang -arch x86_64 -isysroot $SDK" \
            CXX="$CLT_BIN/clang++ -arch x86_64 -isysroot $SDK" \
            OBJC="$CLT_BIN/clang -arch x86_64 -isysroot $SDK" \
            CFLAGS='-O2 -Wno-error' OBJCFLAGS='-O2 -Wno-error' CROSSCFLAGS='-O2 -Wno-error' \
            LDFLAGS='-Wl,-rpath,@loader_path/../../' \
            PKG_CONFIG_LIBDIR="$BASE/empty-pkgconfig" \
            FREETYPE_CFLAGS="-I$BREW/opt/freetype/include/freetype2" \
            FREETYPE_LIBS="-L$GCENX_LIB -lfreetype" \
            GNUTLS_CFLAGS="-I$BREW/opt/gnutls/include" \
            GNUTLS_LIBS="-L$GCENX_LIB -lgnutls" \
            SDL2_CFLAGS="-I$BREW/include/SDL2 -D_THREAD_SAFE" \
            SDL2_LIBS="-L$GCENX_LIB -lSDL2" \
            ac_cv_lib_soname_freetype=libfreetype.6.dylib \
            ac_cv_lib_soname_gnutls=libgnutls.30.dylib \
            ac_cv_lib_soname_SDL2=libSDL2-2.0.0.dylib \
            ac_cv_lib_soname_vulkan=libMoltenVK.dylib
    ) >"$LOGS/configure.log" 2>&1 \
        || { rm -f "$BUILD/Makefile"; tail -20 "$LOGS/configure.log"; die "configure failed; see $BUILD/config.log"; }
fi
config_h="$BUILD/include/config.h"
grep -q 'SONAME_LIBFREETYPE "libfreetype.6.dylib"' "$config_h" || die "configure did not detect freetype"
grep -q 'SONAME_LIBGNUTLS "libgnutls.30.dylib"'    "$config_h" || die "configure did not detect gnutls"
# CrossOver's "CW HACK 25909" in win32u/vulkan.c needs SONAME_LIBVULKAN even
# when configure does not define it. Add it without touching config.h's
# mtime, so an existing build does not recompile from scratch.
if ! grep -q '^#define SONAME_LIBVULKAN' "$config_h"; then
    cp -p "$config_h" "$config_h.orig"
    printf '\n#define SONAME_LIBVULKAN "libMoltenVK.dylib"\n' >>"$config_h"
    touch -r "$config_h.orig" "$config_h"
    rm -f "$config_h.orig"
fi
ok "freetype, gnutls and Vulkan (MoltenVK) configured"
# Build-time tools (e.g. sfnt2fon) link to the Gcenx dylibs by bare install
# name, which dyld resolves relative to the current folder: the build folder.
for lib in "$GCENX_LIB"/*.dylib; do
    ln -sf "$lib" "$BUILD/$(basename "$lib")"
done
ln -sf "$GCENX_LIB/libfreetype.6.dylib" "$BUILD/libfreetype.dylib"
ln -sf "$GCENX_LIB/libgnutls.30.dylib"  "$BUILD/libgnutls.dylib"

# --- 5. Compile ---------------------------------------------------------------
step "Compiling with ${JOBS} jobs (about 15 minutes on an M4 for a first build)"
make -C "$BUILD" -j"$JOBS" >"$LOGS/make.log" 2>&1 \
    || { tail -40 "$LOGS/make.log"; die "make failed; full log at $LOGS/make.log"; }
ok "compiled"

# --- 6. Install into a staging folder -----------------------------------------
step "Installing into $STAGE"
rm -rf "$STAGE"
make -C "$BUILD" install-lib >"$LOGS/install.log" 2>&1 \
    || { tail -40 "$LOGS/install.log"; die "make install-lib failed"; }
[[ -x "$STAGE/bin/wine" ]]                      || die "bin/wine missing"
[[ -f "$STAGE/lib/wine/x86_64-unix/ntdll.so" ]] || die "ntdll.so missing"
[[ -d "$STAGE/lib/wine/i386-windows" ]]         || die "32-bit DLLs missing"
ok "installed"

# --- 7. Assemble Wine CX.app --------------------------------------------------
step "Assembling $OUT_APP"
if pgrep -f "$OUT_WINE/bin/" >/dev/null 2>&1; then
    die "Wine from $OUT_APP is running; quit Steam and run this script again"
fi
rm -rf "$OUT_APP"
mkdir -p "$(dirname "$OUT_APP")"
cp -cR "$GCENX_APP" "$OUT_APP" 2>/dev/null || cp -R "$GCENX_APP" "$OUT_APP"
rm -rf "${OUT_WINE:?}/bin" "${OUT_WINE:?}/lib/wine"
cp -R "$STAGE/bin"      "$OUT_WINE/bin"
cp -R "$STAGE/lib/wine" "$OUT_WINE/lib/wine"
mkdir -p "$OUT_WINE/share/wine"
cp -R "$STAGE/share/wine/." "$OUT_WINE/share/wine/"
xattr -dr com.apple.quarantine "$OUT_APP" 2>/dev/null || true
rm -rf "$STAGE"
ok "$("${X86[@]}" "$OUT_WINE/bin/wine" --version)"

step "Done"
du -sh "$BUILD" 2>/dev/null | awk '{print "Build folder: " $1 " (keep it with src/ for fast rebuilds, or delete both)"}'
echo "App: $OUT_APP"
echo "Next: bash steam-cx.sh   (see README.md)"
