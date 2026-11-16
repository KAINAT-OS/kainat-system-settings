extends SettingsPanel
# Language & Region: locale, formats, spell checking, input methods and time.

var _tz_popup: PopupPanel = null
var _tz_filter: LineEdit = null
var _tz_list: ItemList = null
var _tz_all: PackedStringArray = PackedStringArray()
var _tz_row: HBoxContainer = null


func build() -> void:
	page_header("Language & Region", "Language, formats, input methods and the system clock.")

	section("Current Locale")
	var c := card()
	info_row(c, "Language", _locale_label(_env("LANG", UNAVAILABLE)))
	info_row(c, "Numeric / Time", _locale_label(_env("LC_ALL", _env("LC_TIME", "Default"))))
	info_row(c, "Keyboard Layout", _keyboard_layout())
	_tz_row = info_row(c, "Timezone", _timezone())

	section("Language")
	var c2 := card()
	kcm_row(c2, "Region & Language", "Language, formats and translations.", "L", "kcm_regionandlang")
	kcm_row(c2, "Spell Checking", "Dictionaries and spell options.", "S", "kcmspellchecking")
	nav_row(c2, "Input Method", "Configure Fcitx 5 or IBus.", "I", _open_input_method)
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
			if Sh.run_wait("pkexec timedatectl set-ntp true") == 0:
				notify("Network time enabled.")
			else:
				notify("Could not enable network time.")
		else:
			Sh._notify_missing("timedatectl", "Automatic time sync", notify))
	kcm_row(c3, "Date & Time", "Time zone and clock format.", "T", "kcm_clock")


func _open_input_method() -> void:
	if Sh.has_tool("fcitx5-configtool"):
		Sh.launch("fcitx5-configtool")
	elif Sh.has_tool("ibus-setup"):
		Sh.launch("ibus-setup")
	elif Sh.has_tool("fcitx-configtool"):
		Sh.launch("fcitx-configtool")
	else:
		Sh._notify_missing("fcitx5-configtool or ibus-setup", "Input method settings", notify)


func _env(key: String, fallback: String) -> String:
	var value: String = OS.get_environment(key)
	return value if not value.is_empty() else fallback


func _keyboard_layout() -> String:
	if Sh.has_tool("localectl"):
		var keymap := ""
		for line in Sh.run_lines("localectl status 2>/dev/null"):
			if not line.contains(":"):
				continue
			var value := line.split(":", true, 1)[1].strip_edges()
			# "(unset)" is localectl saying the field has no value, not the name
			# of a layout: returning it made the row claim a layout that does
			# not exist.
			if value.is_empty() or value.begins_with("("):
				continue
			# The X11 layout is what the session uses. The virtual console keymap
			# is the fallback for a machine that never sorts a GUI session and
			# is read second because localectl prints it first.
			if line.contains("X11 Layout"):
				return value
			if line.contains("VC Keymap") and keymap.is_empty():
				keymap = value
		if not keymap.is_empty():
			return keymap
	return UNAVAILABLE


# Locale ids ("en_US.UTF-8") are glibc handles; the page names the language and
# region instead. Anything that is not a language_territory id (C, POSIX, a
# value with a modifier) is shown with the charset dropped and nothing else.
const _LANGUAGES := {
	"en": "English", "de": "German", "fr": "French", "es": "Spanish",
	"it": "Italian", "pt": "Portuguese", "ru": "Russian", "ja": "Japanese",
	"zh": "Chinese", "ko": "Korean", "ar": "Arabic", "hi": "Hindi",
	"bn": "Bengali", "tr": "Turkish", "nl": "Dutch", "pl": "Polish",
	"sv": "Swedish", "cs": "Czech", "el": "Greek", "he": "Hebrew",
	"fa": "Persian", "ur": "Urdu", "uk": "Ukrainian", "vi": "Vietnamese",
	"th": "Thai", "id": "Indonesian", "ro": "Romanian", "hu": "Hungarian",
	"fi": "Finnish", "da": "Danish", "no": "Norwegian", "sk": "Slovak",
}

const _REGIONS := {
	"US": "United States", "GB": "United Kingdom", "BD": "Bangladesh",
	"IN": "India", "DE": "Germany", "FR": "France", "ES": "Spain",
	"IT": "Italy", "BR": "Brazil", "PT": "Portugal", "RU": "Russia",
	"JP": "Japan", "CN": "China", "TW": "Taiwan", "KR": "South Korea",
	"CA": "Canada", "AU": "Australia", "NL": "Netherlands", "PL": "Poland",
	"SE": "Sweden", "TR": "Türkiye", "SA": "Saudi Arabia", "PK": "Pakistan",
	"UA": "Ukraine", "MX": "Mexico", "AR": "Argentina", "ZA": "South Africa",
	"CH": "Switzerland", "AT": "Austria", "BE": "Belgium", "DK": "Denmark",
	"NO": "Norway", "FI": "Finland", "IE": "Ireland", "IL": "Israel",
	"AE": "United Arab Emirates", "SG": "Singapore", "MY": "Malaysia",
	"ID": "Indonesia", "TH": "Thailand", "VN": "Vietnam", "PH": "Philippines",
	"NG": "Nigeria", "EG": "Egypt", "KE": "Kenya",
}


func _locale_label(raw: String) -> String:
	var text := raw.strip_edges()
	if text.is_empty():
		return UNAVAILABLE
	if text == "C" or text == "POSIX":
		return text
	var charset: int = text.find(".")
	if charset > 0:
		text = text.substr(0, charset)
	var modifier: int = text.find("@")
	if modifier > 0:
		text = text.substr(0, modifier)
	var parts := text.split("_", false)
	if parts.is_empty():
		return UNAVAILABLE
	var language := str(_LANGUAGES.get(str(parts[0]).to_lower(), ""))
	if language.is_empty():
		# Not a language this build knows: the id itself is the honest answer.
		return text
	if parts.size() < 2 or str(parts[1]).is_empty():
		return language
	var territory := str(parts[1]).to_upper()
	var region := str(_REGIONS.get(territory, ""))
	return language + " (" + (region if not region.is_empty() else territory) + ")"


func _timezone() -> String:
	if Sh.has_tool("timedatectl"):
		for line in Sh.run_lines("timedatectl 2>/dev/null"):
			if line.contains("Time zone") and line.contains(":"):
				var value := line.split(":", true, 1)[1].strip_edges()
				var zone := value.split(" ")[0]
				if not zone.is_empty():
					return zone
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
	_tz_popup.hide()
	notify("Requesting the time zone change…")
	run_async("pkexec timedatectl set-timezone " + Sh.quote(tz), func(code: int) -> void:
		if code != 0:
			notify("Could not change the time zone.")
			return
		if _tz_row != null and is_instance_valid(_tz_row):
			set_info_value(_tz_row, tz)
		notify("Time zone set to " + tz + "."))


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