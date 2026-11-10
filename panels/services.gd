extends SettingsPanel
# System Services: inspect and control systemd units without a terminal.
#
# Everything here goes through `systemctl` with pkexec, so the user gets the
# normal polkit prompt instead of having to open a terminal and type sudo.

var _search: LineEdit
var _failed_only: CheckButton
var _list: ItemList
var _units: Array = []
var _status: Label
var _start_btn: Button
var _stop_btn: Button
var _restart_btn: Button
var _enable_btn: Button
var _disable_btn: Button


func build() -> void:
	page_header("System Services", "Start, stop and control the background services on this computer.")

	section("Services")
	var c := card()

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	c.add_child(controls)

	_search = LineEdit.new()
	_search.placeholder_text = "Filter services (e.g. bluetooth, printing)…"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_text: String) -> void: _apply_filter())
	controls.add_child(_search)

	_failed_only = CheckButton.new()
	_failed_only.text = "Failed only"
	_failed_only.toggled.connect(func(_on: bool) -> void: _apply_filter())
	controls.add_child(_failed_only)

	var refresh := Button.new()
	refresh.text = "Refresh"
	refresh.pressed.connect(_refresh)
	controls.add_child(refresh)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 360)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_selected)
	_list.item_activated.connect(func(_idx: int) -> void: _show_details())
	c.add_child(_list)

	_status = Label.new()
	_status.text = "Loading services…"
	_status.add_theme_color_override("font_color", _muted())
	c.add_child(_status)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	c.add_child(actions)

	_start_btn = _action_button(actions, "Start", _start_selected)
	_stop_btn = _action_button(actions, "Stop", _stop_selected)
	_restart_btn = _action_button(actions, "Restart", _restart_selected)
	_enable_btn = _action_button(actions, "Enable at Boot", _enable_selected)
	_disable_btn = _action_button(actions, "Disable at Boot", _disable_selected)
	var details_btn := _action_button(actions, "Details", _show_details)
	details_btn.tooltip_text = "Show the full status output for the selected service."

	_set_actions_enabled(false)
	defer(_refresh)


func _action_button(parent: HBoxContainer, text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_press)
	parent.add_child(button)
	return button


func _refresh() -> void:
	_status.text = "Loading services…"
	_list.clear()
	_units.clear()
	_set_actions_enabled(false)

	var enabled_map := _enabled_map()
	for raw in Sh.run_lines("systemctl list-units --type=service --all --no-legend --no-pager 2>/dev/null"):
		var line: String = str(raw).strip_edges()
		if line.begins_with("●"):
			line = line.substr(1).strip_edges()
		var parts: PackedStringArray = line.split(" ", false)
		if parts.size() < 4:
			continue
		var unit: String = parts[0]
		if not unit.ends_with(".service"):
			continue
		var description := ""
		if parts.size() > 4:
			description = " ".join(parts.slice(4))
		_units.append({
			"name": unit,
			"active": parts[2],
			"sub": parts[3],
			"description": description,
			"enabled": str(enabled_map.get(unit, "unknown")),
		})

	_units.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["name"]) < str(b["name"]))
	_apply_filter()


# `list-unit-files` is the only source for "enabled at boot" that works without
# root, and it is separate from the runtime state in `list-units`.
func _enabled_map() -> Dictionary:
	var map: Dictionary = {}
	for raw in Sh.run_lines("systemctl list-unit-files --type=service --no-legend --no-pager 2>/dev/null"):
		var parts: PackedStringArray = str(raw).strip_edges().split(" ", false)
		if parts.size() >= 2:
			map[parts[0]] = parts[1]
	return map


func _apply_filter() -> void:
	if _list == null:
		return
	_list.clear()
	var needle := _search.text.strip_edges().to_lower()
	var only_failed := _failed_only.button_pressed
	var shown := 0
	for i in _units.size():
		var unit: Dictionary = _units[i]
		var active: String = str(unit["active"])
		if only_failed and active != "failed":
			continue
		var haystack: String = (str(unit["name"]) + " " + str(unit["description"])).to_lower()
		if not needle.is_empty() and not haystack.contains(needle):
			continue
		var prefix := "● " if active == "failed" else ""
		var boot := "  ·  starts at boot" if str(unit["enabled"]) == "enabled" else ""
		_list.add_item(prefix + str(unit["name"]) + "  —  " + active + "/" + str(unit["sub"]) + boot)
		_list.set_item_metadata(_list.item_count - 1, i)
		shown += 1
	_status.text = "%d of %d services shown" % [shown, _units.size()]


func _selected_unit() -> Dictionary:
	var selected := _list.get_selected_items()
	if selected.is_empty():
		return {}
	var item: int = selected[0]
	var meta: Variant = _list.get_item_metadata(item)
	if meta == null:
		return {}
	var index: int = int(meta)
	if index < 0 or index >= _units.size():
		return {}
	return _units[index]


func _on_selected(_idx: int) -> void:
	var unit := _selected_unit()
	if unit.is_empty():
		_set_actions_enabled(false)
		return
	var active: String = str(unit["active"])
	var enabled: String = str(unit["enabled"])
	_start_btn.disabled = active == "active"
	_stop_btn.disabled = not (active == "active" or active == "activating")
	_restart_btn.disabled = active != "active"
	_enable_btn.disabled = enabled == "enabled"
	_disable_btn.disabled = enabled == "disabled"


func _set_actions_enabled(enabled: bool) -> void:
	_start_btn.disabled = not enabled
	_stop_btn.disabled = not enabled
	_restart_btn.disabled = not enabled
	_enable_btn.disabled = not enabled
	_disable_btn.disabled = not enabled


func _start_selected() -> void:
	_act("start", "Started")


func _stop_selected() -> void:
	var unit := _selected_unit()
	if unit.is_empty():
		return
	_confirm("Stop service?",
		"Stopping " + str(unit["name"]) + " can interrupt whatever it is providing.\n\nStop it anyway?",
		"Stop", func() -> void: _act("stop", "Stopped"))


func _restart_selected() -> void:
	_act("restart", "Restarted")


func _enable_selected() -> void:
	_act("enable", "Enabled at boot")


func _disable_selected() -> void:
	var unit := _selected_unit()
	if unit.is_empty():
		return
	_confirm("Disable at boot?",
		str(unit["name"]) + " will no longer start automatically when the computer boots.\n\nIt keeps running until you stop it or restart.",
		"Disable", func() -> void: _act("disable", "Disabled at boot"))


func _act(verb: String, done_text: String) -> void:
	var unit := _selected_unit()
	if unit.is_empty():
		return
	var name: String = str(unit["name"])
	_set_actions_enabled(false)
	_status.text = done_text + ": " + name + "…"
	run_async("pkexec systemctl " + verb + " " + Sh.quote(name), func(code: int) -> void:
		if code == 0:
			notify(done_text + ": " + name)
		else:
			notify("Could not change " + name + " (exit code " + str(code) + ").")
		_refresh())


func _show_details() -> void:
	var unit := _selected_unit()
	if unit.is_empty():
		return
	var name: String = str(unit["name"])
	run_async_capture("systemctl status " + Sh.quote(name) + " --no-pager --full 2>&1", func(_code: int, text: String) -> void:
		var dialog := AcceptDialog.new()
		dialog.title = "Service: " + name
		dialog.size = Vector2i(760, 560)
		var edit := TextEdit.new()
		edit.text = text.strip_edges()
		edit.editable = false
		edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		edit.custom_minimum_size = Vector2(720, 500)
		dialog.add_child(edit)
		dialog.ok_button_text = "Close"
		get_tree().root.add_child(dialog)
		dialog.popup_centered()
		dialog.confirmed.connect(dialog.queue_free)
		dialog.canceled.connect(dialog.queue_free))


func _confirm(title: String, text: String, ok: String, on_yes: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.dialog_text = text
	dialog.ok_button_text = ok
	dialog.add_cancel_button("Cancel")
	dialog.confirmed.connect(func() -> void: on_yes.call())
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
