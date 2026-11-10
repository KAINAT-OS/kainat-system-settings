extends SettingsPanel
# Accessibility: screen reader, magnifier, visual alerts and keyboard helpers.
#
# The toggles write KDE's kaccessrc, which the running KAccess service watches,
# so changes take effect immediately without a terminal or a re-login.

const CONFIG := "kaccessrc"


func build() -> void:
	page_header("Accessibility", "Make the desktop easier to see, hear and operate.")
	_build_vision()
	_build_keyboard()
	_build_more()


func _build_vision() -> void:
	section("Seeing and Hearing")
	var c := card()

	var intro := Label.new()
	intro.text = "These helpers stay out of the way until you turn them on. You can change them again at any time."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", _muted())
	c.add_child(intro)

	if Sh.has_tool("orca"):
		var reader_check: CheckButton = null
		reader_check = toggle_row(c, "Screen Reader",
				"Reads the screen aloud. Starts speaking as soon as it is turned on.",
				"◉", _option("ScreenReader", "Enabled"), func(on: bool) -> void:
					_set_option("ScreenReader", "Enabled", on, reader_check,
							"Screen reader turned on." if on else "Screen reader turned off.")
					if on:
						Sh.launch("orca"))
	else:
		unavailable_row(c, "Screen Reader", "Install the Orca screen reader to use this feature.", "◉")
		action_row(c, "Install Screen Reader", "Adds the Orca screen reader to this computer.",
				"↓", "Install", _install_orca)

	if Sh.has_tool("kmag"):
		action_row(c, "Screen Magnifier",
				"Open a magnified view that follows the pointer.",
				"⊕", "Open", func() -> void: Sh.launch("kmag"))
	else:
		unavailable_row(c, "Screen Magnifier", "The KDE magnifier (kmag) is not installed.", "⊕")

	var colorblind_check: CheckButton = null
	colorblind_check = toggle_row(c, "Color Blindness Correction",
			"Adjusts colors so they are easier to tell apart.",
			"◐", _option("Plugins", "colorblindnesscorrectionEnabled"), func(on: bool) -> void:
				_set_option("Plugins", "colorblindnesscorrectionEnabled", on, colorblind_check,
						"Color correction turned on." if on else "Color correction turned off."))

	var shake_check: CheckButton = null
	shake_check = toggle_row(c, "Shake Cursor to Find It",
			"Shake the mouse and the pointer grows so it is easy to spot.",
			"↯", _option("Plugins", "shakecursorEnabled"), func(on: bool) -> void:
				_set_option("Plugins", "shakecursorEnabled", on, shake_check,
						"Cursor highlighting turned on." if on else "Cursor highlighting turned off."))

	var bell_check: CheckButton = null
	bell_check = toggle_row(c, "Visual Bell",
			"Flash the screen instead of playing a beep.",
			"◍", _option("Bell", "VisibleBell"), func(on: bool) -> void:
				_set_option("Bell", "VisibleBell", on, bell_check,
						"Visual alerts turned on." if on else "Visual alerts turned off."))

	var invert_check: CheckButton = null
	invert_check = toggle_row(c, "Invert Screen Colors",
			"Swap light and dark colors when the visual bell flashes.",
			"◑", _option("Bell", "VisibleBellInvert"), func(on: bool) -> void:
				_set_option("Bell", "VisibleBellInvert", on, invert_check,
						"Visual bell will invert the screen." if on else "Visual bell will not invert the screen."))

	nav_row(c, "Text Size, Contrast and Cursor",
			"Make text larger, switch to high contrast and resize the pointer.",
			"⤢", func() -> void: _open_page("personalization"))


func _build_keyboard() -> void:
	section("Keyboard and Mouse")
	var c := card()

	var sticky_check: CheckButton = null
	sticky_check = toggle_row(c, "Sticky Keys",
			"Press shortcut keys one at a time instead of holding them together.",
			"⌨", _option("Keyboard", "StickyKeys"), func(on: bool) -> void:
				_set_option("Keyboard", "StickyKeys", on, sticky_check,
						"Sticky keys turned on." if on else "Sticky keys turned off."))

	var beep_check: CheckButton = null
	beep_check = toggle_row(c, "Beep on Lock Keys",
			"Play a sound when Caps Lock or Num Lock is pressed.",
			"♫", _option("Keyboard", "ToggleKeysBeep"), func(on: bool) -> void:
				_set_option("Keyboard", "ToggleKeysBeep", on, beep_check,
						"Lock-key beeps turned on." if on else "Lock-key beeps turned off."))

	var mouse_check: CheckButton = null
	mouse_check = toggle_row(c, "Mouse Keys",
			"Move the pointer with the numeric keypad instead of the mouse.",
			"🖱", _option("Mouse", "MouseKeys"), func(on: bool) -> void:
				_set_option("Mouse", "MouseKeys", on, mouse_check,
						"Mouse keys turned on." if on else "Mouse keys turned off."))


func _build_more() -> void:
	section("More Options")
	var c := card()

	kcm_row(c, "All Accessibility Settings",
			"Fine-tune every accessibility option KDE offers.",
			"⚙", "kcm_access")
	info_row(c, "Changes Apply", "Immediately")
	info_row(c, "Settings File", "~/.config/" + CONFIG)


# --- helpers -----------------------------------------------------------------

func _option(group: String, key: String) -> bool:
	return Sh.kde_read(CONFIG, group, key, "false") == "true"


func _set_option(group: String, key: String, on: bool, check: CheckButton,
		message: String) -> void:
	var wanted := "true" if on else "false"
	Sh.kde_write(CONFIG, group, key, wanted, "", "bool")
	if Sh.kde_read(CONFIG, group, key, "false") != wanted:
		check.set_pressed_no_signal(not on)
		notify("Could not change this setting.")
		return
	notify(message)


func _install_orca() -> void:
	run_async(Sh.install_command("orca"), func(code: int, text: String) -> void:
		if code == 0:
			Sh.clear_tool_cache()
			notify("Screen reader installed. Reopen this page to use it.")
		else:
			notify("Could not install the screen reader: " + _tail(text)))


func _open_page(page_name: String) -> void:
	var menu: Node = get_tree().root.find_child("menu-buttons", true, false)
	if menu and menu.has_method("virtual_press_button"):
		menu.virtual_press_button(page_name)


func _tail(text: String) -> String:
	var lines: PackedStringArray = text.strip_edges().split("\n")
	var out: Array[String] = []
	for i in range(maxi(0, lines.size() - 3), lines.size()):
		var line: String = lines[i].strip_edges()
		if not line.is_empty():
			out.append(line)
	return " ".join(out).substr(0, 240)
