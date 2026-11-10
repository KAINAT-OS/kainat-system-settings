extends SettingsPanel
# Startup Apps: manage the programs that launch when you log in.
#
# Autostart entries are plain .desktop files in /etc/xdg/autostart (system
# defaults) and ~/.config/autostart (per user). Disabling a system entry does
# not need root: a small override file in the user folder hides it.

const SYSTEM_DIR := "/etc/xdg/autostart"

var _list: ItemList
var _entries: Array = []
var _status: Label
var _toggle_btn: Button
var _remove_btn: Button


func build() -> void:
	page_header("Startup Apps", "Choose which programs open automatically when you log in.")

	section("At Login")
	var c := card()

	var intro := Label.new()
	intro.text = "Everything listed here starts in the background after you sign in. Turning an app off does not uninstall it."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", _muted())
	c.add_child(intro)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 320)
	_list.item_selected.connect(_on_selected)
	_list.item_activated.connect(func(_i: int) -> void: _toggle_selected())
	c.add_child(_list)

	_status = Label.new()
	_status.add_theme_color_override("font_color", _muted())
	c.add_child(_status)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	c.add_child(actions)

	_toggle_btn = Button.new()
	_toggle_btn.text = "Turn Off"
	_toggle_btn.pressed.connect(_toggle_selected)
	actions.add_child(_toggle_btn)

	_remove_btn = Button.new()
	_remove_btn.text = "Remove Entry"
	_remove_btn.pressed.connect(_remove_selected)
	actions.add_child(_remove_btn)

	var add_btn := Button.new()
	add_btn.text = "Add Program…"
	add_btn.pressed.connect(_add_dialog)
	actions.add_child(add_btn)

	var refresh := Button.new()
	refresh.text = "Refresh"
	refresh.pressed.connect(_refresh)
	actions.add_child(refresh)

	section("Where These Live")
	var c2 := card()
	info_row(c2, "Your Entries", _user_dir())
	info_row(c2, "System Defaults", SYSTEM_DIR)
	info_row(c2, "Tip", "Removing a system entry restores its default state instead of deleting it.")

	_set_actions_enabled(false)
	defer(_refresh)


func _user_dir() -> String:
	return OS.get_environment("HOME").path_join(".config/autostart")


func _refresh() -> void:
	_list.clear()
	_entries.clear()
	_set_actions_enabled(false)

	var by_name: Dictionary = {}
	for dir_path: String in [SYSTEM_DIR, _user_dir()]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file in dir.get_files():
			if not file.ends_with(".desktop"):
				continue
			var path := dir_path.path_join(file)
			var info := _read_entry(path)
			if info.is_empty():
				continue
			# A user file with the same name overrides the system one.
			by_name[file] = info
			info["system"] = dir_path == SYSTEM_DIR

	var names: Array = by_name.keys()
	names.sort_custom(func(a: Variant, b: Variant) -> bool:
		return str(by_name[a]["name"]).to_lower() < str(by_name[b]["name"]).to_lower())

	for file in names:
		var info: Dictionary = by_name[file]
		if bool(info.get("no_display", false)):
			continue
		_entries.append(info)
		var mark := "on  ·  " if bool(info["enabled"]) else "off  ·  "
		_list.add_item(mark + str(info["name"]))
		_list.set_item_metadata(_list.item_count - 1, _entries.size() - 1)

	var enabled := 0
	for entry in _entries:
		if bool(entry["enabled"]):
			enabled += 1
	_status.text = "%d of %d startup apps enabled" % [enabled, _entries.size()]
	if _entries.is_empty():
		_status.text = "No startup apps found."


func _read_entry(path: String) -> Dictionary:
	var text := Sh.read_text(path)
	if text.is_empty():
		return {}
	var info := {
		"path": path,
		"file": path.get_file(),
		"name": path.get_file().get_basename(),
		"enabled": true,
		"system": false,
		"no_display": false,
	}
	for line in text.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.is_empty() or trimmed.begins_with("#") or trimmed.begins_with("["):
			if trimmed.begins_with("[") and trimmed != "[Desktop Entry]":
				break
			continue
		var eq := trimmed.find("=")
		if eq <= 0:
			continue
		var key := trimmed.substr(0, eq).strip_edges()
		var value := trimmed.substr(eq + 1).strip_edges()
		match key:
			"Name":
				if not value.is_empty():
					info["name"] = value
			"Hidden":
				if value.to_lower() == "true":
					info["enabled"] = false
			"X-GNOME-Autostart-enabled":
				if value.to_lower() == "false":
					info["enabled"] = false
			"NoDisplay":
				if value.to_lower() == "true":
					info["no_display"] = true
	return info


func _selected() -> Dictionary:
	var selected := _list.get_selected_items()
	if selected.is_empty():
		return {}
	var meta: Variant = _list.get_item_metadata(selected[0])
	if meta == null:
		return {}
	var index: int = int(meta)
	if index < 0 or index >= _entries.size():
		return {}
	return _entries[index]


func _on_selected(_idx: int) -> void:
	var entry := _selected()
	if entry.is_empty():
		_set_actions_enabled(false)
		return
	var enabled := bool(entry["enabled"])
	_toggle_btn.text = "Turn Off" if enabled else "Turn On"
	_toggle_btn.disabled = false
	_remove_btn.disabled = not FileAccess.file_exists(_user_dir().path_join(str(entry["file"])))


func _set_actions_enabled(enabled: bool) -> void:
	_toggle_btn.disabled = not enabled
	_remove_btn.disabled = not enabled


func _toggle_selected() -> void:
	var entry := _selected()
	if entry.is_empty():
		return
	var enable := not bool(entry["enabled"])
	if _write_override(entry, enable):
		notify(str(entry["name"]) + (" will start at login." if enable else " will no longer start at login."))
		_refresh()
	else:
		notify("Could not update " + str(entry["file"]) + ".")


# Writes a user-level copy with Hidden set either way, which is how desktops
# both disable a system entry and re-enable one.
func _write_override(entry: Dictionary, enabled: bool) -> bool:
	var dir_path := _user_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)
	var target := dir_path.path_join(str(entry["file"]))
	var source := str(entry["path"])
	var lines: PackedStringArray = []
	if FileAccess.file_exists(target):
		lines = Sh.read_text(target).split("\n")
	else:
		lines = Sh.read_text(source).split("\n")

	var out: PackedStringArray = []
	var wrote_hidden := false
	var wrote_gnome := false
	for line in lines:
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("Hidden="):
			out.append("Hidden=" + ("false" if enabled else "true"))
			wrote_hidden = true
			continue
		if trimmed.begins_with("X-GNOME-Autostart-enabled="):
			out.append("X-GNOME-Autostart-enabled=" + ("true" if enabled else "false"))
			wrote_gnome = true
			continue
		out.append(line)
	if not wrote_hidden or not wrote_gnome:
		# Insert at the end of the [Desktop Entry] section.
		var insert_at := out.size()
		for i in out.size():
			if out[i].strip_edges().begins_with("[") and out[i].strip_edges() != "[Desktop Entry]":
				insert_at = i
				break
		var extra: Array[String] = []
		if not wrote_hidden:
			extra.append("Hidden=" + ("false" if enabled else "true"))
		if not wrote_gnome:
			extra.append("X-GNOME-Autostart-enabled=" + ("true" if enabled else "false"))
		for i in extra.size():
			out.insert(insert_at + i, extra[i])

	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string("\n".join(out))
	file.close()
	return true


func _remove_selected() -> void:
	var entry := _selected()
	if entry.is_empty():
		return
	var target := _user_dir().path_join(str(entry["file"]))
	if not FileAccess.file_exists(target):
		notify("This entry is a system default; turn it off instead.")
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Remove startup entry?"
	dialog.dialog_text = "Remove your personal entry for " + str(entry["name"]) + "?\n\nIf it is also a system default, that default becomes active again."
	dialog.ok_button_text = "Remove"
	dialog.add_cancel_button("Cancel")
	dialog.confirmed.connect(func() -> void:
		var err := DirAccess.remove_absolute(target)
		if err == OK:
			notify("Removed " + str(entry["name"]) + ".")
		else:
			notify("Could not remove the entry.")
		_refresh())
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


func _installed_apps() -> Array:
	var apps: Array = []
	var seen: Dictionary = {}
	for dir_path: String in ["/usr/share/applications", "/usr/local/share/applications",
			OS.get_environment("HOME").path_join(".local/share/applications")]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file in dir.get_files():
			if not file.ends_with(".desktop") or seen.has(file):
				continue
			var info := _read_entry(dir_path.path_join(file))
			if info.is_empty() or bool(info.get("no_display", false)):
				continue
			seen[file] = true
			info["system"] = false
			apps.append(info)
	apps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["name"]).to_lower() < str(b["name"]).to_lower())
	return apps


func _add_dialog() -> void:
	var apps := _installed_apps()
	if apps.is_empty():
		notify("No installed applications were found.")
		return

	var dialog := ConfirmationDialog.new()
	dialog.title = "Add Startup App"
	dialog.ok_button_text = "Add"
	dialog.add_cancel_button("Cancel")
	dialog.dialog_hide_on_ok = false

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 8)
	dialog.add_child(box)

	var hint := Label.new()
	hint.text = "Pick an installed application to start automatically at login."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	var picker := OptionButton.new()
	for app in apps:
		picker.add_item(str(app["name"]))
	box.add_child(picker)

	var error := Label.new()
	error.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(error)

	dialog.confirmed.connect(func() -> void:
		if picker.selected < 0 or picker.selected >= apps.size():
			error.text = "Choose an application first."
			return
		var app: Dictionary = apps[picker.selected]
		var target := _user_dir().path_join(str(app["file"]))
		if FileAccess.file_exists(target):
			error.text = str(app["name"]) + " is already in your startup list."
			return
		DirAccess.make_dir_recursive_absolute(_user_dir())
		var content := Sh.read_text(str(app["path"]))
		if content.is_empty():
			error.text = "That application's entry could not be read."
			return
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			error.text = "Could not write to " + _user_dir() + "."
			return
		file.store_string(content)
		file.close()
		_write_override({"path": target, "file": str(app["file"])}, true)
		dialog.queue_free()
		notify(str(app["name"]) + " will start at login.")
		_refresh())

	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.canceled.connect(dialog.queue_free)
