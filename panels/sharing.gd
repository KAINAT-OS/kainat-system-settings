extends SettingsPanel
# File Sharing: share folders over the local network with Samba, without
# editing smb.conf by hand.

const SMB_CONF := "/etc/samba/smb.conf"

var _service_row: HBoxContainer
var _count_row: HBoxContainer
var _workgroup_row: HBoxContainer
var _list: ItemList
var _share_list: Array = []
var _status: Label
var _remove_btn: Button
var _details_btn: Button


func build() -> void:
	page_header("File Sharing", "Share folders with other computers on your network.")

	section("Sharing")
	var c := card()
	_service_row = info_row(c, "Sharing Service", "…")
	_count_row = info_row(c, "Shared Folders", "…")
	_workgroup_row = info_row(c, "Workgroup", "…")

	if not Sh.has_tool("smbd"):
		set_info_value(_service_row, "Not installed")
		set_info_value(_count_row, UNAVAILABLE)
		set_info_value(_workgroup_row, UNAVAILABLE)
		unavailable_row(c, "File Sharing",
			"The Samba file sharing service is not installed.", "S")
		action_row(c, "Install File Sharing",
			"Adds Samba so other computers can open the folders you share.",
			"I", "Install", _install_samba)
		return

	var share_check: CheckButton = null
	share_check = toggle_row(c, "Share Files on This Network",
		"Other computers can reach the folders you share while this is on.",
		"S", _service_active(), func(on: bool) -> void: _set_service(on, share_check))

	action_row(c, "Share a Folder", "Pick a folder and give it a name others can see.",
		"A", "Choose Folder", _open_share_dialog)

	section("Shared Folders")
	var c2 := card()
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 220)
	_list.item_selected.connect(_on_selected)
	_list.item_activated.connect(func(_i: int) -> void: _show_details())
	c2.add_child(_list)

	_status = Label.new()
	_status.add_theme_color_override("font_color", _muted())
	c2.add_child(_status)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	c2.add_child(actions)
	_details_btn = _button(actions, "Details", _show_details)
	_remove_btn = _button(actions, "Stop Sharing", _remove_selected)
	_button(actions, "Refresh", _refresh)
	_set_actions_enabled(false)

	section("Accounts and Advanced Settings")
	var c3 := card()
	action_row(c3, "Set Sharing Password",
		"Other computers sign in with your user name and this password.",
		"K", "Change", _open_password_dialog)
	kcm_row(c3, "Advanced Sharing Settings",
		"Fine tune the service, printers and network discovery.", "A", "kcm_smb")

	_refresh()


# --- state ------------------------------------------------------------------

func _service_active() -> bool:
	return Sh.run_capture("systemctl is-active smbd 2>/dev/null").strip_edges() == "active"


func _workgroup() -> String:
	for line in Sh.read_lines(SMB_CONF):
		if line.to_lower().begins_with("workgroup"):
			var idx: int = line.find("=")
			if idx >= 0:
				var value: String = line.substr(idx + 1).strip_edges()
				if not value.is_empty():
					return value
	return "WORKGROUP"


func _load_shares() -> Array:
	var out: String = Sh.run_capture("testparm -s " + Sh.quote(SMB_CONF) + " 2>/dev/null")
	var found: Array = []
	var current: Dictionary = {}
	for raw in out.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("[") and line.ends_with("]"):
			if not current.is_empty():
				found.append(current)
			current = {
				"name": line.substr(1, line.length() - 2).strip_edges(),
				"path": "",
				"read_only": true,
				"guest_ok": false,
				"comment": "",
			}
			continue
		if current.is_empty():
			continue
		var idx: int = line.find("=")
		if idx <= 0:
			continue
		var key: String = line.substr(0, idx).strip_edges().to_lower()
		var value: String = line.substr(idx + 1).strip_edges()
		match key:
			"path":
				current["path"] = value
			"read only":
				current["read_only"] = value.to_lower() in ["yes", "true", "1"]
			"guest ok":
				current["guest_ok"] = value.to_lower() in ["yes", "true", "1"]
			"comment":
				current["comment"] = value
	if not current.is_empty():
		found.append(current)

	var result: Array = []
	for share in found:
		var share_name: String = str(share["name"]).to_lower()
		if share_name == "global" or share_name in ["print$", "printers", "homes"]:
			continue
		if str(share["path"]).is_empty():
			continue
		result.append(share)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["name"]).nocasecmp_to(str(b["name"])) < 0)
	return result


func _refresh() -> void:
	if _service_row == null or not is_instance_valid(_service_row):
		return
	var active: bool = _service_active()
	set_info_value(_service_row, "Running" if active else "Stopped")
	set_info_value(_workgroup_row, _workgroup())

	_share_list = _load_shares()
	set_info_value(_count_row, "%d shared" % _share_list.size())

	_list.clear()
	for share in _share_list:
		var access: String = "read only" if bool(share["read_only"]) else "read and write"
		_list.add_item("%s  —  %s (%s)" % [str(share["name"]), str(share["path"]), access])
		if not bool(share["guest_ok"]):
			_list.set_item_tooltip(_list.item_count - 1, "Sign in with your user name and sharing password.")

	if _share_list.is_empty():
		_status.text = "No folders are shared yet."
	else:
		_status.text = "%d folder%s shared" % [_share_list.size(), "" if _share_list.size() == 1 else "s"]
	_set_actions_enabled(false)


func _set_actions_enabled(enabled: bool) -> void:
	if _remove_btn != null and is_instance_valid(_remove_btn):
		_remove_btn.disabled = not enabled
	if _details_btn != null and is_instance_valid(_details_btn):
		_details_btn.disabled = not enabled


func _on_selected(index: int) -> void:
	_set_actions_enabled(index >= 0 and index < _share_list.size())


func _selected_share() -> Dictionary:
	var picked: PackedInt32Array = _list.get_selected_items()
	if picked.is_empty() or picked[0] >= _share_list.size():
		notify("Choose a shared folder first.")
		return {}
	return _share_list[picked[0]]


# --- service ----------------------------------------------------------------

func _install_samba() -> void:
	run_async(Sh.install_command("samba"), func(code: int, _text: String) -> void:
		if code == 0:
			Sh.clear_tool_cache()
			notify("File sharing installed. Open this page again to use it.")
		else:
			notify("Could not install file sharing.")
	)


func _set_service(on: bool, check: CheckButton) -> void:
	var verb: String = "enable --now smbd" if on else "disable --now smbd"
	var code: int = Sh.run_wait("pkexec systemctl " + verb)
	if code != 0:
		check.set_pressed_no_signal(not on)
		notify("Could not change the sharing service.")
	else:
		notify("File sharing is on." if on else "File sharing is off.")
	_refresh()


# --- sharing a folder -------------------------------------------------------

func _open_share_dialog() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Share a Folder"
	dialog.ok_button_text = "Share Folder"
	dialog.cancel_button_text = "Cancel"
	dialog.dialog_hide_on_ok = false
	dialog.min_size = Vector2i(460, 320)
	get_tree().root.add_child(dialog)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	dialog.add_child(box)

	var intro := Label.new()
	intro.text = "Choose a folder on this computer. Everyone on your network will be able to open it."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", _muted())
	box.add_child(intro)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)

	var folder_label := Label.new()
	folder_label.text = "Folder:"
	grid.add_child(folder_label)

	var folder_box := HBoxContainer.new()
	folder_box.add_theme_constant_override("separation", 6)
	folder_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(folder_box)

	var folder_edit := LineEdit.new()
	folder_edit.placeholder_text = Sh.home()
	folder_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	folder_box.add_child(folder_edit)

	var browse := Button.new()
	browse.text = "Browse…"
	folder_box.add_child(browse)

	var name_label := Label.new()
	name_label.text = "Name:"
	grid.add_child(name_label)

	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Shared"
	name_edit.max_length = 32
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(name_edit)

	var guest_check := CheckBox.new()
	guest_check.text = "Let guests open it without a password"
	box.add_child(guest_check)

	var write_check := CheckBox.new()
	write_check.text = "Allow guests to add and change files"
	write_check.disabled = true
	box.add_child(write_check)

	guest_check.toggled.connect(func(on: bool) -> void:
		write_check.disabled = not on
		if not on:
			write_check.button_pressed = false
	)

	var error := Label.new()
	error.add_theme_color_override("font_color", Color(0.95, 0.35, 0.35))
	error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(error)

	var picker := FileDialog.new()
	picker.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.current_dir = Sh.home()
	picker.title = "Choose a Folder to Share"
	picker.dir_selected.connect(func(path: String) -> void:
		folder_edit.text = path
		if name_edit.text.strip_edges().is_empty():
			name_edit.text = _share_name_for(path)
	)
	browse.pressed.connect(func() -> void: picker.popup_centered_ratio(0.6))
	get_tree().root.add_child(picker)

	dialog.confirmed.connect(func() -> void:
		var path: String = folder_edit.text.strip_edges()
		var share_name: String = name_edit.text.strip_edges()
		if not path.begins_with("/") or not DirAccess.dir_exists_absolute(path):
			error.text = "Choose a folder that exists on this computer."
			return
		if not _valid_name(share_name):
			error.text = "Use 1–32 letters, numbers, dots, dashes or underscores for the name."
			return
		if _name_taken(share_name):
			error.text = "A shared folder with that name already exists."
			return
		error.text = ""
		dialog.hide()
		_create_share(share_name, path, guest_check.button_pressed, write_check.button_pressed,
			dialog, picker)
	)

	dialog.canceled.connect(func() -> void:
		dialog.queue_free()
		picker.queue_free()
	)
	dialog.popup_centered()


func _share_name_for(path: String) -> String:
	var base: String = path.trim_suffix("/").get_file()
	var clean := ""
	for ch in base:
		if ch.is_valid_identifier() or ch.is_valid_int() or ch in ["-", ".", "_"]:
			clean += ch
	if clean.is_empty():
		clean = "Shared"
	return clean.substr(0, 32)


func _valid_name(name: String) -> bool:
	if name.is_empty() or name.length() > 32:
		return false
	for ch in name:
		if not (ch.is_valid_identifier() or ch.is_valid_int() or ch in ["-", ".", "_"]):
			return false
	return name.to_lower() != "global" and name.to_lower() != "printers"


func _name_taken(name: String) -> bool:
	for share in _share_list:
		if str(share["name"]).nocasecmp_to(name) == 0:
			return true
	return false


func _create_share(share_name: String, path: String, guest: bool, writable: bool,
		dialog: ConfirmationDialog, picker: FileDialog) -> void:
	var block := PackedStringArray()
	block.append("")
	block.append("[" + share_name + "]")
	block.append("   path = " + path)
	block.append("   comment = Shared with Kainat System Settings")
	block.append("   browseable = yes")
	block.append("   read only = " + ("no" if writable else "yes"))
	block.append("   guest ok = " + ("yes" if guest else "no"))
	block.append("   create mask = 0664")
	block.append("   directory mask = 0775")

	var original: String = Sh.read_text(SMB_CONF)
	var updated: String = _without_share(original, share_name)
	if not updated.ends_with("\n"):
		updated += "\n"
	updated += "\n".join(block) + "\n"

	_save_conf(updated, func(ok: bool) -> void:
		dialog.queue_free()
		picker.queue_free()
		if ok:
			notify("Shared “%s”." % share_name)
			_refresh()
	)


func _remove_selected() -> void:
	var share := _selected_share()
	if share.is_empty():
		return
	var name: String = str(share["name"])
	var dialog := ConfirmationDialog.new()
	dialog.title = "Stop Sharing"
	dialog.dialog_text = "Stop sharing “%s”?\n\nThe folder and its files stay untouched." % name
	dialog.ok_button_text = "Stop Sharing"
	dialog.cancel_button_text = "Keep Sharing"
	get_tree().root.add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		dialog.queue_free()
		var updated: String = _without_share(Sh.read_text(SMB_CONF), name)
		_save_conf(updated, func(ok: bool) -> void:
			if ok:
				notify("Stopped sharing “%s”." % name)
				_refresh()
		)
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	dialog.popup_centered()


func _show_details() -> void:
	var share := _selected_share()
	if share.is_empty():
		return
	var lines := PackedStringArray()
	lines.append("Name: " + str(share["name"]))
	lines.append("Folder: " + str(share["path"]))
	lines.append("Access: " + ("Read only" if bool(share["read_only"]) else "Read and write"))
	lines.append("Guests: " + ("Allowed without a password" if bool(share["guest_ok"]) else "Sign in required"))
	if not str(share["comment"]).is_empty():
		lines.append("Comment: " + str(share["comment"]))
	lines.append("")
	lines.append("Other computers open it as \\\\<this-computer>\\" + str(share["name"]) + ".")

	var dialog := AcceptDialog.new()
	dialog.title = str(share["name"])
	dialog.ok_button_text = "Close"
	dialog.dialog_text = "\n".join(lines)
	get_tree().root.add_child(dialog)
	dialog.confirmed.connect(func() -> void: dialog.queue_free())
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	dialog.popup_centered(Vector2i(480, 260))


# --- writing smb.conf -------------------------------------------------------

func _without_share(original: String, share_name: String) -> String:
	var kept := PackedStringArray()
	var target: String = "[" + share_name.to_lower() + "]"
	var skipping := false
	for raw in original.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("[") and line.ends_with("]"):
			skipping = line.to_lower() == target
			if skipping:
				continue
		if skipping:
			continue
		kept.append(raw)
	return "\n".join(kept)


func _save_conf(new_text: String, on_done: Callable) -> void:
	var tmp: String = "/tmp/kainat-smb-%d.conf" % Time.get_ticks_usec()
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		notify("Could not prepare the sharing settings.")
		on_done.call(false)
		return
	file.store_string(new_text)
	file.close()

	if Sh.run_wait("testparm -s " + Sh.quote(tmp) + " >/dev/null 2>&1") != 0:
		DirAccess.remove_absolute(tmp)
		notify("Those sharing settings are not valid, so nothing was changed.")
		on_done.call(false)
		return

	var script: String = "cp " + Sh.quote(SMB_CONF) + " " + Sh.quote(SMB_CONF + ".kainat-backup") \
		+ " && install -m 644 " + Sh.quote(tmp) + " " + Sh.quote(SMB_CONF) \
		+ "; rm -f " + Sh.quote(tmp) \
		+ "; systemctl restart smbd >/dev/null 2>&1 || true"

	run_async("pkexec sh -c " + Sh.quote(script), func(code: int, text: String) -> void:
		if code == 0:
			on_done.call(true)
		else:
			notify("Could not save the sharing settings.")
			if not text.strip_edges().is_empty():
				print("[sharing] ", text.strip_edges())
			on_done.call(false)
	)


# --- sharing password -------------------------------------------------------

func _open_password_dialog() -> void:
	if not Sh.has_tool("smbpasswd"):
		notify("The sharing password tool is not available.")
		return
	var user: String = Sh.run_capture("whoami").strip_edges()
	if user.is_empty():
		user = OS.get_environment("USER")

	var dialog := ConfirmationDialog.new()
	dialog.title = "Sharing Password"
	dialog.ok_button_text = "Save Password"
	dialog.cancel_button_text = "Cancel"
	dialog.dialog_hide_on_ok = false
	dialog.min_size = Vector2i(420, 300)
	get_tree().root.add_child(dialog)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	dialog.add_child(box)

	var intro := Label.new()
	intro.text = "Other computers sign in to your shared folders as “%s” with this password." % user
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", _muted())
	box.add_child(intro)

	var first := LineEdit.new()
	first.secret = true
	first.placeholder_text = "Password"
	box.add_child(first)

	var second := LineEdit.new()
	second.secret = true
	second.placeholder_text = "Repeat password"
	box.add_child(second)

	var error := Label.new()
	error.add_theme_color_override("font_color", Color(0.95, 0.35, 0.35))
	error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(error)

	dialog.confirmed.connect(func() -> void:
		var password: String = first.text
		if password.length() < 8:
			error.text = "Use at least 8 characters."
			return
		if password != second.text:
			error.text = "The two passwords do not match."
			return
		error.text = ""
		dialog.hide()
		_apply_password(user, password, dialog)
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	dialog.popup_centered()
	first.grab_focus()


func _apply_password(user: String, password: String, dialog: ConfirmationDialog) -> void:
	var dir: String = "/tmp/kainat-smbpw-%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		notify("Could not prepare the password change.")
		dialog.queue_free()
		return
	var path: String = dir + "/secret"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		notify("Could not prepare the password change.")
		dialog.queue_free()
		return
	file.store_string(password + "\n" + password + "\n")
	file.close()

	var script: String = "smbpasswd -s -a \"$1\" < \"$2\"; rm -rf " + Sh.quote(dir)
	run_async("pkexec sh -c " + Sh.quote(script) + " sh " + Sh.quote(user) + " " + Sh.quote(path),
		func(code: int, text: String) -> void:
			dialog.queue_free()
			if code == 0:
				notify("Sharing password updated.")
			else:
				notify("Could not update the sharing password.")
				if not text.strip_edges().is_empty():
					print("[sharing] ", text.strip_edges())
	)


func _button(parent: HBoxContainer, text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_press)
	parent.add_child(button)
	return button
