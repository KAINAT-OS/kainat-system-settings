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

	# System maintenance section
	_add_reset_section()

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


# --- System Reset & Diagnostics ---

func _add_reset_section() -> void:
	section("System Maintenance")
	var c := card()
	
	action_row(c, "Run System Diagnostics", "Check disk, RAM, CPU temperature, and services.", "D", "Run Diagnostics", func() -> void:
		_run_diagnostics()
	)
	
	action_row(c, "Reset System Settings", "Restore themes, panel layout, and configs to defaults.\nPreserves user files (Documents, Downloads, etc.).", "R", "Reset Settings", func() -> void:
		_reset_settings()
	)
	
	action_row(c, "Collect System Logs", "Gather journalctl, dmesg, and system info for bug reports.", "L", "Collect Logs", func() -> void:
		_collect_logs()
	)


func _run_diagnostics() -> void:
	notify("Running system diagnostics...")
	
	var output := ""
	
	# CPU Temperature
	var temp := Sh.get_cpu_temp()
	if temp > 0:
		output += "CPU Temperature: " + str(temp) + "°C\n"
		if temp > 80:
			output += "  ⚠️ HIGH - Consider cleaning dust or checking cooling\n"
	elif temp == -1:
		output += "CPU Temperature: Could not read (no sensors)\n"
	
	# RAM Usage
	var ram := Sh.get_ram_usage()
	if ram["total"] > 0:
		output += "RAM: " + str(ram["used"]) + " MB / " + str(ram["total"]) + " MB (" + str(int(ram["percent"])) + "%)\n"
		if ram["percent"] > 85:
			output += "  ⚠️ HIGH - Consider closing unused apps\n"
	
	# Disk Usage
	var disk := Sh.get_disk_health()
	if not disk.is_empty():
		output += "Disk (root): " + disk + " used\n"
		var pct := int(disk.trim_suffix("%"))
		if pct > 90:
			output += "  ⚠️ CRITICAL - Free up space immediately\n"
		elif pct > 80:
			output += "  ⚠️ HIGH - Consider cleaning up\n"
	
	# Services
	var failed := Sh.run_capture("systemctl --failed --no-legend 2>/dev/null | wc -l").strip_edges().to_int()
	if failed > 0:
		output += "\nFailed systemd services: " + str(failed) + "\n"
	
	# Show results
	var dialog := AcceptDialog.new()
	dialog.title = "System Diagnostics"
	dialog.text = output.strip_edges()
	dialog.ok_text = "OK"
	dialog.min_size = Vector2(500, 400)
	dialog.popup_centered()


func _reset_settings() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Reset System Settings?"
	dialog.text = "This will delete your user configuration files:\n• ~/.config/*\n• ~/.local/share/config/*\n\nYour personal files (Documents, Downloads, Pictures, etc.) will NOT be touched.\n\nYou will need to log out and back in for changes to take full effect."
	dialog.ok_text = "Reset Settings"
	dialog.add_cancel_button("Cancel")
	
	if dialog.popup() == OK:
		notify("Resetting settings... Please wait.")
		var code := Sh.reset_user_settings()
		if code == 0:
			notify("Settings reset complete. Please log out and back in.")
		else:
			notify("Reset completed with some errors. Check terminal.")


func _collect_logs() -> void:
	notify("Collecting system logs...")
	
	var log_dir := Sh.home() + "/kainat-logs-" + str(OS.get_unix_time())
	Sh.run("mkdir -p " + Sh.quote(log_dir))
	
	Sh.run("journalctl --no-pager > " + Sh.quote(log_dir + "/journalctl.log") + " 2>&1")
	Sh.run("dmesg > " + Sh.quote(log_dir + "/dmesg.log") + " 2>&1")
	Sh.run("lspci -nn > " + Sh.quote(log_dir + "/lspci.log") + " 2>&1")
	Sh.run("lsusb > " + Sh.quote(log_dir + "/lsusb.log") + " 2>&1")
	Sh.run("df -h > " + Sh.quote(log_dir + "/disk.log") + " 2>&1")
	Sh.run("free -h > " + Sh.quote(log_dir + "/memory.log") + " 2>&1")
	Sh.run("cat /etc/os-release > " + Sh.quote(log_dir + "/os-release.log") + " 2>&1")
	Sh.run("uname -a > " + Sh.quote(log_dir + "/kernel.log") + " 2>&1")
	
	notify("Logs saved to: " + log_dir)
	
	var dialog := AcceptDialog.new()
	dialog.title = "Logs Collected"
	dialog.text = "System logs saved to:\n" + log_dir + "\n\nYou can attach these when reporting issues."
	dialog.ok_text = "Open Folder"
	dialog.add_cancel_button("Close")
	if dialog.popup() == OK:
		Sh.run("xdg-open " + Sh.quote(log_dir))