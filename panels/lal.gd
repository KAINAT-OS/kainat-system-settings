extends SettingsPanel
# Language & Region: locale, formats, spell checking, input methods and time.

var _tz_popup: PopupPanel = null
var _tz_filter: LineEdit = null
var _tz_list: ItemList = null
var _tz_all: PackedStringArray = PackedStringArray()


func build() -> void:
	page_header("Language & Region", "Language, formats, input methods and the system clock.")

	section("Current Locale")
	var c := card()
	info_row(c, "Language", _env("LANG", UNAVAILABLE))
	info_row(c, "Numeric / Time", _env("LC_ALL", _env("LC_TIME", "Default")))
	info_row(c, "Keyboard Layout", _keyboard_layout())
	info_row(c, "Timezone", _timezone())

	section("Language")
	var c2 := card()
	kcm_row(c2, "Region & Language", "Language, formats and translations.", "L", "kcm_regionandlang")
	kcm_row(c2, "Spell Checking", "Dictionaries and spell options.", "S", "kcmspellchecking")
	kcm_row(c2, "Input Method", "Fcitx / IBus configuration.", "I", "kcm_fcitx5")
	nav_row(c2, "IBus Setup", "Configure IBus input sources.", "B", func() -> void:
		if Sh.has_tool("ibus-setup"):
			Sh.launch("ibus-setup")
		else:
			Sh._notify_missing("ibus-setup", "IBus setup", notify))

	section("Clock")
	var c3 := card()
	nav_row(c3, "Time Zone", _timezone() + " — search and change.", "Z", _open_timezone_picker)
	choice_row(c3, "Clock Format", "Hour format for the desktop clock.", "C",
		["12-Hour", "Use region defaults", "24-Hour"], _clock_format_index(), _set_clock_format)
	action_row(c3, "Set Time Automatically", "Sync the clock over the network.", "A", "Sync", func() -> void:
		if Sh.has_tool("timedatectl"):
			Sh.run("pkexec timedatectl set-ntp true")
			notify("Network time enabled.")
		else:
			Sh._notify_missing("timedatectl", "Automatic time sync", notify))
	kcm_row(c3, "Date & Time", "Time zone and clock format.", "T", "kcm_clock")


func _env(key: String, fallback: String) -> String:
	var value: String = OS.get_environment(key)
	return value if not value.is_empty() else fallback


func _keyboard_layout() -> String:
	if Sh.has_tool("localectl"):
		for line in Sh.run_lines("localectl status 2>/dev/null"):
			if line.contains("X11 Layout") or line.contains("VC Keymap") or line.contains("Layout"):
				return line.split(":", true, 1)[1].strip_edges()
	return UNAVAILABLE


func _timezone() -> String:
	if Sh.has_tool("timedatectl"):
		for line in Sh.run_lines("timedatectl 2>/dev/null"):
			if line.contains("Time zone"):
				return line.split(":", true, 1)[1].strip_edges().split(" ")[0]
	return UNAVAILABLE


# --- timezone picker --------------------------------------------------------

func _open_timezone_picker() -> void:
	if _tz_popup == null or not is_instance_valid(_tz_popup):
		_build_timezone_picker()
		_tz_all = Sh.run_lines("timedatectl list-timezones 2>/dev/null")
	_tz_filter.text = ""
	_apply_tz_filter("")
	_tz_popup.popup_centered(Vector2i(540, 580))
	_tz_filter.grab_focus()


func _build_timezone_picker() -> void:
	_tz_popup = PopupPanel.new()
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_tz_popup.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	_tz_filter = LineEdit.new()
	_tz_filter.placeholder_text = "Filter zones (e.g. dhaka, europe, tokyo)"
	_tz_filter.clear_button_enabled = true
	_tz_filter.text_changed.connect(_apply_tz_filter)
	box.add_child(_tz_filter)

	_tz_list = ItemList.new()
	_tz_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tz_list.custom_minimum_size = Vector2(0, 460)
	_tz_list.item_activated.connect(_on_tz_activated)
	box.add_child(_tz_list)

	var hint := Label.new()
	hint.text = "Double-click a zone to apply. Admin password may be requested."
	hint.add_theme_color_override("font_color", _muted())
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	add_child(_tz_popup)


func _apply_tz_filter(text: String) -> void:
	var needle := text.strip_edges().to_lower()
	_tz_list.clear()
	var current := _timezone()
	var idx := -1
	for tz in _tz_all:
		if needle.is_empty() or tz.to_lower().contains(needle):
			var i := _tz_list.add_item(tz)
			if tz == current:
				idx = i
	if idx >= 0:
		_tz_list.select(idx)
		_tz_list.ensure_current_is_visible()


func _on_tz_activated(index: int) -> void:
	var tz := _tz_list.get_item_text(index)
	Sh.run("pkexec timedatectl set-timezone " + Sh.quote(tz))
	notify("Requesting time zone change to " + tz + "…")
	_tz_popup.hide()


# --- 12/24h clock format (Plasma digital clock applet) -----------------------

func _appletsrc_path() -> String:
	return Sh.home() + "/.config/plasma-org.kde.plasma.desktop-appletsrc"


# Returns [containment, applet] ids of the org.kde.plasma.digitalclock applet.
func _clock_applet_groups() -> Array:
	var header := ""
	for line in Sh.read_lines(_appletsrc_path()):
		if line.begins_with("["):
			header = line
		elif line == "plugin=org.kde.plasma.digitalclock":
			var clean := header.trim_prefix("[").trim_suffix("]")
			var parts := clean.split("][")
			if parts.size() >= 4 and parts[0] == "Containments" and parts[2] == "Applets":
				return [parts[1], parts[3]]
	return []


func _clock_format_index() -> int:
	var g := _clock_applet_groups()
	if g.is_empty():
		return 1
	var out := Sh.run_capture(
		"kreadconfig6 --file " + Sh.quote(_appletsrc_path()) +
		" --group Containments --group " + str(g[0]) +
		" --group Applets --group " + str(g[1]) +
		" --group Configuration --group Appearance --key use24hFormat 2>/dev/null").strip_edges()
	return int(out) if out.is_valid_int() else 1


func _set_clock_format(index: int) -> void:
	var g := _clock_applet_groups()
	if g.is_empty():
		notify("Desktop clock applet not found.")
		return
	# Write first, then restart plasmashell so the applet reloads the file.
	Sh.run(
		"kwriteconfig6 --file " + Sh.quote(_appletsrc_path()) +
		" --group Containments --group " + str(g[0]) +
		" --group Applets --group " + str(g[1]) +
		" --group Configuration --group Appearance --key use24hFormat " + str(index) +
		" && sleep 0.3 && plasmashell --replace >/dev/null 2>&1 &")
	notify("Clock format: " + ["12-hour", "region default", "24-hour"][index])