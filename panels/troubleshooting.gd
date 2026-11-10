extends SettingsPanel
# Troubleshooting — checks the common failure points on a Kainat OS machine and
# offers one-click repairs, so nothing here requires a terminal.

var _audio_row: HBoxContainer
var _network_row: HBoxContainer
var _packages_row: HBoxContainer
var _disk_row: HBoxContainer
var _services_row: HBoxContainer


func build() -> void:
	page_header("Troubleshooting", "Find out what is wrong and fix it without a terminal.")

	section("System Check")
	var c := card()
	_audio_row = info_row(c, "Sound", "Checking…")
	_network_row = info_row(c, "Network", "Checking…")
	_packages_row = info_row(c, "Package Database", "Checking…")
	_disk_row = info_row(c, "Free Space", "Checking…")
	_services_row = info_row(c, "Failed Services", "Checking…")
	action_row(c, "Check Again", "Re-test everything above.", "R", "Check", _refresh)

	section("Quick Fixes")
	var c2 := card()
	action_row(c2, "Restart Sound", "Fixes missing audio after login or a device change.", "A", "Restart",
		_restart_audio)
	action_row(c2, "Restart Networking", "Reconnects Wi-Fi and Ethernet when the network stops responding.", "N", "Restart",
		_restart_network)
	action_row(c2, "Rebuild Font Cache", "Repairs missing or garbled text in applications.", "F", "Rebuild",
		_rebuild_fonts)
	action_row(c2, "Clear Thumbnail Cache", "Frees space and fixes wrong or missing previews.", "T", "Clear",
		_clear_thumbnails)
	action_row(c2, "Empty the Trash", "Permanently removes deleted files. Your documents are untouched.", "E", "Empty",
		_empty_trash)

	section("Package Problems")
	var c3 := card()
	action_row(c3, "Repair Package Database", "Finishes interrupted installs and repairs broken dependencies.", "P", "Repair",
		_repair_packages)
	action_row(c3, "Remove Stale Locks", "Clears the lock left behind when an update crashes.", "L", "Remove",
		_remove_locks)
	action_row(c3, "Free Up Disk Space", "Deletes downloaded package files that are no longer needed.", "D", "Clean",
		_clean_cache)

	section("Logs")
	var c4 := card()
	action_row(c4, "Recent Errors", "The most serious messages from this boot.", "E", "View",
		func() -> void: _show_journal("-p 3 -b --no-pager", "Recent Errors"))
	action_row(c4, "Boot Messages", "Kernel messages from this boot.", "B", "View",
		func() -> void: _show_journal("-k -b --no-pager", "Boot Messages"))
	action_row(c4, "Failed Services", "Full status of every service that did not start.", "S", "View",
		_show_failed_services)

	defer(_refresh)


func _refresh() -> void:
	set_info_value(_audio_row, _audio_status())
	set_info_value(_network_row, _network_status())
	set_info_value(_packages_row, _package_status())
	set_info_value(_disk_row, _disk_status())
	set_info_value(_services_row, _service_status())


func _audio_status() -> String:
	if not Sh.has_tool("pactl"):
		return "Sound tools are not installed"
	var info := Sh.run_capture("pactl info 2>/dev/null")
	if info.contains("Server Name"):
		return "Working"
	return "Not running — use Restart Sound"


func _network_status() -> String:
	if Sh.has_tool("nmcli"):
		var state := Sh.run_capture("nmcli -t -f STATE general 2>/dev/null").strip_edges()
		if state == "connected":
			return "Connected"
		if state == "connecting":
			return "Connecting…"
		if not state.is_empty():
			return state.capitalize()
	var route := Sh.run_capture("ip route show default 2>/dev/null").strip_edges()
	if route.is_empty():
		return "Not connected"
	return "Connected"


func _package_status() -> String:
	var audit := Sh.run_capture("dpkg --audit 2>/dev/null").strip_edges()
	if audit.is_empty():
		return "Healthy"
	var count := audit.split("\n", false).size()
	return "Needs repair (%d problem%s)" % [count, "" if count == 1 else "s"]


func _disk_status() -> String:
	var usage: Dictionary = Sh.get_disk_usage("/")
	if int(usage.get("total", 0)) == 0:
		return "Could not read disk usage"
	var percent := int(usage.get("percent", 0))
	var text := "%d%% used, %s free" % [percent, str(usage.get("available", "?"))]
	if percent >= 90:
		text += " — running low"
	return text


func _service_status() -> String:
	var failed := Sh.run_capture("systemctl --failed --no-legend 2>/dev/null").strip_edges()
	if failed.is_empty():
		return "None"
	var count := failed.split("\n", false).size()
	return "%d service%s did not start" % [count, "" if count == 1 else "s"]


# --- quick fixes -------------------------------------------------------------

func _restart_audio() -> void:
	notify("Restarting sound…")
	var code := Sh.run_wait("systemctl --user restart pipewire pipewire-pulse wireplumber")
	if code != 0:
		# A session without user units can still be repaired through the
		# system-wide service.
		code = Sh.run_wait("pkexec systemctl restart pipewire pipewire-pulse wireplumber")
	if code == 0:
		notify("Sound restarted.")
	else:
		notify("Could not restart the sound service.")
	_refresh()


func _restart_network() -> void:
	run_async("pkexec systemctl restart NetworkManager", func(code: int) -> void:
		if code == 0:
			notify("Networking restarted.")
		else:
			notify("Could not restart networking.")
		_refresh())


func _rebuild_fonts() -> void:
	run_async("fc-cache -f", func(code: int) -> void:
		if code == 0:
			notify("Font cache rebuilt.")
		else:
			notify("Could not rebuild the font cache."))


func _clear_thumbnails() -> void:
	var dir := Sh.home().path_join(".cache/thumbnails")
	run_async("sh -c " + Sh.quote("rm -rf " + Sh.quote(dir) + "/*"), func(code: int) -> void:
		if code == 0:
			notify("Thumbnail cache cleared.")
		else:
			notify("Could not clear the thumbnail cache."))


func _empty_trash() -> void:
	var dir := Sh.home().path_join(".local/share/Trash/files")
	_confirm("Empty the Trash?", "Every file in the Trash will be deleted permanently.\n\nYour documents, downloads and pictures are not affected.", "Empty Trash", func() -> void:
		run_async("sh -c " + Sh.quote("rm -rf " + Sh.quote(dir) + "/*"), func(code: int) -> void:
			if code == 0:
				notify("Trash emptied.")
			else:
				notify("Could not empty the Trash.")))


# --- package problems --------------------------------------------------------

func _repair_packages() -> void:
	_confirm("Repair Package Database?", "This finishes interrupted installs and repairs broken dependencies. It can take a few minutes.\n\nLeave the computer on until it finishes.", "Repair", func() -> void:
		notify("Repairing packages…")
		run_async_capture("pkexec sh -c 'dpkg --configure -a; apt-get -f install -y'", func(code: int, text: String) -> void:
			if code == 0:
				notify("Package database repaired.")
			else:
				notify("Repair failed: " + _tail(text))
			_refresh()))


func _remove_locks() -> void:
	_confirm("Remove Stale Locks?", "Only do this when no other update or software installer is running.\n\nIf a package manager is still working, nothing is removed.", "Remove Locks", func() -> void:
		var script := "if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then echo BUSY; " \
			+ "else rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock " \
			+ "/var/cache/apt/archives/lock; echo CLEARED; fi"
		run_async_capture("pkexec sh -c " + Sh.quote(script), func(code: int, text: String) -> void:
			if text.contains("BUSY"):
				notify("A package manager is still running. Try again when it finishes.")
			elif text.contains("CLEARED"):
				notify("Stale locks removed.")
			else:
				notify("Could not remove the locks: " + _tail(text))
			_refresh()))


func _clean_cache() -> void:
	var before := _cache_size()
	run_async_capture("pkexec apt-get clean", func(code: int, _text: String) -> void:
		if code != 0:
			notify("Could not clean the package cache.")
			return
		var after := _cache_size()
		if before > after:
			notify("Freed %s." % _human_size(before - after))
		else:
			notify("Package cache cleared.")
		_refresh())


func _cache_size() -> int:
	var text := Sh.run_capture("du -sk /var/cache/apt/archives 2>/dev/null").strip_edges()
	var parts := text.split("\t", false)
	if parts.size() >= 1 and parts[0].is_valid_int():
		return int(parts[0]) * 1024
	return 0


func _human_size(bytes: int) -> String:
	if bytes >= 1024 * 1024 * 1024:
		return "%.1f GB" % (float(bytes) / (1024.0 * 1024.0 * 1024.0))
	if bytes >= 1024 * 1024:
		return "%.0f MB" % (float(bytes) / (1024.0 * 1024.0))
	return "%d KB" % maxi(1, bytes / 1024)


# --- logs --------------------------------------------------------------------

func _show_journal(arguments: String, title: String) -> void:
	run_async_capture("journalctl " + arguments + " 2>&1 | tail -n 60", func(_code: int, text: String) -> void:
		var body := text.strip_edges()
		if body.is_empty():
			body = "No messages were recorded."
		_show_text(title, body))


func _show_failed_services() -> void:
	run_async_capture("systemctl --failed --no-pager --full 2>&1", func(_code: int, text: String) -> void:
		var body := text.strip_edges()
		if body.is_empty():
			body = "No services have failed."
		_show_text("Failed Services", body))


func _show_text(title: String, text: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = title
	dialog.size = Vector2i(680, 440)
	var edit := TextEdit.new()
	edit.text = text
	edit.editable = false
	edit.custom_minimum_size = Vector2(640, 380)
	dialog.add_child(edit)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)


func _tail(text: String) -> String:
	var lines := text.strip_edges().split("\n", false)
	var start := maxi(0, lines.size() - 3)
	var picked := PackedStringArray()
	for i in range(start, lines.size()):
		picked.append(lines[i].strip_edges())
	return " ".join(picked)


func _confirm(title: String, text: String, ok: String, on_yes: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.dialog_text = text
	dialog.ok_button_text = ok
	dialog.add_cancel_button("Cancel")
	dialog.confirmed.connect(func() -> void: on_yes.call())
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
