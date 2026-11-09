extends SettingsPanel
# Updates: configure update behaviour, manage repositories, and trigger upgrades.
# Includes built-in repository manager (no external tool needed).

var _sources_list: ItemList


func build() -> void:
	page_header("Updates", "Keep Kainat OS and its packages up to date.")
	
	section("Software Updates")
	var c := card()
	info_row(c, "Distribution", str(Sh.os_release().get("PRETTY_NAME", "Kainat OS")))
	kcm_row(c, "Update Settings", "Choose how and when updates are applied.", "S", "kcm_updates")
	
	section("Package Maintenance")
	c = card()
	action_row(c, "Check for Updates", "Refresh the package lists.", "C", "Run", func() -> void:
		notify("Refreshing package lists…")
		Sh.run("pkexec apt-get update"))
	action_row(c, "Upgrade All Packages", "Install all available updates.", "U", "Upgrade", func() -> void:
		notify("Upgrading packages…")
		Sh.run("pkexec apt-get -y upgrade"))
	action_row(c, "Remove Unused Packages", "Clean up dependencies and cache.", "R", "Clean", func() -> void:
		notify("Cleaning up…")
		Sh.run("pkexec apt-get -y autoremove && pkexec apt-get -y autoclean"))
	
	# Built-in Repository Manager
	section("Software Sources (Repositories)")
	c = card()
	
	_sources_list = ItemList.new()
	_sources_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sources_list.custom_minimum_size = Vector2(0, 250)
	c.add_child(_sources_list)
	
	var actions := HBoxContainer.new()
	c.add_child(actions)
	
	var add_btn := Button.new()
	add_btn.text = "+ Add Repository"
	add_btn.pressed.connect(_on_add_repo)
	actions.add_child(add_btn)
	
	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.pressed.connect(_refresh_sources)
	actions.add_child(refresh_btn)
	
	var ext_btn := Button.new()
	ext_btn.text = "Open in Software Sources"
	ext_btn.flat = true
	ext_btn.pressed.connect(_open_software_sources)
	actions.add_child(ext_btn)
	
	_refresh_sources()


func _refresh_sources() -> void:
	_sources_list.clear()
	
	var sources := Sh.list_apt_sources()
	for src in sources:
		var src_name: String = str(src.get("name", ""))
		var src_enabled: bool = bool(src.get("enabled", false))
		var icon := "✅" if src_enabled else "⏸️"
		_sources_list.add_item(icon + " " + src_name)
		_sources_list.set_item_metadata(_sources_list.item_count - 1, {"file": str(src.get("file", "")), "enabled": src_enabled})

	# Also show main sources.list
	var main_content := Sh.read_text("/etc/apt/sources.list")
	if not main_content.strip_edges().is_empty():
		var main_enabled := not main_content.begins_with("#")
		var main_icon := "✅" if main_enabled else "⏸️"
		_sources_list.add_item(main_icon + " sources.list (main)")
		_sources_list.set_item_metadata(_sources_list.item_count - 1, {"file": "/etc/apt/sources.list", "enabled": main_enabled, "is_main": true})


func _on_add_repo() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Add Repository"
	dialog.text = "Enter repository line (e.g., deb http://archive.ubuntu.com/ubuntu jammy main):"
	dialog.ok_text = "Add"
	dialog.add_cancel_button("Cancel")
	
	var repo_edit := LineEdit.new()
	repo_edit.placeholder_text = "deb http://example.com/ubuntu jammy main"
	
	var vbox := VBoxContainer.new()
	vbox.add_child(repo_edit)
	dialog.add_child(vbox)
	
	dialog.confirmed.connect(func() -> void:
		var line := repo_edit.text.strip_edges()
		if line.is_empty() or not line.begins_with("deb "):
			notify("Invalid repository format. Must start with 'deb '")
			return

		# Create a new .list file
		var name := "custom-" + str(int(Time.get_unix_time_from_system()))
		var path := "/etc/apt/sources.list.d/" + name + ".list"
		var code := Sh.run_wait("pkexec sh -c 'printf %s " + Sh.quote(line + "\n") + " > " + Sh.quote(path) + "'")

		if code == 0:
			notify("Repository added. Running apt update...")
			Sh.run("pkexec apt-get update")
			_refresh_sources()
		else:
			notify("Failed to add repository."))
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


func _on_repo_toggled(idx: int) -> void:
	var item_data: Dictionary = _sources_list.get_item_metadata(idx)
	var file: String = str(item_data.get("file", ""))
	var enabled: bool = bool(item_data.get("enabled", false))

	var new_enabled := not enabled
	var code := Sh.toggle_apt_source(file, new_enabled)

	if code == 0:
		var state_text := "enabled" if new_enabled else "disabled"
		notify("Repository " + state_text + ". Running apt update...")
		Sh.run("pkexec apt-get update")
		_refresh_sources()
	else:
		notify("Failed to toggle repository.")


func _open_software_sources() -> void:
	for tool in ["software-properties-qt", "software-properties-gtk", "plasma-discover"]:
		if Sh.has_tool(tool):
			if tool == "plasma-discover":
				Sh.launch(tool, ["--mode", "sources"])
			else:
				Sh.launch(tool)
			return
	Sh._notify_missing("software-properties-qt or plasma-discover", "Software sources", notify)