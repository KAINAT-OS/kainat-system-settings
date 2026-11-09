extends SettingsPanel
# Login & Sessions: session type, login manager and auto-start apps.


func build() -> void:
	page_header("Login & Sessions", "Session type, login manager and startup.")

	section("Current Session")
	var c := card()
	info_row(c, "Session Type", _session_type())
	info_row(c, "Desktop", _env("XDG_CURRENT_DESKTOP", "Kainat"))
	info_row(c, "Session ID", str(OS.get_process_id()))
	info_row(c, "Uptime", _uptime())

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


func _env(key: String, fallback: String) -> String:
	var value: String = OS.get_environment(key)
	return value if not value.is_empty() else fallback


func _uptime() -> String:
	var raw: String = Sh.read_text("/proc/uptime")
	if raw.is_empty():
		return UNAVAILABLE
	var seconds: float = float(raw.split(" ")[0])
	return "%dh %dm" % [int(seconds / 3600.0), int((seconds - int(seconds / 3600.0) * 3600) / 60.0)]