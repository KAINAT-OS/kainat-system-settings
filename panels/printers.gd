extends SettingsPanel
# Printers: see the printers CUPS knows about, set a default, print a test page
# and open the full printer setup window.

const LPADMIN := "/usr/sbin/lpadmin"
const TESTPAGE := "/usr/share/cups/data/testprint"

var _service_row: HBoxContainer
var _count_row: HBoxContainer
var _default_row: HBoxContainer
var _list: ItemList
var _printers: Array = []
var _status: Label
var _test_btn: Button
var _default_btn: Button
var _remove_btn: Button


func build() -> void:
	page_header("Printers", "Set up printers, check their status and print a test page.")

	section("Printing")
	var c := card()
	_service_row = info_row(c, "Printing Service", "…")
	_count_row = info_row(c, "Printers", "…")
	_default_row = info_row(c, "Default Printer", "…")

	if not Sh.has_tool("lpstat"):
		set_info_value(_service_row, "Not available")
		set_info_value(_count_row, UNAVAILABLE)
		set_info_value(_default_row, UNAVAILABLE)
		unavailable_row(c, "Printing", "The printing tools are not installed.", "P")
		action_row(c, "Install Printing Support", "Adds CUPS and its command line tools.", "I", "Install", _install_cups)
		return

	if not _service_active():
		set_info_value(_service_row, "Stopped")
		set_info_value(_count_row, UNAVAILABLE)
		set_info_value(_default_row, UNAVAILABLE)
		unavailable_row(c, "Printing", "The printing service is not running.", "P")
		action_row(c, "Start Printing Service", "Turns CUPS on and enables it at boot.", "S", "Start", _start_service)
		return

	action_row(c, "Add or Set Up a Printer", "Opens the printer setup window to add a new printer.", "A", "Open", _open_settings)

	section("Installed Printers")
	var c2 := card()
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 240)
	_list.item_selected.connect(_on_selected)
	_list.item_activated.connect(func(_i: int) -> void: _print_test())
	c2.add_child(_list)

	_status = Label.new()
	_status.add_theme_color_override("font_color", _muted())
	c2.add_child(_status)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	c2.add_child(actions)

	_test_btn = _button(actions, "Print Test Page", _print_test)
	_default_btn = _button(actions, "Set as Default", _set_default)
	_remove_btn = _button(actions, "Remove Printer", _remove_selected)
	_button(actions, "Refresh", _refresh)
	_button(actions, "Open Printer Settings", _open_settings)

	section("Jobs")
	var c3 := card()
	action_row(c3, "Cancel My Print Jobs", "Stops every job you have queued.", "C", "Cancel Jobs", _cancel_jobs)
	info_row(c3, "Test Page", "Uses the standard CUPS test page; no ink-heavy photo is printed.")

	_set_actions_enabled(false)
	defer(_refresh)


func _button(parent: HBoxContainer, text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_press)
	parent.add_child(button)
	return button


func _service_active() -> bool:
	return Sh.run_capture("systemctl is-active cups 2>/dev/null").strip_edges() == "active"


func _install_cups() -> void:
	notify("Installing printing support…")
	run_async("pkexec apt-get install -y cups cups-client", func(code: int) -> void:
		if code == 0:
			Sh.clear_tool_cache()
			notify("Printing support installed. Open the Printers page again.")
		else:
			notify("Could not install printing support (exit code " + str(code) + ")."))


func _start_service() -> void:
	notify("Starting the printing service…")
	run_async("pkexec systemctl enable --now cups", func(code: int) -> void:
		if code == 0:
			notify("Printing started. Open the Printers page again.")
		else:
			notify("Could not start printing (exit code " + str(code) + ")."))


func _refresh() -> void:
	_list.clear()
	_printers.clear()
	_set_actions_enabled(false)

	var default_name := _default_printer()
	for raw in Sh.run_capture("lpstat -p 2>/dev/null").split("\n"):
		var line: String = raw.strip_edges()
		if not line.begins_with("printer "):
			continue
		var rest := line.substr(8).strip_edges()
		var space := rest.find(" ")
		var name := rest if space < 0 else rest.substr(0, space)
		var state := "ready"
		var lowered := rest.to_lower()
		if lowered.contains("disabled"):
			state = "disabled"
		elif lowered.contains("is idle"):
			state = "idle"
		elif lowered.contains("now printing"):
			state = "printing"
		_printers.append({"name": name, "state": state, "default": name == default_name})

	_printers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["name"]).to_lower() < str(b["name"]).to_lower())

	for i in _printers.size():
		var printer: Dictionary = _printers[i]
		var mark := "★  " if bool(printer["default"]) else "   "
		_list.add_item(mark + str(printer["name"]) + "  —  " + str(printer["state"]))
		_list.set_item_metadata(_list.item_count - 1, i)
		if bool(printer["default"]):
			_list.select(_list.item_count - 1)

	set_info_value(_service_row, "Running")
	set_info_value(_count_row, str(_printers.size()) + " installed" if not _printers.is_empty() else "None")
	set_info_value(_default_row, default_name if not default_name.is_empty() else "Not set")

	var jobs := _job_count()
	_status.text = "%d printer%s, %d queued job%s" % [
		_printers.size(), "" if _printers.size() == 1 else "s",
		jobs, "" if jobs == 1 else "s"]
	if _printers.is_empty():
		_status.text = "No printers installed yet. Use “Add or Set Up a Printer”."

	var selected := _list.get_selected_items()
	if not selected.is_empty():
		_on_selected(selected[0])


func _default_printer() -> String:
	var out := Sh.run_capture("lpstat -d 2>/dev/null").strip_edges()
	var marker := "system default destination:"
	if out.to_lower().begins_with(marker):
		return out.substr(marker.length()).strip_edges()
	return ""


func _job_count() -> int:
	var count := 0
	for raw in Sh.run_capture("lpstat -o 2>/dev/null").split("\n"):
		if not raw.strip_edges().is_empty():
			count += 1
	return count


func _selected() -> Dictionary:
	var selected := _list.get_selected_items()
	if selected.is_empty():
		return {}
	var meta: Variant = _list.get_item_metadata(selected[0])
	if meta == null:
		return {}
	var index: int = int(meta)
	if index < 0 or index >= _printers.size():
		return {}
	return _printers[index]


func _on_selected(_idx: int) -> void:
	var printer := _selected()
	if printer.is_empty():
		_set_actions_enabled(false)
		return
	_test_btn.disabled = false
	_default_btn.disabled = bool(printer["default"])
	_remove_btn.disabled = false


func _set_actions_enabled(enabled: bool) -> void:
	_test_btn.disabled = not enabled
	_default_btn.disabled = not enabled
	_remove_btn.disabled = not enabled


func _open_settings() -> void:
	if Sh.open_kcm("kcm_printer_manager"):
		return
	for candidate in ["system-config-printer", "systemsettings"]:
		if Sh.has_tool(candidate):
			OS.create_process(candidate, [])
			return
	notify("The printer setup window is not available on this system.")


func _print_test() -> void:
	var printer := _selected()
	if printer.is_empty():
		return
	if not FileAccess.file_exists(TESTPAGE):
		notify("The test page file is missing on this system.")
		return
	notify("Sending a test page to " + str(printer["name"]) + "…")
	run_async_capture("lp -d " + Sh.quote(str(printer["name"])) + " " + Sh.quote(TESTPAGE), func(code: int, text: String) -> void:
		if code == 0:
			notify("Test page sent to " + str(printer["name"]) + ".")
		else:
			notify("Could not print: " + _tail(text))
		_refresh())


func _set_default() -> void:
	var printer := _selected()
	if printer.is_empty():
		return
	if not FileAccess.file_exists(LPADMIN):
		notify("The printer administration tool is not installed.")
		return
	notify("Setting " + str(printer["name"]) + " as the default printer…")
	run_async("pkexec " + LPADMIN + " -d " + Sh.quote(str(printer["name"])), func(code: int) -> void:
		if code == 0:
			notify(str(printer["name"]) + " is now the default printer.")
		else:
			notify("Could not set the default printer (exit code " + str(code) + ").")
		_refresh())


func _remove_selected() -> void:
	var printer := _selected()
	if printer.is_empty():
		return
	if not FileAccess.file_exists(LPADMIN):
		notify("The printer administration tool is not installed.")
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Remove printer?"
	dialog.dialog_text = "Remove " + str(printer["name"]) + " from this computer?\n\nQueued jobs for it are discarded."
	dialog.ok_button_text = "Remove"
	dialog.add_cancel_button("Cancel")
	dialog.confirmed.connect(func() -> void:
		run_async("pkexec " + LPADMIN + " -x " + Sh.quote(str(printer["name"])), func(code: int) -> void:
			if code == 0:
				notify("Removed " + str(printer["name"]) + ".")
			else:
				notify("Could not remove the printer (exit code " + str(code) + ").")
			_refresh()))
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


func _cancel_jobs() -> void:
	var code := Sh.run_wait("cancel -a")
	if code == 0:
		notify("Queued print jobs cancelled.")
	else:
		notify("Could not cancel the print jobs.")
	_refresh()


func _tail(text: String) -> String:
	var lines: PackedStringArray = text.strip_edges().split("\n")
	var out: Array[String] = []
	for i in range(maxi(0, lines.size() - 3), lines.size()):
		var line: String = lines[i].strip_edges()
		if not line.is_empty():
			out.append(line)
	return " ".join(out).substr(0, 240)
