extends SettingsPanel
# VPN Manager: Visual OpenVPN/WireGuard connection management.
# Stores configs in ~/.config/openvpn/ and uses nmcli for system VPNs.

var _vpn_list: ItemList
var _config_dir: String
var _connect_btn: Button
var _disconnect_btn: Button
var _remove_btn: Button
var _status_label: Label


func build() -> void:
	page_header("VPN Manager", "Connect to OpenVPN and WireGuard networks.")
	
	_config_dir = Sh.home() + "/.config/openvpn/"
	
	# Configs can embed credentials, so keep the directory private.
	if not Sh.dir_exists(_config_dir):
		DirAccess.make_dir_recursive_absolute(_config_dir)
		Sh.run_wait("chmod 700 " + Sh.quote(_config_dir))
	
	_build_ui()
	_refresh_list()


func _build_ui() -> void:
	var c := card()
	
	# Add VPN button
	var add_btn := Button.new()
	add_btn.text = "+ Add VPN Config"
	add_btn.pressed.connect(_on_add_vpn)
	c.add_child(add_btn)
	
	# VPN List
	_vpn_list = ItemList.new()
	_vpn_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vpn_list.custom_minimum_size = Vector2(0, 300)
	_vpn_list.item_selected.connect(_on_vpn_selected)
	c.add_child(_vpn_list)
	
	# Action buttons
	var actions := HBoxContainer.new()
	c.add_child(actions)
	
	var connect_btn := Button.new()
	connect_btn.text = "Connect"
	connect_btn.disabled = true
	connect_btn.name = "connect_btn"
	connect_btn.pressed.connect(_on_connect)
	actions.add_child(connect_btn)
	_connect_btn = connect_btn
	
	var disconnect_btn := Button.new()
	disconnect_btn.text = "Disconnect"
	disconnect_btn.disabled = true
	disconnect_btn.name = "disconnect_btn"
	disconnect_btn.pressed.connect(_on_disconnect)
	actions.add_child(disconnect_btn)
	_disconnect_btn = disconnect_btn
	
	var remove_btn := Button.new()
	remove_btn.text = "Remove"
	remove_btn.disabled = true
	remove_btn.name = "remove_btn"
	remove_btn.flat = true
	remove_btn.pressed.connect(_on_remove)
	actions.add_child(remove_btn)
	_remove_btn = remove_btn
	
	# Status label
	var status_label := Label.new()
	status_label.name = "status_label"
	status_label.text = "No VPN selected"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(status_label)
	_status_label = status_label


func _add_vpn_item(text: String, meta: Dictionary) -> void:
	_vpn_list.add_item(text)
	_vpn_list.set_item_metadata(_vpn_list.item_count - 1, meta)


# nmcli prints "NAME:TYPE:ACTIVE"; the name is the only field we need.
func _active_connections() -> Dictionary:
	var active: Dictionary = {}
	for line in Sh.run_lines("nmcli -t -f NAME,TYPE,ACTIVE con show 2>/dev/null"):
		var parts: PackedStringArray = line.split(":")
		if parts.size() >= 3 and parts[2].strip_edges() == "yes":
			active[parts[0].strip_edges()] = true
	return active


func _running_openvpn() -> String:
	return Sh.run_capture("pgrep -af 'openvpn --config' 2>/dev/null")


func _refresh_list() -> void:
	_vpn_list.clear()
	_set_actions_enabled(false)
	_status_label.text = "No VPN selected"

	var active := _active_connections()
	var running_ovpn := _running_openvpn()

	# OpenVPN configs
	for file in Sh.list_vpn_configs(_config_dir):
		var path: String = _config_dir + str(file)
		var is_up := running_ovpn.contains(path)
		var suffix := " (connected)" if is_up else ""
		_add_vpn_item("🔐 " + str(file) + suffix, {"type": "openvpn", "file": str(file), "active": is_up})

	# WireGuard configs (nmcli)
	for conn in Sh.run_lines("nmcli -t -f NAME,TYPE con show | grep wireguard | cut -d: -f1"):
		var stripped := conn.strip_edges()
		if not stripped.is_empty():
			var is_up: bool = active.has(stripped)
			_add_vpn_item("🔒 " + stripped + (" (connected)" if is_up else ""),
				{"type": "wireguard", "name": stripped, "active": is_up})

	# Other VPN types
	for conn in Sh.run_lines("nmcli -t -f NAME,TYPE con show | grep -E 'vpn|openvpn' | grep -v wireguard | cut -d: -f1"):
		var stripped := conn.strip_edges()
		if not stripped.is_empty():
			var is_up: bool = active.has(stripped)
			_add_vpn_item("🌐 " + stripped + (" (connected)" if is_up else ""),
				{"type": "nm", "name": stripped, "active": is_up})

	if _vpn_list.item_count == 0:
		_status_label.text = "No VPN profiles yet — use “Add VPN Config”."


func _set_actions_enabled(enabled: bool) -> void:
	_connect_btn.disabled = not enabled
	_disconnect_btn.disabled = not enabled
	_remove_btn.disabled = not enabled


func _on_vpn_selected(idx: int) -> void:
	if idx < 0:
		_set_actions_enabled(false)
		_status_label.text = "No VPN selected"
		return
	var item_data: Dictionary = _vpn_list.get_item_metadata(idx)
	var is_up: bool = bool(item_data.get("active", false))
	_connect_btn.disabled = is_up
	_disconnect_btn.disabled = not is_up
	_remove_btn.disabled = false
	_status_label.text = ("Connected: " if is_up else "Selected: ") + _vpn_list.get_item_text(idx)


func _on_add_vpn() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.title = "Select VPN Config File"
	dialog.filters = ["*.ovpn, *.conf ; VPN configs"]
	dialog.current_dir = Sh.home()
	dialog.file_selected.connect(_on_vpn_file_selected)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.file_selected.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


func _on_vpn_file_selected(path: String) -> void:
	var filename := path.get_file()
	# WireGuard .conf files have to go through NetworkManager; copying them to
	# ~/.config/openvpn would leave a profile that nothing can ever connect.
	if path.get_extension().to_lower() == "conf":
		if not Sh.has_tool("nmcli"):
			notify("NetworkManager (nmcli) is required to import WireGuard profiles.")
			return
		notify("Importing " + filename + "...")
		run_async("nmcli connection import type wireguard file " + Sh.quote(path), func(code: int) -> void:
			if code == 0:
				notify("WireGuard profile imported: " + filename)
			else:
				notify("Could not import " + filename + " (exit code " + str(code) + ").")
			_refresh_list())
		return

	var dest := _config_dir + filename
	if Sh.file_exists(dest):
		_confirm_overwrite(path, dest)
		return
	_copy_config(path, dest)


func _confirm_overwrite(source: String, dest: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Replace existing config?"
	dialog.text = dest.get_file() + " already exists.\n\nReplace it with the selected file?"
	dialog.ok_text = "Replace"
	dialog.add_cancel_button("Cancel")
	dialog.confirmed.connect(func() -> void: _copy_config(source, dest))
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


func _copy_config(source: String, dest: String) -> void:
	# 0600: OpenVPN configs often contain inline credentials.
	var command := "install -m 600 " + Sh.quote(source) + " " + Sh.quote(dest)
	var code := Sh.run_wait(command)
	if code == 0:
		notify("VPN config added: " + dest.get_file())
	else:
		notify("Could not copy " + source.get_file() + " (exit code " + str(code) + ").")
	_refresh_list()


func _on_connect() -> void:
	var idx := _vpn_list.get_selected_items()
	if idx.is_empty():
		return
	
	var idx_val: int = idx[0]
	var item_data: Dictionary = _vpn_list.get_item_metadata(idx_val)
	var name := _vpn_list.get_item_text(idx_val)

	notify("Connecting to " + name + "...")
	_set_actions_enabled(false)

	var kind := str(item_data.get("type", ""))
	var command := ""
	if kind == "openvpn":
		command = "pkexec openvpn --config " + Sh.quote(_config_dir + str(item_data.get("file", ""))) + " --daemon"
	elif kind == "wireguard" or kind == "nm":
		command = "nmcli con up " + Sh.quote(str(item_data.get("name", "")))
	if command.is_empty():
		notify("Unknown VPN type.")
		_refresh_list()
		return

	run_async(command, func(code: int) -> void:
		if code == 0:
			notify("Connected to " + name)
		else:
			notify("Failed to connect to " + name + " (exit code " + str(code) + ").")
		_refresh_list())


func _on_disconnect() -> void:
	var idx := _vpn_list.get_selected_items()
	if idx.is_empty():
		return
	
	var idx_val: int = idx[0]
	var item_data: Dictionary = _vpn_list.get_item_metadata(idx_val)
	var name := _vpn_list.get_item_text(idx_val)

	notify("Disconnecting " + name + "...")
	_set_actions_enabled(false)

	var kind := str(item_data.get("type", ""))
	var command := ""
	if kind == "openvpn":
		command = "pkexec pkill -f 'openvpn --config'"
	elif kind == "wireguard" or kind == "nm":
		command = "nmcli con down " + Sh.quote(str(item_data.get("name", "")))
	if command.is_empty():
		notify("Unknown VPN type.")
		_refresh_list()
		return

	run_async(command, func(code: int) -> void:
		# pkill exits 1 when no process matched, which still means "not connected".
		if code == 0 or kind == "openvpn":
			notify("Disconnected " + name)
		else:
			notify("Failed to disconnect " + name + " (exit code " + str(code) + ").")
		_refresh_list())


func _on_remove() -> void:
	var idx := _vpn_list.get_selected_items()
	if idx.is_empty():
		return
	
	var idx_val: int = idx[0]
	var item_data: Dictionary = _vpn_list.get_item_metadata(idx_val)
	var name := _vpn_list.get_item_text(idx_val)

	var dialog := ConfirmationDialog.new()
	dialog.title = "Remove VPN?"
	dialog.text = "Remove " + name + " from the list?\n\nConfig files will be deleted."
	dialog.ok_text = "Remove"
	dialog.add_cancel_button("Cancel")
	dialog.confirmed.connect(func() -> void:
		var kind := str(item_data.get("type", ""))
		var code := 0
		if kind == "openvpn":
			code = Sh.run_wait("rm -f " + Sh.quote(_config_dir + str(item_data.get("file", ""))))
		elif kind == "wireguard" or kind == "nm":
			code = Sh.run_wait("nmcli con delete " + Sh.quote(str(item_data.get("name", ""))))
		if code == 0:
			notify("Removed " + name)
		else:
			notify("Could not remove " + name + " (exit code " + str(code) + ").")
		_refresh_list())
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)