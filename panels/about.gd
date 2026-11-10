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
	info_row(c, "Kernel", _kernel())
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
	action_row(c3, "Copy System Information", "Paste this into a bug report or support chat.", "C", "Copy", func() -> void:
		_copy_report())

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


# Everything the About page shows, flattened into plain text. Clipboard output
# is what people paste into issue trackers, so it must not depend on the UI.
func _system_report() -> String:
	var rel: Dictionary = Sh.os_release()
	var lines := PackedStringArray()
	lines.append("Operating System: " + str(rel.get("PRETTY_NAME", "Kainat OS")))
	lines.append("Version: " + str(rel.get("VERSION", UNAVAILABLE)))
	lines.append("Kernel: " + _kernel())
	lines.append("Architecture: " + Engine.get_architecture_name())
	lines.append("Hostname: " + _hostname())
	lines.append("Desktop: " + _plasma_version())
	lines.append("Session: " + _session())
	lines.append("Display Server: " + _display_server())
	lines.append("Processor: " + _cpu_model())
	lines.append("Memory: " + _memory())
	lines.append("Graphics: " + _gpu())
	lines.append("Disk Usage: " + _disk())
	return "\n".join(lines)


func _copy_report() -> void:
	DisplayServer.clipboard_set(_system_report())
	notify("System information copied to the clipboard.")


func _hostname() -> String:
	var h: String = Sh.run_capture("hostname").strip_edges()
	return h if not h.is_empty() else OS.get_environment("HOSTNAME")


# OS.get_version() reports the *distribution* version on Linux ("LTS 25.1"),
# not the kernel, so the kernel has to come from uname.
func _kernel() -> String:
	var release := Sh.run_capture("uname -r").strip_edges()
	return release if not release.is_empty() else UNAVAILABLE


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
			# The PCI address also contains a colon ("01:00.0"), so the model
			# name starts after the ": " that follows the device class.
			var idx: int = line.find(": ")
			if idx != -1:
				return line.substr(idx + 2).strip_edges()
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
	var failed_output := Sh.run_capture("systemctl --failed --no-legend 2>/dev/null").strip_edges()
	var failed := 0
	if not failed_output.is_empty():
		failed = failed_output.split("\n", false).size()
	if failed > 0:
		output += "\nFailed systemd services: " + str(failed) + "\n"
		for line in failed_output.split("\n", false):
			var service: String = line.strip_edges().split(" ", false)[0]
			if not service.is_empty():
				output += "  • " + service + "\n"
		output += "Open System Monitor → Services for details.\n"
	
	# Show results
	var dialog := AcceptDialog.new()
	dialog.title = "System Diagnostics"
	dialog.dialog_text = output.strip_edges()
	dialog.ok_button_text = "OK"
	dialog.min_size = Vector2(500, 400)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)


func _reset_settings() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Reset System Settings?"
	dialog.dialog_text = "This will reset your user configuration files:\n• ~/.config/*\n• ~/.local/share/config/*\n\nNothing is deleted. The old files are moved to a timestamped backup folder in your home directory, so you can restore them if needed.\n\nYour personal files (Documents, Downloads, Pictures, etc.) will NOT be touched.\n\nYou will need to log out and back in for changes to take full effect."
	dialog.ok_button_text = "Reset Settings"
	dialog.add_cancel_button("Cancel")
	
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(_on_reset_confirmed.bind(dialog))


func _on_reset_confirmed(dialog: ConfirmationDialog) -> void:
	dialog.queue_free()
	notify("Resetting settings... Please wait.")
	var code := Sh.reset_user_settings()
	var backup := Sh.last_reset_backup()
	if code == 0 and backup.is_empty():
		notify("Settings reset complete. Please log out and back in.")
		return
	if backup.is_empty():
		notify("Reset failed. Your settings were left unchanged.")
		return
	var done := AcceptDialog.new()
	done.title = "Settings Reset"
	done.dialog_text = "Your settings were reset.\n\nA backup of the old configuration is here:\n" + backup + "\n\nLog out and back in for the changes to take full effect."
	done.ok_button_text = "Open Backup Folder"
	done.add_cancel_button("Close")
	add_child(done)
	done.popup_centered()
	done.confirmed.connect(_on_reset_backup_confirmed.bind(done, backup))


func _on_reset_backup_confirmed(dialog: AcceptDialog, backup: String) -> void:
	dialog.queue_free()
	Sh.run("xdg-open " + Sh.quote(backup))


func _collect_logs() -> void:
	notify("Collecting system logs...")

	var log_dir := Sh.home() + "/kainat-logs-" + str(int(Time.get_unix_time_from_system()))
	_last_log_dir = log_dir

	# One background shell writes every report and drops a marker file when the
	# last one finishes. The UI stays responsive, and the folder is never opened
	# while the files are still half empty.
	var steps := PackedStringArray()
	steps.append("mkdir -p " + Sh.quote(log_dir) + " && cd " + Sh.quote(log_dir) + " || exit 1")
	steps.append("journalctl --no-pager -n 20000 > journalctl.log 2>&1")
	steps.append("dmesg > dmesg.log 2>&1")
	steps.append("lspci -nn > lspci.log 2>&1")
	steps.append("lsusb > lsusb.log 2>&1")
	steps.append("df -h > disk.log 2>&1")
	steps.append("free -h > memory.log 2>&1")
	steps.append("cat /etc/os-release > os-release.log 2>&1")
	steps.append("uname -a > kernel.log 2>&1")
	steps.append("touch .done")
	Sh.run(" ; ".join(steps))

	if _log_poll_timer == null:
		_log_poll_timer = Timer.new()
		_log_poll_timer.wait_time = 0.25
		_log_poll_timer.timeout.connect(_poll_logs)
		add_child(_log_poll_timer)
	_log_poll_elapsed = 0.0
	_log_poll_timer.start()


func _poll_logs() -> void:
	_log_poll_elapsed += 0.25
	var finished := FileAccess.file_exists(_last_log_dir + "/.done")
	# Never spin forever: a blocked journalctl should not swallow the dialog.
	if not finished and _log_poll_elapsed < 30.0:
		return
	_log_poll_timer.stop()
	_show_logs_dialog()


func _show_logs_dialog() -> void:
	notify("Logs saved to: " + _last_log_dir)

	var dialog := AcceptDialog.new()
	dialog.title = "Logs Collected"
	dialog.dialog_text = "System logs saved to:\n" + _last_log_dir + "\n\nYou can attach these when reporting issues."
	dialog.ok_button_text = "Open Folder"
	dialog.add_cancel_button("Close")

	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(_on_logs_confirmed.bind(dialog))


func _on_logs_confirmed(dialog: AcceptDialog) -> void:
	dialog.queue_free()
	Sh.run("xdg-open " + Sh.quote(_last_log_dir))


var _last_log_dir: String = ""
var _log_poll_timer: Timer = null
var _log_poll_elapsed: float = 0.0
