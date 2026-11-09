extends SettingsPanel
# Networks & Connections: native device status via nmcli, complex config via KCMs.

var _status_card: VBoxContainer
# Read live by the toggle's callback (GDScript lambdas capture locals by
# value, but member variables are looked up when the lambda runs) so a failed
# radio change can snap the switch back to reality.
var _bt_check: CheckButton = null


func build() -> void:
	page_header("Networks & Connections", "Wi-Fi, Ethernet, Bluetooth and connectivity.")
	_build_static()
	defer(_populate_status)


func _build_static() -> void:
	section("Status")
	var c := card()
	_status_card = c

	section("Wi-Fi")
	var c2 := card()
	action_row(c2, "Wi-Fi", "Connect to or disconnect from wireless networks.", "W", "Manage", func() -> void:
		_open_network())
	kcm_row(c2, "Network Connections", "Edit saved connection profiles.", "N", "kcm_networkmanagement")
	kcm_row(c2, "Network Preferences", "Generic network preferences.", "P", "kcm_netpref")
	kcm_row(c2, "Proxy", "HTTP and SOCKS proxy configuration.", "X", "kcm_proxy")

	section("Sharing & Devices")
	var c3 := card()
	_bt_check = toggle_row(c3, "Bluetooth", "Enable or disable Bluetooth radio.", "B", _is_bluetooth_on(),
		func(on: bool) -> void:
			_set_bluetooth(on))
	kcm_row(c3, "Bluetooth Devices", "Pair and manage Bluetooth devices.", "D", "kcm_bluetooth")
	kcm_row(c3, "KDE Connect", "Link your phone and other devices.", "K", "kcm_kdeconnect")
	kcm_row(c3, "Samba", "Windows file sharing status.", "S", "kcm_samba")
	kcm_row(c3, "Web Shortcuts", "Search keywords for web services.", "U", "kcm_webshortcuts")


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
		var parts: PackedStringArray = line.split(":")
		if parts.size() >= 3:
			var label: String = "%s (%s)" % [parts[0], parts[1]]
			var state: String = parts[2]
			if parts.size() >= 4 and not parts[3].is_empty():
				state += " -> " + parts[3]
			info_row(c, label, state)


func _open_network() -> void:
	if Sh.has_tool("plasma-nm"):
		Sh.launch("plasma-nm")
	elif Sh.has_tool("nm-connection-editor"):
		Sh.launch("nm-connection-editor")
	elif Sh.has_tool("nmcli"):
		Sh.run("nmcli device wifi list; nmcli device status")
	else:
		Sh._notify_missing("nmcli", "Network configuration", notify)


# bluetoothctl is quick, so run it to completion and look at the exit code.
# A fire-and-forget call would announce "enabled" even when the radio is
# rfkill-blocked or bluetoothd is down — and the switch would keep claiming
# it. On failure, re-read what the adapter actually reports and undo.
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

