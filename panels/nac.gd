extends SettingsPanel
# Networks & Connections: native device status via nmcli, VPN, Proxy, Hotspot.
# Complex config delegated to KCMs.

var _status_card: VBoxContainer
var _bt_check: CheckButton = null
var _proxy_host: LineEdit
var _proxy_port: LineEdit
var _proxy_mode: OptionButton


func build() -> void:
	page_header("Networks & Connections", "Wi-Fi, Ethernet, Bluetooth, VPN, Proxy, and Hotspot.")
	_build_static()
	defer(_populate_status)


func _build_static() -> void:
	section("Status")
	var c := card()
	_status_card = c
	
	section("Wi-Fi & Ethernet")
	c = card()
	action_row(c, "Network Connections", "Connect to or edit Wi-Fi/Ethernet profiles.", "N", "Manage", func() -> void:
		_open_network())
	kcm_row(c, "Network Connections (Advanced)", "Full NetworkManager editor.", "N", "kcm_networkmanagement")
	kcm_row(c, "Network Preferences", "Generic network preferences.", "P", "kcm_netpref")
	
	# VPN Section
	section("VPN")
	c = card()
	action_row(c, "VPN Manager", "Manage OpenVPN and WireGuard connections.", "V", "Open VPN Manager", func() -> void:
		_open_page("vpn_manager")
	)
	kcm_row(c, "VPN Settings (KDE)", "Configure VPN via KDE.", "V", "kcm_vpn")
	
	# Proxy Section
	section("Proxy")
	c = card()
	
	# Load current proxy settings
	var proxy := Sh.get_system_proxy()
	
	_proxy_mode = OptionButton.new()
	_proxy_mode.add_item("None")
	_proxy_mode.add_item("Manual")
	_proxy_mode.add_item("Auto (PAC)")
	_proxy_mode.selected = 0 if proxy["mode"] == "none" else (1 if proxy["mode"] == "manual" else 2)
	
	_proxy_host = LineEdit.new()
	_proxy_host.placeholder_text = "proxy.example.com"
	_proxy_host.text = proxy["host"]
	_proxy_host.visible = _proxy_mode.selected == 1
	
	_proxy_port = LineEdit.new()
	_proxy_port.placeholder_text = "8080"
	_proxy_port.text = proxy["port"]
	_proxy_port.visible = _proxy_mode.selected == 1
	
	_proxy_mode.item_selected.connect(_on_proxy_mode_changed)
	
	# A grid keeps the fields aligned and lets the host field grow instead of
	# squeezing three controls into one unreadable row.
	var proxy_grid := GridContainer.new()
	proxy_grid.columns = 2
	proxy_grid.add_theme_constant_override("h_separation", 12)
	proxy_grid.add_theme_constant_override("v_separation", 6)
	_proxy_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_proxy_port.custom_minimum_size = Vector2(90, 0)
	for entry in [
		["Mode:", _proxy_mode],
		["Host:", _proxy_host],
		["Port:", _proxy_port],
	]:
		var key := Label.new()
		key.text = str(entry[0])
		proxy_grid.add_child(key)
		proxy_grid.add_child(entry[1])
	c.add_child(proxy_grid)
	
	action_row(c, "Apply Proxy", "Save proxy settings system-wide.", "A", "Apply", func() -> void:
		_apply_proxy()
	)
	
	# Hotspot Section
	section("WiFi Hotspot")
	c = card()
	action_row(c, "Create Hotspot", "Turn this device into a WiFi access point.", "H", "Create", func() -> void:
		_create_hotspot()
	)
	action_row(c, "Stop Hotspot", "Disable the WiFi hotspot.", "H", "Stop", func() -> void:
		_stop_hotspot()
	)
	
	# Bluetooth
	section("Bluetooth")
	c = card()
	_bt_check = toggle_row(c, "Bluetooth", "Enable or disable Bluetooth radio.", "B", _is_bluetooth_on(),
		func(on: bool) -> void:
			_set_bluetooth(on))
	kcm_row(c, "Bluetooth Devices", "Pair and manage Bluetooth devices.", "D", "kcm_bluetooth")
	kcm_row(c, "KDE Connect", "Link your phone and other devices.", "K", "kcm_kdeconnect")
	
	# Sharing
	section("Sharing")
	c = card()
	kcm_row(c, "Samba", "Windows file sharing status.", "S", "kcm_samba")
	kcm_row(c, "Web Shortcuts", "Search keywords for web services.", "U", "kcm_webshortcuts")


func _open_page(page_name: String) -> void:
	var menu: Node = get_tree().root.find_child("menu-buttons", true, false)
	if menu and menu.has_method("virtual_press_button"):
		menu.virtual_press_button(page_name)


func _on_proxy_mode_changed(idx: int) -> void:
	var manual: bool = idx == 1
	_proxy_host.visible = manual
	_proxy_port.visible = manual


func _apply_proxy() -> void:
	var mode_map: Array[String] = ["none", "manual", "auto"]
	var mode: String = mode_map[_proxy_mode.selected]
	var host := _proxy_host.text.strip_edges()
	var port := _proxy_port.text.strip_edges()
	
	Sh.set_system_proxy(mode, host, port)
	notify("Proxy settings applied.")


func _create_hotspot() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Create WiFi Hotspot"
	dialog.text = "This will create a hotspot using your WiFi adapter.\n\nEnter SSID and Password:"
	dialog.ok_text = "Create"
	dialog.add_cancel_button("Cancel")
	
	var ssid_edit := LineEdit.new()
	ssid_edit.placeholder_text = "Kainat-Hotspot"
	ssid_edit.text = "Kainat-" + str(int(Time.get_unix_time_from_system()) % 10000)
	
	var pass_edit := LineEdit.new()
	pass_edit.placeholder_text = "Minimum 8 characters"
	pass_edit.text = _random_password()
	pass_edit.secret = true
	
	var vbox := VBoxContainer.new()
	var ssid_label := Label.new()
	ssid_label.text = "SSID:"
	vbox.add_child(ssid_label)
	vbox.add_child(ssid_edit)
	var pass_label := Label.new()
	pass_label.text = "Password:"
	vbox.add_child(pass_label)
	vbox.add_child(pass_edit)
	dialog.add_child(vbox)

	dialog.confirmed.connect(func() -> void:
		var ssid := ssid_edit.text.strip_edges()
		var password := pass_edit.text.strip_edges()

		if ssid.is_empty() or password.length() < 8:
			notify("SSID required, password must be 8+ chars")
			return

		notify("Creating hotspot...")
		var code := Sh.create_wifi_hotspot(ssid, password)
		if code == 0:
			notify("Hotspot created: " + ssid)
		else:
			notify("Failed to create hotspot. Is WiFi available?"))
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


func _stop_hotspot() -> void:
	notify("Stopping hotspot...")
	var code := Sh.stop_wifi_hotspot()
	if code == 0:
		notify("Hotspot stopped.")
	else:
		notify("Failed to stop hotspot.")


# Hotspot passwords must be 8+ chars and easy to read out loud: no ambiguous
# characters (0/O, 1/l/I) since the user types this on a phone.
func _random_password() -> String:
	const ALPHABET := "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var out := ""
	for _i in 12:
		out += ALPHABET[randi() % ALPHABET.length()]
	return out


func _nmcli_available() -> bool:
	return Sh.has_tool("nmcli")


func _populate_status() -> void:
	var c: VBoxContainer = _status_card
	if not _nmcli_available():
		unavailable_row(c, "Network manager", "NetworkManager (nmcli) is not installed")
		return
	var devices: PackedStringArray = Sh.run_lines("nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device 2>/dev/null")
	if devices.is_empty():
		unavailable_row(c, "Network", "No devices reported")
		return
	for line in devices:
		# nmcli escapes ':' inside values; splitting with a limit keeps a
		# connection name that contains a colon intact in the last field.
		var parts: PackedStringArray = line.split(":", true, 4)
		if parts.size() >= 3:
			var label: String = "%s (%s)" % [parts[0], parts[1]]
			var state: String = parts[2]
			if parts.size() >= 4 and not parts[3].is_empty():
				state += " -> " + parts[3]
			info_row(c, label, state)


func _open_network() -> void:
	for tool in ["plasma-nm", "nm-connection-editor"]:
		if Sh.has_tool(tool):
			Sh.launch(tool)
			return
	if Sh.has_tool("systemsettings"):
		Sh.open_kcm("kcm_networkmanagement")
		return
	Sh._notify_missing("plasma-nm", "Network configuration", notify)


func _set_bluetooth(on: bool) -> void:
	if not Sh.has_tool("bluetoothctl"):
		notify("Bluetooth tools are not installed.")
		if _bt_check != null and is_instance_valid(_bt_check):
			_bt_check.set_pressed_no_signal(_is_bluetooth_on())
		return
	var code := Sh.run_wait("bluetoothctl power " + ("on" if on else "off") + " 2>/dev/null")
	if code == 0:
		notify("Bluetooth " + ("enabled" if on else "disabled"))
		return
	notify("Could not change the Bluetooth power state.")
	if _bt_check != null and is_instance_valid(_bt_check):
		_bt_check.set_pressed_no_signal(_is_bluetooth_on())


func _is_bluetooth_on() -> bool:
	var out := Sh.run_capture("bluetoothctl show 2>/dev/null")
	return out.contains("Powered: yes")