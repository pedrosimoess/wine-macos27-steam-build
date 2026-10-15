# wine-macos27-steam-build

[Português](README.pt-BR.md)

Build the Wine from CodeWeavers' **CrossOver open-source release** on an Apple Silicon Mac, and use it with [steam-on-m1-wine](https://github.com/notpop/steam-on-m1-wine) to run the Windows Steam client.

This fixed one thing that plain Wine 11 couldn't: **Steam multiplayer lobbies**. With Gcenx's Wine 11.0, The Binding of Isaac: Repentance+ got stuck at "Creating lobby" and couldn't join a friend's lobby. With this build, creating and joining lobbies works instantly.

> Not affiliated with or endorsed by CodeWeavers. CrossOver is a trademark of CodeWeavers, Inc. This project only uses the source code they publish under the LGPL. If you can afford it, [buy CrossOver](https://www.codeweavers.com/crossover): it funds a large part of Wine's development, and it includes the closed-source parts this build doesn't have.

## Tested on

| | |
| --- | --- |
| Mac | MacBook Air M4 |
| macOS | 27.0.1, Command Line Tools 27 |
| Wine source | CrossOver 26.3.0 (Wine 11.0) |
| Base app | Gcenx Wine Stable 11.0_1 |
| steam-on-m1-wine | [alexwinskii fork](https://github.com/alexwinskii/steam-on-m1-wine/tree/macos26-fixes), branch `macos26-fixes` |
| Game | The Binding of Isaac: Rebirth + Repentance+, online co-op |

Other games and macOS 26 should work but haven't been tested.

## How to use

**1. Install steam-on-m1-wine and log in to Steam once.** Follow its README. The minimal install is enough. This was tested with the fork's `macos26-fixes` branch, which fixes the install on recent macOS and Homebrew; upstream may also work by now.

```bash
git clone -b macos26-fixes https://github.com/alexwinskii/steam-on-m1-wine.git ~/steam-on-m1-wine
cd ~/steam-on-m1-wine
bash install.sh --minimal
```

This installs Gcenx's `Wine Stable.app` (which `build.sh` reuses) and creates the Steam prefix at `~/.wine-steam`.

**2. Build Wine CX.** A first build takes about 15 minutes on an M4 (longer on older Macs) and about 6 GB of disk space:

```bash
git clone https://github.com/pedrosimoess/wine-macos27-steam-build.git
cd wine-macos27-steam-build
bash build.sh
```

The script installs the missing Homebrew build tools, downloads the CrossOver sources from CodeWeavers (checked against a SHA-256), compiles them and creates `~/Games/wine-cx/Wine CX.app`.

**3. Launch Steam with Wine CX:**

```bash
bash steam-cx.sh
```

The first launch updates the prefix to the new Wine version, which takes a minute. To go back to plain Wine 11, launch steam-on-m1-wine as usual.

To keep your original prefix untouched, clone it and point the launcher at the copy:

```bash
cp -cR ~/.wine-steam ~/.wine-steam-cx
WINEPREFIX=~/.wine-steam-cx bash steam-cx.sh
```

### Configuration

Both scripts read environment variables. `bash build.sh --help` lists them.

| Variable | Default | Used by |
| --- | --- | --- |
| `WINE_CX_DIR` | `~/Games/wine-cx` | both |
| `OUT_APP` | `$WINE_CX_DIR/Wine CX.app` | `build.sh` |
| `GCENX_APP` | `/Applications/Wine Stable.app` | `build.sh` |
| `JOBS` | number of CPU cores | `build.sh` |
| `STEAM_ON_M1_WINE` | `~/steam-on-m1-wine` | `steam-cx.sh` |
| `WINE_APP` | `$WINE_CX_DIR/Wine CX.app` | `steam-cx.sh` |
| `WINEPREFIX` | `~/.wine-steam` | `steam-cx.sh` |
| `WINEMSYNC` | `1` | `steam-cx.sh` |

### Troubleshooting

- **Black Steam window after a Steam update.** Steam overwrote steam-on-m1-wine's `steamwebhelper` wrapper. Quit Steam and run `steam-cx.sh` again: it reinstalls the wrapper on every launch.
- **Steam asks you to log in again.** The prefix was opened with the Windows user name `crossover` (CrossOver's default). `steam-cx.sh` sets `CX_REPORT_REAL_USERNAME=1` to avoid this. If you launch Wine CX another way, set it too.
- **Quit everything Wine:** `pkill -9 -i -f '\.exe|wineserver|wine64-preloader'`

## Rebuilding and uninstalling

Keep `src/` and `build/` in `~/Games/wine-cx` and `build.sh` only recompiles what changed. The build folder depends on the sources, so move or delete them together.

To uninstall, delete `~/Games/wine-cx`. Prefixes and `Wine Stable.app` are never modified by `build.sh`.

## What it takes to build CrossOver's Wine on macOS 27

The build mirrors the options of Gcenx's wine-stable, plus fixes for problems that show up on macOS 27:

| Problem | Fix in `build.sh` |
| --- | --- |
| The Command Line Tools are arm64-only, so `xcrun` and the `/usr/bin` shims fail under Rosetta | Only `configure` runs as x86_64. `clang` and `make` are called natively from the CLT folder, with `-arch x86_64` |
| The CLT's bison 2.3 shadows Homebrew's | Homebrew bison and flex come first in `PATH` |
| Gcenx's dylibs have unversioned install names, so configure detects garbage SONAMEs | SONAMEs passed explicitly with `ac_cv_lib_soname_*` |
| `sfnt2fon` aborts because dyld can't find `libfreetype.dylib` | Gcenx dylibs symlinked into the build folder |
| CrossOver's `CW HACK 25909` in `win32u/vulkan.c` requires `SONAME_LIBVULKAN` | Built `--with-vulkan` against the MoltenVK bundled with Wine Stable |

Which CodeWeavers patch fixes the lobbies hasn't been isolated yet. The likely candidates are in the network code (`nsiproxy`, `ws2_32`). If you find it, please open an issue.

## License and credits

The scripts in this repository are MIT-licensed (see [LICENSE](LICENSE)). The Wine you build is LGPL-2.1-or-later, like the CodeWeavers sources it comes from. The bundled libraries copied from Wine Stable.app keep their own licenses.

- [Wine](https://www.winehq.org) and [CodeWeavers](https://www.codeweavers.com), for the source release
- [Gcenx](https://github.com/Gcenx/macOS_Wine_builds), for the macOS Wine builds this one is based on
- [notpop/steam-on-m1-wine](https://github.com/notpop/steam-on-m1-wine) and the [alexwinskii fork](https://github.com/alexwinskii/steam-on-m1-wine), for making the Steam client run on Wine 11
