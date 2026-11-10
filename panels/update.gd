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
		run_async("pkexec apt-get update", func(code: int) -> void:
			notify("Package lists updated." if code == 0 else "Could not refresh the package lists.")))
	action_row(c, "Upgrade All Packages", "Install all available updates.", "U", "Upgrade", func() -> void:
		notify("Upgrading packages… This can take a while.")
		run_async("pkexec apt-get -y upgrade", func(code: int) -> void:
			notify("Upgrade finished." if code == 0 else "Upgrade failed. Check your network connection.")
			_refresh_sources()))
	action_row(c, "Remove Unused Packages", "Clean up dependencies and cache.", "R", "Clean", func() -> void:
		notify("Cleaning up…")
		run_async("pkexec sh -c 'apt-get -y autoremove; apt-get -y autoclean'", func(code: int) -> void:
			notify("Cleanup finished." if code == 0 else "Cleanup failed.")))
	
	# Built-in Repository Manager
	section("Software Sources (Repositories)")
	c = card()
	
	_sources_list = ItemList.new()
	_sources_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sources_list.custom_minimum_size = Vector2(0, 250)
	_sources_list.item_activated.connect(_on_repo_toggled)
	c.add_child(_sources_list)
	
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	c.add_child(actions)
	
	var add_btn := Button.new()
	add_btn.text = "+ Add Repository"
	add_btn.pressed.connect(_on_add_repo)
	actions.add_child(add_btn)
	
	var toggle_btn := Button.new()
	toggle_btn.text = "Enable / Disable"
	toggle_btn.tooltip_text = "Toggle the selected repository (or double-click it)."
	toggle_btn.pressed.connect(func() -> void: _on_repo_toggled(_first_selected()))
	actions.add_child(toggle_btn)
	
	var remove_btn := Button.new()
	remove_btn.text = "Remove"
	remove_btn.tooltip_text = "Delete the selected custom repository."
	remove_btn.pressed.connect(_on_remove_repo)
	actions.add_child(remove_btn)
	
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


func _first_selected() -> int:
	var selected := _sources_list.get_selected_items()
	return selected[0] if not selected.is_empty() else -1


func _selected_source() -> Dictionary:
	var idx := _first_selected()
	if idx < 0:
		notify("Select a repository first.")
		return {}
	var meta: Variant = _sources_list.get_item_metadata(idx)
	if not meta is Dictionary:
		return {}
	return meta


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
	dialog.ok_button_text = "Add"
	dialog.add_cancel_button("Cancel")
	
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(460, 0)
	vbox.add_theme_constant_override("separation", 8)
	dialog.add_child(vbox)
	
	var hint := Label.new()
	hint.text = "Enter the repository line exactly as it should appear in the sources file."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)
	
	var repo_edit := LineEdit.new()
	repo_edit.placeholder_text = "deb http://example.com/ubuntu jammy main"
	vbox.add_child(repo_edit)
	
	dialog.confirmed.connect(func() -> void:
		var line := repo_edit.text.strip_edges()
		if not (line.begins_with("deb ") or line.begins_with("deb-src ")):
			notify("Invalid repository line. It must start with 'deb ' or 'deb-src '.")
			return
		if line.contains("\n"):
			notify("Repository lines cannot span multiple lines.")
			return

		# One .list file per custom repository so it can be toggled or removed.
		var name := "custom-" + str(int(Time.get_unix_time_from_system()))
		var path := "/etc/apt/sources.list.d/" + name + ".list"
		notify("Adding repository…")
		run_async("pkexec sh -c " + Sh.quote("printf %s " + Sh.quote(line + "\n") + " > " + Sh.quote(path)), func(code: int) -> void:
			if code != 0:
				notify("Failed to add repository.")
				return
			notify("Repository added. Refreshing package lists…")
			_refresh_sources()
			_refresh_package_lists()))
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	repo_edit.grab_focus()


func _on_remove_repo() -> void:
	var src := _selected_source()
	if src.is_empty():
		return
	var file: String = str(src.get("file", ""))
	if bool(src.get("is_main", false)):
		notify("The main sources.list cannot be removed from here.")
		return
	var name := file.get_file()
	var dialog := ConfirmationDialog.new()
	dialog.title = "Remove Repository"
	dialog.dialog_text = "Delete " + name + "?\n\nPackages installed from it stay installed, but they will stop receiving updates."
	dialog.ok_button_text = "Remove"
	dialog.add_cancel_button("Cancel")
	dialog.confirmed.connect(func() -> void:
		run_async(Sh.remove_apt_source_command(file), func(code: int) -> void:
			if code != 0:
				notify("Could not remove " + name + ".")
				return
			notify(name + " removed.")
			_refresh_sources()))
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


func _refresh_package_lists() -> void:
	run_async("pkexec apt-get update", func(code: int) -> void:
		notify("Package lists updated." if code == 0 else "Could not refresh the package lists."))


func _on_repo_toggled(idx: int) -> void:
	if idx < 0 or idx >= _sources_list.item_count:
		notify("Select a repository first.")
		return
	var item_data: Dictionary = _sources_list.get_item_metadata(idx)
	var file: String = str(item_data.get("file", ""))
	var enabled: bool = bool(item_data.get("enabled", false))
	var new_enabled := not enabled

	notify(("Enabling " if new_enabled else "Disabling ") + file.get_file() + "…")
	run_async(Sh.toggle_apt_source_command(file, new_enabled), func(code: int) -> void:
		if code != 0:
			notify("Failed to change the repository state.")
			return
		notify("Repository " + ("enabled" if new_enabled else "disabled") + ". Refreshing package lists…")
		_refresh_sources()
		_refresh_package_lists())


func _open_software_sources() -> void:
	for tool in ["software-properties-qt", "software-properties-gtk", "plasma-discover"]:
		if Sh.has_tool(tool):
			if tool == "plasma-discover":
				Sh.launch(tool, ["--mode", "sources"])
			else:
				Sh.launch(tool)
			return
	Sh._notify_missing("software-properties-qt or plasma-discover", "Software sources", notify)