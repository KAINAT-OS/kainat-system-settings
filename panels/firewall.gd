extends SettingsPanel
# Firewall: a friendly front end for ufw (Uncomplicated Firewall).
#
# Reading the enabled state does not need root (it lives in /etc/ufw/ufw.conf),
# so the page opens without a password prompt; only changing rules does.

var _status_row: HBoxContainer
var _policy_row: HBoxContainer
var _toggle: CheckButton


func build() -> void:
	page_header("Firewall", "Control which network connections are allowed into this computer.")

	section("Status")
	var c := card()
	_status_row = info_row(c, "Firewall", "…")
	_policy_row = info_row(c, "Incoming Policy", "…")

	if not Sh.has_tool("ufw"):
		set_info_value(_status_row, "Not installed")
		set_info_value(_policy_row, UNAVAILABLE)
		unavailable_row(c, "Firewall", "ufw is not installed on this system.", "F")
		action_row(c, "Install Firewall", "Installs ufw with the system package manager.", "I", "Install", _install_ufw)
		return

	_toggle = toggle_row(c, "Firewall Enabled", "Block unsolicited incoming connections.", "S",
		_is_enabled(), _on_toggle)
	_toggle.tooltip_text = "Changes take effect immediately and persist across restarts."

	section("Rules")
	var c2 := card()
	action_row(c2, "Show Active Rules", "See every port and program currently allowed.", "R", "Show", _show_rules)
	action_row(c2, "Add Rule", "Allow, deny or rate-limit a port or program.", "A", "Add Rule", _add_rule)
	action_row(c2, "Remove Rule", "Delete a rule by its number in the list.", "X", "Remove", _remove_rule)
	action_row(c2, "Reset Firewall", "Delete all rules and return to the defaults.", "Z", "Reset", _reset_firewall)

	section("How It Works")
	var c3 := card()
	info_row(c3, "Default Behaviour", "Incoming connections are blocked unless a rule allows them.")
	info_row(c3, "Outgoing Connections", "Always allowed; nothing here restricts what you open.")
	info_row(c3, "Common Ports", "22 = SSH, 80 = web, 443 = secure web, 5900 = screen sharing.")
	defer(_refresh_status)


func _install_ufw() -> void:
	notify("Installing the firewall…")
	run_async(Sh.install_command("ufw"), func(code: int) -> void:
		if code == 0:
			Sh.clear_tool_cache()
			notify("Firewall installed. Open the Firewall page again to manage it.")
		else:
			notify("Could not install ufw (exit code " + str(code) + ")."))


func _is_enabled() -> bool:
	var conf := Sh.read_text("/etc/ufw/ufw.conf")
	for line in conf.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("ENABLED="):
			return trimmed.substr(8).strip_edges().to_lower() == "yes"
	# Fallback for a system whose config is unreadable but the unit is active.
	return Sh.run_capture("systemctl is-active ufw 2>/dev/null").strip_edges() == "active"


func _incoming_policy() -> String:
	var conf := Sh.read_text("/etc/default/ufw")
	for line in conf.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("DEFAULT_INPUT_POLICY="):
			var value := trimmed.substr(21).strip_edges().trim_prefix("\"").trim_suffix("\"")
			return value.capitalize() if not value.is_empty() else UNAVAILABLE
	return UNAVAILABLE


func _refresh_status() -> void:
	var enabled := _is_enabled()
	set_info_value(_status_row, "Active" if enabled else "Inactive")
	set_info_value(_policy_row, _incoming_policy())
	if _toggle != null:
		_toggle.set_pressed_no_signal(enabled)


func _on_toggle(enabled: bool) -> void:
	var command := "pkexec ufw --force enable" if enabled else "pkexec ufw --force disable"
	notify(("Enabling" if enabled else "Disabling") + " the firewall…")
	run_async(command, func(code: int) -> void:
		if code == 0:
			notify("Firewall " + ("enabled." if enabled else "disabled."))
		else:
			notify("Could not change the firewall (exit code " + str(code) + ").")
		_refresh_status())


func _show_rules() -> void:
	notify("Reading firewall rules…")
	run_async_capture("pkexec ufw status numbered", func(_code: int, text: String) -> void:
		var body := text.strip_edges()
		if body.is_empty():
			body = "The firewall returned no output. Is ufw installed and enabled?"
		var dialog := AcceptDialog.new()
		dialog.title = "Active Firewall Rules"
		dialog.size = Vector2i(720, 520)
		var edit := TextEdit.new()
		edit.text = body
		edit.editable = false
		edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		edit.custom_minimum_size = Vector2(680, 460)
		dialog.add_child(edit)
		dialog.ok_button_text = "Close"
		get_tree().root.add_child(dialog)
		dialog.popup_centered()
		dialog.confirmed.connect(dialog.queue_free)
		dialog.canceled.connect(dialog.queue_free))


# App profiles come from /etc/ufw/applications.d; listing them needs no root.
func _profiles() -> Array:
	var out: Array = []
	var started := false
	for raw in Sh.run_lines("ufw app list 2>/dev/null"):
		var line: String = str(raw).strip_edges()
		if line.begins_with("Available applications"):
			started = true
			continue
		if started and not line.is_empty():
			out.append(line)
	return out


func _add_rule() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Add Firewall Rule"
	dialog.ok_button_text = "Add Rule"
	dialog.add_cancel_button("Cancel")
	# Keep the dialog open when validation fails so the inline error is visible.
	dialog.dialog_hide_on_ok = false

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 8)
	dialog.add_child(box)

	var intro := Label.new()
	intro.text = "Choose what to allow or block from the network."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(intro)

	var action_row_box := HBoxContainer.new()
	action_row_box.add_theme_constant_override("separation", 8)
	box.add_child(action_row_box)
	var action_label := Label.new()
	action_label.text = "Action:"
	action_label.custom_minimum_size = Vector2(130, 0)
	action_row_box.add_child(action_label)
	var action_box := OptionButton.new()
	action_box.add_item("Allow")
	action_box.add_item("Deny")
	action_box.add_item("Limit (block floods)")
	action_row_box.add_child(action_box)

	var target_row := HBoxContainer.new()
	target_row.add_theme_constant_override("separation", 8)
	box.add_child(target_row)
	var target_label := Label.new()
	target_label.text = "Program:"
	target_label.custom_minimum_size = Vector2(130, 0)
	target_row.add_child(target_label)
	var program_box := OptionButton.new()
	program_box.add_item("Custom port…")
	for profile in _profiles():
		program_box.add_item(str(profile))
	program_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_row.add_child(program_box)

	var port_row := HBoxContainer.new()
	port_row.add_theme_constant_override("separation", 8)
	box.add_child(port_row)
	var port_label := Label.new()
	port_label.text = "Port:"
	port_label.custom_minimum_size = Vector2(130, 0)
	port_row.add_child(port_label)
	var port_edit := LineEdit.new()
	port_edit.placeholder_text = "e.g. 22, 443, or 8000:8100"
	port_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	port_row.add_child(port_edit)

	var proto_row := HBoxContainer.new()
	proto_row.add_theme_constant_override("separation", 8)
	box.add_child(proto_row)
	var proto_label := Label.new()
	proto_label.text = "Protocol:"
	proto_label.custom_minimum_size = Vector2(130, 0)
	proto_row.add_child(proto_label)
	var proto_box := OptionButton.new()
	proto_box.add_item("Any")
	proto_box.add_item("TCP")
	proto_box.add_item("UDP")
	proto_row.add_child(proto_box)

	var error := Label.new()
	error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	box.add_child(error)

	# A custom port is meaningless once a named program is selected.
	var update_fields := func() -> void:
		var custom := program_box.selected == 0
		port_edit.editable = custom
		proto_box.disabled = not custom
		if not custom:
			port_edit.text = ""
	program_box.item_selected.connect(func(_idx: int) -> void: update_fields.call())
	update_fields.call()

	dialog.confirmed.connect(func() -> void:
		var actions: Array[String] = ["allow", "deny", "limit"]
		var action: String = actions[clampi(action_box.selected, 0, 2)]
		var target := ""
		if program_box.selected == 0:
			var port := port_edit.text.strip_edges()
			if not _valid_port(port):
				error.text = "Enter a port number between 1 and 65535, or a range like 8000:8100."
				return
			var protos: Array[String] = ["", "tcp", "udp"]
			var proto: String = protos[clampi(proto_box.selected, 0, 2)]
			target = port + ("/" + proto if not proto.is_empty() else "")
		else:
			target = str(program_box.get_item_text(program_box.selected))
		if target.is_empty():
			error.text = "Choose a program or enter a port."
			return
		dialog.queue_free()
		_apply_rule(action, target))

	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.canceled.connect(dialog.queue_free)


func _valid_port(text: String) -> bool:
	if text.is_empty():
		return false
	var bounds := text.split(":")
	if bounds.size() > 2:
		return false
	for bound in bounds:
		if not bound.is_valid_int():
			return false
		var value := bound.to_int()
		if value < 1 or value > 65535:
			return false
	return true


func _apply_rule(action: String, target: String) -> void:
	notify("Updating firewall rules…")
	run_async("pkexec ufw " + action + " " + Sh.quote(target), func(code: int) -> void:
		if code == 0:
			notify("Firewall rule added: " + action + " " + target)
		else:
			notify("Could not add the rule (exit code " + str(code) + ").")
		_refresh_status())


func _remove_rule() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Remove Firewall Rule"
	dialog.ok_button_text = "Remove Rule"
	dialog.add_cancel_button("Cancel")
	dialog.dialog_hide_on_ok = false

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 8)
	dialog.add_child(box)

	var intro := Label.new()
	intro.text = "Use “Show Active Rules” first: rules are numbered there."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(intro)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var label := Label.new()
	label.text = "Rule number:"
	row.add_child(label)
	var number_edit := LineEdit.new()
	number_edit.placeholder_text = "e.g. 3"
	number_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(number_edit)

	var error := Label.new()
	error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	box.add_child(error)

	dialog.confirmed.connect(func() -> void:
		var raw := number_edit.text.strip_edges()
		if not raw.is_valid_int() or raw.to_int() < 1:
			error.text = "Enter the rule number shown in the rules list."
			return
		var number := raw.to_int()
		dialog.queue_free()
		notify("Removing firewall rule " + str(number) + "…")
		run_async("pkexec ufw --force delete " + str(number), func(code: int) -> void:
			if code == 0:
				notify("Rule " + str(number) + " removed.")
			else:
				notify("Could not remove rule " + str(number) + " (exit code " + str(code) + ").")
			_refresh_status()))

	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.canceled.connect(dialog.queue_free)


func _reset_firewall() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Reset Firewall?"
	dialog.dialog_text = "This deletes every rule and restores the default policy.\n\nExisting connections may be interrupted. Continue?"
	dialog.ok_button_text = "Reset"
	dialog.add_cancel_button("Cancel")
	dialog.confirmed.connect(func() -> void:
		notify("Resetting firewall…")
		run_async("pkexec ufw --force reset", func(code: int) -> void:
			if code == 0:
				notify("Firewall reset to defaults.")
			else:
				notify("Could not reset the firewall (exit code " + str(code) + ").")
			_refresh_status()))
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
