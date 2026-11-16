# kainat System Settings

A single graphical control centre for kainat OS. Network, sound, displays,
users, disks, services and firewall in one window — no terminal, no editing
configuration files by hand.

The app is deliberately **GUI-only**. When a feature needs a command-line tool
that is not installed, the panel says which tool is missing instead of failing
silently or printing an error to a console you cannot see. Where we can install
it, the row offers an *Install* action and says what will be installed.

## Install

Every download is a self-contained Linux x86_64 build. Pick one.

### Debian package (recommended)

```sh
sudo apt install ./kainat-system-settings_1.4.4_amd64.deb
```

This is the only format that adds a menu entry and an icon, and it is the only
one `apt` keeps up to date with the rest of the system.

### AppImage

```sh
chmod +x kainat-system-settings-1.4.4-x86_64.AppImage
./kainat-system-settings-1.4.4-x86_64.AppImage
```

The AppImage runtime needs FUSE 2 at run time. On this distribution the package
is `libfuse2t64`; on systems that call it `libfuse2`, install that. If you would
rather not install it, run the image with the extract-and-run flag:

```sh
./kainat-system-settings-1.4.4-x86_64.AppImage --appimage-extract-and-run
```

### Standalone binary

```sh
chmod +x kainat-system-settings-1.4.4-linux.x86_64
./kainat-system-settings-1.4.4-linux.x86_64
```

The `.zip` archives contain the same binaries plus a short readme, for people who
prefer a folder to a single file.

> **Which asset?** Take the one whose name ends in `.deb`, `.AppImage`, or
> `-linux.x86_64` / `-linux-x86_64.zip`. Names containing `internal-debug` are
> diagnostics builds: they carry the engine's debug symbols, log more, run
> slower, and are not meant for daily use.

## Verify the download

Each release ships `SHA256SUMS.txt`, covering every published asset. Put it in the
same directory as the file you downloaded, then run:

```sh
sha256sum -c --ignore-missing SHA256SUMS.txt
```

`--ignore-missing` skips the assets you did not download; without it `sha256sum`
reports them as missing files and exits non-zero.

## Requirements

- A Debian-based system running KDE Plasma (developed on kainat OS)
- An x86_64 CPU and a working OpenGL or Vulkan driver
- `pkexec` for the actions that need administrator rights

The `.deb` declares its library dependencies, so `apt` resolves those for you.
Desktop features are discovered at run time — NetworkManager, systemd, UPower,
power-profiles-daemon, PipeWire or PulseAudio. A KDE settings module is used when
present; a missing one shows a row saying the module is not installed.

## Building from source

The interface is GDScript for the Redot engine 26.2. Point `redotpath.txt` at your
own engine binary and install the Redot 26.2 export templates; the `--import` pass
below resolves the shared panel classes before the export runs.

```sh
ENGINE="$(cat redotpath.txt)"
"$ENGINE" --headless --path . --import
"$ENGINE" --headless --path . --export-release "Linux" "kainat-system-settings.x86_64"
packaging/linux/make-deb.sh       "kainat-system-settings.x86_64" "1.4.4"
packaging/linux/make-appimage.sh  "kainat-system-settings.x86_64" "1.4.4"
```

Both packaging scripts take `<binary> <version> [output-dir]`. CI
(`.github/workflows/build.yml`) runs the same steps, exports the release and
internal debug builds, builds the `.deb` and the AppImage, writes
`SHA256SUMS.txt` and publishes everything on a tag push.

## Source layout

| Path | Contents |
|---|---|
| `panels/` | one script per panel, plus the shared panel base class |
| `menu_buttons.gd` | sidebar and the panel registry |
| `search_bar.gd`, `search_manager.gd` | the search field and its index |
| `main-panel.tscn` | the window scene |
| `icons/` | icon assets |
| `packaging/linux/` | `.deb` and AppImage builders, desktop entry, icon |
| `project.godot` | engine configuration; the single source of the version |
| `LICENSE` | GNU GPL v3 licence text |

## Licence

We release the app under the GNU General Public License, version 3 or any later
version. The full text ships in `LICENSE` at the repository root, and the `.deb`
installs the same licence as a DEP-5 machine-readable file at
`/usr/share/doc/kainat-system-settings/copyright`.
