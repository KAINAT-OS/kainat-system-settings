extends SettingsPanel
# Windows App Compatibility — Wine, Proton, Lutris and the rest of the
# Windows-compatibility toolchain, gathered in one place.
#
# build() only lays out the sections so switching to the panel stays instant;
# every value is probed from the live system in the deferred _populate().

var _tiles: Array = []           # value Labels returned by info_tiles()
var _tools_card: VBoxContainer
var _prefix_card: VBoxContainer
var _proton_card: VBoxContainer
var _gfx_card: VBoxContainer
var _exe_dialog: FileDialog = null


func build() -> void:
	page_header("Windows App Compatibility",
			"Run and manage Windows applications with Wine, Proton and other compatibility layers.")

	# "…" placeholders keep the layout stable while the probes run.
	_tiles = info_tiles([
		{"value": "…", "label": "Wine"},
		{"value": "…", "label": "Proton"},
		{"value": "…", "label": "Wine prefix"},
		{"value": "…", "label": "DXVK"},
		{"value": "…", "label": "Winetricks"},
		{"value": "…", "label": "Compat data"},
	])

	section("Compatibility Tools")
	_tools_card = card()

	section("Wine Prefixes")
	_prefix_card = card()

	section("Steam & Proton")
	_proton_card = card()

	section("Graphics Translation")
	_gfx_card = card()

	defer(_populate)


func _populate() -> void:
	# This panel can install tools itself, so a process-lifetime memo would go
	# on reporting a freshly installed tool as missing until the app restarts.
	Sh.clear_tool_cache()

	# Rows are rebuilt from the live system on every refresh (including after an
	# install), so clear the previous pass first or the sections would double up.
	_clear_card(_tools_card)
	_clear_card(_prefix_card)
	_clear_card(_proton_card)
	_clear_card(_gfx_card)

	var wine_ver := _wine_version()
	var tricks_ver := _winetricks_version()
	var steam := _probe_steam()
	var prefix := _prefix_path()
	var dxvk := _dxvk_installed(prefix)

	_fill_tiles(wine_ver, steam, prefix, dxvk, tricks_ver)
	_build_tools(wine_ver, tricks_ver)
	_build_prefix(prefix)
	_build_proton(steam)
	_build_graphics(prefix, dxvk)


func _clear_card(card_box: VBoxContainer) -> void:
	for child in card_box.get_children():
		card_box.remove_child(child)
		child.queue_free()


# --- overview tiles ---------------------------------------------------------

func _fill_tiles(wine_ver: String, steam: Dictionary, prefix: String,
		dxvk: bool, tricks_ver: String) -> void:
	if _tiles.size() != 6:
		return
	var proton: PackedStringArray = steam["proton"]
	var compat := int(steam["compat"])

	_tiles[0].text = _short_version(wine_ver) if not wine_ver.is_empty() else "—"
	_tiles[1].text = str(proton.size()) if not proton.is_empty() else "—"
	_tiles[2].text = _prefix_arch(prefix) if _dir_exists(prefix) else "—"
	_tiles[3].text = "Installed" if dxvk else "Not installed"
	_tiles[4].text = tricks_ver if not tricks_ver.is_empty() else "—"
	_tiles[5].text = str(compat) if compat > 0 else "—"


# "wine-10.0 (debian 10.0~repack-12+b1)" -> "10.0"
func _short_version(raw: String) -> String:
	var head := raw.split(" ")[0].strip_edges()
	if head.begins_with("wine-"):
		head = head.trim_prefix("wine-")
	return head


# --- compatibility tools ----------------------------------------------------

# SearchManager indexes a panel by regex-matching *literal* row calls in the
# source, so every tool row is written out here rather than generated from a
# table — a helper would hide "Lutris" from search entirely. The two info rows
# use "… version" titles so the version fact and the tool row stay distinct
# search hits instead of two entries both called "Wine".
func _build_tools(wine_ver: String, tricks_ver: String) -> void:
	var c: VBoxContainer = _tools_card

	if not wine_ver.is_empty():
		info_row(c, "Wine version", wine_ver)
	if Sh.has_tool("wine"):
		action_row(c, "Wine", "Windows application compatibility layer", "W",
				"Configure", func() -> void: _launch_or_notify("winecfg"))
	else:
		_missing_row(c, "Wine", "Windows application compatibility layer", "W", "wine")

	if not tricks_ver.is_empty():
		info_row(c, "Winetricks version", tricks_ver)
	if Sh.has_tool("winetricks"):
		action_row(c, "Winetricks", "Scripted installer for Windows libraries", "T",
				"Open", func() -> void: _launch_or_notify("winetricks"))
	else:
		_missing_row(c, "Winetricks", "Scripted installer for Windows libraries",
				"T", "winetricks")

	if Sh.has_tool("lutris"):
		action_row(c, "Lutris", "Game manager for Windows titles", "L",
				"Launch", func() -> void: _launch_or_notify("lutris"))
	else:
		_missing_row(c, "Lutris", "Game manager for Windows titles", "L", "lutris")

	if Sh.has_tool("steam"):
		action_row(c, "Steam", "Storefront that runs Windows games through Proton", "S",
				"Launch", func() -> void: _launch_or_notify("steam"))
	else:
		_missing_row(c, "Steam", "Storefront that runs Windows games through Proton",
				"S", "steam")

	if Sh.has_tool("bottles"):
		action_row(c, "Bottles", "Isolated Wine prefixes with templates", "B",
				"Launch", func() -> void: _launch_or_notify("bottles"))
	else:
		_missing_row(c, "Bottles", "Isolated Wine prefixes with templates",
				"B", "bottles")


# The "not installed" half of a tool row: offer the package when apt can
# provide it, and fall back to a dead row when nothing can install it.
func _missing_row(c: VBoxContainer, title: String, subtitle: String,
		glyph: String, apt_pkg: String) -> void:
	if _has_candidate(_apt_candidate(apt_pkg)):
		action_row(c, title, subtitle, glyph, "Install",
				func() -> void: _install(apt_pkg))
	else:
		unavailable_row(c, title, "Not installed and no package provides it.", glyph)


func _launch_or_notify(tool: String) -> void:
	if not Sh.has_tool(tool):
		notify(tool + " is not available.")
		return
	Sh.launch(tool)


func _install(pkg: String) -> void:
	notify("Installing " + pkg + "…")
	run_async(Sh.install_command(pkg), func(code: int) -> void:
		if code == 0:
			notify(pkg + " installed.")
			_populate()
		else:
			notify("Could not install " + pkg + "."))


# --- wine prefixes ----------------------------------------------------------

func _build_prefix(prefix: String) -> void:
	var c: VBoxContainer = _prefix_card

	if _dir_exists(prefix):
		info_row(c, "Location", prefix)
		var arch := _prefix_arch(prefix)
		if not arch.is_empty():
			info_row(c, "Architecture", arch)
		action_row(c, "Open Prefix Folder", "Browse the virtual C: drive.", "F",
				"Open", func() -> void: _open_folder(prefix))
	else:
		unavailable_row(c, "No Wine prefix",
				"Run a Windows app once and Wine will create " + prefix + ".")

	if Sh.has_tool("wine"):
		action_row(c, "Run Windows Application", "Launch an .exe or .msi installer with Wine.", "E",
				"Browse…", _pick_exe, true)


func _pick_exe() -> void:
	if _exe_dialog == null or not is_instance_valid(_exe_dialog):
		_exe_dialog = FileDialog.new()
		_exe_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_exe_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_exe_dialog.title = "Choose a Windows executable"
		var filt := PackedStringArray()
		filt.append("Windows executables *.exe,*.msi")
		filt.append("All files *")
		_exe_dialog.filters = filt
		_exe_dialog.file_selected.connect(_run_exe)
		add_child(_exe_dialog)
	_exe_dialog.popup_centered_ratio(0.6)


func _run_exe(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		notify("That file does not exist.")
		return
	if not Sh.has_tool("wine"):
		notify("Wine is not installed.")
		return
	notify("Launching " + path.get_file() + "…")
	var code := Sh.run_wine_exe(path, _prefix_path())
	if code == 127:
		notify("Wine is not installed.")
	elif code != 0:
		notify("Wine could not start " + path.get_file() + ".")


func _open_folder(path: String) -> void:
	if not _dir_exists(path):
		notify("That folder does not exist: " + path)
		return
	if not Sh.has_tool("xdg-open"):
		notify("No file manager is available to open it.")
		return
	Sh.launch("xdg-open", [path])


# --- steam & proton ---------------------------------------------------------

# Steam ships three paths here that are all symlinks to
# ~/.steam/debian-installation, so every root is resolved first — otherwise
# the compat-data count comes out three times too high.
func _probe_steam() -> Dictionary:
	var roots: Array = []
	var seen: Array = []
	var proton := PackedStringArray()
	var compat := 0

	for base in [Sh.home() + "/.local/share/Steam",
			Sh.home() + "/.steam/steam",
			Sh.home() + "/.steam/root"]:
		var path: String = str(base)
		if DirAccess.open(path) == null:
			continue
		var real: String = Sh.run_capture("readlink -f " + Sh.quote(path) + " 2>/dev/null").strip_edges()
		if real.is_empty():
			real = path
		if seen.has(real):
			continue
		seen.append(real)
		roots.append(path)

		for rel in ["steamapps/common", "steamapps/compattools.d"]:
			var dir := DirAccess.open(path + "/" + rel)
			if dir == null:
				continue
			dir.list_dir_begin()
			var entry := dir.get_next()
			while entry != "":
				if dir.current_is_dir() and entry.begins_with("Proton") \
						and not entry.begins_with(".") and not proton.has(entry):
					proton.append(entry)
				entry = dir.get_next()
			dir.list_dir_end()

		compat += _count_children(path + "/steamapps/compatdata")

	return {"roots": roots, "proton": proton, "compat": compat}


func _build_proton(steam: Dictionary) -> void:
	var c: VBoxContainer = _proton_card
	var roots: Array = steam["roots"]
	var proton: PackedStringArray = steam["proton"]
	var compat := int(steam["compat"])

	if roots.is_empty():
		unavailable_row(c, "Steam",
				"Steam is not installed, so Proton has nothing to run in.")
		return

	info_row(c, "Steam library", str(roots[0]))
	if proton.is_empty():
		info_row(c, "Proton versions", "None installed")
	else:
		var joined := ""
		for i in proton.size():
			if i > 0:
				joined += ", "
			joined += proton[i]
		info_row(c, "Proton versions", joined)
	info_row(c, "Game prefixes", str(compat))

	if compat > 0:
		action_row(c, "Compat Data", "The per-game Wine prefixes Steam keeps.", "C",
				"Open", func() -> void: _open_folder(str(roots[0]) + "/steamapps/compatdata"))
	else:
		unavailable_row(c, "Compat Data", "Steam has no game prefixes yet.")


# --- graphics translation ---------------------------------------------------

func _build_graphics(prefix: String, dxvk: bool) -> void:
	var c: VBoxContainer = _gfx_card

	if not _dir_exists(prefix):
		unavailable_row(c, "Graphics translation",
				"A Wine prefix is needed before its graphics backend can change.")
		return

	info_row(c, "Direct3D 11 backend", "DXVK" if dxvk else "Wine native")

	if not Sh.has_tool("winetricks"):
		unavailable_row(c, "DXVK", "winetricks is required to install it.", "D")
	elif dxvk:
		info_row(c, "DXVK status", "Installed in this prefix")
		action_row(c, "DXVK", "Install the current DXVK release into this prefix.", "D",
				"Reinstall", _install_dxvk)
	else:
		action_row(c, "Install DXVK",
				"Map Direct3D 10/11 to Vulkan — usually much faster in games.",
				"D", "Install", _install_dxvk, true)


func _install_dxvk() -> void:
	var prefix := _prefix_path()
	if not _dir_exists(prefix):
		notify("No Wine prefix at " + prefix)
		return
	if not Sh.has_tool("winetricks"):
		notify("winetricks is not installed.")
		return
	notify("Installing DXVK — this can take a few minutes.")
	run_async("WINEPREFIX=" + Sh.quote(prefix) + " winetricks -q dxvk", func(code: int) -> void:
		if code == 0:
			notify("DXVK installed.")
			_populate()
		else:
			notify("DXVK installation failed."))


# --- probes -----------------------------------------------------------------

func _wine_version() -> String:
	if not Sh.has_tool("wine"):
		return ""
	return Sh.run_capture("wine --version 2>/dev/null").strip_edges()


# winetricks prints a checksum after the date; only the first token is useful.
func _winetricks_version() -> String:
	if not Sh.has_tool("winetricks"):
		return ""
	var raw := Sh.run_capture("winetricks --version 2>/dev/null").strip_edges()
	if raw.is_empty():
		return ""
	return raw.split("\n")[0].strip_edges().split(" ")[0].strip_edges()


func _prefix_path() -> String:
	var p := OS.get_environment("WINEPREFIX")
	if p.is_empty():
		p = Sh.home() + "/.wine"
	return p


func _prefix_arch(prefix: String) -> String:
	var reg := prefix + "/system.reg"
	if not FileAccess.file_exists(reg):
		return ""
	var line := Sh.run_capture("grep -m1 '^#arch=' " + Sh.quote(reg) + " 2>/dev/null").strip_edges()
	return line.trim_prefix("#arch=")


# DXVK's replacement DLL carries the string "DXVK"; Wine's own does not —
# verified here, where the prefix has no DXVK and grep finds no match.
func _dxvk_installed(prefix: String) -> bool:
	var dll := prefix + "/drive_c/windows/system32/d3d11.dll"
	if not FileAccess.file_exists(dll):
		return false
	var hit := Sh.run_capture("grep -a -m1 -o -i dxvk " + Sh.quote(dll) + " 2>/dev/null")
	return not hit.strip_edges().is_empty()


func _apt_candidate(pkg: String) -> String:
	for line in Sh.run_lines("apt-cache policy " + Sh.quote(pkg) + " 2>/dev/null"):
		if line.begins_with("Candidate:"):
			return line.trim_prefix("Candidate:").strip_edges()
	return ""


func _has_candidate(candidate: String) -> bool:
	return not candidate.is_empty() and candidate != "(none)"


func _dir_exists(path: String) -> bool:
	return DirAccess.open(path) != null


func _count_children(path: String) -> int:
	var dir := DirAccess.open(path)
	if dir == null:
		return 0
	var n := 0
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			n += 1
		entry = dir.get_next()
	dir.list_dir_end()
	return n
