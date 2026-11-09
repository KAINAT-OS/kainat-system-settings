extends SettingsPanel
# Display & monitor settings. Brightness is applied through Plasma's
# PowerDevil DBus API, which drives the real backlight on both Wayland and
# X11; complex multi-monitor/color work is delegated to KDE KCMs.

const POWERDEVIL_SERVICE := "org.kde.org_kde_powerdevil"
const BRIGHTNESS_PATH := "/org/kde/ScreenBrightness"
const SCREEN_BRIGHTNESS_INTERFACE := "org.kde.ScreenBrightness"
const DISPLAY_INTERFACE := "org.kde.ScreenBrightness.Display"

var _brightness_display := ""
var _brightness_max := 0.0


func build() -> void:
	page_header("Displays", "Configure monitors, brightness, color and night light.")

	var outputs: Array = _connected_outputs()
	var primary: String = str(outputs[0]) if outputs.size() > 0 else ""
	_init_brightness()

	info_tiles([
		{"value": str(outputs.size()), "label": "Connected displays"},
		{"value": _primary_resolution(), "label": "Primary resolution"},
		{"value": primary if not primary.is_empty() else UNAVAILABLE, "label": "Primary output"},
	])

	section("Brightness")
	var c := card()
	slider_row(c, "Screen brightness", "Adjust the primary display backlight.", "B", 10, 100,
		_current_brightness(), func(v: float) -> void: _set_brightness(primary, v), "%")

	_build_resolution_section()

	section("Display")
	var c2 := card()
	kcm_row(c2, "Monitors & Resolution", "Arrange displays, resolution and scaling.", "M", "kcm_kscreen")
	kcm_row(c2, "Night Light", "Reduce blue light at night.", "N", "kcm_nightlight")
	kcm_row(c2, "Color Calibration", "Gamma and color correction.", "C", "kcm_kgamma")

	section("Advanced")
	var c3 := card()
	kcm_row(c3, "Display Information (EDID)", "Detailed panel capabilities.", "E", "kcm_edid")
	kcm_row(c3, "Screen Edges", "Active screen corners and edges.", "S", "kcm_kwinscreenedges")


func _connected_outputs() -> Array:
	var outputs: Array = []
	var out: String = Sh.run_capture("xrandr --query 2>/dev/null")
	for line in out.split("\n"):
		if line.contains(" connected"):
			var parts: PackedStringArray = line.split(" ", false)
			if parts.size() > 0:
				outputs.append(parts[0])
	return outputs


# --- resolution & scaling (kscreen-doctor) ----------------------------------

func _build_resolution_section() -> void:
	section("Resolution & Scaling")
	var c := card()
	if not Sh.has_tool("kscreen-doctor"):
		unavailable_row(c, "Resolution & Scaling", "kscreen-doctor is not installed")
		return
	var out: Dictionary = _primary_kscreen_output()
	if out.is_empty():
		unavailable_row(c, "Resolution & Scaling", "No active output detected")
		return
	var name: String = out["name"]
	var modes: Array = out["modes"]          # [{label, id}], first is current
	var current_mode: String = out["current"]  # e.g. "1920x1080@165"

	var labels: Array = []
	var selected := 0
	for i in modes.size():
		labels.append(modes[i]["label"])
		if modes[i]["label"] == current_mode:
			selected = i
	if labels.is_empty():
		info_row(c, "Resolution", "No modes reported for " + name + ".")
	else:
		choice_row(c, "Resolution", "Current: " + current_mode + " on " + name + ".", "R",
			labels, selected, func(idx: int) -> void:
				_set_kscreen_mode(name, str(modes[idx]["id"]), str(modes[idx]["label"])))

	var scale_opts: Array = ["100%", "125%", "150%", "175%", "200%"]
	var scale_vals: Array = [1.0, 1.25, 1.5, 1.75, 2.0]
	var scale_cur: float = float(out["scale"])
	var scale_idx := 0
	var best := absf(scale_cur - 1.0)
	for i in scale_vals.size():
		var d := absf(scale_cur - float(scale_vals[i]))
		if d < best:
			best = d
			scale_idx = i
	choice_row(c, "Scale", "Interface scaling for " + name + ".", "S",
		scale_opts, scale_idx, func(idx: int) -> void:
			_set_kscreen_scale(name, float(scale_vals[idx]), str(scale_opts[idx])))


# Returns {name, modes: [{label, id}], current, scale} for the first enabled output.
func _primary_kscreen_output() -> Dictionary:
	var raw := Sh.run_capture("kscreen-doctor -o 2>/dev/null")
	# Strip ANSI colour codes.
	var re := RegEx.new()
	re.compile("\u001b\\[[0-9;]*m")
	var text := re.sub(raw, "", true)

	var current: Dictionary = {}
	var outputs: Array = []
	for line in text.split("\n"):
		var s := line.strip_edges()
		if s.begins_with("Output: "):
			if not current.is_empty():
				outputs.append(current)
			var rest := s.substr(8)
			var parts := rest.split(" ", false)
			# parts: [id, name]
			current = {"name": parts[1] if parts.size() > 1 else "", "modes": [],
				"current": "", "scale": 1.0, "enabled": false}
		elif not current.is_empty():
			if s == "enabled":
				current["enabled"] = true
			elif s.begins_with("Modes:"):
				current["modes"] = _parse_kscreen_modes(s)
			elif s.begins_with("Scale:"):
				var v := s.get_slice(":", 1).strip_edges()
				current["scale"] = float(v) if v.is_valid_float() else 1.0
			elif s.begins_with("Geometry:"):
				pass
	if not current.is_empty():
		outputs.append(current)

	for o in outputs:
		if o["enabled"] and not o["modes"].is_empty():
			# Find the active mode (flagged '*' by kscreen-doctor).
			for m in o["modes"]:
				if m["current"]:
					o["current"] = str(m["label"])
					break
			if o["current"] == "":
				o["current"] = str(o["modes"][0]["label"])
			return o
	return {}


# "Modes: 1:1920x1080@60! 2:1920x1080@165*" -> [{label, id, current}], ...
# Suffixes: '!' = preferred, '*' = currently active.
func _parse_kscreen_modes(line: String) -> Array:
	var modes: Array = []
	var body := line.substr(line.find(":") + 1)
	for token in body.split(" ", false):
		var t := token.strip_edges()
		var sep := t.find(":")
		if sep <= 0:
			continue
		var id := t.substr(0, sep)
		var label := t.substr(sep + 1)
		var current := label.ends_with("*")
		label = label.trim_suffix("*").trim_suffix("!")
		if not id.is_valid_int() or not label.contains("x"):
			continue
		modes.append({"id": id, "label": label, "current": current})
	return modes


func _set_kscreen_mode(output: String, mode_id: String, label: String) -> void:
	# kscreen-doctor applies modes atomically; a wrong mode is auto-reverted by
	# KScreen's own 20s revert timer in most cases, but we only ever offer modes
	# the display reported, so this is safe. These are one-shot dropdown picks
	# (not slider spam) and finish fast, so run them to completion and report a
	# failure instead of leaving "Setting resolution to …" hanging forever.
	var code := Sh.run_wait(
			"kscreen-doctor output." + Sh.quote(output) + ".mode." + Sh.quote(label)
			+ " >/dev/null 2>&1")
	if code == 0:
		notify("Resolution set to " + label + ".")
	else:
		notify("Could not set the resolution to " + label + ".")


func _set_kscreen_scale(output: String, scale: float, label: String) -> void:
	var code := Sh.run_wait(
			"kscreen-doctor output." + Sh.quote(output) + ".scale." + str(scale)
			+ " >/dev/null 2>&1")
	if code == 0:
		notify("Scale set to " + label + ".")
	else:
		notify("Could not set the scale to " + label + ".")


func _primary_resolution() -> String:
	var out: String = Sh.run_capture("xrandr --query 2>/dev/null")
	for line in out.split("\n"):
		if line.contains(" connected primary") or line.contains(" connected"):
			for token in line.split(" ", false):
				if token.contains("x") and token.contains("+"):
					return token.split("+")[0]
	return UNAVAILABLE


# --- brightness ------------------------------------------------------------

func _init_brightness() -> void:
	var displays := _brightness_displays()
	if displays.is_empty():
		return
	_brightness_display = str(displays[0])
	var max_str := _brightness_property("MaxBrightness")
	_brightness_max = float(max_str) if not max_str.is_empty() else 0.0


func _brightness_displays() -> Array:
	var raw := _qdbus_get(BRIGHTNESS_PATH, SCREEN_BRIGHTNESS_INTERFACE, "DisplaysDBusNames")
	var displays: Array = []
	var cleaned := raw.replace("[", " ").replace("]", " ").replace("'", " ").replace(",", " ")
	for token in cleaned.split(" ", false):
		if token.begins_with("display") and not displays.has(token):
			displays.append(token)
	return displays


func _current_brightness() -> float:
	if _brightness_display.is_empty() or _brightness_max <= 0.0:
		return 100.0
	var current := float(_brightness_property("Brightness"))
	return clampf(current / _brightness_max * 100.0, 0.0, 100.0)


func _set_brightness(output: String, percent: float) -> void:
	if not _brightness_display.is_empty() and _brightness_max > 0.0:
		var target: int = int(round(_brightness_max * clampf(percent, 0.0, 100.0) / 100.0))
		var tool := _qdbus_tool()
		if tool.is_empty():
			return
		Sh.run(tool + " " + Sh.quote(POWERDEVIL_SERVICE) + " "
			+ Sh.quote(BRIGHTNESS_PATH + "/" + _brightness_display) + " "
			+ Sh.quote(DISPLAY_INTERFACE + ".SetBrightness") + " " + str(target) + " 0")
		return
	# Fall back to the xrandr gamma trick, which only has an effect on X11.
	if output.is_empty() or OS.get_environment("XDG_SESSION_TYPE") != "x11":
		return
	var value: String = "%.2f" % (percent / 100.0)
	Sh.run("xrandr --output " + Sh.quote(output) + " --brightness " + value)


func _brightness_property(property: String) -> String:
	if _brightness_display.is_empty():
		return ""
	return _qdbus_get(BRIGHTNESS_PATH + "/" + _brightness_display, DISPLAY_INTERFACE, property)


func _qdbus_get(path: String, interface: String, property: String) -> String:
	var tool := _qdbus_tool()
	if tool.is_empty():
		return ""
	return Sh.run_capture(tool + " " + Sh.quote(POWERDEVIL_SERVICE) + " " + Sh.quote(path)
		+ " org.freedesktop.DBus.Properties.Get " + Sh.quote(interface) + " " + Sh.quote(property)
		+ " 2>/dev/null").strip_edges()


func _qdbus_tool() -> String:
	if Sh.has_tool("qdbus6"):
		return "qdbus6"
	if Sh.has_tool("qdbus"):
		return "qdbus"
	return ""