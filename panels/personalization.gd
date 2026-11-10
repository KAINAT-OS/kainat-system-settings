extends SettingsPanel
# Personalization / Appearance: colors, themes, icons, cursors and wallpaper.
# Uses plasma-apply-* helpers when present so changes apply live.

# Held as a member so the Desktop Count lambda can clamp it: GDScript lambdas
# capture locals by value, so a local assigned after the closure was made would
# read as null inside it.
var _rows_slider: HSlider = null


func build() -> void:
	page_header("Personalization", "Themes, colors, icons, cursors and desktop effects.")

	section("Appearance")
	var c := card()
	_choice_row_dirs(c, "Global Theme", "Complete look and feel presets.", "G",
		_list_dirs(["/usr/share/plasma/look-and-feel", Sh.home() + "/.local/share/plasma/look-and-feel"]),
		_current_kde("KDE", "LookAndFeelPackage"),
		func(name: String) -> void:
			if Sh.has_tool("plasma-apply-lookandfeel"):
				Sh.run("plasma-apply-lookandfeel -a " + Sh.quote(name))
			else:
				Sh.kde_write("kdeglobals", "KDE", "LookAndFeelPackage", name)
			notify("Global theme: " + name))
	kcm_row(c, "Global Theme (advanced)", "Browse and preview theme packages.", "G", "kcm_lookandfeel")

	_choice_row_dirs(c, "Color Scheme", "Window and accent colors.", "C",
		_list_files(["/usr/share/color-schemes", Sh.home() + "/.local/share/color-schemes"], ".colors"),
		Sh.kde_read("kdeglobals", "General", "ColorScheme"),
		func(name: String) -> void:
			if Sh.has_tool("plasma-apply-colorscheme"):
				Sh.run("plasma-apply-colorscheme " + Sh.quote(name))
			else:
				Sh.kde_write("kdeglobals", "General", "ColorScheme", name)
			notify("Color scheme: " + name))

	_choice_row_dirs(c, "Plasma Style", "Widget and panel style.", "P",
		_list_dirs(["/usr/share/plasma/desktoptheme", Sh.home() + "/.local/share/plasma/desktoptheme"]),
		Sh.kde_read("plasmarc", "Theme", "name", "Breeze"),
		func(name: String) -> void:
			if Sh.has_tool("plasma-apply-desktoptheme"):
				Sh.run("plasma-apply-desktoptheme " + Sh.quote(name))
			else:
				Sh.kde_write("plasmarc", "Theme", "name", name)
			notify("Plasma style: " + name))

	_choice_row_dirs(c, "Icons", "Icon theme for apps and the desktop.", "I",
		_list_dirs(["/usr/share/icons", Sh.home() + "/.local/share/icons"], "index.theme"),
		Sh.kde_read("kdeglobals", "Icons", "Theme"),
		func(name: String) -> void:
			Sh.kde_write("kdeglobals", "Icons", "Theme", name)
			Sh.run("kbuildsycoca6 >/dev/null 2>&1 &")
			notify("Icon theme: " + name))

	_choice_row_dirs(c, "Cursor Theme", "Mouse pointer style.", "R",
		_list_dirs(["/usr/share/icons", Sh.home() + "/.local/share/icons"], "cursors"),
		Sh.kde_read("kcminputrc", "Mouse", "cursorTheme"),
		func(name: String) -> void:
			if Sh.has_tool("plasma-apply-cursortheme"):
				Sh.run("plasma-apply-cursortheme " + Sh.quote(name))
			else:
				Sh.kde_write("kcminputrc", "Mouse", "cursorTheme", name)
			notify("Cursor theme: " + name))

	section("Desktop")
	var c2 := card()
	kcm_row(c2, "Wallpaper", "Choose and configure the desktop background.", "W", "kcm_wallpaper")
	kcm_row(c2, "Window Decorations", "Titlebars, borders and buttons.", "D", "kcm_kwindecoration")
	kcm_row(c2, "Fonts", "Interface, fixed-width and toolbar fonts.", "F", "kcm_fonts")
	kcm_row(c2, "Splash Screen", "Boot and login splash theme.", "S", "kcm_splashscreen")
	kcm_row(c2, "Sound Theme", "Notification and event sounds.", "O", "kcm_soundtheme")
	kcm_row(c2, "Night Light", "Warm the screen colors at night.", "N", "kcm_nightlight")

	section("Window Management")
	var c3 := card()

	# KWin ignores kwinrc Number until the session restarts (verified: count
	# stayed 1 after Number=3 + reconfigure), so these talk to the compositor
	# over D-Bus and let it write kwinrc back. kwinrc is the offline fallback.
	var desk_count := Sh.kwin_desktop_count()
	if desk_count < 0:
		desk_count = _kwinrc_int("Number", 1)
	var desk_rows := Sh.kwin_desktop_rows()
	if desk_rows < 0:
		desk_rows = _kwinrc_int("Rows", 1)
	desk_count = clampi(desk_count, 1, Sh.KWIN_MAX_DESKTOPS)
	desk_rows = clampi(desk_rows, 1, desk_count)

	var count_slider := slider_row(c3, "Desktop Count",
			"How many virtual desktops to switch between.", "M",
			1, Sh.KWIN_MAX_DESKTOPS, desk_count, func(v: float) -> void:
				var want := int(round(v))
				if not Sh.kwin_set_desktop_count(want):
					notify("Could not reach KWin to change desktops.")
					return
				if _rows_slider != null:
					# Grid rows can never exceed the desktop count.
					_rows_slider.max_value = want
					if _rows_slider.value > want:
						_rows_slider.value = want
				notify("Virtual desktops: %d" % want))
	count_slider.step = 1

	_rows_slider = slider_row(c3, "Grid Rows",
			"Rows in the desktop grid layout.", "L",
			1, desk_count, desk_rows, func(v: float) -> void:
				var want := int(round(v))
				if Sh.kwin_set_desktop_rows(want):
					notify("Grid rows: %d" % want)
				else:
					notify("Could not reach KWin to change the grid."))
	_rows_slider.step = 1

	kcm_row(c3, "Window Behaviour", "Focus, actions and movement.", "B", "kcm_kwinoptions")
	kcm_row(c3, "Desktop Effects", "Compositor effects and animations.", "E", "kcm_kwin_effects")
	kcm_row(c3, "Virtual Desktops", "Number and layout of desktops.", "V", "kcm_kwin_virtualdesktops")
	kcm_row(c3, "Window Rules", "Per-window behaviour overrides.", "R", "kcm_kwinrules")
	kcm_row(c3, "Window Switching", "Task switcher (Alt+Tab) layout.", "T", "kcm_kwintabbox")
	kcm_row(c3, "KWin Scripts", "Extend the window manager.", "K", "kcm_kwin_scripts")

	# Accessibility / Visual
	section("Accessibility & Visual")
	var c4 := card()

	toggle_row(c4, "High Contrast Mode", "Stronger colors for better visibility.", "H",
		Sh.get_high_contrast(), func(on: bool) -> void:
			_on_high_contrast_toggled(on))

	var scale_names: Array = ["100% (Default)", "125%", "150%", "175%", "200%"]
	choice_row(c4, "UI Scale Factor", "Makes text and controls larger.", "S",
		scale_names, _current_scale_index(), func(index: int) -> void:
			_on_scale_changed(index))

	action_row(c4, "Mouse Cursor Size", "Make the pointer easier to see.", "L", "Configure", func() -> void:
		Sh.open_kcm("kcm_cursortheme")
	)

	action_row(c4, "Screen Reader (Orca)", "Read the interface out loud.", "R", "Start", func() -> void:
		if Sh.has_tool("orca"):
			Sh.run("orca --replace >/dev/null 2>&1 &")
			notify("Starting screen reader...")
		else:
			Sh._notify_missing("orca", "Screen reader", notify)
	)


func _on_high_contrast_toggled(enabled: bool) -> void:
	Sh.set_high_contrast(enabled)
	notify("High Contrast Mode: " + ("Enabled" if enabled else "Disabled"))


# Index of the closest offered scale to what the compositor reports.
func _current_scale_index() -> int:
	var scale := Sh.ui_scale()
	if scale < 0.0:
		var raw := Sh.kde_read("kdeglobals", "KScreen", "ScaleFactor", "1.0").strip_edges()
		scale = float(raw) if raw.is_valid_float() else 1.0
	var options: Array[float] = [1.0, 1.25, 1.5, 1.75, 2.0]
	var best := 0
	var best_delta := INF
	for i in options.size():
		var delta := absf(options[i] - scale)
		if delta < best_delta:
			best_delta = delta
			best = i
	return best


func _on_scale_changed(idx: int) -> void:
	var scales: Array[float] = [1.0, 1.25, 1.5, 1.75, 2.0]
	var scale := scales[idx]
	# Plasma scales fonts together with widgets, so no separate DPI write.
	if Sh.set_ui_scale(scale):
		notify("UI scale set to %d%%." % int(round(scale * 100.0)))
	else:
		notify("Could not change the scale here. Use Display & Monitor settings.")


func _choice_row_dirs(card_box: VBoxContainer, title: String, subtitle: String, glyph: String,
		options: Array, current: String, on_select: Callable) -> void:
	if options.is_empty():
		unavailable_row(card_box, title, "None found")
		return
	var selected: int = options.find(current)
	choice_row(card_box, title, subtitle, glyph, options, selected, func(index: int) -> void:
		on_select.call(str(options[index])))


func _list_files(bases: Array, extension: String) -> Array:
	var names: Array = []
	for base in bases:
		if not DirAccess.dir_exists_absolute(base):
			continue
		var dir: DirAccess = DirAccess.open(base)
		if not dir:
			continue
		dir.list_dir_begin()
		var entry: String = dir.get_next()
		while entry != "":
			if not dir.current_is_dir() and entry.ends_with(extension):
				var name: String = entry.trim_suffix(extension)
				if not names.has(name):
					names.append(name)
			entry = dir.get_next()
	names.sort()
	return names


func _list_dirs(bases: Array, marker: String = "") -> Array:
	var names: Array = []
	for base in bases:
		if not DirAccess.dir_exists_absolute(base):
			continue
		var dir: DirAccess = DirAccess.open(base)
		if not dir:
			continue
		dir.list_dir_begin()
		var entry: String = dir.get_next()
		while entry != "":
			if dir.current_is_dir() and not entry.begins_with("."):
				if marker.is_empty() or FileAccess.file_exists(base.path_join(entry).path_join(marker)):
					if not names.has(entry):
						names.append(entry)
			entry = dir.get_next()
	names.sort()
	return names


func _current_kde(group: String, key: String) -> String:
	return Sh.kde_read("kdeglobals", group, key)


# Numeric kwinrc read used only when the compositor is not on the bus.
func _kwinrc_int(key: String, fallback: int) -> int:
	var raw := Sh.kde_read("kwinrc", "Desktops", key, str(fallback)).strip_edges()
	return int(raw) if raw.is_valid_int() else fallback