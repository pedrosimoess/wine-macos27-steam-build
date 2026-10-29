#!/usr/bin/env bash
#
# steam-cx.sh — launch Steam through steam-on-m1-wine, using Wine CX.app
# instead of Wine Stable.app.
#
# Configuration (environment variables):
#   STEAM_ON_M1_WINE  your steam-on-m1-wine clone       (default: ~/steam-on-m1-wine)
#   WINE_CX_DIR       build.sh work folder              (default: ~/Games/wine-cx)
#   WINE_APP          the app to run                    (default: $WINE_CX_DIR/Wine CX.app)
#   WINEPREFIX        the Steam prefix                  (default: ~/.wine-steam)
#   WINEMSYNC         1 = Mach-based sync (CrossOver's default), 0 = off  (default: 1)
#
set -euo pipefail

STEAM_ON_M1_WINE="${STEAM_ON_M1_WINE:-$HOME/steam-on-m1-wine}"
WINE_CX_DIR="${WINE_CX_DIR:-$HOME/Games/wine-cx}"
export WINE_APP="${WINE_APP:-$WINE_CX_DIR/Wine CX.app}"
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-steam}"
export WINEMSYNC="${WINEMSYNC:-1}"
# CrossOver's Wine reports the Windows user name as "crossover" by default.
# Keep the real one, so an existing prefix (created by Wine Stable) still finds
# its user folder, Steam login and settings.
export CX_REPORT_REAL_USERNAME=1
export MVK_CONFIG_LOG_LEVEL="${MVK_CONFIG_LOG_LEVEL:-1}"

# Options set with ./cx
STATE="$WINE_CX_DIR/state"
# avx: Rosetta runs AVX/AVX2, but only advertises it to games with this variable.
if [[ -f "$STATE/avx" || "${CX_AVX:-0}" == 1 ]]; then
    export ROSETTA_ADVERTISE_AVX=1
fi
# dxvk/dx9: drop dxgi/d3d11 from WINEDLLOVERRIDES so the registry applies
# (DXVK for games, Wine's DirectX for Steam itself). Needs the launch-steam.sh
# patch that ./cx dxvk on applies.
if [[ -f "$STATE/dxvk" || -f "$STATE/dx9" ]]; then
    export STEAM_WINEDLLOVERRIDES="bcrypt=b;ncrypt=b;gameoverlayrenderer,gameoverlayrenderer64=d"
fi
# retina: a virtual desktop at 2x, matching the Retina pixel size.
if [[ -f "$STATE/retina" && -z "${WINE_VIRTUAL_DESKTOP+x}" ]]; then
    b="$(osascript -e 'tell application "Finder" to get bounds of window of desktop' 2>/dev/null || true)"
    w="$(echo "$b" | awk -F', ' '{print $3}')"; h="$(echo "$b" | awk -F', ' '{print $4}')"
    if [[ -n "$w" && -n "$h" ]]; then export WINE_VIRTUAL_DESKTOP="$((w * 2))x$((h * 2))"; fi
fi

launcher="$STEAM_ON_M1_WINE/scripts/launch-steam.sh"
[[ -f "$launcher" ]] || { echo "steam-on-m1-wine not found at $STEAM_ON_M1_WINE (set STEAM_ON_M1_WINE)" >&2; exit 1; }
[[ -x "$WINE_APP/Contents/Resources/wine/bin/wine" ]] || { echo "Wine not found at $WINE_APP (run build.sh first)" >&2; exit 1; }
[[ -d "$WINEPREFIX/drive_c" ]] || { echo "no Wine prefix at $WINEPREFIX (install Steam with steam-on-m1-wine first)" >&2; exit 1; }

# launch-steam.sh also re-installs the steamwebhelper wrapper, which Steam
# updates overwrite (a black Steam window is the symptom).
cd "$STEAM_ON_M1_WINE"
exec bash "$launcher" --detach
