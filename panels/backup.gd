extends SettingsPanel
# Backups: snapshots of the whole system with Timeshift, plus a simple
# archive of the home folder for people who just want their files safe.
#
# Nothing here needs a terminal: Timeshift runs through pkexec, and the home
# archive is a normal tar file written wherever the user points it.

const TIMESHIFT_CONF := "/etc/timeshift/timeshift.json"

var _tool_row: HBoxContainer
var _drive_row: HBoxContainer
var _schedule_row: HBoxContainer
var _kept_row: HBoxContainer
var _home_row: HBoxContainer


func build() -> void:
	page_header("Backups", "Protect your system and files, and undo changes when something goes wrong.")

	section("System Snapshots")
	var c := card()
	_tool_row = info_row(c, "Backup Tool", "…")
	_drive_row = info_row(c, "Backup Drive", "…")
	_schedule_row = info_row(c, "Schedule", "…")
	_kept_row = info_row(c, "Snapshots Kept", "…")
	_home_row = info_row(c, "Includes Home Folder", "…")

	if not Sh.has_tool("timeshift"):
		set_info_value(_tool_row, "Not installed")
		unavailable_row(c, "System Snapshots", "Timeshift is not installed. Install it to snapshot the system.", "B")
		action_row(c, "Install Timeshift", "Adds Timeshift with the system package manager.", "I", "Install", _install_timeshift)
	else:
		action_row(c, "Create Snapshot Now", "Saves the current state of the system so you can return to it.", "C", "Create", _create_snapshot)
		action_row(c, "View Snapshots", "List every snapshot with its date and size.", "L", "View", _list_snapshots)
		action_row(c, "Restore or Browse", "Opens Timeshift to restore a snapshot or explore its files.", "R", "Open", _open_timeshift)
		action_row(c, "Backup Settings", "Choose the drive, schedule and what to include.", "S", "Settings", _open_timeshift_settings)

	section("Home Folder Archive")
	var c2 := card()
	var note := Label.new()
	note.text = "A snapshot covers the system; this archive is a single compressed file of your personal files that you can copy to another drive."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", _muted())
	c2.add_child(note)
	action_row(c2, "Back Up Home Folder", "Creates a .tar.gz of your files in a folder you choose.", "H", "Choose Folder", _backup_home)
	info_row(c2, "What Is Skipped", "Caches, trash and temporary files are left out to keep the archive small.")

	section("Good to Know")
	var c3 := card()
	info_row(c3, "Snapshots Are Incremental", "Only changed files take space, so keeping several is cheap.")
	info_row(c3, "System Only", "By default Timeshift does not include your home folder; use the archive above for files.")
	info_row(c3, "Before Big Changes", "Create a snapshot before driver updates or major upgrades.")

	defer(_refresh_status)


func _install_timeshift() -> void:
	notify("Installing Timeshift…")
	run_async(Sh.install_command("timeshift"), func(code: int) -> void:
		if code == 0:
			Sh.clear_tool_cache()
			notify("Timeshift installed. Open the Backups page again.")
		else:
			notify("Could not install Timeshift (exit code " + str(code) + ")."))


func _conf() -> Dictionary:
	var text := Sh.read_text(TIMESHIFT_CONF)
	if text.is_empty():
		return {}
	var data: Variant = JSON.parse_string(text)
	if data is Dictionary:
		return data
	return {}


func _refresh_status() -> void:
	if not Sh.has_tool("timeshift"):
		return
	var conf := _conf()
	set_info_value(_tool_row, "Timeshift installed")

	var uuid := str(conf.get("backup_device_uuid", ""))
	set_info_value(_drive_row, _drive_name(uuid))

	var schedule := _schedule_text(conf)
	set_info_value(_schedule_row, schedule)

	var kept := 0
	for key in ["count_daily", "count_weekly", "count_monthly", "count_hourly", "count_boot"]:
		kept += str(conf.get(key, "0")).to_int()
	set_info_value(_kept_row, str(kept) + " snapshots" if kept > 0 else "Not configured")

	set_info_value(_home_row, "No (system files only)")


func _drive_name(uuid: String) -> String:
	if uuid.is_empty():
		return "Not chosen"
	var link := "/dev/disk/by-uuid/" + uuid
	var resolved := Sh.run_capture("readlink -f " + Sh.quote(link) + " 2>/dev/null").strip_edges()
	if resolved.is_empty() or not resolved.begins_with("/dev/"):
		return "Not connected (" + uuid.substr(0, 8) + "…)"
	return resolved.get_file() + " (" + resolved + ")"


func _schedule_text(conf: Dictionary) -> String:
	if conf.is_empty():
		return "Unknown"
	var parts: Array[String] = []
	if str(conf.get("schedule_hourly", "false")) == "true":
		parts.append("hourly")
	if str(conf.get("schedule_daily", "false")) == "true":
		parts.append("daily")
	if str(conf.get("schedule_weekly", "false")) == "true":
		parts.append("weekly")
	if str(conf.get("schedule_monthly", "false")) == "true":
		parts.append("monthly")
	if str(conf.get("schedule_boot", "false")) == "true":
		parts.append("at every boot")
	if parts.is_empty():
		return "Off (manual snapshots only)"
	return ", ".join(parts)


func _create_snapshot() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Create Snapshot?"
	dialog.dialog_text = "Save the current state of the system now?\n\nThis can take a few minutes and needs your password."
	dialog.ok_button_text = "Create"
	dialog.add_cancel_button("Cancel")
	dialog.confirmed.connect(func() -> void:
		notify("Creating a snapshot… this can take a few minutes.")
		run_async("pkexec timeshift --create --comments " + Sh.quote("Manual snapshot from Kainat System Settings") + " --tags D", func(code: int) -> void:
			if code == 0:
				notify("Snapshot created.")
			else:
				notify("Could not create the snapshot (exit code " + str(code) + "). See View Snapshots for details.")))
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


func _list_snapshots() -> void:
	notify("Reading snapshots…")
	run_async_capture("pkexec timeshift --list", func(_code: int, text: String) -> void:
		var body := text.strip_edges()
		if body.is_empty():
			body = "No snapshots were reported. Use “Create Snapshot Now” to make the first one."
		var dialog := AcceptDialog.new()
		dialog.title = "Timeshift Snapshots"
		dialog.size = Vector2i(760, 540)
		var edit := TextEdit.new()
		edit.text = body
		edit.editable = false
		edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		edit.custom_minimum_size = Vector2(720, 480)
		dialog.add_child(edit)
		dialog.ok_button_text = "Close"
		get_tree().root.add_child(dialog)
		dialog.popup_centered()
		dialog.confirmed.connect(dialog.queue_free)
		dialog.canceled.connect(dialog.queue_free))


func _open_timeshift() -> void:
	if not _launch("timeshift-gtk"):
		notify("Timeshift's window could not be opened.")


func _open_timeshift_settings() -> void:
	if not _launch("timeshift-gtk --settings"):
		notify("Timeshift's settings could not be opened.")


func _launch(command: String) -> bool:
	var pid := OS.create_process("pkexec", command.split(" ", false))
	return pid > 0


func _backup_home() -> void:
	var dialog := FileDialog.new()
	dialog.title = "Choose where to save the archive"
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.current_dir = OS.get_environment("HOME")
	dialog.dir_selected.connect(func(path: String) -> void:
		dialog.queue_free()
		_confirm_home_backup(path))
	dialog.canceled.connect(dialog.queue_free)
	get_tree().root.add_child(dialog)
	dialog.popup_centered_ratio(0.6)


func _confirm_home_backup(folder: String) -> void:
	var home := OS.get_environment("HOME")
	if home.is_empty() or not DirAccess.dir_exists_absolute(folder):
		notify("That folder cannot be written to.")
		return
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var target := folder.path_join("home-backup-" + stamp + ".tar.gz")

	var dialog := ConfirmationDialog.new()
	dialog.title = "Back Up Home Folder?"
	dialog.dialog_text = "Create an archive of your personal files here?\n\n" + target + "\n\nLarge folders can take a while."
	dialog.ok_button_text = "Start Backup"
	dialog.add_cancel_button("Cancel")
	dialog.confirmed.connect(func() -> void: _run_home_backup(home, target))
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


func _run_home_backup(home: String, target: String) -> void:
	notify("Backing up your home folder…")
	var command := "tar -czf " + Sh.quote(target) + " -C " + Sh.quote(home) \
		+ " --exclude=./.cache --exclude=./.local/share/Trash --exclude=./.local/share/baloo" \
		+ " --exclude=./snap --exclude=./.var/app/*/cache ."
	run_async_capture(command, func(code: int, text: String) -> void:
		if code != 0:
			notify("Backup failed: " + _tail(text))
			return
		var size := Sh.run_capture("du -h " + Sh.quote(target) + " 2>/dev/null").strip_edges()
		var shown := size.split("\t")[0] if not size.is_empty() else ""
		notify("Home folder backed up" + (" (" + shown + ")" if not shown.is_empty() else "") + "."))


func _tail(text: String) -> String:
	var lines: PackedStringArray = text.strip_edges().split("\n")
	var start := maxi(0, lines.size() - 4)
	var out: Array[String] = []
	for i in range(start, lines.size()):
		var line: String = lines[i].strip_edges()
		if not line.is_empty():
			out.append(line)
	var joined := " ".join(out)
	if joined.length() > 300:
		joined = joined.substr(0, 300) + "…"
	return joined
