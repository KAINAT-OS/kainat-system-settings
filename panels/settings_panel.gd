class_name SettingsPanel
extends ScrollContainer
# SettingsPanel.gd
# Base class for every Kainat System Settings page. Provides a small, native
# widget toolkit (page headers, section cards, list rows, toggles, dropdowns,
# sliders, info tiles and a lightweight toast) so panels stay declarative.
#
# Panels extend this class and override build() only.

const Sh := preload("res://panels/kainat_shell.gd")

# Standard placeholder shown by info rows when a value cannot be determined.
const UNAVAILABLE := "Not available"

var content: VBoxContainer
var _toast_layer: Control
var _lazy_parsers: Array[Callable] = []
var _in_tree: bool = false


func _ready() -> void:
	horizontal_scroll_mode = SCROLL_MODE_DISABLED
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_bottom", 36)
	add_child(margin)

	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	margin.add_child(content)

	build()
	_in_tree = true
	_run_lazy()


# Override in panels.
func build() -> void:
	pass


# Queue a Callable to run on the next frame with the loading cursor visible.
# Use for slow shell parses so panel switching stays instant.
func defer(task: Callable) -> void:
	_lazy_parsers.append(task)
	if _in_tree:
		_run_lazy()


func _run_lazy() -> void:
	if _lazy_parsers.is_empty():
		return
	var tasks: Array[Callable] = _lazy_parsers.duplicate()
	_lazy_parsers.clear()
	var tween: Tween = create_tween()
	tween.tween_callback(func() -> void:
		Input.set_default_cursor_shape(Input.CURSOR_BUSY))
	tween.tween_interval(0.01)
	for task in tasks:
		tween.tween_callback(task)
	tween.tween_callback(func() -> void:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW))


# --- theming helpers --------------------------------------------------------

func _accent() -> Color:
	var t: Node = get_node_or_null("/root/KDETheme")
	if t and t.get("kde_colors") and (t.kde_colors as Dictionary).has(&"accent"):
		return t.kde_colors[&"accent"]
	return Color(0.239, 0.682, 0.914)


func _text_color() -> Color:
	return get_theme_color("font_color", "Label")


func _muted() -> Color:
	var c: Color = _text_color()
	c.a = 0.62
	return c


func _with_alpha(color: Color, alpha: float) -> Color:
	var c: Color = color
	c.a = alpha
	return c


func _opacity(node: Control, alpha: float) -> void:
	node.modulate = Color(1, 1, 1, alpha)


func _row_style(hovered: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	if hovered:
		sb.bg_color = _with_alpha(_text_color(), 0.09)
		sb.set_corner_radius_all(6)
	else:
		sb.draw_center = false
	return sb


# --- page structure ---------------------------------------------------------

func page_header(title: String, subtitle: String = "") -> void:
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 26)
	content.add_child(title_label)

	if not subtitle.is_empty():
		var sub := Label.new()
		sub.text = subtitle
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.add_theme_font_size_override("font_size", 13)
		_opacity(sub, 0.6)
		content.add_child(sub)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	content.add_child(gap)


func section(title: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 14)
	content.add_child(spacer)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	content.add_child(row)

	var bar := ColorRect.new()
	bar.color = _accent()
	bar.custom_minimum_size = Vector2(3, 16)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)

	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", _accent())
	row.add_child(label)


func card() -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = _with_alpha(_text_color(), 0.05)
	sb.set_border_width_all(1)
	sb.border_color = _with_alpha(_text_color(), 0.12)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)
	content.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	return box


# --- list rows --------------------------------------------------------------

func _leading(glyph: String, icon_path: String = "") -> Control:
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		var tex := TextureRect.new()
		tex.texture = load(icon_path)
		tex.custom_minimum_size = Vector2(26, 26)
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tex.modulate = _text_color()
		return tex

	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(26, 26)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = _with_alpha(_accent(), 0.22)
	sb.set_corner_radius_all(7)
	chip.add_theme_stylebox_override("panel", sb)
	var letter := Label.new()
	letter.text = glyph.substr(0, 1).to_upper()
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.add_theme_font_size_override("font_size", 14)
	letter.add_theme_color_override("font_color", _accent())
	chip.add_child(letter)
	return chip


func _text_column(title: String, subtitle: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 1)

	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 15)
	box.add_child(t)

	if not subtitle.is_empty():
		var s := Label.new()
		s.text = subtitle
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.add_theme_font_size_override("font_size", 12)
		_opacity(s, 0.6)
		box.add_child(s)
	return box


# Builds the clickable shell for a row. Returns {"button", "row"}.
func _row_shell(card_box: VBoxContainer, title: String, subtitle: String,
		glyph: String, icon_path: String) -> Dictionary:
	var has_sub: bool = not subtitle.is_empty()
	var btn := Button.new()
	btn.text = ""
	btn.custom_minimum_size = Vector2(0, 58 if has_sub else 44)
	btn.focus_mode = Control.FOCUS_ALL
	btn.add_theme_stylebox_override("normal", _row_style(false))
	btn.add_theme_stylebox_override("hover", _row_style(true))
	btn.add_theme_stylebox_override("pressed", _row_style(true))
	btn.add_theme_stylebox_override("focus", _row_style(true))
	btn.add_theme_stylebox_override("disabled", _row_style(false))
	card_box.add_child(btn)

	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_theme_constant_override("margin_left", 12)
	mc.add_theme_constant_override("margin_right", 12)
	mc.add_theme_constant_override("margin_top", 6)
	mc.add_theme_constant_override("margin_bottom", 6)
	btn.add_child(mc)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	mc.add_child(row)

	row.add_child(_leading(glyph, icon_path))
	row.add_child(_text_column(title, subtitle))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	# Let clicks on the decorative content fall through to the row button.
	_click_through(mc)

	return {"button": btn, "row": row}


func _click_through(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_click_through(child)


func _chevron(row: HBoxContainer) -> void:
	var chev := Label.new()
	chev.text = "\u203a"
	chev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chev.add_theme_font_size_override("font_size", 22)
	chev.add_theme_color_override("font_color", _muted())
	chev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chev)


# --- favorites ---------------------------------------------------------------

static var _star_tex: Dictionary = {}


# The theme fonts (Noto Sans, the Godot fallback) carry no U+2605/U+2606, so a
# Label with a star would render tofu — rasterize the glyph ourselves instead.
static func star_texture(filled: bool) -> ImageTexture:
	var key: String = "on" if filled else "off"
	if _star_tex.has(key):
		return _star_tex[key] as ImageTexture

	var s := 24
	var ss := 4  # supersamples per axis
	var pts := PackedVector2Array()
	var c := Vector2(s, s) * 0.5
	var ro := s * 0.46
	var ri := ro * 0.42
	for i in 10:
		var a := -PI * 0.5 + i * (PI / 5.0)
		var r := ro if i % 2 == 0 else ri
		pts.append(c + Vector2(cos(a), sin(a)) * r)

	var half_stroke := 0.62  # px; the outline ends up 2x this wide
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))  # white RGB keeps downsampled edges from graying
	for y in s:
		for x in s:
			var acc := 0.0
			for sy in ss:
				for sx in ss:
					var p := Vector2(x + (float(sx) + 0.5) / ss,
							y + (float(sy) + 0.5) / ss)
					var hit: bool = _point_in_poly(p, pts) if filled \
							else _edge_dist(p, pts) <= half_stroke
					if hit:
						acc += 1.0
			var alpha := acc / float(ss * ss)
			if alpha > 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, alpha))

	var tex := ImageTexture.create_from_image(img)
	_star_tex[key] = tex
	return tex


static func _point_in_poly(p: Vector2, poly: PackedVector2Array) -> bool:
	var inside := false
	var j := poly.size() - 1
	for i in poly.size():
		var a := poly[i]
		var b := poly[j]
		if (a.y > p.y) != (b.y > p.y):
			var x := (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
			if p.x < x:
				inside = not inside
		j = i
	return inside


static func _edge_dist(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	var j := poly.size() - 1
	for i in poly.size():
		best = minf(best, _seg_dist(p, poly[j], poly[i]))
		j = i
	return best


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 <= 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# Panels are keyed by their script file name, which matches the sidebar button
# names (ps, nac, lal ...) used by the router.
func _panel_name() -> String:
	var s: Script = get_script()
	if s != null and not s.resource_path.is_empty():
		return s.resource_path.get_file().trim_suffix(".gd")
	return name


func _star_color(panel: String, title: String) -> Color:
	return _accent() if Sh.is_favorite(panel, title) else _muted()


func _star_tip(panel: String, title: String) -> String:
	return "Remove from Favorites" if Sh.is_favorite(panel, title) \
			else "Add to Favorites"


# Trailing star that pins a row to the sidebar Favorites section.
func _favorite_star(row: HBoxContainer, title: String) -> void:
	var panel := _panel_name()
	var star := Button.new()
	star.flat = true
	star.focus_mode = Control.FOCUS_NONE
	star.custom_minimum_size = Vector2(26, 26)
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	star.add_theme_stylebox_override("normal", _row_style(false))
	star.add_theme_stylebox_override("hover", _row_style(true))
	star.add_theme_stylebox_override("pressed", _row_style(true))
	star.add_theme_stylebox_override("focus", _row_style(false))
	star.tooltip_text = _star_tip(panel, title)

	star.mouse_entered.connect(func() -> void:
		star.self_modulate = _accent() if Sh.is_favorite(panel, title) \
				else _text_color())
	star.mouse_exited.connect(func() -> void:
		star.self_modulate = _star_color(panel, title))
	star.pressed.connect(func() -> void:
		var now := not Sh.is_favorite(panel, title)
		Sh.set_favorite(panel, title, now)
		star.self_modulate = _star_color(panel, title)
		star.icon = star_texture(now)
		star.tooltip_text = _star_tip(panel, title)
		notify("Pinned to Favorites" if now else "Unpinned from Favorites")
		if is_inside_tree():
			get_tree().call_group("favorites_ui", "refresh_favorites"))

	star.self_modulate = _star_color(panel, title)
	star.icon = star_texture(Sh.is_favorite(panel, title))
	row.add_child(star)


# A row that opens something (KCM, app or internal page).
func nav_row(card_box: VBoxContainer, title: String, subtitle: String,
		glyph: String, on_press: Callable, icon_path: String = "") -> void:
	var parts: Dictionary = _row_shell(card_box, title, subtitle, glyph, icon_path)
	_favorite_star(parts["row"], title)
	_chevron(parts["row"])
	(parts["button"] as Button).pressed.connect(on_press)


# A row that opens a KCM module.
func kcm_row(card_box: VBoxContainer, title: String, subtitle: String,
		glyph: String, module: String) -> void:
	nav_row(card_box, title, subtitle, glyph, func(): KainatShell.open_kcm(module))


# A row with a trailing action button.
func action_row(card_box: VBoxContainer, title: String, subtitle: String,
		glyph: String, action_text: String, on_press: Callable,
		primary: bool = false) -> void:
	var parts: Dictionary = _row_shell(card_box, title, subtitle, glyph, "")
	_favorite_star(parts["row"], title)
	var button := Button.new()
	button.text = action_text
	button.pressed.connect(on_press)
	if primary:
		button.add_theme_color_override("font_color", _accent())
	(parts["row"] as HBoxContainer).add_child(button)


# A row with a toggle switch. Clicking anywhere on the row toggles it.
func toggle_row(card_box: VBoxContainer, title: String, subtitle: String,
		glyph: String, value: bool, on_toggle: Callable) -> CheckButton:
	var parts: Dictionary = _row_shell(card_box, title, subtitle, glyph, "")
	var check := CheckButton.new()
	check.button_pressed = value
	check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	(parts["row"] as HBoxContainer).add_child(check)

	var apply := func(pressed: bool) -> void:
		check.set_pressed_no_signal(pressed)
		on_toggle.call(pressed)
	check.toggled.connect(apply)
	(parts["button"] as Button).pressed.connect(func(): check.button_pressed = not check.button_pressed)
	# Returned so a caller whose operation can fail can snap the switch back
	# to what the system actually reports.
	return check


# A row with a dropdown of choices.
func choice_row(card_box: VBoxContainer, title: String, subtitle: String,
		glyph: String, options: Array, selected: int, on_select: Callable) -> OptionButton:
	var parts: Dictionary = _row_shell(card_box, title, subtitle, glyph, "")
	var dropdown := OptionButton.new()
	dropdown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for opt in options:
		dropdown.add_item(str(opt))
	if selected >= 0 and selected < options.size():
		dropdown.select(selected)
	dropdown.item_selected.connect(on_select)
	(parts["row"] as HBoxContainer).add_child(dropdown)
	return dropdown


# A row with a slider and a live value label.
func slider_row(card_box: VBoxContainer, title: String, subtitle: String,
		glyph: String, min_value: float, max_value: float, value: float,
		on_change: Callable, suffix: String = "") -> HSlider:
	var parts: Dictionary = _row_shell(card_box, title, subtitle, glyph, "")
	var row: HBoxContainer = parts["row"]

	var value_label := Label.new()
	value_label.text = _format_value(value, suffix)
	value_label.custom_minimum_size = Vector2(56, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_color_override("font_color", _muted())

	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = (max_value - min_value) / 100.0
	slider.value = value
	slider.custom_minimum_size = Vector2(220, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = _format_value(v, suffix)
		on_change.call(v)
	)

	row.add_child(value_label)
	row.add_child(slider)
	return slider


func _format_value(value: float, suffix: String) -> String:
	return ("%d" % int(round(value))) + suffix


# An informational row (label + value). Returns the row container.
func info_row(card_box: VBoxContainer, label_text: String, value: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 36)
	row.add_theme_constant_override("separation", 12)

	var left := MarginContainer.new()
	left.add_theme_constant_override("margin_left", 12)
	var l := Label.new()
	l.text = label_text
	l.add_theme_font_size_override("font_size", 14)
	left.add_child(l)
	row.add_child(left)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var v := Label.new()
	v.text = value
	v.add_theme_font_size_override("font_size", 14)
	v.add_theme_color_override("font_color", _muted())
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var right := MarginContainer.new()
	right.add_theme_constant_override("margin_right", 12)
	right.add_child(v)
	row.add_child(right)

	card_box.add_child(row)
	return row


# Update the value of an info row created earlier.
func set_info_value(row: HBoxContainer, value: String) -> void:
	if row.get_child_count() >= 3:
		var label: Label = row.get_child(2).get_child(0) as Label
		if label:
			label.text = value
			label.add_theme_color_override("font_color", _muted())


# A muted, non-interactive row with an icon — the standard empty/error state
# for a feature whose backing tool or data is missing.
func unavailable_row(card_box: VBoxContainer, title: String, detail: String,
		glyph: String = "!") -> void:
	var parts: Dictionary = _row_shell(card_box, title, detail, glyph, "")
	var btn: Button = parts["button"]
	btn.disabled = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.modulate = Color(1, 1, 1, 0.6)  # dim everything inside the row

	var tag := Label.new()
	tag.text = "Not available"
	tag.add_theme_font_size_override("font_size", 12)
	tag.add_theme_color_override("font_color", _muted())
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	(parts["row"] as HBoxContainer).add_child(tag)


# A grid of small gradient info cards.
# The accent tiles under a page header. Returns the value Labels in order so
# a panel can show placeholders in build() and fill them in from a deferred
# _populate() once the shell probes have run.
func info_tiles(tiles: Array) -> Array:
	var value_labels: Array = []
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(grid)

	for tile in tiles:
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := StyleBoxFlat.new()
		sb.bg_color = _with_alpha(_accent(), 0.14)
		sb.set_corner_radius_all(8)
		sb.set_border_width_all(1)
		sb.border_color = _with_alpha(_accent(), 0.35)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 12
		sb.content_margin_bottom = 12
		panel.add_theme_stylebox_override("panel", sb)
		grid.add_child(panel)

		var box := VBoxContainer.new()
		panel.add_child(box)

		var value := Label.new()
		value.text = str(tile.get("value", ""))
		value.add_theme_font_size_override("font_size", 20)
		box.add_child(value)
		value_labels.append(value)

		var cap := Label.new()
		cap.text = str(tile.get("label", ""))
		cap.add_theme_font_size_override("font_size", 12)
		cap.add_theme_color_override("font_color", _muted())
		box.add_child(cap)

	return value_labels


# A plain full-width action button.
func big_button(text: String, on_press: Callable, primary: bool = true) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 40)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if primary:
		button.add_theme_color_override("font_color", _accent())
	button.pressed.connect(on_press)
	content.add_child(button)
	return button


# --- toast ------------------------------------------------------------------

func notify(message: String) -> void:
	if _toast_layer == null or not is_instance_valid(_toast_layer):
		_toast_layer = get_tree().root.get_node_or_null("KainatToastLayer")
	if _toast_layer == null:
		_toast_layer = Control.new()
		_toast_layer.name = "KainatToastLayer"
		_toast_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_toast_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		get_tree().root.add_child(_toast_layer)

	var toast := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = _with_alpha(_text_color(), 0.92)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	toast.add_theme_stylebox_override("panel", sb)
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	toast.position.y -= 48
	_toast_layer.add_child(toast)

	var label := Label.new()
	label.text = message
	label.add_theme_color_override("font_color", _text_color())
	toast.add_child(label)

	var tween := create_tween()
	tween.tween_interval(1.8)
	tween.tween_property(toast, "modulate:a", 0.0, 0.35)
	tween.tween_callback(toast.queue_free)


# --- search highlight -------------------------------------------------------

# Find a row by its label text and flash it with the accent color.
# Returns true when the row was found (callers retry across a few frames while
# a freshly-opened panel is still building its deferred rows).
func highlight_row(title: String) -> bool:
	var needle := title.to_lower()
	var target := _find_label(content, needle)
	if target == null:
		return false
	# Walk up to the row Button (rows are Buttons with a MarginContainer overlay).
	var node: Node = target
	var row_button: Control = null
	while node != null and node != content:
		if node is Button:
			row_button = node
			break
		node = node.get_parent()
	if row_button == null:
		row_button = target
	_flash_row(row_button)
	_scroll_to(row_button)
	return true


func _find_label(node: Node, needle: String) -> Label:
	if node is Label and (node as Label).text.to_lower() == needle:
		return node
	for child in node.get_children():
		var found := _find_label(child, needle)
		if found != null:
			return found
	return null


func _scroll_to(control: Control) -> void:
	var parent := control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			(parent as ScrollContainer).ensure_control_visible(control)
			return
		parent = parent.get_parent()


func _flash_row(row: Control) -> void:
	var tween := create_tween()
	tween.tween_property(row, "modulate", Color(1.6, 1.6, 1.4), 0.15)
	tween.tween_property(row, "modulate", Color(1, 1, 1), 0.15)
	tween.tween_property(row, "modulate", Color(1.6, 1.6, 1.4), 0.15)
	tween.tween_property(row, "modulate", Color(1, 1, 1), 0.15)

