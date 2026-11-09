extends VBoxContainer

@onready var io: Button = %io
@onready var router: PanelContainer = $"../../router"

@export var startup_tab: Button
var menu_btn_gr: ButtonGroup 
var pressed
func _ready() -> void:
	menu_btn_gr = io.button_group
	pass
	## Connect the signal (No need for explicit Callable() wrapper in Godot 4)
	#
	## Initialize the UI state without triggering signals
	if startup_tab:
		startup_tab.button_pressed = true
		_on_menu_btn_pressed(startup_tab)
	#else:
		#io.button_pressed = true
		#_change_scene(io.name)



func _process(delta: float) -> void:
	var newpressed = menu_btn_gr.get_pressed_button()
	if newpressed != pressed:
		var btn=menu_btn_gr.get_pressed_button()
		if btn:
			_on_menu_btn_pressed(btn)
			pressed = newpressed
	
func _on_menu_btn_pressed(button: Button) -> void:
	# The 'pressed' signal of ButtonGroup actually passes the button object automatically
	print("Button pressed: ", button.name)
	_change_scene(button.name)

func _change_scene(scene_name: String) -> void:
	var path = "res://panels/" + scene_name + ".tscn"
	
	# Verify file exists to avoid crashes
	if not FileAccess.file_exists(path):
		push_error("Scene not found at: " + path)
		return
	
	# 1. Clear existing children in the router
	for child in router.get_children():
		child.queue_free()
	
	# 2. Instantiate and add the new scene
	var scene_resource = load(path)
	if scene_resource:
		var new_scene = scene_resource.instantiate()
		router.add_child(new_scene)
