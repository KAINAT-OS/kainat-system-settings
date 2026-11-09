extends SettingsPanel
# SSH Key Manager: Generate, view, and manage SSH keys.
# Uses standard ssh-keygen and provides clipboard integration.

var _key_list: ItemList
var _ssh_dir: String


func build() -> void:
	page_header("SSH Key Manager", "Generate and manage SSH keys for secure access.")
	
	_ssh_dir = Sh.home() + "/.ssh/"
	
	# Ensure SSH dir exists
	if not Sh.dir_exists(_ssh_dir):
		DirAccess.make_dir_recursive_absolute(_ssh_dir)
	
	_build_ui()
	_refresh_keys()


func _build_ui() -> void:
	var c := card()
	
	# Generate new key section
	var gen_section := VBoxContainer.new()
	c.add_child(gen_section)
	
	var gen_label := Label.new()
	gen_label.text = "Create New SSH Key"
	gen_label.add_theme_font_size_override("font_size", 16)
	gen_section.add_child(gen_label)
	
	var gen_row := HBoxContainer.new()
	gen_section.add_child(gen_row)
	
	var key_name := LineEdit.new()
	key_name.placeholder_text = "Key name (e.g., id_ed25519)"
	key_name.text = "id_ed25519"
	key_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gen_row.add_child(key_name)
	
	var key_type := OptionButton.new()
	key_type.add_item("ED25519 (Recommended)")
	key_type.add_item("RSA 4096")
	key_type.add_item("ECDSA")
	gen_row.add_child(key_type)
	
	var gen_btn := Button.new()
	gen_btn.text = "Generate"
	gen_btn.pressed.connect(_on_generate.bind(key_name, key_type))
	gen_row.add_child(gen_btn)
	
	# Existing keys list
	var list_label := Label.new()
	list_label.text = "Existing Keys"
	list_label.add_theme_font_size_override("font_size", 16)
	c.add_child(list_label)
	
	_key_list = ItemList.new()
	_key_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_key_list.custom_minimum_size = Vector2(0, 250)
	_key_list.item_selected.connect(_on_key_selected)
	c.add_child(_key_list)
	
	# Action buttons
	var actions := HBoxContainer.new()
	c.add_child(actions)
	
	var copy_btn := Button.new()
	copy_btn.text = "Copy Public Key"
	copy_btn.disabled = true
	copy_btn.name = "copy_btn"
	copy_btn.pressed.connect(_on_copy_key)
	actions.add_child(copy_btn)
	
	var view_btn := Button.new()
	view_btn.text = "View Key"
	view_btn.disabled = true
	view_btn.name = "view_btn"
	view_btn.pressed.connect(_on_view_key)
	actions.add_child(view_btn)
	
	var remove_btn := Button.new()
	remove_btn.text = "Remove"
	remove_btn.flat = true
	remove_btn.disabled = true
	remove_btn.name = "remove_btn"
	remove_btn.pressed.connect(_on_remove_key)
	actions.add_child(remove_btn)
	
	# Quick actions
	var quick_section := VBoxContainer.new()
	c.add_child(quick_section)
	
	var quick_label := Label.new()
	quick_label.text = "Quick Actions"
	quick_label.add_theme_font_size_override("font_size", 16)
	quick_section.add_child(quick_label)
	
	var quick_actions := HBoxContainer.new()
	quick_section.add_child(quick_actions)
	
	var github_btn := Button.new()
	github_btn.text = "Add to GitHub"
	github_btn.flat = true
	github_btn.pressed.connect(_on_github)
	quick_actions.add_child(github_btn)
	
	var gitlab_btn := Button.new()
	gitlab_btn.text = "Add to GitLab"
	gitlab_btn.flat = true
	gitlab_btn.pressed.connect(_on_gitlab)
	quick_actions.add_child(gitlab_btn)
	
	var ssh_config_btn := Button.new()
	ssh_config_btn.text = "Edit SSH Config"
	ssh_config_btn.flat = true
	ssh_config_btn.pressed.connect(_on_edit_ssh_config)
	quick_actions.add_child(ssh_config_btn)


func _refresh_keys() -> void:
	_key_list.clear()
	
	# Find all private keys (non-.pub files that have a matching .pub)
	var files := DirAccess.get_files_at(_ssh_dir)
	for file in files:
		if file.ends_with(".pub"):
			continue
		var pub_path := _ssh_dir + file + ".pub"
		if Sh.file_exists(pub_path):
			# Determine key type from public key
			var pub_content := Sh.read_text(pub_path)
			var key_type := "Unknown"
			if pub_content.begins_with("ssh-ed25519"):
				key_type = "ED25519"
			elif pub_content.begins_with("ssh-rsa"):
				key_type = "RSA"
			elif pub_content.begins_with("ecdsa-sha2"):
				key_type = "ECDSA"
			
			_key_list.add_item("🔑 " + file + " (" + key_type + ")")
			_key_list.set_item_metadata(_key_list.item_count - 1, {"file": file, "path": _ssh_dir + file})


func _on_generate(key_name_edit: LineEdit, key_type_box: OptionButton) -> void:
	var name := key_name_edit.text.strip_edges()
	if name.is_empty():
		notify("Please enter a key name")
		return
	
	if not name.begins_with("id_"):
		name = "id_" + name
	
	var key_path := _ssh_dir + name
	if Sh.file_exists(key_path):
		notify("Key already exists: " + name)
		return
	
	var key_type_map: Array[String] = ["ed25519", "rsa", "ecdsa"]
	var key_type: String = key_type_map[key_type_box.selected]
	
	notify("Generating " + key_type + " key: " + name + "...")
	var code := Sh.generate_ssh_key(key_path, key_type)
	
	if code == 0:
		notify("Key generated: " + name)
		_refresh_keys()
	else:
		notify("Failed to generate key")


func _on_key_selected(idx: int) -> void:
	var copy_btn := content.find_child("copy_btn", true, false)
	var view_btn := content.find_child("view_btn", true, false)
	var remove_btn := content.find_child("remove_btn", true, false)
	
	if idx >= 0:
		copy_btn.disabled = false
		view_btn.disabled = false
		remove_btn.disabled = false
	else:
		copy_btn.disabled = true
		view_btn.disabled = true
		remove_btn.disabled = true


func _on_copy_key() -> void:
	var idx := _key_list.get_selected_items()
	if idx.is_empty():
		return
	
	var idx_val: int = idx[0]
	var item_data: Dictionary = _key_list.get_item_metadata(idx_val)
	var pub_key := Sh.get_ssh_public_key(str(item_data.get("path", "")))

	if pub_key.is_empty():
		notify("Could not read public key")
		return

	DisplayServer.clipboard_set(pub_key)
	notify("Public key copied to clipboard!")


func _on_view_key() -> void:
	var idx := _key_list.get_selected_items()
	if idx.is_empty():
		return
	
	var idx_val: int = idx[0]
	var item_data: Dictionary = _key_list.get_item_metadata(idx_val)
	var pub_key := Sh.get_ssh_public_key(str(item_data.get("path", "")))

	if pub_key.is_empty():
		notify("Could not read public key")
		return

	var dialog := AcceptDialog.new()
	dialog.title = "Public Key: " + str(item_data.get("file", ""))
	dialog.text = pub_key
	dialog.ok_text = "Close"
	dialog.min_size = Vector2(600, 200)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)


func _on_remove_key() -> void:
	var idx := _key_list.get_selected_items()
	if idx.is_empty():
		return
	
	var idx_val: int = idx[0]
	var item_data: Dictionary = _key_list.get_item_metadata(idx_val)
	var name: String = str(item_data.get("file", ""))
	var key_path: String = str(item_data.get("path", ""))

	var dialog := AcceptDialog.new()
	dialog.title = "Remove Key?"
	dialog.text = "Permanently delete " + name + " and " + name + ".pub?\n\nThis cannot be undone."
	dialog.ok_text = "Delete"
	dialog.confirmed.connect(func() -> void:
		Sh.run("rm " + Sh.quote(key_path) + " " + Sh.quote(key_path + ".pub"))
		notify("Deleted " + name)
		_refresh_keys())
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


func _on_github() -> void:
	var idx := _key_list.get_selected_items()
	if idx.is_empty():
		notify("Select a key first")
		return
	
	OS.shell_open("https://github.com/settings/keys")
	notify("Opened GitHub SSH keys page. Paste your key there.")


func _on_gitlab() -> void:
	var idx := _key_list.get_selected_items()
	if idx.is_empty():
		notify("Select a key first")
		return
	
	OS.shell_open("https://gitlab.com/-/profile/keys")
	notify("Opened GitLab SSH keys page. Paste your key there.")


func _on_edit_ssh_config() -> void:
	var config_path := _ssh_dir + "config"
	if not Sh.file_exists(config_path):
		Sh.run("touch " + Sh.quote(config_path))
	
	if Sh.has_tool("kate"):
		Sh.run("kate " + Sh.quote(config_path) + " &")
	elif Sh.has_tool("gedit"):
		Sh.run("gedit " + Sh.quote(config_path) + " &")
	else:
		Sh.run("xdg-open " + Sh.quote(config_path))