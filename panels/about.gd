extends SettingsPanel
# About This System — fast, native, no external fetch tool required.

var _hostname_row: HBoxContainer
var _plasma_row: HBoxContainer
var _session_row: HBoxContainer
var _display_row: HBoxContainer
var _cpu_row: HBoxContainer
var _mem_row: HBoxContainer
var _gpu_row: HBoxContainer
var _disk_row: HBoxContainer


func build() -> void:
	var rel: Dictionary = Sh.os_release()
	page_header("About This System", "Information about Kainat OS and this device.")

	section("System")
	var c := card()
	info_row(c, "Operating System", str(rel.get("PRETTY_NAME", "Kainat OS")))
	info_row(c, "Version", str(rel.get("VERSION", UNAVAILABLE)))
	info_row(c, "Base", str(rel.get("ID_LIKE", "debian")).capitalize())
	info_row(c, "Kernel", OS.get_version())
	info_row(c, "Architecture", Engine.get_architecture_name())
	_hostname_row = info_row(c, "Hostname", "…")
	_plasma_row = info_row(c, "Desktop", "…")
	_session_row = info_row(c, "Session", "…")
	_display_row = info_row(c, "Display Server", "…")

	section("Device")
	var c2 := card()
	_cpu_row = info_row(c2, "Processor", "…")
	_mem_row = info_row(c2, "Memory", "…")
	_gpu_row = info_row(c2, "Graphics", "…")
	_disk_row = info_row(c2, "Disk Usage", "…")

	section("Details")
	var c3 := card()
	nav_row(c3, "Hardware & System Information", "Full component inventory.", "H",
		func() -> void: _open_page("hardware"))
	kcm_row(c3, "About This Distribution", "Distro-provided about page.", "A", "kcm_about-distro")
	kcm_row(c3, "Wayland / Session", "Display server information.", "W", "kcm_wayland")
	kcm_row(c3, "OpenGL Information", "Graphics stack details.", "G", "kcm_glx")

	defer(_populate)


func _populate() -> void:
	set_info_value(_hostname_row, _hostname())
	set_info_value(_plasma_row, _plasma_version())
	set_info_value(_session_row, _session())
	set_info_value(_display_row, _display_server())
	set_info_value(_cpu_row, _cpu_model())
	set_info_value(_mem_row, _memory())
	set_info_value(_gpu_row, _gpu())
	set_info_value(_disk_row, _disk())


func _open_page(page_name: String) -> void:
	var menu: Node = get_tree().root.find_child("menu-buttons", true, false)
	if menu and menu.has_method("virtual_press_button"):
		menu.virtual_press_button(page_name)


func _hostname() -> String:
	var h: String = Sh.run_capture("hostname").strip_edges()
	return h if not h.is_empty() else OS.get_environment("HOSTNAME")


# The "Desktop" row used to read kdeglobals [General] Name, which is the
# *color scheme* name ("KOS Light") — not a desktop environment at all.
func _plasma_version() -> String:
	var parts := Sh.run_capture("plasmashell --version 2>/dev/null").strip_edges().split(" ", false)
	var version := ""
	if parts.size() > 0:
		var candidate: String = parts[parts.size() - 1]
		if candidate.length() > 0 and candidate[0].is_valid_int():
			version = candidate
	var desktop := OS.get_environment("XDG_CURRENT_DESKTOP")
	if desktop.is_empty():
		desktop = "KDE"
	else:
		desktop = desktop.split(":")[0]
	if version.is_empty():
		return desktop
	return "%s Plasma %s" % [desktop, version]


# Raw session type, lower-cased. XDG_SESSION_TYPE is absent when the app is
# launched outside a desktop session, so fall back to the display sockets.
func _session_kind() -> String:
	var kind := OS.get_environment("XDG_SESSION_TYPE").to_lower()
	if kind.is_empty():
		if not OS.get_environment("WAYLAND_DISPLAY").is_empty():
			kind = "wayland"
		elif not OS.get_environment("DISPLAY").is_empty():
			kind = "x11"
	return kind


func _session() -> String:
	var kind := _session_kind()
	match kind:
		"wayland":
			return "Wayland"
		"x11":
			return "X11"
		"tty":
			return "TTY"
	return kind.capitalize() if not kind.is_empty() else UNAVAILABLE


# Under Wayland the compositor *is* the display server, so report the socket
# plus the XWayland bridge when present — that is the part that varies and
# that people actually need when an app renders incorrectly.
func _display_server() -> String:
	var kind := _session_kind()
	var wl := OS.get_environment("WAYLAND_DISPLAY")
	var x11 := OS.get_environment("DISPLAY")
	if kind == "x11":
		if x11.is_empty():
			return "X11"
		return "X11 (%s)" % x11
	if not wl.is_empty():
		var server := "Wayland (%s)" % wl
		if not x11.is_empty():
			server += " · XWayland %s" % x11
		return server
	return UNAVAILABLE


# --output pins the row to fixed columns: POSIX df wraps long device names
# onto a second line, which breaks naive field parsing. Both parses are kept
# because BusyBox df has no --output.
func _disk() -> String:
	var cols := Sh.run_capture("df -B1 --output=size,used,pcent / 2>/dev/null").split("\n", false)
	if cols.size() >= 2:
		var f: PackedStringArray = cols[cols.size() - 1].split(" ", false)
		if f.size() >= 3 and f[0].is_valid_float() and float(f[0]) > 0.0:
			return "%.0f GB used of %.0f GB (%s)" % [
				float(f[1]) / 1073741824.0, float(f[0]) / 1073741824.0, f[2]]
	var legacy := Sh.run_capture("df -h / 2>/dev/null").split("\n", false)
	if legacy.size() >= 2:
		var g: PackedStringArray = legacy[legacy.size() - 1].split(" ", false)
		if g.size() >= 5 and g[4].ends_with("%"):
			return "%s used of %s (%s)" % [g[2], g[1], g[4]]
	return UNAVAILABLE

func _cpu_model() -> String:
	for line in Sh.read_lines("/proc/cpuinfo"):
		if line.begins_with("model name"):
			return line.split(":", true, 1)[1].strip_edges()
	return UNAVAILABLE

func _memory() -> String:
	var lines: PackedStringArray = Sh.read_lines("/proc/meminfo")
	if lines.size() > 0:
		var parts: PackedStringArray = lines[0].split(" ", false)
		if parts.size() >= 2:
			return "%.1f GB" % (float(parts[1].replace("kB", "")) / 1024.0 / 1024.0)
	return UNAVAILABLE

func _gpu() -> String:
	for line in Sh.run_lines("lspci 2>/dev/null"):
		if line.contains("VGA compatible controller") or line.contains("3D controller"):
			var idx: int = line.find(":")
			if idx != -1:
				return line.substr(idx + 1).strip_edges()
	return UNAVAILABLE