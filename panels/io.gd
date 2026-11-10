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
	nav_row(c4, "Input Method", "Configure Fcitx 5 or IBus.", "I", _open_input_method)

	defer(_populate)


func _populate() -> void:
	var sinks: Array = _audio_devices("sinks")
	if sinks.size() > 1:
		var labels: Array = []
		var current: String = Sh.run_capture("pactl get-default-sink 2>/dev/null").strip_edges()
		var selected := 0
		for i in sinks.size():
			labels.append(str(sinks[i]["label"]))
			if str(sinks[i]["name"]) == current:
				selected = i
		choice_row(_sound_card, "Output Device", "Where sound is played.", "D",
			labels, selected, func(idx: int) -> void:
				_set_default_sink(str(sinks[idx]["name"]), str(sinks[idx]["label"])))

	var volume: int = _get_volume()
	slider_row(_sound_card, "Output volume", "Master volume for the default sink.", "V", 0, 150, volume,
		func(v: float) -> void:
			debounce("volume", 0.12, func() -> void:
				Sh.run("pactl set-sink-volume @DEFAULT_SINK@ %d%%" % int(v))), "%")
	toggle_row(_sound_card, "Mute", "Silence all audio output.", "M", _is_muted(),
		func(on: bool) -> void:
			Sh.run("pactl set-sink-mute @DEFAULT_SINK@ " + ("1" if on else "0")))
	action_row(_sound_card, "Test Speakers", "Play a short sample on the default output.", "T",
		"Play", _test_sound)
	kcm_row(_sound_card, "Audio Devices", "Outputs, inputs and per-app volume.", "A", "kcm_pulseaudio")

	var one_click: String = "One-click to open files"
	toggle_row(_point_card, one_click, "Open files and folders with a single click.", "O",
		_is_single_click(), func(on: bool) -> void:
			Sh.kde_write("kdeglobals", "KDE", "SingleClick", "true" if on else "false")
			notify("Click behaviour updated."))


# --- audio ------------------------------------------------------------------

# [{name, label}] for "sinks" (outputs) or "sources" (inputs). pactl 16+ can
# emit JSON with human descriptions; the tab-separated listing is the fallback.
func _audio_devices(kind: String) -> Array:
	var devices: Array = []
	var raw := Sh.run_capture("pactl -f json list " + kind + " 2>/dev/null")
	if not raw.strip_edges().is_empty():
		var data: Variant = JSON.parse_string(raw)
		if typeof(data) == TYPE_ARRAY:
			for item in (data as Array):
				if typeof(item) != TYPE_DICTIONARY:
					continue
				var d: Dictionary = item
				var name := str(d.get("name", ""))
				if name.is_empty():
					continue
				var label := str(d.get("description", "")).strip_edges()
				devices.append({"name": name, "label": label if not label.is_empty() else name})
	if devices.is_empty():
		for line in Sh.run_lines("pactl list short " + kind + " 2>/dev/null"):
			var parts: PackedStringArray = line.split("\t", false)
			if parts.size() >= 2:
				devices.append({"name": parts[1], "label": parts[1]})
	return devices


func _set_default_sink(name: String, label: String) -> void:
	if Sh.run_wait("pactl set-default-sink " + Sh.quote(name)) != 0:
		notify("Could not switch the output to " + label + ".")
		return
	# Move streams that are already playing so audio continues seamlessly.
	for line in Sh.run_lines("pactl list short sink-inputs 2>/dev/null"):
		var parts: PackedStringArray = line.split("\t", false)
		if not parts.is_empty() and parts[0].is_valid_int():
			Sh.run("pactl move-sink-input " + parts[0] + " " + Sh.quote(name))
	notify("Audio output: " + label)


func _test_sound() -> void:
	const sample := "/usr/share/sounds/freedesktop/stereo/complete.oga"
	if not Sh.has_tool("paplay"):
		notify("paplay is not available, so the test sound cannot play.")
		return
	if not FileAccess.file_exists(sample):
		notify("No test sound file is installed.")
		return
	Sh.run("paplay " + Sh.quote(sample) + " >/dev/null 2>&1 &")


func _open_input_method() -> void:
	if Sh.has_tool("fcitx5-configtool"):
		Sh.launch("fcitx5-configtool")
	elif Sh.has_tool("ibus-setup"):
		Sh.launch("ibus-setup")
	elif Sh.has_tool("fcitx-configtool"):
		Sh.launch("fcitx-configtool")
	else:
		Sh._notify_missing("fcitx5-configtool or ibus-setup", "Input method settings", notify)


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
