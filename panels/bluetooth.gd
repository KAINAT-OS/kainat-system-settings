extends SettingsPanel
# Bluetooth: pair, connect and manage wireless devices without bluetoothctl.
#
# Everything is driven through bluetoothctl in non-interactive mode, which
# talks to the system Bluetooth service over D-Bus.

var _name_row: HBoxContainer
var _address_row: HBoxContainer
var _power_toggle: CheckButton
var _discoverable_toggle: CheckButton
var _list: ItemList
var _devices: Array = []
var _status: Label
var _connect_btn: Button
var _disconnect_btn: Button
var _pair_btn: Button
var _remove_btn: Button
var _scan_btn: Button


func build() -> void:
	page_header("Bluetooth", "Connect headphones, mice, keyboards and other wireless devices.")

	section("Adapter")
	var c := card()
	_name_row = info_row(c, "Adapter Name", "…")
	_address_row = info_row(c, "Address", "…")

	if not Sh.has_tool("bluetoothctl"):
		set_info_value(_name_row, "Not available")
		set_info_value(_address_row, UNAVAILABLE)
		unavailable_row(c, "Bluetooth", "The Bluetooth tools are not installed.", "B")
		return

	if not _service_active():
		set_info_value(_name_row, "Service stopped")
		set_info_value(_address_row, UNAVAILABLE)
		unavailable_row(c, "Bluetooth", "The Bluetooth service is not running.", "B")
		action_row(c, "Start Bluetooth", "Turns the Bluetooth service on and enables it at boot.", "S", "Start", _start_service)
		return

	if _controller() == "":
		set_info_value(_name_row, "No adapter")
		set_info_value(_address_row, UNAVAILABLE)
		unavailable_row(c, "Bluetooth", "No Bluetooth adapter was found on this computer.", "B")
		return

	_power_toggle = toggle_row(c, "Bluetooth On", "Turn the radio on or off.", "P", _powered(), _set_power)
	_discoverable_toggle = toggle_row(c, "Discoverable", "Let nearby devices find this computer.", "D", _discoverable(), _set_discoverable)

	section("Devices")
	var c2 := card()

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 300)
	_list.item_selected.connect(_on_selected)
	_list.item_activated.connect(func(_i: int) -> void: _connect_selected())
	c2.add_child(_list)

	_status = Label.new()
	_status.add_theme_color_override("font_color", _muted())
	c2.add_child(_status)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	c2.add_child(actions)

	_scan_btn = _button(actions, "Scan for Devices", _scan)
	_connect_btn = _button(actions, "Connect", _connect_selected)
	_disconnect_btn = _button(actions, "Disconnect", _disconnect_selected)
	_pair_btn = _button(actions, "Pair", _pair_selected)
	_remove_btn = _button(actions, "Forget", _remove_selected)
	_button(actions, "Refresh", _refresh_devices)

	section("Tips")
	var c3 := card()
	info_row(c3, "Pairing Mode", "Put headphones or a mouse in pairing mode before scanning.")
	info_row(c3, "Discoverable", "Only needed when another device connects to this computer.")
	info_row(c3, "Forget", "Removes the pairing; you will need to pair the device again.")

	_set_actions_enabled(false)
	defer(_refresh_devices)


func _button(parent: HBoxContainer, text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_press)
	parent.add_child(button)
	return button


func _service_active() -> bool:
	return Sh.run_capture("systemctl is-active bluetooth 2>/dev/null").strip_edges() == "active"


func _controller() -> String:
	var out := Sh.run_capture("bluetoothctl list 2>/dev/null")
	for raw in out.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("Controller "):
			var parts: PackedStringArray = line.split(" ", false)
			if parts.size() >= 2:
				return parts[1]
	return ""


func _show_field(key: String) -> String:
	var out := Sh.run_capture("bluetoothctl show 2>/dev/null")
	for raw in out.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with(key + ":"):
			return line.substr(key.length() + 1).strip_edges()
	return ""


func _powered() -> bool:
	return _show_field("Powered").to_lower() == "yes"


func _discoverable() -> bool:
	return _show_field("Discoverable").to_lower() == "yes"


func _start_service() -> void:
	notify("Starting Bluetooth…")
	run_async("pkexec systemctl enable --now bluetooth", func(code: int) -> void:
		if code == 0:
			notify("Bluetooth started. Open the Bluetooth page again.")
		else:
			notify("Could not start Bluetooth (exit code " + str(code) + ")."))


func _set_power(on: bool) -> void:
	var code := Sh.run_wait("bluetoothctl power " + ("on" if on else "off"))
	if code != 0:
		notify("Could not turn Bluetooth " + ("on" if on else "off") + ".")
		_power_toggle.set_pressed_no_signal(not on)
		return
	notify("Bluetooth " + ("on" if on else "off") + ".")
	if not on:
		_refresh_devices()


func _set_discoverable(on: bool) -> void:
	var code := Sh.run_wait("bluetoothctl discoverable " + ("on" if on else "off"))
	if code != 0:
		notify("Could not change discoverability.")
		_discoverable_toggle.set_pressed_no_signal(not on)


func _refresh_devices() -> void:
	if _list == null:
		return
	_list.clear()
	_devices.clear()
	_set_actions_enabled(false)

	var paired := _device_set("Paired")
	var connected := _device_set("Connected")
	for raw in Sh.run_capture("bluetoothctl devices 2>/dev/null").split("\n"):
		var line: String = raw.strip_edges()
		if not line.begins_with("Device "):
			continue
		var rest := line.substr(7).strip_edges()
		var space := rest.find(" ")
		var address := rest if space < 0 else rest.substr(0, space)
		var name := "Unknown device" if space < 0 else rest.substr(space + 1).strip_edges()
		if name.is_empty():
			name = "Unknown device"
		_devices.append({
			"address": address,
			"name": name,
			"paired": paired.has(address),
			"connected": connected.has(address),
		})

	_devices.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["name"]).to_lower() < str(b["name"]).to_lower())

	for i in _devices.size():
		var device: Dictionary = _devices[i]
		var mark := "●  " if bool(device["connected"]) else ("○  " if bool(device["paired"]) else "   ")
		var suffix := "  ·  connected" if bool(device["connected"]) else ("  ·  paired" if bool(device["paired"]) else "")
		_list.add_item(mark + str(device["name"]) + suffix)
		_list.set_item_metadata(_list.item_count - 1, i)

	_status.text = "%d device%s known" % [_devices.size(), "" if _devices.size() == 1 else "s"]
	if _devices.is_empty():
		_status.text = "No devices yet. Use “Scan for Devices” while the device is in pairing mode."
	if _power_toggle != null:
		_power_toggle.set_pressed_no_signal(_powered())
	if _discoverable_toggle != null:
		_discoverable_toggle.set_pressed_no_signal(_discoverable())


func _device_set(property: String) -> Dictionary:
	var set: Dictionary = {}
	for raw in Sh.run_capture("bluetoothctl devices " + property + " 2>/dev/null").split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("Device "):
			var parts: PackedStringArray = line.substr(7).strip_edges().split(" ", false)
			if parts.size() >= 1:
				set[parts[0]] = true
	return set


func _selected() -> Dictionary:
	var selected := _list.get_selected_items()
	if selected.is_empty():
		return {}
	var meta: Variant = _list.get_item_metadata(selected[0])
	if meta == null:
		return {}
	var index: int = int(meta)
	if index < 0 or index >= _devices.size():
		return {}
	return _devices[index]


func _on_selected(_idx: int) -> void:
	var device := _selected()
	if device.is_empty():
		_set_actions_enabled(false)
		return
	var paired := bool(device["paired"])
	var connected := bool(device["connected"])
	_connect_btn.disabled = connected
	_disconnect_btn.disabled = not connected
	_pair_btn.disabled = paired
	_remove_btn.disabled = not paired
	_scan_btn.disabled = false


func _set_actions_enabled(enabled: bool) -> void:
	_connect_btn.disabled = not enabled
	_disconnect_btn.disabled = not enabled
	_pair_btn.disabled = not enabled
	_remove_btn.disabled = not enabled


func _scan() -> void:
	if not _powered():
		notify("Turn Bluetooth on before scanning.")
		_power_toggle.set_pressed_no_signal(false)
		return
	_scan_btn.disabled = true
	_status.text = "Scanning for nearby devices…"
	notify("Scanning for about 12 seconds…")
	run_async_capture("bluetoothctl --timeout 12 scan on", func(_code: int, _text: String) -> void:
		_scan_btn.disabled = false
		_refresh_devices()
		notify("Scan finished. If your device did not appear, put it in pairing mode and try again."))


func _connect_selected() -> void:
	_device_command("connect", "Connected to ")


func _disconnect_selected() -> void:
	_device_command("disconnect", "Disconnected from ")


func _pair_selected() -> void:
	_device_command("pair", "Paired with ")


func _device_command(verb: String, done_text: String) -> void:
	var device := _selected()
	if device.is_empty():
		return
	var address: String = str(device["address"])
	_set_actions_enabled(false)
	_status.text = done_text + str(device["name"]) + "…"
	run_async_capture("bluetoothctl " + verb + " " + Sh.quote(address), func(code: int, text: String) -> void:
		if code == 0 and not text.to_lower().contains("failed"):
			notify(done_text + str(device["name"]) + ".")
		else:
			notify("Could not " + verb + " " + str(device["name"]) + ": " + _tail(text))
		_refresh_devices())


func _remove_selected() -> void:
	var device := _selected()
	if device.is_empty():
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Forget device?"
	dialog.dialog_text = "Remove the pairing for " + str(device["name"]) + "?\n\nYou will need to pair it again to use it."
	dialog.ok_button_text = "Forget"
	dialog.add_cancel_button("Cancel")
	dialog.confirmed.connect(func() -> void:
		var code := Sh.run_wait("bluetoothctl remove " + Sh.quote(str(device["address"])))
		if code == 0:
			notify("Forgot " + str(device["name"]) + ".")
		else:
			notify("Could not remove the device.")
		_refresh_devices())
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


func _tail(text: String) -> String:
	var lines: PackedStringArray = text.strip_edges().split("\n")
	var out: Array[String] = []
	for i in range(maxi(0, lines.size() - 3), lines.size()):
		var line: String = lines[i].strip_edges()
		if not line.is_empty():
			out.append(line)
	var joined := " ".join(out)
	return joined.substr(0, 240)
