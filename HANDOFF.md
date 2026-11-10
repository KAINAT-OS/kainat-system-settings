# Handoff — Kainat System Settings

**Audience:** anyone (human or agent) working on another part of Kainat OS who needs to
understand, modify, package or integrate this app.

**Status:** feature-complete for its current scope, tagged **v1.4.0**, branch `master`,
clean working tree.

| | |
|---|---|
| Repo | `/media/kainatq/GAMES_AND_OTHERS/kainat-os/sources/apps/kainat-system-settings` |
| Git root | that directory (the parent `kainat-os/` tree is *not* a git repo) |
| Engine | Redot LTS **v26.2** (Godot 4 fork), GL Compatibility renderer |
| Binary used for testing | `/media/kainatq/GAMES_AND_OTHERS/godot/redot/redot.linuxbsd.editor.x86_64` (also recorded in `redotpath.txt`) |
| Entry scene | `res://main-panel.tscn` |
| Target OS | Debian-based Kainat OS, KDE Plasma desktop |
| Tags | `v1.1.0`, `v1.2.0`, `v1.3.0`, `v1.4.0` |
| Rollback branch | `baseline-before-overhaul` (state before the GUI overhaul) |

---

## 1. What this app is

A complete graphical replacement for the terminal: a newcomer to Linux should be able to
administer a Kainat OS machine without ever opening a shell. Every action is a native
Redot control or, where a task is genuinely complex (printer setup, Samba, KWin effects),
a one-click hand-off to the corresponding KDE KCM.

**29 panels** exist today:

| Section | Panels |
|---|---|
| (top) | `about` (startup page / system information) |
| Appearance | `personalization`, `displays`, `accessibility`, `input_methods` |
| Sound & Devices | `io`, `bluetooth`, `printers`, `hardware` |
| Network | `nac` (networks & proxy & hotspot), `vpn_manager`, `ssh_manager`, `sharing` (Samba), `firewall` (ufw) |
| Applications | `applications`, `universal_installer`, `windows_compat`, `startup` |
| System | `update`, `driver-manager`, `services`, `disk_manager`, `backup`, `boot`, `troubleshooting`, `ps` (power), `lal` (date/time & language), `las` (sessions), `users`, `about` |

`panels/settings_panel.gd` is the shared base class, `panels/kainat_shell.gd` is the
system-command helper library. Neither is a page.

---

## 2. Architecture in one screen

```
main-panel.tscn
├── SearchBar (script search_bar.gd)        search box + floating results popup
├── MarginContainer/VBoxContainer/HBoxContainer
│   ├── ScrollContainer/menu-buttons        VBoxContainer, script menu_buttons.gd
│   │   ├── Brand                            "Kainat OS / System Settings"
│   │   ├── Favorites (runtime-only box)     rebuilt from kdeglobals
│   │   ├── Section_Appearance (Label wrap)  runtime-built section headers
│   │   ├── personalization, displays, …     one Button per panel (node name == panel name)
│   │   └── …
│   └── router (PanelContainer)              current panel instance lives here
└── (theme applied to root by the KDETheme autoload)
```

* **Navigation** — `menu_buttons.gd::_change_scene(name)` loads
  `res://panels/<name>.gd`, instantiates it and replaces all children of `router`.
  A legacy `res://panels/<name>.tscn` is used as a fallback. Panels are recreated on
  every navigation, so panels keep no state between visits.
* **Sidebar button name == panel script name.** That is the entire registration
  mechanism for navigation; there is no manifest.
* **Favourites** are stored in `kdeglobals` (group `Kainat System Settings`,
  key `Favourites`) via `KainatShell.favorites()` / `set_favorite()`, and the star on
  each row toggles them. Sidebar favourites are rebuilt on demand through the
  `favorites_ui` node group.
* **Search** — `search_manager.gd` is an autoload that regex-scans every
  `res://panels/*.gd` at startup and indexes:
  * the `page_header("Title", "Subtitle")` call, and
  * every `kcm_row/nav_row/action_row/toggle_row/slider_row/choice_row/info_row`
    call's first two string literals.
  Selecting a result calls `menu.virtual_press_button(panel)` then
  `panel.highlight_row(title)`, which scrolls to and flashes the row.
  → **Adding a row automatically makes it searchable.** No index maintenance.
* **Theming** — the `KDETheme` autoload (`KDEThemeSync.gd`) parses the active KDE
  colour scheme + font, builds a full Godot `Theme`, assigns it to the scene root and
  polls `kdeglobals`/the `.colors` file every 1.5 s to rebuild on change. That is why
  `settings_panel.gd` asks the theme for `_text_color()`, `_accent()`, `_muted()`
  instead of hard-coding colours.
* **No terminal dependency in the UI**: system work happens through `KainatShell`
  (`bash -c`, `pkexec`, `qdbus6`, `nmcli`, `pactl`, `systemctl`, `bluetoothctl`,
  `ufw`, `testparm`, `timeshift`, `lpadmin`, …).

---

## 3. Running and verifying (do this before every commit)

```bash
cd /media/kainatq/GAMES_AND_OTHERS/kainat-os/sources/apps/kainat-system-settings
REDOT=/media/kainatq/GAMES_AND_OTHERS/godot/redot/redot.linuxbsd.editor.x86_64

# Real scene, headless, boot every autoload and the main panel:
$REDOT --headless --path . --quit-after 120 2>&1 | grep -E "SCRIPT ERROR|Parse Error|ERROR:"
```

### 3.1 `--check-only` is **not** a reliable check

`redot --headless --quit --check-only` only parses scripts reachable from
`main-panel.tscn`/autoloads. Panels are loaded dynamically, so a broken panel can pass
`--check-only` and fail when clicked. Use a smoke script that loads every panel:

```gdscript
# scratch/smoke.gd
extends SceneTree

var _frame := 0
var _built := 0

func _initialize() -> void:
	process_frame.connect(_tick)          # watchdog first: an error in _initialize
	var dir := DirAccess.open("res://panels")   # otherwise hangs forever
	for f in dir.get_files():
		if not f.ends_with(".gd") or f in ["settings_panel.gd", "kainat_shell.gd"]:
			continue
		var node = load("res://panels/" + f).new()
		root.add_child(node)
		_built += 1
	print("SMOKE built=", _built)

func _tick() -> void:
	_frame += 1
	if _frame >= 40:
		print("SMOKE DONE panels=", _built)
		quit()
```

```bash
$REDOT --headless --path . --script res://scratch/smoke.gd 2>&1 \
  | grep -E "SMOKE|SCRIPT ERROR|Parse Error"
# expected: SMOKE built=29 / SMOKE DONE panels=29
```

**Delete `scratch/*.gd` before committing.** `scratch/` holds only a tracked screenshot.

### 3.2 Project settings that matter

* `debug/gdscript/warnings/*` — this project treats warnings as errors. The usual
  offender is `Variant` inference: give explicit types (`var x: int = …`,
  `for s: String in array`).
* `run/low_processor_mode=true` with an 11 ms sleep — background work should stay
  timer-driven; avoid `_process` polling loops.
* Autoload order: `KDETheme`, then `SearchManager`.

### 3.3 Probe scripts (runtime logic checks)

Headless `--script` scripts can instantiate a panel and call helpers, but **only after
a few frames** — `SettingsPanel._ready()` creates `content` and calls `build()`, and
`defer()` work runs one frame later. Pattern: create the node in `_initialize()`, then
in `_tick()` at frame ~8–10 call the helper and `print()` results. This is how real
values (sensor counts, unit lists, share parsing, …) were verified throughout
development.

---

## 4. Adding a panel (the only workflow you need)

1. **Create `panels/<name>.gd`** — `extends SettingsPanel`, implement `build()`.
2. **Add a sidebar Button** to `main-panel.tscn` with `node name == <name>`:
   * parent `MarginContainer/VBoxContainer/HBoxContainer/ScrollContainer/menu-buttons`
   * `custom_minimum_size = Vector2(0, 44)`, `toggle_mode = true`,
     `button_group = ExtResource("2_8an0a")` (the shared `[gr]menu-buttons.tres`),
   * `text` is what the user reads.
3. **Add `"<name>"` to the right list** in `menu_buttons.gd::SECTIONS`. Unlisted
   buttons still appear (under a trailing "More" heading) but that is a fallback.
4. Optional: add the panel title to the About/README-style summaries if one exists.
5. Run `--headless --quit-after 120` and the smoke script. Check the sidebar parity
   command in §9.

### 4.1 Minimal panel

```gdscript
extends SettingsPanel
# What this page does, in one line.

var _state_row: HBoxContainer


func build() -> void:
	page_header("Example", "One-line description shown under the title.")

	section("Status")
	var c := card()
	_state_row = info_row(c, "Current State", "Checking…")
	action_row(c, "Do the Thing", "Explains what will happen.", "D", _do_thing)

	defer(_refresh)   # slow reads run after the page is visible


func _refresh() -> void:
	set_info_value(_state_row, Sh.run_capture("some-command").strip_edges())


func _do_thing() -> void:
	run_async("pkexec some-command", func(code: int) -> void:
		notify("Done." if code == 0 else "Could not do the thing."))
```

### 4.2 Rules of the road

* **Never block the UI.** Anything that can take more than a few milliseconds goes
  through `run_async()` / `run_async_capture()`; use `run_wait()` only for instant
  operations where you need the result to snap a toggle back.
* **Confirm destructive actions** with a `ConfirmationDialog`
  (`dialog_text`, `ok_button_text`, `confirmed` signal), and phrase the text so the
  user knows what is *not* touched.
* **Only ever delete configuration**, never user documents (reset features back up
  first, see `last_reset_backup()`).
* **Secrets never go on a command line.** Write them to a `0700` temp directory as a
  file and pipe them in (`users.gd` and `sharing.gd` show the pattern), then delete.
* **Quote everything** with `Sh.quote()`; never interpolate raw user text into a shell.
* **Back up before overwriting** a system file (`*.kainat-backup`), validate with the
  tool's own parser where possible (`testparm`, `visudo -c`, …), then install.
* **Report outcomes.** `notify()` on success *and* on failure; show the tail of the
  command output when a package manager fails.
* **Graceful degradation.** Missing tool → `unavailable_row()` + an install `action_row`
  (`Sh.install_command(pkg)` then `Sh.clear_tool_cache()`), or a KCM row. Never a dead
  end and never a raw error.

---

## 5. `SettingsPanel` API (widgets)

All of these are instance methods on the base class. `card_box` is the `VBoxContainer`
returned by `card()`.

```gdscript
page_header(title: String, subtitle: String = "") -> void
section(title: String) -> void                     # small accent-bar heading
card() -> VBoxContainer                            # rounded translucent card

# Rows (first args are always: card, title, subtitle, glyph)
nav_row(card_box, title, subtitle, glyph, on_press: Callable, icon_path := "") 
kcm_row(card_box, title, subtitle, glyph, kcm_module: String)              # opens KDE module
action_row(card_box, title, subtitle, glyph, action_text: String,
           on_press: Callable, primary := false)                           # trailing button
toggle_row(card_box, title, subtitle, glyph, value: bool,
           on_toggle: Callable) -> CheckButton                             # returns the switch
choice_row(card_box, title, subtitle, glyph, options: Array,
           selected: int, on_select: Callable) -> OptionButton
slider_row(card_box, title, subtitle, glyph, min_value: float, max_value: float,
           value: float, on_change: Callable, suffix := "") -> HSlider
info_row(card_box, label, value) -> HBoxContainer        # read-only key/value
set_info_value(row: HBoxContainer, value: String) -> void
unavailable_row(card_box, title, detail, glyph)          # greyed "not available" row
info_tiles(tiles: Array) -> Array                        # dashboard-style tiles
big_button(text, on_press, primary := true) -> Button

# Behaviour
defer(task: Callable) -> void                 # run after the page is built (slow reads)
run_async(command, on_done: Callable)         # on_done(code: int); non-blocking
run_async_capture(command, on_done: Callable) # on_done(code: int, output: String)
debounce(key: String, delay: float, task: Callable) -> void  # coalesce rapid input
notify(message: String) -> void               # bottom-centre toast
highlight_row(title: String) -> bool          # scroll/flash (used by search)
```

**`run_async` arity gotcha:** `on_done` receives **one** argument (exit code);
`run_async_capture` receives **two** (code, combined stdout+stderr). A two-argument
lambda passed to `run_async` is a runtime error.

Theming helpers: `_accent()`, `_text_color()`, `_muted()`, `_with_alpha(color, a)`,
`_opacity(node, a)`.

---

## 6. `KainatShell` (`panels/kainat_shell.gd`, class `KainatShell`)

Static helpers, preloaded as `const Sh := preload("res://panels/kainat_shell.gd")`.

```gdscript
# Processes
run(cmd) -> int                     # fire and forget
run_wait(cmd, read_stderr := false) -> int
run_capture(cmd, read_stderr := false) -> String
run_lines(cmd) -> PackedStringArray
launch(tool, args := []) -> void    # detached process, no shell
quote(value) -> String              # single-quote escaping for shell
protect_command(command) -> String  # see §7.1 — applied automatically by run*()

# Tools / KDE
has_tool(name) -> bool              # cached PATH lookup; clear_tool_cache() to refresh
kcm_available(module) -> bool       # scans installed KCM plugin dirs
open_kcm(module) -> bool            # tries kcmshell6/5, systemsettings

# Files / text
read_text(path) / read_lines(path) / file_exists / dir_exists / home()
kde_read(file, group, key, default := "", ...) -> String
kde_write(file, group, key, value, subgroup := "", value_type := "") -> void
write_system_file(path, content)    # pkexec install

# Favourites (kdeglobals)
favorites() -> Array, is_favorite(panel, title), set_favorite(panel, title, on)

# Packages
is_package_installed(pkg) -> bool
installed_packages(names: Array) -> Dictionary   # one dpkg-query call
install_command(pkg) / remove_command(pkg) -> String   # pkexec apt-get …-y -- …
install_package(pkg) -> int

# Storage
list_block_devices() -> Array
get_disk_usage(mount) -> Dictionary   # {total, used, available, percent} human strings
unmount_device(dev), eject_drive(dev), format_command(dev, fs), format_drive(dev, fs)

# Networking / VPN / SSH / sharing
set_system_proxy(mode, host, port, script_url := "") / get_system_proxy() -> Dictionary
create_wifi_hotspot_command(ssid, pw) / stop_wifi_hotspot_command()
start_openvpn(cfg) / stop_openvpn() / list_vpn_configs(dir)
generate_ssh_key(path, type := "ed25519") / get_ssh_public_key(path)
list_apt_sources() -> Array          # {file, line, enabled, is_main}
toggle_apt_source_command(file, enabled) / remove_apt_source_command(file)
deb_install_command / rpm_install_command / run_appimage / run_wine_exe(path, prefix := "")

# Virtual desktops (KWin DBus)
kwin_desktop_count() / kwin_desktop_rows() / kwin_set_desktop_count(n) / kwin_set_desktop_rows(n)

# Appearance / input / diagnostics
get_high_contrast() / set_high_contrast(on)
ui_scale() / set_ui_scale(scale)
get_input_method_framework() / set_input_method_framework(name)
get_cpu_temp() / get_ram_usage() / get_disk_health()
last_reset_backup() / reset_user_settings()
```

`kainat_shell.gd` opens with a comment explaining that it is a **library, not an entry
point**: launching it directly (`--script panels/kainat_shell.gd`, editor F6) produces
“Can't load the script … as it doesn't inherit from SceneTree or MainLoop”. That is
expected; run `main-panel.tscn`.

---

## 7. Engine and API gotchas (hard-won — do not relearn these)

### 7.1 Redot expands `$` in `OS.execute` arguments before the shell runs

`OS.create_process("bash", ["-c", cmd])` expands `$VAR`, `$1`, `$$` and backticks
**even inside single quotes**. `~` is *not* expanded. Consequences that already bit us:

* `awk '{print $4}'` returned garbage,
* `dpkg-query -f='${Package} …'` produced blank fields,
* `sh -c '… "$1"'` received an empty argument.

`KainatShell.protect_command()` escapes exactly the expandable `$` forms and
backticks, and is applied inside `run()`, `run_wait()`, `run_capture()`. `run_lines()`
and `run_async`/`run_async_capture` in `settings_panel.gd` go through the same path.
**If you add a new process helper, apply `protect_command()`.** Existing backslash
escapes are preserved, and a regex anchor like `c$` is untouched.

Also: an argument containing **double-quoted** `<` or `>` breaks the same way; write
single-quoted `'<...>'`.

### 7.2 Dialogs in this Redot build

| Wrong | Right |
|---|---|
| `dialog.text = "…"` | `dialog.dialog_text = "…"` |
| `dialog.ok_text = "…"` | `dialog.ok_button_text = "…"` |
| `if dialog.popup() == OK:` | `dialog.confirmed.connect(...)`; `popup()` returns `void` |

`AcceptDialog`/`ConfirmationDialog` have no `text`/`ok_text` properties here — assigning
them raises `Invalid assignment of property or key 'text'` at runtime, so a mistake is
invisible until the dialog is opened.

### 7.3 GDScript strict-mode traps

* **Warnings are errors.** `var x := something_untyped` → *“The variable type is being
  inferred from a Variant value”*. Type the variable explicitly.
* A lambda cannot reference the variable it is being assigned to. This fails:
  `var c := toggle_row(..., func(on): _set(..., c))`. Do:
  ```gdscript
  var c: CheckButton = null
  c = toggle_row(..., func(on: bool) -> void: _set(..., c))
  ```
  (`nac.gd` Wi-Fi switch and `accessibility.gd` use this pattern.)
* A member variable and a function cannot share a name (`_shares` collision in
  `sharing.gd`). Rename one.
* Typed `for` loops are needed when the loop body calls `String` methods on the loop
  variable: `for path: String in dirs:`.
* `DirAccess.get_directories()` (static) does not exist; use
  `DirAccess.open(path).get_directories()`.
* `String.is_valid_int()`, not `is_valid_number()`.
* `Time.get_unix_time()`, not `OS.get_unix_time()`.
* `kde_write()` grew a 6th `value_type` argument for `kwriteconfig6 --type` — needed
  for booleans (`"bool"`), otherwise KDE reads the value as a string.
* `menu_buttons.gd` builds headers as plain `Label`/`MarginContainer` nodes on purpose:
  only `Button` children join the `ButtonGroup` and the discovery loop.

### 7.4 Environment noise

Fontconfig warnings (`10-sub-pixel-rgb.conf`, `56-kubuntu-noto.conf`) appear on every
headless run on this machine; they are not app errors.

---

## 8. Conventions in this repo

* **Commits** are one feature/fix each, imperative subject ("feat: …", "fix: …",
  "perf: …", "chore: …"). Version bumps are their own commit, followed by an annotated
  tag (`vX.Y.Z`) whose message names the highlights.
* **Scratch files** live in `scratch/` and must be deleted before committing (the
  directory tracks only a screenshot).
* **Backup files**: `menu_buttons-back.gd`, `panels/panel-template.tscn`, and the
  sibling `kainat-system-settings-bak*` folders are historical. Do not edit or copy
  from them; the live code is the listed panel scripts.
* Language in UI: plain English, no jargon, no terminal instructions; sentence case
  for row titles; every risky action explains consequences and offers a confirmation.
* Colours always come from the theme (`_accent()`, `_text_color()`), never hard-coded.

---

## 9. Useful audit commands

```bash
# Sidebar ↔ panel parity (no output means every panel is reachable)
comm -3 \
  <(ls panels/*.gd | sed 's|panels/||;s|\.gd$||' | grep -v -E "^(kainat_shell|settings_panel)$" | sort) \
  <(grep -oP '^\[node name="\K[a-z_-]+(?=" type="Button" parent="[^"]*menu-buttons")' main-panel.tscn | sort)

# Leftovers from older APIs (should print nothing)
grep -rn "popup() == OK\|OS.get_unix_time\|is_valid_number\|DirAccess.get_directories\|\.ok_text\b" --include=*.gd .

# Search index size / hit check (needs a probe script):
#   SearchManager.get_index_size()  and  SearchManager.search("backup")
```

---

## 10. Known limits and next steps

1. **Not packaged.** There is no `export_presets.cfg`, `.desktop` file or Debian
   packaging in this repo. Whoever builds the Kainat OS image must export the project
   with the Redot runtime and install a launcher. `redotpath.txt` names the editor
   binary used during development.
2. **Untested branches on the dev machine** (no hardware/config to exercise them):
   ufw not installed, no Samba server, no printers, no Bluetooth devices paired
   beyond one, no VPN configs. Those paths are written against the tools' real output
   formats but should be smoke-tested on a machine that has them.
3. **KCM dependencies.** `kcm_row()` hides a module when
   `kcm_available()` cannot find it, and shows an "not installed" row — so missing
   Plasma packages degrade visibly instead of silently failing. `kcm_disks` and
   `kcm_baloofile` are the main modules not yet linked from any page.
4. **Possible future panels:** remote desktop (krfb/gnome-remote-desktop), NFS,
   single-use boot entry (`grub-reboot`), kernel parameter editor (currently read-only),
   per-app firewall rules.
5. **`hardware.gd`** reads temps from hwmon sysfs (no process spawns) and only falls
   back to `sensors` when sysfs is empty; the live timer also stops when the panel is
   not visible. Keep it that way.
6. Version bump + tag when landing work:
   `sed -i 's|config/version="1.4.0"|config/version="1.5.0"|' project.godot` → commit →
   `git tag -a v1.5.0 -m "…"`.

---

## 11. Expectations on the rest of Kainat OS

This app assumes a **Debian/KDE Plasma** system. If another component changes any of
these, it must be reflected here (or the corresponding panel will degrade — it will
not crash):

* `pkexec` present and polkit configured for desktop users (nearly every privileged
  action).
* Plasma + `kcmshell6`/`systemsettings` for KCM hand-offs; KCM plugin `.so` files under
  `…/qt{5,6}/plugins/plasma/kcms/*/` (used for availability detection).
* `kdeglobals`, `kioslaverc` and the active colour scheme at the usual XDG paths —
  theming, favourites and proxy settings are written there.
* NetworkManager (`nmcli`), PulseAudio/PipeWire (`pactl`), `systemd`, `loginctl`,
  `journalctl`, `ufw`, `smartctl`, `fwupdmgr`, `powerprofilesctl`, `kscreen-doctor`,
  `bluetoothctl`, `lpstat`/`lpadmin`, `testparm`/`smbd`, `timeshift`, `flatpak`,
  `snap`, `wine`/`winetricks` — each panel checks `has_tool()` first and offers an
  install row instead of failing.
* The system font and colour scheme are read live; a branded Kainat OS theme will be
  picked up automatically without code changes.
