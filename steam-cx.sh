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

launcher="$STEAM_ON_M1_WINE/scripts/launch-steam.sh"
[[ -f "$launcher" ]] || { echo "steam-on-m1-wine not found at $STEAM_ON_M1_WINE (set STEAM_ON_M1_WINE)" >&2; exit 1; }
[[ -x "$WINE_APP/Contents/Resources/wine/bin/wine" ]] || { echo "Wine not found at $WINE_APP (run build.sh first)" >&2; exit 1; }
[[ -d "$WINEPREFIX/drive_c" ]] || { echo "no Wine prefix at $WINEPREFIX (install Steam with steam-on-m1-wine first)" >&2; exit 1; }

# launch-steam.sh also re-installs the steamwebhelper wrapper, which Steam
# updates overwrite (a black Steam window is the symptom).
cd "$STEAM_ON_M1_WINE"
exec bash "$launcher" --detach
