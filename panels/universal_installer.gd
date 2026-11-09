extends SettingsPanel
# Universal Installer: Install .deb, .rpm, .AppImage, and .exe files graphically.
# Drag-and-drop support with auto-detection of file type.

var _file_path: String = ""
var _file_label: Label
var _install_btn: Button
var _file_type: String = ""


func build() -> void:
	page_header("Universal Installer", "Install .deb, .rpm, .AppImage, .exe, and other packages.")
	
	# Drop zone
	var c := card()
	
	var drop_zone := VBoxContainer.new()
	drop_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drop_zone.custom_minimum_size = Vector2(0, 120)
	c.add_child(drop_zone)
	
	var drop_icon := Label.new()
	drop_icon.text = "📦"
	drop_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drop_icon.add_theme_font_size_override("font_size", 48)
	drop_zone.add_child(drop_icon)
	
	_file_label = Label.new()
	_file_label.text = "Drag a package file here\nor click to browse"
	_file_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_file_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	drop_zone.add_child(_file_label)
	
	var browse_btn := Button.new()
	browse_btn.text = "Browse Files"
	browse_btn.pressed.connect(_on_browse)
	drop_zone.add_child(browse_btn)
	
	# Make it a drop target
	drop_zone.mouse_entered.connect(_on_drag_enter.bind(drop_zone))
	drop_zone.mouse_exited.connect(_on_drag_exit.bind(drop_zone))
	if is_inside_tree():
		get_window().files_dropped.connect(_on_files_dropped)
	
	# Info section
	var info_section := VBoxContainer.new()
	c.add_child(info_section)
	
	_install_btn = Button.new()
	_install_btn.text = "Install / Run"
	_install_btn.disabled = true
	_install_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_install_btn.custom_minimum_size = Vector2(0, 40)
	_install_btn.pressed.connect(_on_install)
	info_section.add_child(_install_btn)
	
	var info_label := Label.new()
	info_label.text = "Supported: .deb, .rpm, .AppImage, .exe (Wine), .flatpakref"
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	info_section.add_child(info_label)
	
	# Progress/Output area
	var output_c := card()
	
	var output_label := Label.new()
	output_label.text = "Ready"
	output_label.name = "output_label"
	output_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	output_c.add_child(output_label)
	
	# Supported formats info
	section("Supported Formats")
	var fmt_c := card()
	
	var formats := [
		{ "ext": ".deb", "desc": "Debian/Ubuntu packages (native)", "tool": "dpkg/apt" },
		{ "ext": ".rpm", "desc": "Red Hat/Fedora packages", "tool": "alien → dpkg" },
		{ "ext": ".AppImage", "desc": "Portable Linux applications", "tool": "chmod +x → run" },
		{ "ext": ".exe", "desc": "Windows executables", "tool": "Wine" },
		{ "ext": ".flatpakref", "desc": "Flatpak repository references", "tool": "flatpak install" },
		{ "ext": ".snap", "desc": "Snap packages", "tool": "snap install" },
	]
	
	for fmt in formats:
		var row := HBoxContainer.new()
		fmt_c.add_child(row)
		
		var ext_label := Label.new()
		ext_label.text = fmt["ext"]
		ext_label.custom_minimum_size = Vector2(100, 0)
		ext_label.add_theme_font_size_override("font_size", 13)
		ext_label.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))
		row.add_child(ext_label)
		
		var desc_label := Label.new()
		desc_label.text = fmt["desc"]
		desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(desc_label)
		
		var tool_label := Label.new()
		tool_label.text = "(" + fmt["tool"] + ")"
		tool_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		tool_label.add_theme_font_size_override("font_size", 11)
		row.add_child(tool_label)


func _on_browse() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.title = "Select Package File"
	dialog.filters = ["*.deb", "*.rpm", "*.AppImage", "*.exe", "*.flatpakref", "*.snap", "*"]
	dialog.current_dir = Sh.home() + "/Downloads"
	dialog.file_selected.connect(_on_file_selected)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.file_selected.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


func _on_file_selected(path: String) -> void:
	_file_path = path
	_detect_type()
	_update_ui()


func _on_drag_enter(zone: VBoxContainer) -> void:
	zone.add_theme_stylebox_override("panel", _make_drop_stylebox(Color(0.3, 0.6, 1.0, 0.3)))


func _on_drag_exit(zone: VBoxContainer) -> void:
	zone.add_theme_stylebox_override("panel", _make_drop_stylebox(Color(0.1, 0.1, 0.1, 0.1)))


func _on_files_dropped(files: PackedStringArray) -> void:
	# Window.files_dropped: OS file drag-and-drop onto the app window.
	for file in files:
		if file.ends_with(".deb") or file.ends_with(".rpm") or file.ends_with(".AppImage") or \
		   file.ends_with(".exe") or file.ends_with(".flatpakref") or file.ends_with(".snap"):
			_file_path = file
			_detect_type()
			_update_ui()
			break


func _detect_type() -> void:
	if _file_path.ends_with(".deb"):
		_file_type = "deb"
	elif _file_path.ends_with(".rpm"):
		_file_type = "rpm"
	elif _file_path.ends_with(".AppImage") or _file_path.ends_with(".appimage"):
		_file_type = "appimage"
	elif _file_path.ends_with(".exe"):
		_file_type = "exe"
	elif _file_path.ends_with(".flatpakref"):
		_file_type = "flatpakref"
	elif _file_path.ends_with(".snap"):
		_file_type = "snap"
	else:
		_file_type = "unknown"


func _update_ui() -> void:
	if _file_path.is_empty():
		_file_label.text = "Drag a package file here\nor click to browse"
		_install_btn.disabled = true
		_install_btn.text = "Install / Run"
		return
	
	var filename := _file_path.get_file()
	var icons: Dictionary = {"deb": "📦", "rpm": "📦", "appimage": "🚀", "exe": "🪟", "flatpakref": "📱", "snap": "📦"}
	var icon: String = str(icons.get(_file_type, "📄"))
	
	_file_label.text = icon + " " + filename + "\nType: " + _file_type.to_upper()
	
	var btn_texts := {
		"deb": "Install Package",
		"rpm": "Convert & Install",
		"appimage": "Run Application",
		"exe": "Run with Wine",
		"flatpakref": "Install Flatpak",
		"snap": "Install Snap",
	}
	_install_btn.text = btn_texts.get(_file_type, "Install")
	_install_btn.disabled = _file_type == "unknown"


func _on_install() -> void:
	if _file_path.is_empty() or _file_type == "unknown":
		notify("No valid file selected")
		return
	
	var output_label := content.find_child("output_label", true, false)
	output_label.text = "Working..."
	
	notify("Processing " + _file_path.get_file() + "...")
	
	var code: int = -1
	match _file_type:
		"deb":
			code = Sh.install_deb_file(_file_path)
		"rpm":
			code = Sh.install_rpm_file(_file_path)
		"appimage":
			code = Sh.run_appimage(_file_path)
		"exe":
			code = Sh.run_wine_exe(_file_path)
		"flatpakref":
			code = Sh.run_wait("flatpak install " + Sh.quote(_file_path))
		"snap":
			code = Sh.run_wait("pkexec snap install " + Sh.quote(_file_path))
	
	if code == 0:
		output_label.text = "✅ Success! " + _file_path.get_file() + " processed."
		notify("Done!")
	else:
		output_label.text = "❌ Failed (exit code: " + str(code) + ")"
		notify("Installation failed. Check terminal for details.")


func _make_drop_stylebox(bg_color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_color = Color(0.4, 0.7, 1.0)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	return sb