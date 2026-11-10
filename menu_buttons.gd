extends VBoxContainer

const Sh := preload("res://panels/kainat_shell.gd")
const FAV_GROUP := "favorites_ui"

# Sidebar layout. Buttons are regrouped under these headings in this order;
# any button not listed here lands in a trailing "More" section so a new panel
# never disappears from the sidebar.
const SECTIONS: Array = [
	{
		"title": "Appearance",
		"panels": ["personalization", "displays", "accessibility", "input_methods"],
	},
	{
		"title": "Sound & Devices",
		"panels": ["io", "bluetooth", "printers", "hardware"],
	},
	{
		"title": "Network",
		"panels": ["nac", "vpn_manager", "ssh_manager", "sharing", "firewall"],
	},
	{
		"title": "Applications",
		"panels": ["applications", "universal_installer", "windows_compat", "startup"],
	},
	{
		"title": "System",
		"panels": [
			"update", "driver-manager", "services", "disk_manager", "backup",
			"boot", "ps", "lal", "las", "users", "about",
		],
	},
]

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

	_build_sections()

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


# Reorder the flat button list into titled sections and insert a heading
# before each group. Headings are plain Labels so they never join the
# ButtonGroup or receive keyboard focus.
func _build_sections() -> void:
	var by_name: Dictionary = {}
	for b in _buttons:
		by_name[b.name] = b

	var order: Array[Node] = []
	for child in get_children():
		if child.name == "Brand":
			order.append(child)
			break

	var placed: Dictionary = {}
	for section in SECTIONS:
		var panels: Array = section["panels"]
		var members: Array[Button] = []
		for p in panels:
			var key := str(p)
			if by_name.has(key) and not placed.has(key):
				members.append(by_name[key])
				placed[key] = true
		if members.is_empty():
			continue
		var head := _section_header(str(section["title"]))
		add_child(head)
		order.append(head)
		for b in members:
			order.append(b)

	var leftovers: Array[Button] = []
	for b in _buttons:
		if not placed.has(b.name):
			leftovers.append(b)
	if not leftovers.is_empty():
		var more := _section_header("More")
		add_child(more)
		order.append(more)
		for b in leftovers:
			order.append(b)

	for i in order.size():
		move_child(order[i], i)


func _section_header(title: String) -> MarginContainer:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wrap := MarginContainer.new()
	wrap.name = "Section_%s" % title.replace(" ", "").replace("&", "and")
	wrap.add_theme_constant_override("margin_left", 16)
	wrap.add_theme_constant_override("margin_top", 14)
	wrap.add_theme_constant_override("margin_bottom", 2)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(label)
	return wrap


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
