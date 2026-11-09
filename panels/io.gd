extends SettingsPanel
# Input & Output devices: audio, mouse, keyboard, touchpad and peripherals.
# Audio is native (PulseAudio/PipeWire); device calibration uses KCMs.

var _sound_card: VBoxContainer
var _point_card: VBoxContainer


func build() -> void:
	page_header("Input & Output Devices", "Audio, mice, keyboards, touchpads and game controllers.")

	section("Sound")
	_sound_card = card()

	section("Pointing Devices")
	_point_card = card()
	kcm_row(_point_card, "Mouse", "Speed, acceleration and buttons.", "M", "kcm_mouse")
	nav_row(_point_card, "Gaming Mouse", "DPI, polling rate, buttons and RGB for gaming mice.", "G",
		func() -> void: _open_piper())
	kcm_row(_point_card, "Touchpad", "Tap, scroll and gesture settings.", "T", "kcm_touchpad")
	kcm_row(_point_card, "Touchscreen", "On-screen touch calibration.", "S", "kcm_touchscreen")
	kcm_row(_point_card, "Tablet", "Graphics tablet mapping.", "B", "kcm_tablet")

	section("Keyboard")
	var c3 := card()
	kcm_row(c3, "Keyboard Hardware & Layout", "Keymap and repeat settings.", "K", "kcm_keyboard")
	kcm_row(c3, "Keyboard Shortcuts", "Global and application shortcuts.", "H", "kcm_keys")
	kcm_row(c3, "Virtual Keyboard", "On-screen keyboard and input method.", "V", "kcm_virtualkeyboard")

	# Backed by kaccessrc [Keyboard], whose keys are declared verbatim in
	# /usr/share/config.kcfg/kcmaccessibilitykeyboard.kcfg — i.e. the exact
	# same file the official kcm_access writes to.
	section("Accessibility")
	var c7 := card()
	toggle_row(c7, "Sticky Keys", "Latch modifiers so shortcuts can be pressed one key at a time.",
		"C", _access_flag("StickyKeys"),
		func(on: bool) -> void: _set_access_flag("StickyKeys", on, "Sticky Keys"))
	toggle_row(c7, "Modifier Notifications", "Show feedback when a modifier key is pressed.",
		"L", _access_flag("kNotifyModifiers"),
		func(on: bool) -> void: _set_access_flag("kNotifyModifiers", on, "Modifier notifications"))
	toggle_row(c7, "Lock Key Beep", "Beep when Caps Lock or Num Lock changes.",
		"F", _access_flag("ToggleKeysBeep"),
		func(on: bool) -> void: _set_access_flag("ToggleKeysBeep", on, "Lock key beep"))
	kcm_row(c7, "Accessibility", "Screen reader, bounce keys and mouse keys.", "X", "kcm_access")

	section("Printers")
	var c5 := card()
	kcm_row(c5, "Print Queue & Printers", "Add, remove and manage printers.", "P", "kcm_printer_manager")

	section("Notifications")
	var c6 := card()
	toggle_row(c6, "Do Not Disturb", "Silence all notification popups.", "D", _is_dnd(),
		func(on: bool) -> void:
			Sh.kde_write("kdeglobals", "Notifications", "DoNotDisturb", "true" if on else "false")
			Sh.run("plasmashell --replace >/dev/null 2>&1 &")
			notify("Do Not Disturb " + ("enabled" if on else "disabled")))
	kcm_row(c6, "Notification Settings", "Per-app sounds, popups and badges.", "N", "kcm_notifications")

	section("Other Input")
	var c4 := card()
	kcm_row(c4, "Game Controllers", "Test and map gamepads.", "G", "kcm_gamecontroller")
	kcm_row(c4, "Input Method", "Fcitx / IBus configuration.", "I", "kcm_fcitx5")

	defer(_populate)


func _populate() -> void:
	var volume: int = _get_volume()
	slider_row(_sound_card, "Output volume", "Master volume for the default sink.", "V", 0, 150, volume,
		func(v: float) -> void: Sh.run("pactl set-sink-volume @DEFAULT_SINK@ %d%%" % int(v)), "%")
	toggle_row(_sound_card, "Mute", "Silence all audio output.", "M", _is_muted(),
		func(on: bool) -> void: Sh.run("pactl set-sink-mute @DEFAULT_SINK@ " + ("1" if on else "0")))
	kcm_row(_sound_card, "Audio Devices", "Outputs, inputs and per-app volume.", "A", "kcm_pulseaudio")

	var one_click: String = "One-click to open files"
	toggle_row(_point_card, one_click, "Open files and folders with a single click.", "O",
		_is_single_click(), func(on: bool) -> void:
			Sh.kde_write("kdeglobals", "KDE", "SingleClick", "true" if on else "false")
			Sh.run("plasmashell --replace >/dev/null 2>&1 &")
			notify("Click behaviour updated."))


func _get_volume() -> int:
	var out: String = Sh.run_capture("pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null")
	var idx: int = out.find("%")
	if idx > 2:
		var start: int = out.rfind(" ", idx - 1)
		if start == -1:
			start = 0
		return out.substr(start + 1, idx - start - 1).to_int()
	return 100


func _is_muted() -> bool:
	return Sh.run_capture("pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null").contains("yes")


func _is_single_click() -> bool:
	return Sh.kde_read("kdeglobals", "KDE", "SingleClick", "true").strip_edges() == "true"


func _open_piper() -> void:
	if Sh.has_tool("piper"):
		Sh.launch("piper")
	else:
		Sh._notify_missing("piper", "Gaming mouse settings", notify)


func _is_dnd() -> bool:
	return Sh.kde_read("kdeglobals", "Notifications", "DoNotDisturb", "false").strip_edges() == "true"


func _access_flag(key: String) -> bool:
	return Sh.kde_read("kaccessrc", "Keyboard", key, "false").strip_edges().to_lower() == "true"


func _set_access_flag(key: String, on: bool, label: String) -> void:
	Sh.kde_write("kaccessrc", "Keyboard", key, "true" if on else "false")
	_apply_accessibility()
	notify(label + " " + ("enabled" if on else "disabled"))


# Neither kaccess nor kwin_wayland holds an inotify watch on kaccessrc (checked
# via /proc/<pid>/fdinfo — both had zero inotify fds), so a config write alone
# does nothing until the owning daemon re-reads it. systemd owns the unit, so a
# service restart is routine; KWin is nudged too because it is the component
# that actually applies keyboard accessibility inside a Wayland session.
func _apply_accessibility() -> void:
	if Sh.has_tool("systemctl"):
		Sh.run("systemctl --user restart plasma-kaccess.service >/dev/null 2>&1 &")
	Sh._kwin_reconfigure()
