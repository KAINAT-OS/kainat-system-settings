extends SettingsPanel
# Disk Manager: view disks, format, eject, and check health.
# Uses udisks2 for safe operations and lsblk/df for info.

var _disk_cards: Array[Node] = []


func build() -> void:
	page_header("Disk Manager", "Manage storage devices, format drives, and monitor health.")
	_build_placeholder()
	defer(_populate)


func _build_placeholder() -> void:
	var c := card()
	_disk_cards.append(c.get_parent())
	info_row(c, "Scanning...", "Detecting storage devices")


func _clear_cards() -> void:
	for node in _disk_cards:
		if is_instance_valid(node):
			if node.get_parent() == content:
				content.remove_child(node)
			node.queue_free()
	_disk_cards.clear()


func _populate() -> void:
	_clear_cards()

	var devices := Sh.list_block_devices()
	if devices.is_empty():
		var c := card()
		_disk_cards.append(c.get_parent())
		unavailable_row(c, "Storage devices", "Could not read block devices.")
		return

	for dev in devices:
		_build_disk_card(dev)


func _build_disk_card(dev: Dictionary) -> void:
	var name: String = _field(dev, "name", "unknown")
	var mountpoint: String = _field(dev, "mountpoint", "")
	var size: String = _field(dev, "size", "?")
	var dtype: String = _field(dev, "type", "")
	var children: Array = dev.get("children") if dev.get("children") is Array else []

	# Skip loop devices, RAM disks and optical drives with no media.
	if name.begins_with("loop") or name.begins_with("ram") or name.begins_with("zram"):
		return
	if dtype == "rom":
		return

	var c := card()
	_disk_cards.append(c.get_parent())

	# Header with icon
	var header := HBoxContainer.new()
	c.add_child(header)
	
	var icon := Label.new()
	icon.text = "💾" if dtype == "disk" else "📁"
	icon.add_theme_font_size_override("font_size", 24)
	header.add_child(icon)
	
	var title_vbox := VBoxContainer.new()
	header.add_child(title_vbox)
	title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var name_label := Label.new()
	name_label.text = "/dev/" + name + "  (" + size + ")"
	name_label.add_theme_constant_override("autowrap_mode", TextServer.AUTOWRAP_WORD_SMART)
	title_vbox.add_child(name_label)
	
	if not mountpoint.is_empty():
		var mount_label := Label.new()
		mount_label.text = "Mounted at: " + mountpoint
		mount_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		mount_label.add_theme_font_size_override("font_size", 12)
		title_vbox.add_child(mount_label)
		
		# Usage bar
		var usage := Sh.get_disk_usage(mountpoint)
		var percent: int = int(usage.get("percent", 0))
		if percent > 0:
			var bar := ProgressBar.new()
			bar.min_value = 0
			bar.max_value = 100
			bar.value = percent
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var usage_text := Label.new()
			usage_text.text = "Usage: %s / %s (%d%%)" % [str(usage["used"]), str(usage["total"]), percent]
			title_vbox.add_child(usage_text)
			title_vbox.add_child(bar)
	
	# Actions for physical disks (not partitions)
	if dtype == "disk":
		var actions := HBoxContainer.new()
		c.add_child(actions)
		
		# Eject (if removable)
		var eject_btn := Button.new()
		eject_btn.text = "Eject"
		eject_btn.flat = true
		eject_btn.pressed.connect(_on_eject.bind("/dev/" + name))
		actions.add_child(eject_btn)
		
		# Format
		var format_btn := Button.new()
		format_btn.text = "Format..."
		format_btn.flat = true
		format_btn.pressed.connect(_on_format.bind("/dev/" + name, size))
		actions.add_child(format_btn)
		
		# SMART/Health
		var health_btn := Button.new()
		health_btn.text = "Health (SMART)"
		health_btn.flat = true
		health_btn.pressed.connect(_on_health.bind("/dev/" + name))
		actions.add_child(health_btn)
	
	# Recurse for partitions
	for child in children:
		_build_disk_card(child)


func _on_eject(device: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Eject " + device + "?"
	dialog.dialog_text = "This will unmount all partitions and power off the device.\n\nAre you sure?"
	dialog.ok_button_text = "Eject"
	dialog.confirmed.connect(func() -> void:
		notify("Ejecting " + device + "...")
		var code := Sh.eject_drive(device)
		if code == 0:
			notify(device + " ejected safely. You may remove it.")
			_populate()  # Refresh
		else:
			notify("Failed to eject " + device))
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


func _on_format(device: String, size: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Format " + device + "?"
	dialog.dialog_text = "WARNING: This will ERASE ALL DATA on " + device + " (" + size + ").\n\nThis action cannot be undone."
	dialog.ok_button_text = "Format"
	dialog.add_cancel_button("Cancel")
	
	# Filesystem selector
	var fs_box := OptionButton.new()
	fs_box.add_item("FAT32 (Universal, ≤4GB files)")
	fs_box.add_item("NTFS (Windows/Linux, large files)")
	fs_box.add_item("ext4 (Linux native)")
	fs_box.selected = 0
	
	var vbox := VBoxContainer.new()
	var fs_label := Label.new()
	fs_label.text = "Filesystem:"
	vbox.add_child(fs_label)
	vbox.add_child(fs_box)
	dialog.add_child(vbox)

	dialog.confirmed.connect(func() -> void:
		var fs_map: Array[String] = ["vfat", "ntfs", "ext4"]
		var fs: String = fs_map[fs_box.selected]
		if fs == "ntfs" and not Sh.has_tool("mkfs.ntfs"):
			notify("NTFS support is missing. Install the ntfs-3g package first.")
			return
		notify("Formatting " + device + " as " + fs + "...")
		# mkfs refuses to touch a mounted device; unmount it and any children.
		# mkfs itself can take a while on a large drive, so run it off the main
		# thread and report the result when it finishes.
		Sh.unmount_device(device)
		run_async(Sh.format_command(device, fs), func(code: int) -> void:
			if code == 0:
				notify(device + " formatted successfully as " + fs)
				_populate()
			else:
				notify("Format failed. Is the drive in use?")))
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


func _on_health(device: String) -> void:
	if not Sh.has_tool("smartctl"):
		notify("SMART tools are not installed. Install smartmontools first.")
		return
	notify("Checking SMART data for " + device + "… this can take a moment.")
	run_async_capture("pkexec smartctl -H " + Sh.quote(device), func(code: int, output: String) -> void:
		var text := output.strip_edges()
		if text.is_empty():
			text = "Could not read SMART data."
		elif code != 0:
			text += "\n\n(smartctl exited with status " + str(code) + ")"
		_show_smart(device, text))


func _show_smart(device: String, text: String) -> void:
	var result_dialog := AcceptDialog.new()
	result_dialog.title = "SMART Health: " + device
	result_dialog.size = Vector2i(720, 520)
	var edit := TextEdit.new()
	edit.text = text
	edit.editable = false
	edit.custom_minimum_size = Vector2(680, 460)
	result_dialog.add_child(edit)
	get_tree().root.add_child(result_dialog)
	result_dialog.popup_centered()
	result_dialog.confirmed.connect(result_dialog.queue_free)


# lsblk's JSON reports absent values as null; str(null) would print "null".
func _field(dev: Dictionary, key: String, fallback: String) -> String:
	var value: Variant = dev.get(key)
	if value == null:
		return fallback
	return str(value)
