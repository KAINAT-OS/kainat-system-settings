extends SettingsPanel
# Users & Accounts: native user identity + management KCMs.

var _account_card: VBoxContainer
var _groups_row: HBoxContainer
var _avatar_dialog: FileDialog = null


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
	kcm_row(c2, "KDE Wallet", "Stored credentials and secrets.", "W", "kcm_kwallet5")
	kcm_row(c2, "Activities", "Task-focused workspaces.", "A", "kcm_activities")
	kcm_row(c2, "User Feedback", "Send anonymous usage statistics.", "F", "kcm_feedback")

	defer(_populate)


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

func _change_password() -> void:
	var user := Sh.run_capture("whoami").strip_edges()
	if Sh.has_tool("konsole"):
		# passwd is interactive — run it inside a terminal window.
		Sh.run("konsole -e passwd " + Sh.quote(user) + " >/dev/null 2>&1 &")
		notify("A terminal opened — enter your new password there.")
	elif Sh.has_tool("xterm"):
		Sh.run("xterm -e passwd " + Sh.quote(user) + " >/dev/null 2>&1 &")
		notify("A terminal opened — enter your new password there.")
	else:
		notify(Sh._notify_missing("konsole or xterm", "Password change")
			+ " Open any terminal and run: passwd")


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
