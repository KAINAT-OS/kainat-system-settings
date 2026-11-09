extends Node
# KDEThemeSync.gd
# Keeps Kainat System Settings visually in sync with the running KDE Plasma
# color scheme and fonts, so the app feels like a native KDE application.
#
# How it works:
#   1. Resolve the active KDE color scheme from kdeglobals (or a fallback).
#   2. Parse the matching .colors file into a role -> Color map.
#   3. Build a complete Godot Theme from those colors + the system font.
#   4. Assign it to the scene-tree root so every control inherits it.
#   5. Watch kdeglobals / the scheme file (and gtk.css as a fallback source)
#      and rebuild the theme when the user changes it in System Settings.
#
# This script is registered as an autoload named "KDETheme".

class_name KDEThemeLoader

const POLL_INTERVAL := 1.5
const DEFAULT_FONT_FAMILY := "Noto Sans"
const DEFAULT_FONT_POINT := 10.0
const MAX_UI_FONT_PX := 22

# KDE .colors section/key -> internal role name
const KDE_COLOR_ROLES: Dictionary = {
	"Colors:Window": {
		"BackgroundNormal": &"background",
		"BackgroundAlternate": &"alternate_base",
		"ForegroundNormal": &"font_color",
		"ForegroundInactive": &"disabled_font_color",
		"ForegroundLink": &"link_color",
	},
	"Colors:View": {
		"BackgroundNormal": &"base_color",
		"BackgroundAlternate": &"alternate_base_color",
		"ForegroundNormal": &"text_color",
		"ForegroundInactive": &"disabled_text_color",
		"ForegroundLink": &"link_color",
	},
	"Colors:Button": {
		"BackgroundNormal": &"button_face",
		"BackgroundAlternate": &"button_alternate",
		"ForegroundNormal": &"button_font_color",
		"ForegroundInactive": &"button_disabled_font_color",
		"DecorationFocus": &"button_focus_color",
		"DecorationHover": &"button_hover_color",
	},
	"Colors:Selection": {
		"BackgroundNormal": &"highlight_color",
		"BackgroundAlternate": &"highlight_alternate",
		"ForegroundNormal": &"highlight_font_color",
	},
	"Colors:Tooltip": {
		"BackgroundNormal": &"tooltip_color",
		"ForegroundNormal": &"tooltip_font_color",
	},
	"Colors:Header": {
		"BackgroundNormal": &"header_background",
		"ForegroundNormal": &"header_font_color",
	},
	"Colors:Complementary": {
		"BackgroundNormal": &"complementary_background",
		"ForegroundNormal": &"complementary_font_color",
	},
}

# Breeze-Dark-ish defaults. Also used when KDE cannot be detected at all.
var fallback_colors: Dictionary = {
	&"background": Color(0.125, 0.149, 0.168),
	&"alternate_base": Color(0.129, 0.145, 0.161),
	&"base_color": Color(0.078, 0.086, 0.098),
	&"alternate_base_color": Color(0.11, 0.122, 0.137),
	&"font_color": Color(0.729, 0.769, 0.821),
	&"text_color": Color(0.729, 0.769, 0.821),
	&"disabled_font_color": Color(0.5, 0.53, 0.56),
	&"disabled_text_color": Color(0.5, 0.53, 0.56),
	&"link_color": Color(0.11, 0.6, 0.95),
	&"button_face": Color(0.161, 0.173, 0.188),
	&"button_alternate": Color(0.117, 0.341, 0.456),
	&"button_font_color": Color(0.988, 0.988, 0.988),
	&"button_disabled_font_color": Color(0.5, 0.53, 0.56),
	&"button_hover_color": Color(0.239, 0.682, 0.914),
	&"button_focus_color": Color(0.239, 0.682, 0.914),
	&"highlight_color": Color(0.239, 0.682, 0.914),
	&"highlight_alternate": Color(0.117, 0.341, 0.456),
	&"highlight_font_color": Color(1, 1, 1),
	&"tooltip_color": Color(0.161, 0.173, 0.188),
	&"tooltip_font_color": Color(0.988, 0.988, 0.988),
	&"header_background": Color(0.125, 0.149, 0.168),
	&"header_font_color": Color(0.988, 0.988, 0.988),
	&"complementary_background": Color(0.125, 0.137, 0.149),
	&"complementary_font_color": Color(0.988, 0.988, 0.988),
}

var kde_colors: Dictionary = {}

# Runtime state
var _source: String = "fallback"   # "kde" | "gtk" | "fallback"
var _scheme_name: String = ""
var _watched_files: Array[String] = []
var _mtimes: Dictionary = {}
var _accum: float = 0.0
var _font_family: String = ""
var _font_px: int = 0
var _is_dark: bool = true


func _ready() -> void:
	print("[KDETheme] KDEThemeSync starting (autoload)")
	_reload(true)
	set_process(true)


func _process(delta: float) -> void:
	_accum += delta
	if _accum < POLL_INTERVAL:
		return
	_accum = 0.0
	if _settings_changed():
		print("[KDETheme] KDE settings changed, re-applying theme")
		_reload(false)


func force_reload() -> void:
	_reload(true)


func reload_theme() -> void:
	_reload(true)


# ---------------------------------------------------------------------------
# Source detection & watching
# ---------------------------------------------------------------------------

func _settings_changed() -> bool:
	for path in _watched_files:
		var current: int = _file_mtime(path)
		if int(_mtimes.get(path, -1)) != current:
			return true
	return false


func _file_mtime(path: String) -> int:
	if path.is_empty() or not FileAccess.file_exists(path):
		return -1
	# ConfigFile exposes a mtime helper; fall back to stat via bash.
	var st_mtime: int = _stat_mtime(path)
	if st_mtime != -1:
		return st_mtime
	return -2


func _stat_mtime(path: String) -> int:
	var out: Array = []
	var escaped: String = path.replace("'", "'\\''")
	OS.execute("bash", ["-c", "stat -c %Y '" + escaped + "' 2>/dev/null"], out)
	if out.is_empty():
		return -1
	return out[0].strip_edges().to_int()


func _detect_source() -> void:
	_scheme_name = _get_kde_scheme_name()
	if not _scheme_name.is_empty():
		_source = "kde"
		return

	# Fallback: infer from the GTK theme (if present), mapped to a Breeze scheme.
	var hint: String = _detect_gtk_hint()
	if hint == "dark" and not get_color_scheme_path("BreezeDark").is_empty():
		_scheme_name = "BreezeDark"
		_source = "kde"
		return
	if hint == "light" and not get_color_scheme_path("BreezeLight").is_empty():
		_scheme_name = "BreezeLight"
		_source = "kde"
		return
	if not get_color_scheme_path("Breeze").is_empty():
		_scheme_name = "Breeze"
		_source = "kde"
		return

	_source = "fallback"
	_scheme_name = ""


func _get_kde_scheme_name() -> String:
	var config_path: String = get_kde_config_path()
	if not FileAccess.file_exists(config_path):
		return ""
	# ConfigFile.load() chokes on some KDE-generated values, so parse manually.
	var value: String = _parse_ini_value(config_path, "General", "ColorScheme")
	if value.is_empty():
		value = _find_available_color_scheme()
	return value


func _detect_gtk_hint() -> String:
	var home: String = _home()
	var candidates: Array[String] = [
		home.path_join(".config/gtk-4.0/gtk.css"),
		home.path_join(".config/gtk-3.0/gtk.css"),
	]
	for path in candidates:
		if not FileAccess.file_exists(path):
			continue
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if not file:
			continue
		var content: String = file.get_as_text().to_lower()
		file.close()
		if content.find("-dark") != -1 or content.find("gtk-dark") != -1:
			return "dark"
		if content.find("-light") != -1:
			return "light"
	return ""


func _refresh_watched_files() -> void:
	_watched_files.clear()
	var gtk4: String = _home().path_join(".config/gtk-4.0/gtk.css")
	var gtk4colors: String = _home().path_join(".config/gtk-4.0/colors.css")
	if _source == "kde":
		_watched_files.append(get_kde_config_path())
		var scheme_path: String = get_color_scheme_path(_scheme_name)
		if not scheme_path.is_empty():
			_watched_files.append(scheme_path)
	# Always watch GTK sources so light/dark switches are noticed too.
	_watched_files.append(gtk4)
	_watched_files.append(gtk4colors)

	_mtimes.clear()
	for path in _watched_files:
		_mtimes[path] = _file_mtime(path)


# ---------------------------------------------------------------------------
# Loading KDE colors
# ---------------------------------------------------------------------------

func _reload(force: bool) -> void:
	if force:
		_detect_source()
		_refresh_watched_files()
	else:
		var previous_source: String = _source
		var previous_scheme: String = _scheme_name
		_detect_source()
		if _source != previous_source or _scheme_name != previous_scheme:
			_refresh_watched_files()
		else:
			# Same source, just refresh cached mtimes.
			for path in _watched_files:
				_mtimes[path] = _file_mtime(path)

	kde_colors = {}

	if _source == "kde" and not _scheme_name.is_empty():
		var scheme_path: String = get_color_scheme_path(_scheme_name)
		if not scheme_path.is_empty() and FileAccess.file_exists(scheme_path):
			_parse_color_scheme_file(scheme_path)
		else:
			print("[KDETheme] Scheme file missing for '%s', using fallback" % _scheme_name)

	if kde_colors.is_empty():
		print("[KDETheme] No KDE colors found, using built-in fallback palette")
		_source = "fallback"

	_apply_defaults()
	_read_font()
	_build_and_apply_theme()


func _parse_color_scheme_file(file_path: String) -> void:
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("[KDETheme] Cannot open scheme file: " + file_path)
		return

	var current_section: String = ""
	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#") or line.begins_with(";"):
			continue

		if line.begins_with("[") and line.ends_with("]"):
			var inner: String = line.substr(1, line.length() - 2)
			# Skip subsection variants like [Colors:Header][Inactive].
			current_section = "" if inner.find("][") != -1 else inner
			continue

		if current_section.is_empty():
			continue

		var eq_pos: int = line.find("=")
		if eq_pos == -1:
			continue
		var key: String = line.substr(0, eq_pos).strip_edges()
		var value: String = line.substr(eq_pos + 1).strip_edges()

		if not KDE_COLOR_ROLES.has(current_section):
			continue
		var role_mapping: Dictionary = KDE_COLOR_ROLES[current_section]
		if not role_mapping.has(key):
			continue
		var role: StringName = role_mapping[key]
		var color: Color = parse_kde_color(value)
		if color != Color.TRANSPARENT:
			kde_colors[role] = color

	file.close()
	print("[KDETheme] Parsed %d roles from %s" % [kde_colors.size(), file_path.get_file()])


func _apply_defaults() -> void:
	for role: StringName in fallback_colors:
		if not kde_colors.has(role):
			kde_colors[role] = fallback_colors[role]

	# Derived roles that KDE does not provide directly.
	var background: Color = kde_colors[&"background"]
	var base: Color = kde_colors[&"base_color"]
	var button: Color = kde_colors[&"button_face"]
	var accent: Color = kde_colors[&"highlight_color"]

	_is_dark = background.get_luminance() < 0.5

	kde_colors[&"line_edit_color"] = base
	if not kde_colors.has(&"disabled_font_color"):
		kde_colors[&"disabled_font_color"] = kde_colors[&"font_color"].lerp(background, 0.55)
	if not kde_colors.has(&"disabled_text_color"):
		kde_colors[&"disabled_text_color"] = kde_colors[&"text_color"].lerp(base, 0.55)
	if not kde_colors.has(&"button_disabled_font_color"):
		kde_colors[&"button_disabled_font_color"] = kde_colors[&"button_font_color"].lerp(button, 0.6)
	if not kde_colors.has(&"button_hover_color"):
		kde_colors[&"button_hover_color"] = _shade(button, 0.12)
	if not kde_colors.has(&"button_focus_color"):
		kde_colors[&"button_focus_color"] = accent

	# Surfaces
	kde_colors[&"accent"] = accent
	kde_colors[&"panel_border"] = _shade(base, 0.18)
	kde_colors[&"surface_raised"] = _shade(background, 0.07)
	kde_colors[&"button_hover_bg"] = button.lerp(accent, 0.22)
	kde_colors[&"line_edit_border"] = _shade(base, 0.22)
	kde_colors[&"disabled_bg"] = button.lerp(background, 0.55)


func _shade(color: Color, amount: float) -> Color:
	if _is_dark:
		return color.lightened(amount)
	return color.darkened(amount)


# ---------------------------------------------------------------------------
# Fonts
# ---------------------------------------------------------------------------

func _read_font() -> void:
	_font_family = ""
	_font_px = 0

	var raw: String = _parse_ini_value(get_kde_config_path(), "General", "font")
	if raw.is_empty():
		raw = _parse_ini_value("/etc/xdg/kdeglobals", "General", "font")

	if not raw.is_empty():
		var parts: PackedStringArray = raw.split(",")
		_font_family = parts[0].strip_edges()
		if parts.size() > 1:
			var point: float = float(parts[1])
			if point > 0.0:
				_font_px = int(round(clampf(point * 1.4, 12.0, float(MAX_UI_FONT_PX))))

	if _font_family.is_empty():
		_font_family = DEFAULT_FONT_FAMILY
	if _font_px <= 0:
		_font_px = int(round(clampf(DEFAULT_FONT_POINT * 1.4, 12.0, float(MAX_UI_FONT_PX))))


func _make_system_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray([_font_family, DEFAULT_FONT_FAMILY, "sans-serif"])
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return font


# ---------------------------------------------------------------------------
# Theme construction
# ---------------------------------------------------------------------------

func _build_and_apply_theme() -> void:
	var theme := Theme.new()

	theme.default_font = _make_system_font()
	theme.default_font_size = _font_px

	_setup_panels(theme)
	_setup_labels(theme)
	_setup_buttons(theme)
	_setup_sidebar(theme)
	_setup_line_edits(theme)
	_setup_spinbox(theme)
	_setup_item_views(theme)
	_setup_tabs(theme)
	_setup_scrollbars(theme)
	_setup_sliders(theme)
	_setup_progress(theme)
	_setup_checks(theme)
	_setup_popups(theme)
	_setup_tooltips(theme)
	_setup_misc(theme)

	_apply_theme(theme)


func _apply_theme(theme: Theme) -> void:
	var tree: SceneTree = get_tree()
	if not tree or not is_instance_valid(tree.root):
		return
	tree.root.theme = theme
	print("[KDETheme] Applied theme (source=%s, scheme=%s, font=%s %dpx, dark=%s)" % [
		_source, _scheme_name, _font_family, _font_px, str(_is_dark)
	])


# -- helpers ----------------------------------------------------------------

func _flat(bg: Color, radius: float = 3.0, border_w: float = 0.0,
		border: Color = Color.TRANSPARENT, margin_h: float = 8.0,
		margin_v: float = 5.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(radius))
	if border_w > 0.0:
		sb.set_border_width_all(int(border_w))
		sb.border_color = border
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	return sb


func _line(color: Color, thickness: int = 1) -> StyleBoxLine:
	var sb := StyleBoxLine.new()
	sb.color = color
	sb.thickness = thickness
	return sb


func _c(key: StringName) -> Color:
	return kde_colors.get(key, Color.MAGENTA)


func _make_circle_texture(diameter: int, color: Color) -> ImageTexture:
	var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var radius: float = diameter / 2.0
	var center := Vector2(radius, radius)
	for y in diameter:
		for x in diameter:
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(center)
			if d <= radius - 1.0:
				img.set_pixel(x, y, color)
			elif d < radius:
				var a: float = clampf(radius - d, 0.0, 1.0)
				img.set_pixel(x, y, Color(color.r, color.g, color.b, color.a * a))
	return ImageTexture.create_from_image(img)


# -- individual control setups ---------------------------------------------

func _setup_panels(theme: Theme) -> void:
	var bg: Color = _c(&"background")
	var border: Color = _c(&"panel_border")

	theme.set_stylebox("panel", "Panel", _flat(bg, 0.0))
	theme.set_stylebox("panel", "PanelContainer", _flat(bg.lerp(_c(&"base_color"), 0.35), 4.0, 1.0, border, 10.0, 10.0))
	theme.set_stylebox("panel", "PopupPanel", _flat(_c(&"surface_raised"), 4.0, 1.0, border, 8.0, 6.0))
	theme.set_stylebox("panel", "ColorRect", StyleBoxEmpty.new())

	# Window / dialogs
	theme.set_stylebox("embedded_border", "Window", _flat(bg, 4.0, 1.0, border, 0.0, 0.0))
	theme.set_stylebox("embedded_unfocused_border", "Window", _flat(bg, 4.0, 1.0, border, 0.0, 0.0))
	theme.set_stylebox("panel", "AcceptDialog", _flat(bg, 4.0, 1.0, border, 10.0, 10.0))

	# Separators
	theme.set_stylebox("separator", "HSeparator", _line(border))
	theme.set_stylebox("separator", "VSeparator", _line(border))


func _setup_labels(theme: Theme) -> void:
	theme.set_color("font_color", "Label", _c(&"font_color"))
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	theme.set_color("font_disabled_color", "Label", _c(&"disabled_font_color"))

	theme.set_color("default_color", "RichTextLabel", _c(&"text_color"))
	theme.set_color("font_selected_color", "RichTextLabel", _c(&"highlight_font_color"))
	theme.set_color("selection_color", "RichTextLabel", _c(&"highlight_color"))
	theme.set_color("font_shadow_color", "RichTextLabel", Color(0, 0, 0, 0))
	theme.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	theme.set_stylebox("focus", "RichTextLabel", StyleBoxEmpty.new())

	theme.set_color("font_color", "LinkButton", _c(&"link_color"))
	theme.set_color("font_hover_color", "LinkButton", _c(&"accent"))


func _setup_buttons(theme: Theme) -> void:
	var face: Color = _c(&"button_face")
	var face_fg: Color = _c(&"button_font_color")
	var accent: Color = _c(&"accent")
	var focus: Color = _c(&"button_focus_color")
	var normal_border: Color = _c(&"panel_border")

	for cls in ["Button", "OptionButton", "MenuButton"]:
		theme.set_stylebox("normal", cls, _flat(face, 3.0, 1.0, normal_border, 10.0, 6.0))
		theme.set_stylebox("hover", cls, _flat(_c(&"button_hover_bg"), 3.0, 1.0, accent, 10.0, 6.0))
		theme.set_stylebox("pressed", cls, _flat(_c(&"highlight_color"), 3.0, 1.0, accent, 10.0, 6.0))
		theme.set_stylebox("focus", cls, _flat(face, 3.0, 2.0, focus, 10.0, 6.0))
		theme.set_stylebox("disabled", cls, _flat(_c(&"disabled_bg"), 3.0, 1.0, normal_border, 10.0, 6.0))

		theme.set_color("font_color", cls, face_fg)
		theme.set_color("font_hover_color", cls, _c(&"button_font_color"))
		theme.set_color("font_pressed_color", cls, _c(&"highlight_font_color"))
		theme.set_color("font_hover_pressed_color", cls, _c(&"highlight_font_color"))
		theme.set_color("font_focus_color", cls, face_fg)
		theme.set_color("font_disabled_color", cls, _c(&"button_disabled_font_color"))
		theme.set_color("icon_normal_color", cls, face_fg)
		theme.set_color("icon_hover_color", cls, face_fg)
		theme.set_color("icon_pressed_color", cls, _c(&"highlight_font_color"))
		theme.set_color("icon_hover_pressed_color", cls, _c(&"highlight_font_color"))
		theme.set_color("icon_focus_color", cls, face_fg)
		theme.set_color("icon_disabled_color", cls, _c(&"button_disabled_font_color"))
		theme.set_constant("h_separation", cls, 6)


func _setup_sidebar(theme: Theme) -> void:
	# "SidebarButton": flat navigation rows used by the settings sidebar.
	theme.set_type_variation("SidebarButton", "Button")
	var text: Color = _c(&"font_color")
	var accent: Color = _c(&"accent")

	var normal := StyleBoxFlat.new()
	normal.draw_center = false
	normal.content_margin_left = 12
	normal.content_margin_right = 10
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8

	var hover := StyleBoxFlat.new()
	hover.bg_color = _with_alpha_c(text, 0.10)
	hover.set_corner_radius_all(6)
	hover.content_margin_left = 12
	hover.content_margin_right = 10
	hover.content_margin_top = 8
	hover.content_margin_bottom = 8

	var selected := StyleBoxFlat.new()
	selected.bg_color = _with_alpha_c(accent, 0.18)
	selected.border_width_left = 3
	selected.border_color = accent
	selected.set_corner_radius_all(6)
	selected.content_margin_left = 12
	selected.content_margin_right = 10
	selected.content_margin_top = 8
	selected.content_margin_bottom = 8

	theme.set_stylebox("normal", "SidebarButton", normal)
	theme.set_stylebox("hover", "SidebarButton", hover)
	theme.set_stylebox("pressed", "SidebarButton", selected)
	theme.set_stylebox("hover_pressed", "SidebarButton", selected)
	theme.set_stylebox("focus", "SidebarButton", hover)
	theme.set_stylebox("disabled", "SidebarButton", StyleBoxEmpty.new())
	theme.set_color("font_color", "SidebarButton", text)
	theme.set_color("font_hover_color", "SidebarButton", text)
	theme.set_color("font_pressed_color", "SidebarButton", text)
	theme.set_color("font_hover_pressed_color", "SidebarButton", text)
	theme.set_color("font_focus_color", "SidebarButton", text)


func _with_alpha_c(color: Color, alpha: float) -> Color:
	var c: Color = color
	c.a = alpha
	return c


func _setup_checks(theme: Theme) -> void:
	for cls in ["CheckBox", "CheckButton"]:
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			theme.set_stylebox(state, cls, StyleBoxEmpty.new())
		theme.set_color("font_color", cls, _c(&"font_color"))
		theme.set_color("font_hover_color", cls, _c(&"font_color"))
		theme.set_color("font_pressed_color", cls, _c(&"font_color"))
		theme.set_color("font_hover_pressed_color", cls, _c(&"font_color"))
		theme.set_color("font_focus_color", cls, _c(&"font_color"))
		theme.set_color("font_disabled_color", cls, _c(&"disabled_font_color"))
		theme.set_constant("h_separation", cls, 6)

	theme.set_color("checkbox_checked_color", "CheckBox", _c(&"accent"))
	theme.set_color("checkbox_unchecked_color", "CheckBox", _c(&"disabled_text_color"))
	theme.set_color("button_checked_color", "CheckButton", _c(&"accent"))
	theme.set_color("button_unchecked_color", "CheckButton", _c(&"disabled_text_color"))


func _setup_spinbox(theme: Theme) -> void:
	# The text field itself is a LineEdit child and is themed by _setup_line_edits.
	# Style the up/down arrow buttons so they match KDE spin boxes.
	var face: Color = _c(&"button_face")
	for state in ["", "_hovered", "_pressed", "_disabled"]:
		var bg: Color = face
		if state == "_hovered":
			bg = _c(&"button_hover_bg")
		elif state == "_pressed":
			bg = _c(&"highlight_color")
		elif state == "_disabled":
			bg = _c(&"disabled_bg")
		theme.set_stylebox("up_background" + state, "SpinBox", _flat(bg, 2.0, 0.0, Color.TRANSPARENT, 2.0, 2.0))
		theme.set_stylebox("down_background" + state, "SpinBox", _flat(bg, 2.0, 0.0, Color.TRANSPARENT, 2.0, 2.0))
	var icon: Color = _c(&"button_font_color")
	theme.set_color("up_icon_modulate", "SpinBox", icon)
	theme.set_color("down_icon_modulate", "SpinBox", icon)
	theme.set_color("up_hover_icon_modulate", "SpinBox", icon)
	theme.set_color("down_hover_icon_modulate", "SpinBox", icon)
	theme.set_color("up_pressed_icon_modulate", "SpinBox", _c(&"highlight_font_color"))
	theme.set_color("down_pressed_icon_modulate", "SpinBox", _c(&"highlight_font_color"))


func _setup_line_edits(theme: Theme) -> void:
	var bg: Color = _c(&"line_edit_color")
	var border: Color = _c(&"line_edit_border")
	var accent: Color = _c(&"accent")

	for cls in ["LineEdit", "TextEdit", "CodeEdit"]:
		theme.set_stylebox("normal", cls, _flat(bg, 3.0, 1.0, border, 8.0, 5.0))
		theme.set_stylebox("focus", cls, _flat(bg, 3.0, 2.0, accent, 8.0, 5.0))
		theme.set_stylebox("read_only", cls, _flat(bg, 3.0, 1.0, border, 8.0, 5.0))
		theme.set_color("font_color", cls, _c(&"text_color"))
		theme.set_color("font_selected_color", cls, _c(&"highlight_font_color"))
		theme.set_color("font_placeholder_color", cls, _c(&"disabled_text_color"))
		theme.set_color("font_readonly_color", cls, _c(&"disabled_text_color"))
		theme.set_color("caret_color", cls, _c(&"text_color"))
		theme.set_color("selection_color", cls, _c(&"highlight_color"))


func _setup_item_views(theme: Theme) -> void:
	var base: Color = _c(&"base_color")
	var border: Color = _c(&"panel_border")
	var accent: Color = _c(&"accent")

	# ItemList (package lists, etc.)
	theme.set_stylebox("panel", "ItemList", _flat(base, 3.0, 1.0, border, 4.0, 4.0))
	theme.set_stylebox("focus", "ItemList", _flat(base, 3.0, 1.0, accent, 4.0, 4.0))
	theme.set_stylebox("selected", "ItemList", _flat(_c(&"highlight_color"), 2.0, 0.0, Color.TRANSPARENT, 4.0, 3.0))
	theme.set_stylebox("selected_focus", "ItemList", _flat(_c(&"highlight_color"), 2.0, 0.0, Color.TRANSPARENT, 4.0, 3.0))
	theme.set_stylebox("hovered", "ItemList", _flat(_c(&"button_hover_bg"), 2.0, 0.0, Color.TRANSPARENT, 4.0, 3.0))
	theme.set_stylebox("cursor", "ItemList", _flat(Color.TRANSPARENT, 0.0, 1.0, accent, 0.0, 0.0))
	theme.set_stylebox("cursor_unfocused", "ItemList", _flat(Color.TRANSPARENT, 0.0, 1.0, border, 0.0, 0.0))
	theme.set_color("font_color", "ItemList", _c(&"text_color"))
	theme.set_color("font_selected_color", "ItemList", _c(&"highlight_font_color"))
	theme.set_color("font_hovered_color", "ItemList", _c(&"text_color"))
	theme.set_color("font_disabled_color", "ItemList", _c(&"disabled_text_color"))
	theme.set_constant("v_separation", "ItemList", 2)

	# Tree
	theme.set_stylebox("panel", "Tree", _flat(base, 3.0, 1.0, border, 4.0, 4.0))
	theme.set_stylebox("focus", "Tree", _flat(base, 3.0, 1.0, accent, 4.0, 4.0))
	theme.set_stylebox("selected", "Tree", _flat(_c(&"highlight_color"), 2.0, 0.0, Color.TRANSPARENT, 4.0, 3.0))
	theme.set_stylebox("selected_focus", "Tree", _flat(_c(&"highlight_color"), 2.0, 0.0, Color.TRANSPARENT, 4.0, 3.0))
	theme.set_stylebox("cursor", "Tree", _flat(Color.TRANSPARENT, 0.0, 1.0, accent, 0.0, 0.0))
	theme.set_stylebox("cursor_unfocused", "Tree", _flat(Color.TRANSPARENT, 0.0, 1.0, border, 0.0, 0.0))
	theme.set_stylebox("title_button_normal", "Tree", _flat(_c(&"header_background"), 0.0, 0.0, Color.TRANSPARENT, 6.0, 4.0))
	theme.set_stylebox("title_button_hover", "Tree", _flat(_c(&"button_hover_bg"), 0.0, 0.0, Color.TRANSPARENT, 6.0, 4.0))
	theme.set_stylebox("title_button_pressed", "Tree", _flat(_c(&"highlight_color"), 0.0, 0.0, Color.TRANSPARENT, 6.0, 4.0))
	theme.set_color("font_color", "Tree", _c(&"text_color"))
	theme.set_color("font_selected_color", "Tree", _c(&"highlight_font_color"))
	theme.set_color("font_disabled_color", "Tree", _c(&"disabled_text_color"))
	theme.set_color("title_button_color", "Tree", _c(&"header_font_color"))
	theme.set_color("drop_position_color", "Tree", accent)
	theme.set_color("relationship_line_color", "Tree", _c(&"disabled_text_color"))
	theme.set_color("guide_color", "Tree", _c(&"panel_border"))
	theme.set_constant("v_separation", "Tree", 4)
	theme.set_constant("h_separation", "Tree", 4)


func _setup_tabs(theme: Theme) -> void:
	var selected_bg: Color = _c(&"base_color")
	var unselected_bg: Color = _c(&"header_background")
	var hover_bg: Color = _c(&"button_hover_bg")

	theme.set_stylebox("tab_selected", "TabContainer", _flat(selected_bg, 3.0, 0.0, Color.TRANSPARENT, 10.0, 6.0))
	theme.set_stylebox("tab_unselected", "TabContainer", _flat(unselected_bg, 3.0, 0.0, Color.TRANSPARENT, 10.0, 6.0))
	theme.set_stylebox("tab_hovered", "TabContainer", _flat(hover_bg, 3.0, 0.0, Color.TRANSPARENT, 10.0, 6.0))
	theme.set_stylebox("tab_disabled", "TabContainer", _flat(unselected_bg, 3.0, 0.0, Color.TRANSPARENT, 10.0, 6.0))
	theme.set_stylebox("panel", "TabContainer", _flat(selected_bg, 3.0, 1.0, _c(&"panel_border"), 4.0, 4.0))
	theme.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())
	theme.set_color("font_selected_color", "TabContainer", _c(&"font_color"))
	theme.set_color("font_unselected_color", "TabContainer", _c(&"disabled_font_color"))
	theme.set_color("font_hovered_color", "TabContainer", _c(&"font_color"))
	theme.set_color("font_disabled_color", "TabContainer", _c(&"disabled_font_color"))

	for cls in ["TabBar"]:
		theme.set_stylebox("tab_selected", cls, _flat(selected_bg, 3.0, 0.0, Color.TRANSPARENT, 10.0, 6.0))
		theme.set_stylebox("tab_unselected", cls, _flat(unselected_bg, 3.0, 0.0, Color.TRANSPARENT, 10.0, 6.0))
		theme.set_stylebox("tab_hovered", cls, _flat(hover_bg, 3.0, 0.0, Color.TRANSPARENT, 10.0, 6.0))
		theme.set_color("font_selected_color", cls, _c(&"font_color"))
		theme.set_color("font_unselected_color", cls, _c(&"disabled_font_color"))
		theme.set_color("font_hovered_color", cls, _c(&"font_color"))


func _setup_scrollbars(theme: Theme) -> void:
	var track: Color = _c(&"base_color").lerp(_c(&"background"), 0.5)
	var grabber: Color = _c(&"disabled_text_color").lerp(_c(&"base_color"), 0.35)
	var grabber_hi: Color = _c(&"accent")

	for cls in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", cls, _flat(track, 4.0, 0.0, Color.TRANSPARENT, 0.0, 0.0))
		theme.set_stylebox("scroll_focus", cls, _flat(track, 4.0, 0.0, Color.TRANSPARENT, 0.0, 0.0))
		theme.set_stylebox("grabber", cls, _flat(grabber, 4.0, 0.0, Color.TRANSPARENT, 0.0, 0.0))
		theme.set_stylebox("grabber_highlight", cls, _flat(grabber_hi, 4.0, 0.0, Color.TRANSPARENT, 0.0, 0.0))
		theme.set_stylebox("grabber_pressed", cls, _flat(_c(&"accent").lightened(0.1), 4.0, 0.0, Color.TRANSPARENT, 0.0, 0.0))


func _setup_sliders(theme: Theme) -> void:
	var track: Color = _c(&"line_edit_color")
	var filled: Color = _c(&"accent")
	var radius: float = 4.0

	var grabber_tex: ImageTexture = _make_circle_texture(16, _c(&"accent"))
	var grabber_hi_tex: ImageTexture = _make_circle_texture(16, _c(&"accent").lightened(0.15))
	var grabber_dis_tex: ImageTexture = _make_circle_texture(16, _c(&"disabled_text_color"))

	for cls in ["HSlider", "VSlider"]:
		theme.set_stylebox("slider", cls, _flat(track, radius, 0.0, Color.TRANSPARENT, 0.0, 0.0))
		theme.set_stylebox("grabber_area", cls, _flat(filled, radius, 0.0, Color.TRANSPARENT, 0.0, 0.0))
		theme.set_stylebox("grabber_area_highlight", cls, _flat(filled.lightened(0.1), radius, 0.0, Color.TRANSPARENT, 0.0, 0.0))
		theme.set_icon("grabber", cls, grabber_tex)
		theme.set_icon("grabber_highlight", cls, grabber_hi_tex)
		theme.set_icon("grabber_disabled", cls, grabber_dis_tex)


func _setup_progress(theme: Theme) -> void:
	theme.set_stylebox("background", "ProgressBar", _flat(_c(&"line_edit_color"), 3.0, 1.0, _c(&"panel_border"), 4.0, 4.0))
	theme.set_stylebox("fill", "ProgressBar", _flat(_c(&"accent"), 3.0, 0.0, Color.TRANSPARENT, 4.0, 4.0))
	theme.set_color("font_color", "ProgressBar", _c(&"highlight_font_color"))


func _setup_popups(theme: Theme) -> void:
	theme.set_stylebox("panel", "PopupMenu", _flat(_c(&"surface_raised"), 4.0, 1.0, _c(&"panel_border"), 6.0, 6.0))
	theme.set_stylebox("hover", "PopupMenu", _flat(_c(&"highlight_color"), 3.0, 0.0, Color.TRANSPARENT, 4.0, 3.0))
	theme.set_color("font_color", "PopupMenu", _c(&"text_color"))
	theme.set_color("font_hover_color", "PopupMenu", _c(&"highlight_font_color"))
	theme.set_color("font_disabled_color", "PopupMenu", _c(&"disabled_text_color"))
	theme.set_color("font_separator_color", "PopupMenu", _c(&"disabled_text_color"))
	theme.set_color("font_accelerator_color", "PopupMenu", _c(&"disabled_text_color"))
	theme.set_constant("v_separation", "PopupMenu", 4)


func _setup_tooltips(theme: Theme) -> void:
	theme.set_stylebox("panel", "TooltipPanel", _flat(_c(&"tooltip_color"), 3.0, 1.0, _c(&"panel_border"), 8.0, 5.0))
	theme.set_color("font_color", "TooltipLabel", _c(&"tooltip_font_color"))
	theme.set_color("font_shadow_color", "TooltipLabel", Color(0, 0, 0, 0))


func _setup_misc(theme: Theme) -> void:
	# Split containers use a plain grabber.
	theme.set_stylebox("separator", "SplitContainer", StyleBoxEmpty.new())


# ---------------------------------------------------------------------------
# Path resolution / low-level parsing
# ---------------------------------------------------------------------------

func _home() -> String:
	var home: String = OS.get_environment("HOME")
	if home.is_empty():
		home = OS.get_user_data_dir()
	return home


func get_kde_config_path() -> String:
	var xdg_config: String = OS.get_environment("XDG_CONFIG_HOME")
	if not xdg_config.is_empty():
		var cfg_path: String = xdg_config.path_join("kdeglobals")
		if FileAccess.file_exists(cfg_path):
			return cfg_path
	return _home().path_join(".config").path_join("kdeglobals")


func get_color_scheme_path(scheme_name: String) -> String:
	if scheme_name.is_empty():
		return ""
	var home: String = _home()
	var file_name: String = scheme_name if scheme_name.ends_with(".colors") else scheme_name + ".colors"

	var candidates: Array[String] = [
		home.path_join(".local/share/color-schemes").path_join(file_name),
		home.path_join(".kde/share/color-schemes").path_join(file_name),
		"/usr/share/color-schemes/" + file_name,
		"/usr/local/share/color-schemes/" + file_name,
	]
	for path in candidates:
		if FileAccess.file_exists(path):
			return path
	return ""


func _find_available_color_scheme() -> String:
	for scheme in ["BreezeDark", "Breeze", "BreezeLight"]:
		if not get_color_scheme_path(scheme).is_empty():
			return scheme

	# Fall back to the first user scheme on disk.
	var dir_path: String = _home().path_join(".local/share/color-schemes")
	if DirAccess.dir_exists_absolute(dir_path):
		var dir: DirAccess = DirAccess.open(dir_path)
		if dir:
			dir.list_dir_begin()
			var file_name: String = dir.get_next()
			while file_name != "":
				if file_name.ends_with(".colors"):
					return file_name.get_basename()
				file_name = dir.get_next()
	return ""


func _parse_ini_value(path: String, section: String, key: String) -> String:
	if path.is_empty() or not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not file:
		return ""
	var current: String = ""
	var result: String = ""
	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#") or line.begins_with(";"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			current = line.substr(1, line.length() - 2)
			continue
		if current != section:
			continue
		var eq_pos: int = line.find("=")
		if eq_pos == -1:
			continue
		if line.substr(0, eq_pos).strip_edges() == key:
			result = line.substr(eq_pos + 1).strip_edges()
			break
	file.close()
	return result


func parse_kde_color(color_str: String) -> Color:
	var parts: PackedStringArray = color_str.split(",", false)
	if parts.size() < 3:
		return Color.TRANSPARENT
	var r: int = parts[0].strip_edges().to_int()
	var g: int = parts[1].strip_edges().to_int()
	var b: int = parts[2].strip_edges().to_int()
	return Color8(clampi(r, 0, 255), clampi(g, 0, 255), clampi(b, 0, 255))