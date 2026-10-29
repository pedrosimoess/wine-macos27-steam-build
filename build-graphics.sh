#!/usr/bin/env bash
#
# build-graphics.sh — build the DirectX translation layers from the same
# CrossOver open-source release: CodeWeavers' DXVK fork (Direct3D 9/10/11 to
# Vulkan) and CodeWeavers' MoltenVK fork (Vulkan to Metal).
#
# Without them Wine CX only offers Direct3D 11 at feature level 9_3, which most
# DirectX 11 games refuse. Upstream MoltenVK is not enough: this DXVK needs the
# geometry shader support that only CodeWeavers' MoltenVK provides.
#
# Requires full Xcode (for MoltenVK) with its license accepted:
#   sudo /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -license
#
# Output:
#   $WINE_CX_DIR/dxvk-cx/{x64,x32}/*.dll     (turn on with: ./cx dxvk on)
#   libMoltenVK.dylib installed into Wine CX.app (the original is kept as .orig)
#
# Configuration: WINE_CX_DIR, OUT_APP (same as build.sh), XCODE (default /Applications/Xcode.app)
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
fi

CX_VERSION="26.3.0"
CX_URL="https://media.codeweavers.com/pub/crossover/source/crossover-sources-${CX_VERSION}.tar.gz"
CX_SHA256="ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872"

BASE="${WINE_CX_DIR:-$HOME/Games/wine-cx}"
OUT_APP="${OUT_APP:-$BASE/Wine CX.app}"
XCODE="${XCODE:-/Applications/Xcode.app}"
WORK="$BASE/graphics"
SRC="$WORK/sources"
LOGS="$BASE/logs"
DXVK_OUT="$BASE/dxvk-cx"

ts()   { date '+%H:%M:%S'; }
step() { printf '\n[%s] ==> %s\n' "$(ts)" "$*"; }
ok()   { printf '[%s]     ok: %s\n' "$(ts)" "$*"; }
die()  { printf '\n[%s] ERROR: %s\n' "$(ts)" "$*" >&2; exit 1; }
trap 'die "failed at line $LINENO: $BASH_COMMAND"' ERR

# --- 0. Checks ----------------------------------------------------------------
step "Checks"
[[ -d "$OUT_APP/Contents/Resources/wine/lib" ]] || die "Wine CX.app not found at $OUT_APP (run build.sh first)"
[[ -d "$XCODE" ]] || die "Xcode not found at $XCODE (MoltenVK needs full Xcode, not only the Command Line Tools)"
export DEVELOPER_DIR="$XCODE/Contents/Developer"
if xcodebuild -version 2>&1 | grep -qi 'license'; then
    die "accept the Xcode license first: sudo $DEVELOPER_DIR/usr/bin/xcodebuild -license"
fi
ok "$(xcodebuild -version | head -1)"
mkdir -p "$WORK" "$LOGS"

# --- 1. Tools -----------------------------------------------------------------
step "Build tools"
export PATH="/opt/homebrew/bin:$PATH" HOMEBREW_NO_ENV_HINTS=1
need=()
for f in meson ninja glslang mingw-w64; do
    brew list --versions "$f" >/dev/null 2>&1 || need+=("$f")
done
if (( ${#need[@]} )); then brew install "${need[@]}"; fi
ok "meson $(meson --version)"

# --- 2. Sources ---------------------------------------------------------------
step "CrossOver $CX_VERSION sources (dxvk, moltenvk)"
if [[ ! -f "$SRC/dxvk/meson.build" || ! -d "$SRC/moltenvk/MoltenVK" ]]; then
    tarball="$WORK/crossover-sources-${CX_VERSION}.tar.gz"
    [[ -f "$tarball" ]] || { curl -fL --retry 3 --progress-bar -o "$tarball.part" "$CX_URL"; mv "$tarball.part" "$tarball"; }
    echo "$CX_SHA256  $tarball" | shasum -a 256 -c - >/dev/null || die "source checksum mismatch"
    rm -rf "$WORK/x"; mkdir -p "$WORK/x"
    tar -xzf "$tarball" -C "$WORK/x" sources/dxvk sources/moltenvk
    rm -rf "$SRC"; mv "$WORK/x/sources" "$SRC"; rm -rf "$WORK/x" "$tarball"
fi
ok "extracted"

# --- 3. Patches for current compilers -----------------------------------------
step "Patches"
# Newer mingw-w64 headers already declare these; the old workarounds now clash.
perl -0pi -e 's/#else\n(__CRT_UUID_DECL\(ID3D10StateBlock)/#elif 0 \/* newer mingw-w64 headers declare this *\/\n$1/' \
    "$SRC/dxvk/src/d3d10/d3d10_interfaces.h"
perl -0pi -e 's/(#ifndef _MSC_VER\n)(typedef struct _D3DDEVINFO_RESOURCEMANAGER\n\{\n  char dummy;\n\} D3DDEVINFO_RESOURCEMANAGER, \* LPD3DDEVINFO_RESOURCEMANAGER;\n)/$1#if 0 \/* newer mingw-w64 headers define this *\/\n$2#endif\n/' \
    "$SRC/dxvk/src/d3d9/d3d9_include.h"
# Xcode 27 no longer accepts a macOS 10.15 deployment target.
for p in ExternalDependencies.xcodeproj MoltenVK/MoltenVK.xcodeproj MoltenVKShaderConverter/MoltenVKShaderConverter.xcodeproj; do
    sed -i '' 's/MACOSX_DEPLOYMENT_TARGET = 10.15/MACOSX_DEPLOYMENT_TARGET = 12.0/' "$SRC/moltenvk/$p/project.pbxproj"
done
ok "applied"

# --- 4. DXVK ------------------------------------------------------------------
step "DXVK (32 and 64 bit)"
rm -rf "$DXVK_OUT"
for arch in 64 32; do
    b="$WORK/dxvk-build$arch"
    if [[ ! -f "$b/build.ninja" ]]; then
        (cd "$SRC/dxvk" && meson setup --cross-file "build-win$arch.txt" --buildtype release \
            --prefix "$DXVK_OUT" --bindir "x$arch" --libdir "x$arch" \
            -Dc_args=-Wno-error '-Dcpp_args=-Wno-error -include cstdint' "$b") \
            >"$LOGS/dxvk-setup$arch.log" 2>&1 || { tail -30 "$LOGS/dxvk-setup$arch.log"; die "meson setup failed"; }
    fi
    ninja -C "$b" install >"$LOGS/dxvk-build$arch.log" 2>&1 \
        || { grep -m5 -A8 'error' "$LOGS/dxvk-build$arch.log"; die "DXVK $arch-bit build failed"; }
done
rm -f "$DXVK_OUT"/x*/*.dll.a
ok "DXVK built into $DXVK_OUT"

# --- 5. MoltenVK --------------------------------------------------------------
step "MoltenVK (5 to 15 minutes)"
# CodeWeavers ship their own SPIRV-Cross (not a git checkout). fetchDependencies
# deletes External/SPIRV-Cross before linking the root we pass, so keep a copy.
if [[ ! -d "$WORK/spirv-cross-cw" ]]; then
    cp -R "$SRC/moltenvk/External/SPIRV-Cross" "$WORK/spirv-cross-cw"
fi
(
    cd "$SRC/moltenvk"
    ./fetchDependencies --macos --spirv-cross-root "$WORK/spirv-cross-cw" >"$LOGS/moltenvk-deps.log" 2>&1 \
        || { tail -30 "$LOGS/moltenvk-deps.log"; exit 1; }
    make macos >"$LOGS/moltenvk-build.log" 2>&1 \
        || { grep -m10 -A5 'error' "$LOGS/moltenvk-build.log"; exit 1; }
) || die "MoltenVK build failed"
mvk="$SRC/moltenvk/Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib"
lipo -info "$mvk" | grep -q x86_64 || die "built MoltenVK has no x86_64 slice"
lib="$OUT_APP/Contents/Resources/wine/lib"
[[ -f "$lib/libMoltenVK.dylib.orig" ]] || cp -p "$lib/libMoltenVK.dylib" "$lib/libMoltenVK.dylib.orig"
cp -f "$mvk" "$lib/libMoltenVK.dylib.new" && mv -f "$lib/libMoltenVK.dylib.new" "$lib/libMoltenVK.dylib"
ok "installed into $OUT_APP"

step "Done"
echo "Turn DirectX 10/11 on in your Steam prefix (with Steam closed): ./cx dxvk on"
