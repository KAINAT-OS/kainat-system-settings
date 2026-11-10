extends SettingsPanel
# Users & Accounts: native user identity + management KCMs.

var _account_card: VBoxContainer
var _groups_row: HBoxContainer
var _avatar_dialog: FileDialog = null
var _pw_dialog: ConfirmationDialog = null
var _pw_new: LineEdit = null
var _pw_confirm: LineEdit = null
var _pw_error: Label = null


func build() -> void:
	page_header("Users", "Accounts, identity, online services and the wallet.")

	section("Account")
	_account_card = card()
	_groups_row = info_row(_account_card, "Groups", "…")
	action_row(_account_card, "Change Password", "Set a new password for your account.", "P",
		"Change", _change_password)
	nav_row(_account_card, "Change Picture", "Pick an avatar for login and session.", "A",
		_pick_avatar)

	section("Users")
	var c1 := card()
	var users: Array = _local_users()
	if users.is_empty():
		info_row(c1, "Local users", "Could not read /etc/passwd.")
	else:
		for u in users:
			var role := "Administrator" if u["admin"] else "Standard"
			info_row(c1, str(u["name"]), str(u["home"]) + " · " + role)

	section("Management")
	var c2 := card()
	kcm_row(c2, "User Accounts", "Create, edit and remove users.", "U", "kcm_users")
	kcm_row(c2, "Online Accounts", "Google, Microsoft and OwnCloud.", "O", "kcm_kaccounts")
	nav_row(c2, "KDE Wallet", "Stored credentials and secrets.", "W", _open_wallet)
	kcm_row(c2, "Activities", "Task-focused workspaces.", "A", "kcm_activities")
	kcm_row(c2, "User Feedback", "Send anonymous usage statistics.", "F", "kcm_feedback")

	defer(_populate)


func _open_wallet() -> void:
	for tool in ["kwalletmanager5", "kwalletmanager6", "kwalletmanager"]:
		if Sh.has_tool(tool):
			Sh.launch(tool)
			return
	KainatShell.open_kcm("kcm_kwallet5")


func _populate() -> void:
	var user: String = Sh.run_capture("whoami").strip_edges()
	var full_name: String = _full_name(user)
	var groups: String = Sh.run_capture("id -nG " + Sh.quote(user)).strip_edges()

	info_tiles([
		{"value": full_name if not full_name.is_empty() else user, "label": "Current user"},
		{"value": user, "label": "Username"},
		{"value": str(groups.split(" ").size()), "label": "Groups"},
	])

	info_row(_account_card, "Full name", full_name if not full_name.is_empty() else user)
	info_row(_account_card, "Username", user)
	info_row(_account_card, "Home", Sh.home())
	# The Groups placeholder is updated in place.
	set_info_value(_groups_row, groups)


func _full_name(username: String) -> String:
	if username.is_empty():
		return ""
	for line in Sh.read_lines("/etc/passwd"):
		var parts: PackedStringArray = line.split(":")
		if parts.size() >= 5 and parts[0] == username:
			var gecos: String = parts[4].split(",")[0].strip_edges()
			return gecos
	return ""


# --- native user list -------------------------------------------------------

# Human accounts: UID 1000–65533 with a real home directory.
func _local_users() -> Array:
	var users: Array = []
	var admin_group := _group_members("sudo")
	for m in _group_members("wheel"):
		if not admin_group.has(m):
			admin_group.append(m)
	for line in Sh.read_lines("/etc/passwd"):
		var parts: PackedStringArray = line.split(":")
		if parts.size() < 7:
			continue
		var uid := int(parts[2])
		if uid < 1000 or uid >= 65534:
			continue
		if not parts[5].begins_with("/home"):
			continue
		users.append({
			"name": parts[0],
			"uid": uid,
			"home": parts[5],
			"admin": admin_group.has(parts[0]),
		})
	return users


func _group_members(group: String) -> Array:
	var members: Array = []
	for line in Sh.read_lines("/etc/group"):
		var parts: PackedStringArray = line.split(":")
		if parts.size() >= 4 and parts[0] == group:
			for m in parts[3].split(",", false):
				members.append(m.strip_edges())
	return members


# --- password ---------------------------------------------------------------

func _username() -> String:
	var user := Sh.run_capture("whoami").strip_edges()
	return user if not user.is_empty() else OS.get_environment("USER")


func _change_password() -> void:
	if _pw_dialog == null or not is_instance_valid(_pw_dialog):
		_build_password_dialog()
	_pw_new.text = ""
	_pw_confirm.text = ""
	_pw_error.text = ""
	_pw_dialog.get_ok_button().disabled = true
	_pw_dialog.popup_centered(Vector2i(440, 0))
	_pw_new.grab_focus()


func _build_password_dialog() -> void:
	_pw_dialog = ConfirmationDialog.new()
	_pw_dialog.title = "Change Password"
	_pw_dialog.ok_text = "Change Password"
	_pw_dialog.add_cancel_button("Cancel")

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(400, 0)
	box.add_theme_constant_override("separation", 8)
	_pw_dialog.add_child(box)

	var hint := Label.new()
	hint.text = "New password for " + _username() + ":"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	_pw_new = LineEdit.new()
	_pw_new.secret = true
	_pw_new.placeholder_text = "New password"
	_pw_new.text_changed.connect(func(_t: String) -> void: _validate_password())
	box.add_child(_pw_new)

	_pw_confirm = LineEdit.new()
	_pw_confirm.secret = true
	_pw_confirm.placeholder_text = "Repeat new password"
	_pw_confirm.text_changed.connect(func(_t: String) -> void: _validate_password())
	_pw_confirm.text_submitted.connect(func(_t: String) -> void: _validate_password())
	box.add_child(_pw_confirm)

	_pw_error = Label.new()
	_pw_error.add_theme_color_override("font_color", Color(0.92, 0.38, 0.35))
	_pw_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_pw_error)

	_pw_dialog.confirmed.connect(_apply_password)
	add_child(_pw_dialog)


func _validate_password() -> void:
	var ok := true
	var message := ""
	if _pw_new.text.length() < 8:
		message = "Use at least 8 characters."
		ok = false
	elif _pw_new.text == _username():
		message = "The password cannot be your username."
		ok = false
	elif _pw_new.text != _pw_confirm.text:
		message = "The two passwords do not match."
		ok = false
	_pw_error.text = message
	_pw_dialog.get_ok_button().disabled = not ok


func _apply_password() -> void:
	var user := _username()
	var dir := "/tmp/kainat-pw-" + str(Time.get_ticks_usec())
	# The secret goes into a file inside a 0700 directory so no other user can
	# read it, and chpasswd consumes it as root. The directory is removed as
	# soon as the command finishes (success or not).
	if Sh.run_wait("mkdir -m 700 " + Sh.quote(dir)) != 0:
		notify("Could not prepare the password change.")
		return
	var path := dir + "/entry"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		Sh.run_wait("rm -rf " + Sh.quote(dir))
		notify("Could not prepare the password change.")
		return
	f.store_string(user + ":" + _pw_new.text + "\n")
	f.close()

	notify("Changing password…")
	run_async("pkexec sh -c 'chpasswd < \"$1\"' sh " + Sh.quote(path)
		+ "; rm -rf " + Sh.quote(dir), func(code: int) -> void:
			if code == 0:
				notify("Password changed.")
			else:
				notify("Could not change the password."))


# --- avatar -----------------------------------------------------------------

func _pick_avatar() -> void:
	if _avatar_dialog == null or not is_instance_valid(_avatar_dialog):
		_avatar_dialog = FileDialog.new()
		_avatar_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_avatar_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_avatar_dialog.title = "Choose account picture"
		var filt := PackedStringArray()
		filt.append("Images *.png,*.jpg,*.jpeg,*.bmp,*.webp")
		filt.append("All files *")
		_avatar_dialog.filters = filt
		_avatar_dialog.file_selected.connect(_apply_avatar)
		add_child(_avatar_dialog)
	_avatar_dialog.popup_centered_ratio(0.6)


func _apply_avatar(path: String) -> void:
	var src := FileAccess.open(path, FileAccess.READ)
	if src == null:
		notify("Cannot read that file.")
		return
	var bytes := src.get_buffer(src.get_length())
	src.close()
	var dst := FileAccess.open(Sh.home() + "/.face", FileAccess.WRITE)
	if dst == null:
		notify("Cannot write ~/.face.")
		return
	dst.store_buffer(bytes)
	dst.close()
	notify("Account picture updated.")
