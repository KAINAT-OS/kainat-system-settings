extends SettingsPanel
# Login & Sessions: session type, login manager, session actions and startup.

var _session_row: HBoxContainer = null


func build() -> void:
	page_header("Login & Sessions", "Session type, login manager and startup.")

	section("Current Session")
	var c := card()
	info_row(c, "Session Type", _session_type())
	info_row(c, "Desktop", _env("XDG_CURRENT_DESKTOP", "Kainat"))
	_session_row = info_row(c, "Session ID", _session_id())
	info_row(c, "Uptime", _uptime())

	section("Session")
	var c4 := card()
	action_row(c4, "Lock Screen", "Require the password before the session resumes.", "L",
		"Lock", _lock_session)
	action_row(c4, "Log Out", "End this session and return to the login screen.", "O",
		"Log Out", func() -> void:
			_confirm("Log out now?", "Close all open applications and return to the login screen.",
				"Log Out", _logout))
	action_row(c4, "Restart", "Reboot the computer.", "R", "Restart", func() -> void:
		_confirm("Restart now?", "All open applications will be closed.",
			"Restart", _restart))
	action_row(c4, "Shut Down", "Power the computer off.", "S", "Shut Down", func() -> void:
		_confirm("Shut down now?", "All open applications will be closed.",
			"Shut Down", _shutdown))

	section("Login Manager")
	var c2 := card()
	kcm_row(c2, "Login Screen (SDDM)", "Theme and appearance of the login screen.", "L", "kcm_sddm")
	kcm_row(c2, "Login & Logout", "Session behaviour on login/logout.", "O", "kcm_smserver")
	kcm_row(c2, "Screen Locking", "Idle lock timing and password prompt.", "K", "kcm_screenlocker")

	section("Startup")
	var c3 := card()
	kcm_row(c3, "Autostart", "Applications started after login.", "A", "kcm_autostart")
	kcm_row(c3, "Background Services", "Services loaded at session start.", "B", "kcm_kded")
	kcm_row(c3, "Desktop Paths", "Location of common user folders.", "D", "kcm_desktoppaths")
	kcm_row(c3, "Activities", "Workspaces for focused tasks.", "T", "kcm_activities")


func _session_type() -> String:
	var value: String = _env("XDG_SESSION_TYPE", "")
	if not value.is_empty():
		return value.capitalize()
	var wayland: String = _env("WAYLAND_DISPLAY", "")
	if not wayland.is_empty():
		return "Wayland"
	return "X11"


func _session_id() -> String:
	var value: String = _env("XDG_SESSION_ID", "")
	if not value.is_empty():
		return value
	if Sh.has_tool("loginctl"):
		var uid := Sh.run_capture("id -u 2>/dev/null").strip_edges()
		for line in Sh.run_lines("loginctl list-sessions --no-legend 2>/dev/null"):
			var parts: PackedStringArray = line.split(" ", false)
			if parts.size() >= 2 and parts[1] == uid:
				return parts[0]
	return UNAVAILABLE


func _env(key: String, fallback: String) -> String:
	var value: String = OS.get_environment(key)
	if not value.is_empty():
		return value
	return fallback


func _uptime() -> String:
	var raw: String = Sh.read_text("/proc/uptime")
	if raw.is_empty():
		return UNAVAILABLE
	var total := int(float(raw.split(" ")[0]))
	var days := total / 86400
	var hours := (total % 86400) / 3600
	var minutes := (total % 3600) / 60
	if days > 0:
		return "%dd %dh %dm" % [days, hours, minutes]
	return "%dh %dm" % [hours, minutes]


# --- session actions --------------------------------------------------------

func _confirm(title: String, text: String, ok: String, on_yes: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.text = text
	dialog.ok_text = ok
	dialog.add_cancel_button("Cancel")
	dialog.confirmed.connect(func() -> void: on_yes.call())
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


func _lock_session() -> void:
	if Sh.has_tool("loginctl"):
		var code := Sh.run_wait("loginctl lock-session")
		if code == 0:
			return
	if Sh.has_tool("qdbus6"):
		Sh.run("qdbus6 org.freedesktop.ScreenSaver /ScreenSaver org.freedesktop.ScreenSaver.Lock")
		return
	notify("No screen-locking service responded.")


# Plasma's shutdown service handles logout/reboot/poweroff with the same
# polkit rules as the desktop's own menu, so no password prompt is needed.
func _shutdown_call(method: String) -> bool:
	var tool := "qdbus6" if Sh.has_tool("qdbus6") else ("qdbus" if Sh.has_tool("qdbus") else "")
	if tool.is_empty():
		return false
	Sh.run(tool + " org.kde.Shutdown /Shutdown org.kde.Shutdown." + method
		+ " >/dev/null 2>&1 &")
	return true


func _logout() -> void:
	if _shutdown_call("logout"):
		return
	if Sh.has_tool("loginctl"):
		Sh.run("loginctl terminate-session \"$XDG_SESSION_ID\" >/dev/null 2>&1 &")
		return
	notify("Could not end the session.")


func _restart() -> void:
	if _shutdown_call("logoutAndReboot"):
		return
	if Sh.has_tool("systemctl"):
		Sh.run("systemctl reboot >/dev/null 2>&1 &")
		return
	notify("Could not restart the computer.")


func _shutdown() -> void:
	if _shutdown_call("logoutAndShutdown"):
		return
	if Sh.has_tool("systemctl"):
		Sh.run("systemctl poweroff >/dev/null 2>&1 &")
		return
	notify("Could not shut down the computer.")
