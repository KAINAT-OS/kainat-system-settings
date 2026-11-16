extends SettingsPanel
# Networks & Connections: native device status via nmcli, VPN, Proxy, Hotspot.
# Complex config delegated to KCMs.

var _status_card: VBoxContainer
var _bt_check: CheckButton = null
var _proxy_host: LineEdit
var _proxy_port: LineEdit
var _proxy_script: LineEdit
var _proxy_mode: OptionButton
var _wifi_card: VBoxContainer = null
# Row count of the card before the first scan result lands; everything above it
# (the scan row) survives a rescan.
var _wifi_fixed_rows: int = 0


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
	var wifi_check: CheckButton = null
	wifi_check = toggle_row(c, "Wi-Fi", "Enable or disable the Wi-Fi radio.", "W", _wifi_enabled(),
		func(on: bool) -> void:
			_set_wifi(on, wifi_check))
	if not _nmcli_available():
		wifi_check.disabled = true
	action_row(c, "Network Connections", "Connect to or edit Wi-Fi/Ethernet profiles.", "N", "Manage", func() -> void:
		_open_network())
	kcm_row(c, "Network Connections (Advanced)", "Full NetworkManager editor.", "N", "kcm_networkmanagement")
	kcm_row(c, "Network Preferences", "Generic network preferences.", "P", "kcm_netpref")

	# Joining a network belongs on this page: it owns the radio switch, and an
	# app that can turn Wi-Fi on but not join anything leaves the user to a
	# terminal, which this program does not allow.
	section("Wi-Fi Networks")
	_wifi_card = card()
	action_row(_wifi_card, "Scan for Networks", "Look for Wi-Fi networks in range.", "S",
		"Scan", _scan_wifi)
	_wifi_fixed_rows = _wifi_card.get_child_count()
	defer(_populate_wifi)
	
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

	_proxy_script = LineEdit.new()
	_proxy_script.placeholder_text = "http://example.com/proxy.pac"
	_proxy_script.text = str(proxy.get("script", ""))
	_proxy_script.visible = _proxy_mode.selected == 2

	_proxy_mode.item_selected.connect(_on_proxy_mode_changed)

	# A grid keeps the fields aligned and lets the host field grow instead of
	# squeezing three controls into one unreadable row.
	var proxy_grid := GridContainer.new()
	proxy_grid.columns = 2
	proxy_grid.add_theme_constant_override("h_separation", 12)
	proxy_grid.add_theme_constant_override("v_separation", 6)
	_proxy_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_proxy_port.custom_minimum_size = Vector2(90, 0)
	_proxy_script.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for entry in [
		["Mode:", _proxy_mode],
		["Host:", _proxy_host],
		["Port:", _proxy_port],
		["PAC URL:", _proxy_script],
	]:
		var key := Label.new()
		key.text = str(entry[0])
		var field := entry[1] as Control
		proxy_grid.add_child(key)
		proxy_grid.add_child(field)
		# A GridContainer skips an invisible child, so a caption left visible
		# while its field is hidden shifts every following cell one column left
		# and the labels end up over the wrong controls. They hide together.
		field.visibility_changed.connect(func() -> void:
			key.visible = field.visible)
		key.visible = field.visible
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
	kcm_row(c, "Samba", "Windows file sharing status.", "S", "kcm_smb")
	kcm_row(c, "Web Shortcuts", "Search keywords for web services.", "U", "kcm_webshortcuts")


func _open_page(page_name: String) -> void:
	var menu: Node = get_tree().root.find_child("menu-buttons", true, false)
	if menu and menu.has_method("virtual_press_button"):
		menu.virtual_press_button(page_name)


func _on_proxy_mode_changed(idx: int) -> void:
	var manual: bool = idx == 1
	var auto: bool = idx == 2
	_proxy_host.visible = manual
	_proxy_port.visible = manual
	_proxy_script.visible = auto


func _apply_proxy() -> void:
	var mode_map: Array[String] = ["none", "manual", "auto"]
	var mode: String = mode_map[_proxy_mode.selected]
	var host := _proxy_host.text.strip_edges()
	var port := _proxy_port.text.strip_edges()
	var script := _proxy_script.text.strip_edges()

	if mode == "manual":
		if host.is_empty():
			notify("Enter the proxy host, or choose None.")
			return
		if not port.is_empty() and not port.is_valid_int():
			notify("The proxy port must be a number.")
			return
		if port.is_empty():
			port = "8080"
	elif mode == "auto" and script.is_empty():
		notify("Enter the URL of the proxy auto-configuration (PAC) file.")
		return

	Sh.set_system_proxy(mode, host, port, script)
	notify("Proxy settings applied.")


func _create_hotspot() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Create WiFi Hotspot"
	dialog.ok_button_text = "Create"
	dialog.add_cancel_button("Cancel")

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(420, 0)
	vbox.add_theme_constant_override("separation", 6)
	dialog.add_child(vbox)

	var intro := Label.new()
	intro.text = "Share this computer's connection over Wi-Fi."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(intro)

	var ssid_label := Label.new()
	ssid_label.text = "Network name (SSID):"
	vbox.add_child(ssid_label)

	var ssid_edit := LineEdit.new()
	ssid_edit.placeholder_text = "Kainat-Hotspot"
	ssid_edit.text = "Kainat-" + str(int(Time.get_unix_time_from_system()) % 10000)
	vbox.add_child(ssid_edit)

	var pass_label := Label.new()
	pass_label.text = "Password (at least 8 characters):"
	vbox.add_child(pass_label)

	var pass_edit := LineEdit.new()
	pass_edit.placeholder_text = "Minimum 8 characters"
	pass_edit.text = _random_password()
	pass_edit.secret = true
	vbox.add_child(pass_edit)

	dialog.confirmed.connect(func() -> void:
		var ssid := ssid_edit.text.strip_edges()
		var password := pass_edit.text
		if ssid.is_empty():
			notify("Enter a network name.")
			return
		if password.length() < 8:
			notify("The hotspot password must be at least 8 characters.")
			return

		notify("Creating hotspot “" + ssid + "”…")
		run_async(Sh.create_wifi_hotspot_command(ssid, password), func(code: int) -> void:
			if code == 0:
				notify("Hotspot “" + ssid + "” is now broadcasting.")
			else:
				notify("Could not create the hotspot. Check that Wi-Fi is enabled and not in use.")))
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


func _stop_hotspot() -> void:
	notify("Stopping hotspot…")
	run_async(Sh.stop_wifi_hotspot_command(), func(code: int) -> void:
		notify("Hotspot stopped." if code == 0 else "No hotspot is currently running."))


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
		if parts.size() < 3:
			continue
		var device: String = parts[0]
		# nmcli reports device types and states as protocol words ("enp3s0",
		# "connected (externally)"); the row shows what a person would call them
		# and keeps the interface name, which is the only handle that is stable
		# between sessions.
		var value: String = _state_label(parts[2])
		# A connection named after its own device says nothing new, so only a
		# genuinely different profile name is worth the extra words.
		if parts.size() >= 4 and not parts[3].is_empty() and parts[3] != device:
			value += " · " + parts[3]
		info_row(c, "%s (%s)" % [_device_kind(parts[1]), device], value)


# nmcli device types as the words used in the rest of this app. Unknown types
# are capitalised rather than dropped: a new NetworkManager type must still show.
const _DEVICE_KINDS := {
	"ethernet": "Ethernet",
	"wifi": "Wi-Fi",
	"wifi-p2p": "Wi-Fi Direct",
	"wwan": "Mobile broadband",
	"gsm": "Mobile broadband",
	"cdma": "Mobile broadband",
	"bluetooth": "Bluetooth",
	"loopback": "Loopback",
	"tun": "VPN tunnel",
	"tap": "VPN tunnel",
	"wireguard": "WireGuard",
	"bridge": "Bridge",
	"bond": "Bonded link",
	"team": "Bonded link",
	"vlan": "VLAN",
	"dummy": "Virtual",
	"veth": "Virtual",
	"macvlan": "Virtual",
	"ipvlan": "Virtual",
	"vxlan": "Virtual",
}

const _STATE_LABELS := {
	"connected": "Connected",
	"disconnected": "Disconnected",
	"unavailable": "Unavailable",
	"unmanaged": "Not managed",
	"connecting": "Connecting",
	"disconnecting": "Disconnecting",
	"deactivating": "Disconnecting",
	"failed": "Failed",
	"unknown": "Unknown",
}


func _device_kind(kind: String) -> String:
	var key := kind.strip_edges().to_lower()
	if _DEVICE_KINDS.has(key):
		return str(_DEVICE_KINDS[key])
	return key.capitalize() if not key.is_empty() else "Device"


# "connected (externally)" -> "Connected (externally)". Only the state word is an
# enum; the parenthesised part is already written for people, so it is kept.
func _state_label(state: String) -> String:
	var text := state.strip_edges()
	var detail := ""
	var open: int = text.find("(")
	if open > 0:
		detail = text.substr(open)
		text = text.substr(0, open).strip_edges()
	var key := text.to_lower()
	var label: String = str(_STATE_LABELS[key]) if _STATE_LABELS.has(key) else text.capitalize()
	if label.is_empty():
		label = "Unknown"
	return label if detail.is_empty() else label + " " + detail


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


func _wifi_enabled() -> bool:
	if not _nmcli_available():
		return false
	return Sh.run_capture("nmcli radio wifi 2>/dev/null").strip_edges() == "enabled"


func _set_wifi(on: bool, check: CheckButton) -> void:
	if not _nmcli_available():
		notify("NetworkManager tools are not installed.")
		if check != null and is_instance_valid(check):
			check.set_pressed_no_signal(_wifi_enabled())
		return
	var code := Sh.run_wait("nmcli radio wifi " + ("on" if on else "off") + " 2>/dev/null")
	if code == 0:
		notify("Wi-Fi " + ("enabled" if on else "disabled"))
		_populate_wifi()
		return
	notify("Could not change the Wi-Fi radio state.")
	if check != null and is_instance_valid(check):
		check.set_pressed_no_signal(_wifi_enabled())


# --- Wi-Fi networks ---------------------------------------------------------

# The interface name of the first wireless adapter, or "" when the machine has
# none (an Ethernet-only desktop).
func _wifi_device() -> String:
	for line in Sh.run_lines("nmcli -t -f DEVICE,TYPE device 2>/dev/null"):
		var parts: PackedStringArray = line.split(":", true, 1)
		if parts.size() == 2 and parts[1].strip_edges() == "wifi":
			return parts[0].strip_edges()
	return ""


# One line per access point. nmcli escapes ':' inside values, so the line is
# split on every colon and the SSID rebuilt from the middle: the in-use marker
# is always first, signal and security always last.
func _wifi_networks() -> Array:
	var raw: PackedStringArray = Sh.run_lines(
		"nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list 2>/dev/null")
	var best: Dictionary = {}
	for line in raw:
		var fields: PackedStringArray = line.split(":")
		if fields.size() < 4:
			continue
		var signal_text: String = fields[fields.size() - 2].strip_edges()
		# The header line of the listing has the word SIGNAL in this column.
		if not signal_text.is_valid_int():
			continue
		var security: String = fields[fields.size() - 1].strip_edges()
		var name := PackedStringArray()
		for i in range(1, fields.size() - 2):
			name.append(fields[i])
		var ssid: String = _unescape_terse(":".join(name)).strip_edges()
		# A hidden access point broadcasts no name; it can only be joined by
		# typing the name, which the "Join Other Network" row covers.
		if ssid.is_empty():
			continue
		var strength: int = clampi(signal_text.to_int(), 0, 100)
		var connected: bool = fields[0].strip_edges() == "*"
		if not best.has(ssid):
			best[ssid] = {
				"ssid": ssid, "signal": strength,
				"security": security, "connected": connected,
			}
			continue
		# Several access points can broadcast the same name: the row keeps the
		# strongest one and remembers that one of them is the live link.
		var previous: Dictionary = best[ssid]
		connected = connected or bool(previous["connected"])
		if strength <= int(previous["signal"]):
			previous["connected"] = connected
			continue
		best[ssid] = {
			"ssid": ssid, "signal": strength,
			"security": security, "connected": connected,
		}
	var networks: Array = best.values()
	networks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["signal"]) > int(b["signal"]))
	return networks


# nmcli terse mode escapes the field separator, so a network called "Cafe:Guest"
# arrives as "Cafe\:Guest" and has to be unescaped before it is shown or joined.
func _unescape_terse(value: String) -> String:
	var out := ""
	var i := 0
	while i < value.length():
		if value[i] == "\\" and i + 1 < value.length():
			out += value[i + 1]
			i += 2
			continue
		out += value[i]
		i += 1
	return out


# A bare percentage says nothing to someone picking a network out of a list.
func _signal_label(strength: int) -> String:
	var quality := "Weak"
	if strength >= 75:
		quality = "Excellent"
	elif strength >= 50:
		quality = "Good"
	elif strength >= 25:
		quality = "Fair"
	return "%s signal (%d%%)" % [quality, strength]


func _security_label(security: String) -> String:
	if security.is_empty() or security == "--":
		return "Open network"
	return "Secured (" + security + ")"


func _wifi_row(c: VBoxContainer, network: Dictionary) -> void:
	var ssid: String = str(network["ssid"])
	var security: String = str(network["security"])
	var details := PackedStringArray([
		_signal_label(int(network["signal"])),
		_security_label(security),
	])
	if bool(network["connected"]):
		# The link is already up, so there is nothing to press.
		details.append("Connected")
		info_row(c, ssid, " · ".join(details))
		return
	action_row(c, ssid, " · ".join(details), "W", "Connect", func() -> void:
		_join_wifi(ssid, security))


func _join_wifi(ssid: String, security: String) -> void:
	if security.is_empty() or security == "--":
		_connect_wifi(ssid, "")
		return
	# A password is the one thing that cannot be a row, so it is asked for in a
	# dialog. Nothing is sent until the dialog is confirmed.
	var dialog := ConfirmationDialog.new()
	dialog.title = "Join " + ssid
	dialog.ok_button_text = "Connect"
	dialog.add_cancel_button("Cancel")

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(380, 0)
	vbox.add_theme_constant_override("separation", 6)
	dialog.add_child(vbox)

	var intro := Label.new()
	intro.text = "Enter the password for “" + ssid + "”."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(intro)

	var pass_edit := LineEdit.new()
	pass_edit.secret = true
	pass_edit.placeholder_text = "Network password"
	vbox.add_child(pass_edit)

	var show := CheckBox.new()
	show.text = "Show password"
	show.toggled.connect(func(on: bool) -> void:
		pass_edit.secret = not on)
	vbox.add_child(show)

	dialog.confirmed.connect(func() -> void:
		var password := pass_edit.text
		if password.is_empty():
			notify("Enter the network password, or cancel.")
			return
		_connect_wifi(ssid, password))
	_open_dialog(dialog)
	pass_edit.grab_focus()


# A hidden network has no entry in the scan, so its name and password are typed.
func _join_hidden_wifi() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Join Other Network"
	dialog.ok_button_text = "Connect"
	dialog.add_cancel_button("Cancel")

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(380, 0)
	vbox.add_theme_constant_override("separation", 6)
	dialog.add_child(vbox)

	var ssid_label := Label.new()
	ssid_label.text = "Network name (SSID):"
	vbox.add_child(ssid_label)

	var ssid_edit := LineEdit.new()
	ssid_edit.placeholder_text = "Network name"
	vbox.add_child(ssid_edit)

	var pass_label := Label.new()
	pass_label.text = "Password (leave empty for an open network):"
	vbox.add_child(pass_label)

	var pass_edit := LineEdit.new()
	pass_edit.secret = true
	pass_edit.placeholder_text = "Network password"
	vbox.add_child(pass_edit)

	var show := CheckBox.new()
	show.text = "Show password"
	show.toggled.connect(func(on: bool) -> void:
		pass_edit.secret = not on)
	vbox.add_child(show)

	dialog.confirmed.connect(func() -> void:
		var ssid := ssid_edit.text.strip_edges()
		if ssid.is_empty():
			notify("Enter the network name.")
			return
		_connect_wifi(ssid, pass_edit.text))
	_open_dialog(dialog)
	ssid_edit.grab_focus()


func _open_dialog(dialog: ConfirmationDialog) -> void:
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


func _connect_wifi(ssid: String, password: String) -> void:
	var command := "nmcli device wifi connect " + Sh.quote(ssid)
	if not password.is_empty():
		command += " password " + Sh.quote(password)
	var device := _wifi_device()
	if not device.is_empty():
		command += " ifname " + Sh.quote(device)
	notify("Connecting to “" + ssid + "”...")
	run_async(command, func(code: int) -> void:
		if code == 0:
			notify("Connected to “" + ssid + "”.")
		else:
			notify("Could not connect to “" + ssid + "”. Check the password and try again.")
		_populate_wifi())


func _clear_wifi_rows() -> void:
	if _wifi_card == null:
		return
	# The scan row stays put; everything after it came from the previous scan.
	while _wifi_card.get_child_count() > _wifi_fixed_rows:
		var last: Node = _wifi_card.get_child(_wifi_card.get_child_count() - 1)
		_wifi_card.remove_child(last)
		last.queue_free()


func _populate_wifi() -> void:
	if _wifi_card == null:
		return
	_clear_wifi_rows()
	var c: VBoxContainer = _wifi_card
	# Every reason the list can be empty is spelled out in a row: an empty card
	# would look like the scan is still running.
	if not _nmcli_available():
		unavailable_row(c, "Network manager", "NetworkManager (nmcli) is not installed")
		return
	if Sh.run_capture("nmcli -t -f RUNNING general 2>/dev/null").strip_edges() != "running":
		unavailable_row(c, "Network manager", "The NetworkManager service is not running")
		return
	if _wifi_device().is_empty():
		info_row(c, "Wireless adapter", "No Wi-Fi hardware was found")
		return
	if not _wifi_enabled():
		info_row(c, "Wi-Fi", "Off — turn it on above to see networks")
		return
	var networks: Array = _wifi_networks()
	if networks.is_empty():
		info_row(c, "Networks in range", "None found — scan again")
	else:
		for network in networks:
			_wifi_row(c, network)
	# Hidden networks are never in the scan, so this row is always offered.
	action_row(c, "Join Other Network", "Type the name of a hidden network.", "J",
		"Join", _join_hidden_wifi)


func _scan_wifi() -> void:
	if not _nmcli_available():
		notify("NetworkManager tools are not installed.")
		return
	notify("Scanning for Wi-Fi networks...")
	# nmcli returns before the driver has written the new results, so the list is
	# read after the rescan has had a moment to land, not immediately.
	run_async("nmcli device wifi rescan 2>/dev/null; sleep 1", func(_code: int) -> void:
		_populate_wifi())
