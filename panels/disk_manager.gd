extends SettingsPanel
# Disk Manager: view disks, format, eject, and check health.
# Uses udisks2 for safe operations and lsblk/df for info.

var _disk_cards: Array = []


func build() -> void:
	page_header("Disk Manager", "Manage storage devices, format drives, and monitor health.")
	
	var c := card()
	info_row(c, "Scanning...", "Detecting storage devices")
	
	defer(_populate)


func _populate() -> void:
	# Clear the placeholder
	for child in content.get_children():
		if child is VBoxContainer and child.get_child_count() > 0:
			var first = child.get_child(0)
			if first is Label and "Scanning" in first.text:
				child.queue_free()
				break
	
	var devices := Sh.list_block_devices()
	if devices.is_empty():
		unavailable_row(content, "Could not read block devices.")
		return
	
	for dev in devices:
		_build_disk_card(dev)


func _build_disk_card(dev: Dictionary) -> void:
	var name: String = str(dev.get("name", "unknown"))
	var mountpoint: String = str(dev.get("mountpoint", ""))
	var size: String = str(dev.get("size", "?"))
	var dtype: String = str(dev.get("type", ""))
	var children: Array = dev.get("children", [])
	
	# Skip loop devices and ram disks
	if name.begins_with("loop") or name.begins_with("ram"):
		return
	
	var c := card()
	
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
		if usage["percent"] is int:
			var percent: int = usage["percent"]
			var bar := ProgressBar.new()
			bar.min_value = 0
			bar.max_value = 100
			bar.value = percent
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var usage_text := Label.new()
			usage_text.text = "Usage: " + usage["used"] + " / " + usage["total"] + " (" + str(percent) + "%)"
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
	dialog.text = "This will unmount all partitions and power off the device.\n\nAre you sure?"
	dialog.ok_text = "Eject"
	if dialog.popup() == OK:
		notify("Ejecting " + device + "...")
		var code := Sh.eject_drive(device)
		if code == 0:
			notify(device + " ejected safely. You may remove it.")
			_populate()  # Refresh
		else:
			notify("Failed to eject " + device)


func _on_format(device: String, size: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Format " + device + "?"
	dialog.text = "WARNING: This will ERASE ALL DATA on " + device + " (" + size + ").\n\nThis action cannot be undone."
	dialog.ok_text = "Format"
	dialog.add_cancel_button("Cancel")
	
	# Filesystem selector
	var fs_box := OptionButton.new()
	fs_box.add_item("FAT32 (Universal, ≤4GB files)")
	fs_box.add_item("NTFS (Windows/Linux, large files)")
	fs_box.add_item("ext4 (Linux native)")
	fs_box.selected = 0
	
	var vbox := VBoxContainer.new()
	vbox.add_child(Label.new().set_text("Filesystem:"))
	vbox.add_child(fs_box)
	dialog.add_child(vbox)
	
	if dialog.popup() == OK:
		var fs_map := {"vfat", "ntfs", "ext4"}
		var fs := fs_map[fs_box.selected]
		notify("Formatting " + device + " as " + fs + "...")
		var code := Sh.format_drive(device, fs)
		if code == 0:
			notify(device + " formatted successfully as " + fs)
			_populate()
		else:
			notify("Format failed. Is the drive in use?")


func _on_health(device: String) -> void:
	# Simple SMART check via smartctl
	notify("Checking SMART data for " + device + "...")
	var output := Sh.run_capture("pkexec smartctl -H " + Sh.quote(device) + " 2>&1")
	
	var result_dialog := AcceptDialog.new()
	result_dialog.title = "SMART Health: " + device
	result_dialog.text = output.strip_edges().is_empty() ? "Could not read SMART data." : output
	result_dialog.ok_text = "OK"
	result_dialog.popup()