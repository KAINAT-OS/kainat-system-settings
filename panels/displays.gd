extends SettingsPanel
# Display & monitor settings. Outputs, modes and scaling come from
# kscreen-doctor, which works on both Wayland and X11 (xrandr only reports the
# real picture on X11). Brightness is applied through Plasma's PowerDevil DBus
# API, which drives the real backlight on both session types; complex
# multi-monitor/color work is delegated to the KDE KCMs.

const POWERDEVIL_SERVICE := "org.kde.org_kde_powerdevil"
const BRIGHTNESS_PATH := "/org/kde/ScreenBrightness"
const SCREEN_BRIGHTNESS_INTERFACE := "org.kde.ScreenBrightness"
const DISPLAY_INTERFACE := "org.kde.ScreenBrightness.Display"

var _brightness_display := ""
var _brightness_max := 0.0


func build() -> void:
	page_header("Displays", "Configure monitors, brightness, color and night light.")

	var outputs: Array = _kscreen_outputs()
	if outputs.is_empty():
		outputs = _xrandr_outputs()
	var connected: Array = []
	var primary := ""
	for o in outputs:
		if not bool(o["connected"]):
			continue
		connected.append(str(o["name"]))
		if primary.is_empty() and bool(o["enabled"]):
			primary = str(o["name"])
	if primary.is_empty() and not connected.is_empty():
		primary = str(connected[0])

	_init_brightness()

	info_tiles([
		{"value": str(connected.size()), "label": "Connected displays"},
		{"value": _primary_resolution(outputs), "label": "Primary resolution"},
		{"value": primary if not primary.is_empty() else UNAVAILABLE, "label": "Primary output"},
	])

	section("Brightness")
	var c := card()
	slider_row(c, "Screen brightness", "Adjust the primary display backlight.", "B", 10, 100,
		_current_brightness(), func(v: float) -> void:
			debounce("brightness", 0.08, func() -> void: _set_brightness(primary, v)), "%")

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


# --- output discovery -------------------------------------------------------

# Parses `kscreen-doctor -j`. Returns [{name, connected, enabled,
# current_mode_id, modes: [{id, label}], scale, resolution}]. Duplicate mode
# labels are collapsed because panels report the same size/refresh more than
# once (49 modes here for a single 1080p panel).
func _kscreen_outputs() -> Array:
	var raw := Sh.run_capture("kscreen-doctor -j 2>/dev/null")
	if raw.strip_edges().is_empty():
		return []
	var data: Variant = JSON.parse_string(raw)
	if typeof(data) != TYPE_DICTIONARY:
		return []
	var list: Variant = (data as Dictionary).get("outputs", [])
	if typeof(list) != TYPE_ARRAY:
		return []

	var outputs: Array = []
	for item in (list as Array):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var o: Dictionary = item

		var modes: Array = []
		var seen: Dictionary = {}
		var mode_list: Variant = o.get("modes", [])
		if typeof(mode_list) == TYPE_ARRAY:
			for m in (mode_list as Array):
				if typeof(m) != TYPE_DICTIONARY:
					continue
				var md: Dictionary = m
				var label := str(md.get("name", "")).strip_edges()
				if label.is_empty() or seen.has(label):
					continue
				seen[label] = true
				modes.append({"id": str(md.get("id", "")), "label": label})

		var resolution := ""
		var size: Variant = o.get("size", {})
		if typeof(size) == TYPE_DICTIONARY:
			var sd: Dictionary = size
			var w := int(sd.get("width", 0))
			var h := int(sd.get("height", 0))
			if w > 0 and h > 0:
				resolution = "%dx%d" % [w, h]

		outputs.append({
			"name": str(o.get("name", "")),
			"connected": bool(o.get("connected", false)),
			"enabled": bool(o.get("enabled", false)),
			"current_mode_id": str(o.get("currentModeId", "")),
			"modes": modes,
			"scale": float(o.get("scale", 1.0)),
			"resolution": resolution,
		})
	return outputs


# Fallback for a session where kscreen-doctor is missing. xrandr only sees the
# real mode list on X11, so this is a last resort, not the primary source.
func _xrandr_outputs() -> Array:
	var outputs: Array = []
	for line in Sh.run_capture("xrandr --query 2>/dev/null").split("\n"):
		if not line.contains(" connected"):
			continue
		var parts: PackedStringArray = line.split(" ", false)
		if parts.is_empty():
			continue
		var resolution := ""
		for token in parts:
			if token.contains("x") and token.contains("+"):
				resolution = token.split("+")[0]
				break
		outputs.append({
			"name": parts[0],
			"connected": true,
			"enabled": resolution != "",
			"current_mode_id": "",
			"modes": [],
			"scale": 1.0,
			"resolution": resolution,
		})
	return outputs


func _primary_resolution(outputs: Array) -> String:
	for o in outputs:
		if bool(o["enabled"]) and not str(o["resolution"]).is_empty():
			return str(o["resolution"])
	return UNAVAILABLE


# First connected, enabled output that reports modes.
func _active_output() -> Dictionary:
	for o in _kscreen_outputs():
		if bool(o["connected"]) and bool(o["enabled"]) \
				and not (o["modes"] as Array).is_empty():
			return o
	return {}


# --- resolution & scaling ---------------------------------------------------

func _build_resolution_section() -> void:
	section("Resolution & Scaling")
	var c := card()
	if not Sh.has_tool("kscreen-doctor"):
		unavailable_row(c, "Resolution & Scaling", "kscreen-doctor is not installed")
		return
	var out: Dictionary = _active_output()
	if out.is_empty():
		unavailable_row(c, "Resolution & Scaling", "No active output detected")
		return
	var name: String = str(out["name"])
	var modes: Array = out["modes"]
	var current_id: String = str(out["current_mode_id"])

	if modes.is_empty():
		unavailable_row(c, "Resolution", name + " reports no switchable modes")
		return

	var labels: Array = []
	var selected := 0
	for i in modes.size():
		labels.append(str(modes[i]["label"]))
		if str(modes[i]["id"]) == current_id:
			selected = i
	var current_label: String = str(labels[selected]) if not labels.is_empty() else ""

	choice_row(c, "Resolution", "Current: " + current_label + " on " + name + ".", "R",
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


func _set_kscreen_mode(output: String, mode_id: String, label: String) -> void:
	# kscreen-doctor applies modes atomically and KScreen reverts a mode the
	# display cannot drive, but we only ever offer modes the display reported.
	# These are one-shot dropdown picks, not slider spam, so run them to
	# completion and report a failure instead of leaving a toast hanging.
	var code := Sh.run_wait(
			"kscreen-doctor output." + Sh.quote(output) + ".mode." + Sh.quote(mode_id)
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


# --- brightness -------------------------------------------------------------

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
