extends SettingsPanel
# VPN Manager: Visual OpenVPN/WireGuard connection management.
# Stores configs in ~/.config/openvpn/ and uses nmcli for system VPNs.

var _vpn_list: ItemList
var _config_dir: String


func build() -> void:
	page_header("VPN Manager", "Connect to OpenVPN and WireGuard networks.")
	
	_config_dir = Sh.home() + "/.config/openvpn/"
	
	# Ensure config dir exists
	if not Sh.dir_exists(_config_dir):
		DirAccess.make_dir_recursive_absolute(_config_dir)
	
	_build_ui()
	_refresh_list()


func _build_ui() -> void:
	var c := card()
	
	# Add VPN button
	var add_btn := Button.new()
	add_btn.text = "+ Add VPN Config"
	add_btn.icon = theme.get_icon("Add", "EditorIcons") if theme.has_icon("Add", "EditorIcons") else null
	add_btn.pressed.connect(_on_add_vpn)
	c.add_child(add_btn)
	
	# VPN List
	_vpn_list = ItemList.new()
	_vpn_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vpn_list.custom_minimum_height = 300
	_vpn_list.item_selected.connect(_on_vpn_selected)
	c.add_child(_vpn_list)
	
	# Action buttons
	var actions := HBoxContainer.new()
	c.add_child(actions)
	
	var connect_btn := Button.new()
	connect_btn.text = "Connect"
	connect_btn.icon = theme.get_icon("Play", "EditorIcons") if theme.has_icon("Play", "EditorIcons") else null
	connect_btn.disabled = true
	connect_btn.name = "connect_btn"
	connect_btn.pressed.connect(_on_connect)
	actions.add_child(connect_btn)
	
	var disconnect_btn := Button.new()
	disconnect_btn.text = "Disconnect"
	disconnect_btn.icon = theme.get_icon("Stop", "EditorIcons") if theme.has_icon("Stop", "EditorIcons") else null
	disconnect_btn.disabled = true
	disconnect_btn.name = "disconnect_btn"
	disconnect_btn.pressed.connect(_on_disconnect)
	actions.add_child(disconnect_btn)
	
	var remove_btn := Button.new()
	remove_btn.text = "Remove"
	remove_btn.icon = theme.get_icon("Remove", "EditorIcons") if theme.has_icon("Remove", "EditorIcons") else null
	remove_btn.disabled = true
	remove_btn.name = "remove_btn"
	remove_btn.flat = true
	remove_btn.pressed.connect(_on_remove)
	actions.add_child(remove_btn)
	
	# Status label
	var status_label := Label.new()
	status_label.name = "status_label"
	status_label.text = "No VPN selected"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(status_label)


func _refresh_list() -> void:
	_vpn_list.clear()
	
	# OpenVPN configs
	var ovpn_files := Sh.list_vpn_configs(_config_dir)
	for file in ovpn_files:
		_vpn_list.add_item("🔐 " + file, {"type": "openvpn", "file": file})
	
	# WireGuard configs (nmcli)
	var wg_conns := Sh.run_lines("nmcli -t -f NAME,TYPE con show | grep wireguard | cut -d: -f1")
	for conn in wg_conns:
		var stripped := conn.strip_edges()
		if not stripped.is_empty():
			_vpn_list.add_item("🔒 " + stripped, {"type": "wireguard", "name": stripped})
	
	# Other VPN types
	var other_conns := Sh.run_lines("nmcli -t -f NAME,TYPE con show | grep -E 'vpn|openvpn' | grep -v wireguard | cut -d: -f1")
	for conn in other_conns:
		var stripped := conn.strip_edges()
		if not stripped.is_empty():
			_vpn_list.add_item("🌐 " + stripped, {"type": "nm", "name": stripped})


func _on_vpn_selected(idx: int) -> void:
	var connect_btn := content.find_child("connect_btn", true, false)
	var disconnect_btn := content.find_child("disconnect_btn", true, false)
	var remove_btn := content.find_child("remove_btn", true, false)
	var status_label := content.find_child("status_label", true, false)
	
	if idx >= 0:
		connect_btn.disabled = false
		disconnect_btn.disabled = false
		remove_btn.disabled = false
		var item_data := _vpn_list.get_item_metadata(idx)
		status_label.text = "Selected: " + _vpn_list.get_item_text(idx)
	else:
		connect_btn.disabled = true
		disconnect_btn.disabled = true
		remove_btn.disabled = true
		status_label.text = "No VPN selected"


func _on_add_vpn() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.title = "Select VPN Config File"
	dialog.filters = ["*.ovpn", "*.conf", "*.conf"]
	dialog.current_dir = Sh.home()
	dialog.file_selected.connect(_on_vpn_file_selected)
	dialog.popup_centered()


func _on_vpn_file_selected(path: String) -> void:
	# Copy to config dir
	var dest := _config_dir + path.get_file()
	Sh.run_wait("cp " + Sh.quote(path) + " " + Sh.quote(dest))
	notify("VPN config added: " + path.get_file())
	_refresh_list()


func _on_connect() -> void:
	var idx := _vpn_list.get_selected_items()
	if idx.is_empty():
		return
	
	var idx_val := idx[0]
	var item_data := _vpn_list.get_item_metadata(idx_val)
	var name := _vpn_list.get_item_text(idx_val)
	
	notify("Connecting to " + name + "...")
	
	var code: int
	if item_data["type"] == "openvpn":
		var config_path := _config_dir + item_data["file"]
		code = Sh.start_openvpn(config_path)
	elif item_data["type"] == "wireguard" or item_data["type"] == "nm":
		code = Sh.run_wait("nmcli con up " + Sh.quote(item_data["name"]))
	
	if code == 0:
		notify("Connected to " + name)
		_refresh_list()
	else:
		notify("Failed to connect to " + name)


func _on_disconnect() -> void:
	var idx := _vpn_list.get_selected_items()
	if idx.is_empty():
		return
	
	var idx_val := idx[0]
	var item_data := _vpn_list.get_item_metadata(idx_val)
	var name := _vpn_list.get_item_text(idx_val)
	
	notify("Disconnecting " + name + "...")
	
	var code: int
	if item_data["type"] == "openvpn":
		Sh.stop_openvpn()
		code = 0
	elif item_data["type"] == "wireguard" or item_data["type"] == "nm":
		code = Sh.run_wait("nmcli con down " + Sh.quote(item_data["name"]))
	
	if code == 0:
		notify("Disconnected " + name)
	else:
		notify("Failed to disconnect " + name)


func _on_remove() -> void:
	var idx := _vpn_list.get_selected_items()
	if idx.is_empty():
		return
	
	var idx_val := idx[0]
	var item_data := _vpn_list.get_item_metadata(idx_val)
	var name := _vpn_list.get_item_text(idx_val)
	
	var dialog := AcceptDialog.new()
	dialog.title = "Remove VPN?"
	dialog.text = "Remove " + name + " from the list?\n\nConfig files will be deleted."
	dialog.ok_text = "Remove"
	if dialog.popup() == OK:
		if item_data["type"] == "openvpn":
			Sh.run("rm " + Sh.quote(_config_dir + item_data["file"]))
		elif item_data["type"] == "wireguard" or item_data["type"] == "nm":
			Sh.run_wait("nmcli con delete " + Sh.quote(item_data["name"]))
		notify("Removed " + name)
		_refresh_list()