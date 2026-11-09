extends VBoxContainer

const Sh := preload("res://panels/kainat_shell.gd")
const FAV_GROUP := "favorites_ui"

# Configuration
@export var startup_tab: Button

# Internal State
var _button_group: ButtonGroup = null

# Node References (Lazy loading with validation)
@onready var router: PanelContainer = get_node_or_null("../../router")
@onready var _buttons: Array[Button] = []

# The Favorites list is rebuilt from kdeglobals whenever a star toggles.
var _fav_nodes: Array[Node] = []

func _ready() -> void:
	# Stars anywhere in the app call refresh_favorites() through this group.
	add_to_group(FAV_GROUP)

	# Threat Mitigation: Validate critical dependencies early
	if not router:
		push_error("CRITICAL: 'router' PanelContainer not found in hierarchy. Navigation disabled.")
		set_process(false)
		return

	# Discover buttons and enforce exclusive group behavior
	_button_group = ButtonGroup.new()
	
	for child in get_children():
		if child is Button:
			var btn: Button = child as Button
			btn.button_group = _button_group # Enforce mutual exclusivity
			btn.theme_type_variation = "SidebarButton"
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.add_theme_font_size_override("font_size", 14)
			btn.toggled.connect(_on_menu_btn_toggled.bind(btn))
			_buttons.append(btn)

	add_theme_constant_override("separation", 4)

	# Deterministic Startup State
	if startup_tab and startup_tab.get_parent() == self:
		# Force signal emission if setting property directly doesn't trigger logic
		startup_tab.button_pressed = true 
		_change_scene(startup_tab.name)
	elif _buttons.size() > 0:
		# Fallback: Press first available button if startup_tab is invalid
		_buttons[0].button_pressed = true
		_change_scene(_buttons[0].name)

	# Pinned rows live above the section list (built after discovery so these
	# buttons never join the section ButtonGroup).
	refresh_favorites()


func _on_menu_btn_toggled(toggled_on: bool, button: Button) -> void:
	# Only act on the transition to 'ON'
	if toggled_on:
		_change_scene(button.name)

func _change_scene(scene_name: String) -> void:
	if not router:
		return

	var script_path: String = "res://panels/%s.gd" % scene_name
	var scene_path: String = "res://panels/%s.tscn" % scene_name

	var new_scene: Node = null

	# Preferred: script-based native panel.
	if FileAccess.file_exists(script_path):
		var script: GDScript = load(script_path)
		if script:
			new_scene = script.new()
			if new_scene:
				new_scene.name = scene_name
	# Fallback: legacy .tscn panel.
	elif FileAccess.file_exists(scene_path):
		var scene_resource: PackedScene = load(scene_path)
		if scene_resource:
			new_scene = scene_resource.instantiate()

	if not new_scene:
		push_error("PANEL LOAD FAILURE: no script or scene for '%s'" % scene_name)
		return

	# Teardown: Clear existing content safely
	for child in router.get_children():
		router.remove_child(child)
		child.queue_free()

	router.add_child(new_scene)

func virtual_press_button(btn_name: String) -> void:
	# Search results name a panel by script file, which is not always a
	# sidebar entry — fall back to opening it directly instead of erroring.
	var btn := get_node_or_null(btn_name) as Button
	if btn:
		btn.button_pressed = true
	elif FileAccess.file_exists("res://panels/%s.gd" % btn_name):
		_change_scene(btn_name)


# --- favorites ---------------------------------------------------------------

# Rebuild the sidebar Favorites section from kdeglobals. Called from _ready()
# and from every row star via call_group(FAV_GROUP, "refresh_favorites").
func refresh_favorites() -> void:
	for n in _fav_nodes:
		if is_instance_valid(n):
			remove_child(n)
			n.queue_free()
	_fav_nodes.clear()

	var favs: Array = Sh.favorites()
	if favs.is_empty():
		return

	var box := VBoxContainer.new()
	box.name = "Favorites"
	box.add_theme_constant_override("separation", 2)

	var head := Label.new()
	head.text = "Favorites"
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var head_wrap := MarginContainer.new()
	head_wrap.add_theme_constant_override("margin_left", 16)
	head_wrap.add_theme_constant_override("margin_top", 14)
	head_wrap.add_theme_constant_override("margin_bottom", 2)
	head_wrap.add_child(head)
	box.add_child(head_wrap)
	_fav_nodes.append(head_wrap)

	for f in favs:
		var panel := str(f["panel"])
		var title := str(f["title"])
		# Drop entries whose panel has since been deleted.
		if not FileAccess.file_exists("res://panels/%s.gd" % panel):
			continue
		var b := Button.new()
		b.name = "fav_%d" % _fav_nodes.size()
		b.text = title
		b.icon = SettingsPanel.star_texture(true)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 36)
		b.tooltip_text = "Open %s in %s" % [title, panel]
		b.theme_type_variation = "SidebarButton"
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_color_override("icon_normal_color", Color(1, 1, 1, 0.7))
		b.pressed.connect(_open_favorite.bind(panel, title))
		box.add_child(b)
		_fav_nodes.append(b)

	add_child(box)
	# Sit directly below the brand block, above the section list.
	var idx := 0
	for i in get_child_count():
		if get_child(i).name == "Brand":
			idx = i + 1
			break
	move_child(box, idx)
	_fav_nodes.append(box)


func _open_favorite(panel: String, title: String) -> void:
	if not router:
		return

	var target := get_node_or_null(panel) as Button
	if target and not target.button_pressed:
		# Emits toggled -> _change_scene() for us.
		target.button_pressed = true
	elif not target:
		# Panel is not a sidebar section (or the sidebar entry vanished).
		if not FileAccess.file_exists("res://panels/%s.gd" % panel):
			Sh.set_favorite(panel, title, false)
			refresh_favorites()
			return
		_change_scene(panel)
	# Already the active panel: keep it and just re-focus the row below.

	# Rows built by _populate() appear a few frames late, so retry briefly.
	for i in 15:
		await get_tree().process_frame
		if router == null or router.get_child_count() == 0:
			continue
		var p: Node = router.get_child(0)
		if p and p.has_method("highlight_row") and p.highlight_row(title):
			return
