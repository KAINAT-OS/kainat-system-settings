extends Control
# SearchBar — cross-panel search box with results dropdown.
# Searches all settings rows and navigates to the matching panel on selection.

const RESULTS_HEIGHT := 360.0     # never taller than this
const RESULTS_MIN := 52.0         # always enough for one row + padding
const OVERLAY_LAYER := 100
const CARD_MARGIN := 10.0         # content margin baked into the card style
const ROW_ESTIMATE := 33.0        # row height guess until the list is laid out

@onready var _search_box: LineEdit = $SearchBox
@onready var _results: ItemList = $Popup/Results
@onready var _popup: PanelContainer = $Popup

var _menu: Node = null
var _manager: Node = null
var _last_results: Array = []
var _layer: CanvasLayer = null
var _manager_bootstrapping := false


func _ready() -> void:
	_menu = get_tree().root.find_child("menu-buttons", true, false)
	_manager = _resolve_manager()
	_search_box.text_changed.connect(_on_text_changed)
	_search_box.text_submitted.connect(_on_submitted)
	# Enter / double-click.
	_results.item_activated.connect(_on_result_selected)
	# Single click — a result list should not need a double-click to act.
	_results.item_clicked.connect(_on_item_clicked)
	_style_dropdown()
	_move_popup_to_overlay()
	_popup.visible = false
	_results.clear()


# The SearchManager is an autoload, but a missing or failed autoload must not
# silently produce an empty box — that reads as "search is broken". Resolve it
# lazily and, failing that, stand one up so the index still gets built.
func _resolve_manager() -> Node:
	var m: Node = get_tree().root.get_node_or_null("SearchManager")
	if m != null and m.is_inside_tree():
		return m
	# One deferred bootstrap at most — otherwise every keystroke would queue
	# another instance until the first one landed.
	if _manager_bootstrapping:
		return null
	var script = load("res://search_manager.gd")
	if script == null or not script.can_instantiate():
		return null
	_manager_bootstrapping = true
	m = script.new()
	m.name = "SearchManager"
	# Same startup race as the overlay below: while _ready() runs the root is
	# still propagating ready, its data.blocked is non-zero, and a direct
	# add_child() is rejected outright.
	get_tree().root.add_child.call_deferred(m)
	# Not usable until the deferred add lands; the next keystroke will pick
	# it up through get_node_or_null() above.
	return null


# The panel starts life inside the SearchBar VBox, but a container sizes a
# child from its *minimum* size — and an ItemList's minimum is (0,0), so the
# dropdown collapsed to a zero-height strip and nothing was ever drawn, even
# though 158 rows were indexed and 7 matched. Measured before the fix:
# popup.size == (1004, 0). A CanvasLayer is not a container, so the panel is
# free to take a real rect: it renders under the box and no longer shoves the
# sidebar and content down while typing.
#
# Both adds MUST be deferred. This runs from _ready(), which is nested inside
# the root's own _propagate_ready(), so root.data.blocked > 0 and a plain
# add_child() fails with "Parent node is busy setting up children". The layer
# was then never created, the popup stayed in the VBox, and the dropdown
# silently went back to zero height — the exact symptom this function exists
# to fix. Deferred calls flush at idle, after ready propagation unwinds.
func _move_popup_to_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "SearchResultsLayer"
	_layer.layer = OVERLAY_LAYER
	get_tree().root.add_child.call_deferred(_layer)
	# Queued second, so the layer is already in the tree when this runs.
	_finish_overlay.call_deferred()


func _finish_overlay() -> void:
	if not is_instance_valid(_layer) or _layer.get_parent() == null:
		return  # root was still busy; the resize/keystroke path will retry
	if _popup.get_parent() == _layer:
		return
	_popup.get_parent().remove_child(_popup)
	_layer.add_child(_popup)
	# Anchors at zero make offset_* read as plain viewport coordinates.
	_popup.anchor_left = 0.0
	_popup.anchor_top = 0.0
	_popup.anchor_right = 0.0
	_popup.anchor_bottom = 0.0
	_place_popup(_estimated_height(0))
	_search_box.resized.connect(func() -> void: _place_popup(_popup.size.y))


# The popup must be on the overlay before it is shown, or the VBox collapses
# it to zero height. _place_popup() calls this on every show path, so a
# deferred attempt that found a busy root is simply retried later instead of
# leaving a permanently dead dropdown. No-op once the reparent has landed.
func _ensure_overlay() -> void:
	if _layer != null and is_instance_valid(_layer) \
			and _layer.get_parent() != null and _popup.get_parent() == _layer:
		return
	if _layer == null or not is_instance_valid(_layer):
		_layer = CanvasLayer.new()
		_layer.name = "SearchResultsLayer"
		_layer.layer = OVERLAY_LAYER
	if _layer.get_parent() == null:
		get_tree().root.add_child.call_deferred(_layer)
	_finish_overlay.call_deferred()


# A spotlight-style dropdown needs a solid, elevated card. The theme gives
# PanelContainer a transparent panel (cards style themselves), which left the
# results floating straight over the sidebar — and since the box was also a
# fixed 360 px, three results sat in a mostly-empty see-through rectangle.
func _style_dropdown() -> void:
	var card := StyleBoxFlat.new()
	card.bg_color = Color(0.118, 0.125, 0.141, 1.0)
	card.set_corner_radius_all(12)
	card.set_border_width_all(1)
	card.border_color = Color(1, 1, 1, 0.10)
	card.content_margin_left = CARD_MARGIN
	card.content_margin_right = CARD_MARGIN
	card.content_margin_top = CARD_MARGIN
	card.content_margin_bottom = CARD_MARGIN
	card.shadow_color = Color(0, 0, 0, 0.45)
	card.shadow_size = 16
	card.shadow_offset = Vector2(0, 6)
	_popup.add_theme_stylebox_override("panel", card)

	# The card is the backdrop, so the list must not paint its own.
	var clear := StyleBoxFlat.new()
	clear.bg_color = Color(0, 0, 0, 0)
	_results.add_theme_stylebox_override("panel", clear)

	var base := StyleBoxFlat.new()
	base.bg_color = Color(0, 0, 0, 0)
	base.set_corner_radius_all(8)
	base.content_margin_left = 12.0
	base.content_margin_right = 12.0
	base.content_margin_top = 7.0
	base.content_margin_bottom = 7.0

	var hover: StyleBoxFlat = base.duplicate()
	hover.bg_color = Color(1, 1, 1, 0.08)
	var selected: StyleBoxFlat = base.duplicate()
	selected.bg_color = _accent()

	_results.add_theme_stylebox_override("normal", base)
	_results.add_theme_stylebox_override("hover", hover)
	_results.add_theme_stylebox_override("selected", selected)
	_results.add_theme_stylebox_override("selected_focus", selected)
	_results.add_theme_color_override("font_color", Color(0.92, 0.93, 0.95))
	_results.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	_results.add_theme_color_override("font_selected_color", Color(1, 1, 1))
	_results.add_theme_font_size_override("font_size", 15)


func _accent() -> Color:
	var t := get_node_or_null("/root/KDETheme")
	if t and t.get("kde_colors") and (t.kde_colors as Dictionary).has(&"accent"):
		return t.kde_colors[&"accent"]
	return Color(0.239, 0.682, 0.914)


func _estimated_height(count: int) -> float:
	var wanted: float = CARD_MARGIN * 2.0 + ROW_ESTIMATE * float(max(count, 1))
	return clampf(wanted, RESULTS_MIN, RESULTS_HEIGHT)


func _place_popup(height: float) -> void:
	# Guarantee the panel is on the overlay before anything reads its rect.
	_ensure_overlay()
	var box := _search_box.get_global_rect()
	# Never taller than what is left of the window under the search box.
	var available: float = get_viewport_rect().size.y - box.end.y - 12.0
	var h: float = clampf(height, RESULTS_MIN, maxf(available, RESULTS_MIN))
	_popup.offset_left = box.position.x
	_popup.offset_right = box.end.x
	_popup.offset_top = box.end.y
	_popup.offset_bottom = box.end.y + h


# Exact height once the items have actually been laid out — the estimate is
# only used so the box appears on the very first frame instead of one frame
# later, and so a wrong guess can never leave a mostly-empty card.
func _fit_popup_to_content() -> void:
	if not is_instance_valid(_popup) or not _popup.visible:
		return
	if _results.item_count == 0:
		return
	var last: Rect2 = _results.get_item_rect(_results.item_count - 1)
	if last.size.y <= 1.0:
		return  # list not laid out yet; keep the estimate
	_place_popup(last.end.y + CARD_MARGIN * 2.0)


func _input(event: InputEvent) -> void:
	# Ctrl+F jumps to the search box from anywhere in the window, including
	# while a panel scroll is focused.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F and event.ctrl_pressed:
			_search_box.grab_focus()
			_search_box.select_all()
			get_viewport().set_input_as_handled()
			return
	if not _popup.visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_hide_results()
		_search_box.text = ""
		_search_box.release_focus()
		get_viewport().set_input_as_handled()
		return
	# Dismiss when clicking anywhere that is neither the list nor the box.
	# Runs before the ItemList sees the click, so results stay put.
	if event is InputEventMouseButton and event.pressed:
		var pos: Vector2 = event.position
		if not _popup.get_global_rect().has_point(pos) \
				and not _search_box.get_global_rect().has_point(pos):
			_hide_results()


func _hide_results() -> void:
	_popup.visible = false
	_results.clear()
	_last_results.clear()


func _on_text_changed(text: String) -> void:
	_last_results.clear()
	if text.strip_edges().length() < 2:
		_hide_results()
		return
	if _manager == null:
		_manager = _resolve_manager()
	if _manager == null:
		# Never fail silently: an empty box reads as "search does nothing".
		_results.clear()
		_results.add_item("Search is unavailable — the settings index did not load.")
		_place_popup(_estimated_height(1))
		_popup.visible = true
		return
	_last_results = _manager.search(text)
	_results.clear()
	if _last_results.is_empty():
		_results.add_item("No results for \"" + text + "\"")
	else:
		for item in _last_results:
			var label: String = item["title"]
			if not item["subtitle"].is_empty():
				label += "  —  " + item["subtitle"]
			_results.add_item(label)
	_place_popup(_estimated_height(_results.item_count))
	_popup.visible = true
	# One frame later the list knows its real item height, so snap the card to
	# exactly cover its contents instead of a guessed rectangle.
	await get_tree().process_frame
	_fit_popup_to_content()


func _on_item_clicked(index: int, _at_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index == MOUSE_BUTTON_LEFT:
		_on_result_selected(index)


func _on_submitted(_text: String) -> void:
	if _results.get_item_count() > 0:
		_on_result_selected(0)


func _on_result_selected(index: int) -> void:
	# item_clicked and item_activated both land here (a double-click emits
	# both), so only the first pass may act.
	if not _popup.visible:
		return
	if index < 0 or index >= _results.get_item_count():
		return
	var text := _results.get_item_text(index)
	if text.begins_with("No results") or text.begins_with("Search is unavailable"):
		return
	if index >= _last_results.size():
		return
	var item: Dictionary = _last_results[index]
	var panel_name: String = item["panel"]
	var title: String = item["title"]
	_hide_results()
	_search_box.text = ""
	_search_box.release_focus()
	# Switch to the panel
	if _menu and _menu.has_method("virtual_press_button"):
		_menu.virtual_press_button(panel_name)
	# Rows are built by a deferred _populate(), so keep retrying until the
	# target label exists rather than betting on two frames.
	var router: Node = get_tree().root.find_child("router", true, false)
	for i in 15:
		await get_tree().process_frame
		if router == null or not is_instance_valid(router) or router.get_child_count() == 0:
			continue
		var panel = router.get_child(0)
		if panel and panel.has_method("highlight_row") and panel.highlight_row(title):
			return
