extends SettingsPanel
# Boot & Kernel: control the GRUB boot menu and clean up old kernels.
#
# Everything here writes to /etc/default/grub and then rebuilds the boot menu
# with update-grub, which is exactly the two-step terminal dance newcomers are
# told to memorise. The kernel section only ever offers kernels that are
# neither running nor the newest installed one.

const GRUB_FILE := "/etc/default/grub"

# Presets instead of a free slider: every change needs an admin prompt and a
# boot-menu rebuild, so a drag must not fire a dozen authentication dialogs.
const TIMEOUTS: Array = [0, 3, 5, 10, 20, 30, -1]
const TIMEOUT_LABELS: Array = [
	"0 seconds",
	"3 seconds",
	"5 seconds",
	"10 seconds",
	"20 seconds",
	"30 seconds",
	"Wait for a key",
]

var _timeout_row: OptionButton
var _default_row: OptionButton
var _menu_check: CheckButton
var _kernel_row: HBoxContainer
var _boot_row: HBoxContainer


func build() -> void:
	page_header("Boot & Kernel", "Choose how the boot menu behaves and keep the kernel tidy.")

	if FileAccess.file_exists(GRUB_FILE):
		_build_boot_menu()
	else:
		section("Boot Menu")
		var missing := card()
		unavailable_row(missing, "GRUB Not Found",
				"This system does not use the GRUB boot loader, so the boot menu options are not available.", "!")

	_build_kernel()


func _build_boot_menu() -> void:
	section("Boot Menu")
	var c := card()

	var intro := Label.new()
	intro.text = "The boot menu appears before your system starts. These changes ask for your password once and rebuild the menu immediately."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", _muted())
	c.add_child(intro)

	var timeout := _grub_int("GRUB_TIMEOUT", 5)
	var timeout_index := 0
	for i in TIMEOUTS.size():
		if int(TIMEOUTS[i]) == timeout:
			timeout_index = i
	_timeout_row = choice_row(c, "Menu Timeout",
			"How long the boot menu waits before starting the default system.",
			"◷", TIMEOUT_LABELS, timeout_index, _on_timeout_selected)

	var default_value := _grub_value("GRUB_DEFAULT", "0")
	_default_row = choice_row(c, "Default System",
			"Which entry starts automatically when the menu closes.",
			"★", ["First menu entry", "Last system used"],
			1 if default_value == "saved" else 0, _on_default_selected)

	_menu_check = toggle_row(c, "Show Boot Menu",
			"Turn off to boot straight to the default system unless a key is held.",
			"▤", _menu_visible(), _on_menu_toggled)


func _build_kernel() -> void:
	section("Kernel")
	var c := card()

	_kernel_row = info_row(c, "Running Kernel", _running_kernel())
	_boot_row = info_row(c, "Boot Space", _boot_usage())
	info_row(c, "Installed Kernels", "%d installed" % _kernels().size())

	action_row(c, "View Installed Kernels",
			"See every kernel on this computer and which one is running.",
			"≡", "View", _show_kernels)
	action_row(c, "Update Boot Menu",
			"Rebuild the boot menu after installing or removing a kernel.",
			"↻", "Update", _update_grub)
	action_row(c, "Remove Old Kernels",
			"Free disk space by deleting kernels you no longer need.",
			"⌫", "Choose…", _remove_dialog)
	action_row(c, "Kernel Parameters",
			"Advanced options passed to the kernel at startup.",
			"⚙", "Show", _show_parameters)

	var note := Label.new()
	note.text = "The running kernel and the newest installed kernel are always kept. Removing an old kernel cannot be undone without reinstalling it."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", _muted())
	c.add_child(note)

	defer(_refresh_kernel_rows)


# --- GRUB configuration ------------------------------------------------------

func _grub_value(key: String, fallback: String) -> String:
	for line: String in Sh.read_text(GRUB_FILE).split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with(key + "="):
			var value := trimmed.substr(key.length() + 1).strip_edges()
			return value.trim_prefix("\"").trim_suffix("\"")
	return fallback


func _grub_int(key: String, fallback: int) -> int:
	var raw := _grub_value(key, str(fallback))
	return int(raw) if raw.is_valid_int() else fallback


func _menu_visible() -> bool:
	return _grub_value("GRUB_TIMEOUT_STYLE", "menu") == "menu" or _grub_int("GRUB_TIMEOUT", 5) != 0


func _on_timeout_selected(index: int) -> void:
	if index < 0 or index >= TIMEOUTS.size():
		return
	var value: int = int(TIMEOUTS[index])
	var updates: Dictionary = {"GRUB_TIMEOUT": str(value)}
	if value != 0:
		updates["GRUB_TIMEOUT_STYLE"] = "menu"
	_apply_grub(updates, "Boot menu timeout updated.")


func _on_default_selected(index: int) -> void:
	var value := "saved" if index == 1 else "0"
	_apply_grub({"GRUB_DEFAULT": value}, "Default boot system updated.")


func _on_menu_toggled(shown: bool) -> void:
	if shown:
		var updates: Dictionary = {"GRUB_TIMEOUT_STYLE": "menu"}
		if _grub_int("GRUB_TIMEOUT", 5) == 0:
			updates["GRUB_TIMEOUT"] = "5"
		_apply_grub(updates, "The boot menu will be shown at startup.")
	else:
		_apply_grub({"GRUB_TIMEOUT_STYLE": "hidden", "GRUB_TIMEOUT": "0"},
				"The boot menu will be hidden at startup.")


# Edits a copy of the file in memory, writes it to a temp file, then installs it
# with one admin prompt and rebuilds the menu. The original is kept as
# /etc/default/grub.kainat-backup so a bad edit is always recoverable.
func _apply_grub(updates: Dictionary, success_message: String) -> void:
	var text := Sh.read_text(GRUB_FILE)
	if text.is_empty():
		notify("Could not read " + GRUB_FILE + ".")
		return

	var lines: PackedStringArray = text.split("\n")
	for key: Variant in updates.keys():
		var name := str(key)
		var line_value := str(updates[key])
		var replaced := false
		for i in lines.size():
			if lines[i].strip_edges().begins_with(name + "="):
				lines[i] = name + "=" + line_value
				replaced = true
				break
		if not replaced:
			lines.append(name + "=" + line_value)

	var content := "\n".join(lines)
	if not content.ends_with("\n"):
		content += "\n"

	var tmp := "/tmp/kainat-grub-%d.conf" % Time.get_ticks_usec()
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		notify("Could not prepare the new boot configuration.")
		return
	file.store_string(content)
	file.close()

	var script := "cp " + Sh.quote(GRUB_FILE) + " " + Sh.quote(GRUB_FILE + ".kainat-backup") \
			+ " && install -m 644 " + Sh.quote(tmp) + " " + Sh.quote(GRUB_FILE) \
			+ " && /usr/sbin/update-grub"
	run_async("pkexec sh -c " + Sh.quote(script), func(code: int, _text: String) -> void:
		DirAccess.remove_absolute(tmp)
		if code == 0:
			notify(success_message)
		else:
			notify("Could not update the boot menu. Your previous settings are in grub.kainat-backup.")
		_refresh())


func _refresh() -> void:
	if is_instance_valid(_timeout_row):
		var timeout := _grub_int("GRUB_TIMEOUT", 5)
		for i in TIMEOUTS.size():
			if int(TIMEOUTS[i]) == timeout:
				_timeout_row.select(i)
				break
	if is_instance_valid(_default_row):
		_default_row.select(1 if _grub_value("GRUB_DEFAULT", "0") == "saved" else 0)
	if is_instance_valid(_menu_check):
		_menu_check.set_pressed_no_signal(_menu_visible())
	_refresh_kernel_rows()


func _refresh_kernel_rows() -> void:
	if is_instance_valid(_kernel_row):
		set_info_value(_kernel_row, _running_kernel())
	if is_instance_valid(_boot_row):
		set_info_value(_boot_row, _boot_usage())


func _update_grub() -> void:
	run_async("pkexec /usr/sbin/update-grub", func(code: int, text: String) -> void:
		if code == 0:
			notify("Boot menu rebuilt.")
		else:
			notify("Could not rebuild the boot menu: " + _tail(text)))


# --- kernels -----------------------------------------------------------------

func _running_kernel() -> String:
	var raw := Sh.run_capture("uname -r").strip_edges()
	return raw if not raw.is_empty() else "Unknown"


func _boot_usage() -> String:
	var raw := Sh.run_capture("df -h /boot 2>/dev/null | tail -n 1")
	var parts := raw.split(" ", false)
	if parts.size() < 6:
		return "Unknown"
	return "%s of %s used (%s free)" % [parts[2], parts[1], parts[3]]


# Newest last. Uses sort -V so 7.0.9 correctly ranks above 6.19.11.
func _kernels() -> Array:
	var result: Array = []
	var versions := Sh.run_lines("ls -1 /boot/vmlinuz-* 2>/dev/null | sed 's|.*/vmlinuz-||' | sort -V")
	if versions.is_empty():
		return result
	var installed := _installed_packages("linux-image-*")
	var running := _running_kernel()
	var newest := str(versions[versions.size() - 1])
	for v: String in versions:
		var image := "linux-image-" + v
		if not installed.has(image) and not installed.has(image + "-unsigned"):
			continue
		result.append({
			"version": v,
			"running": v == running,
			"newest": v == newest,
			"removable": v != running and v != newest,
		})
	return result


func _installed_packages(pattern: String) -> Dictionary:
	var found: Dictionary = {}
	var raw := Sh.run_capture("dpkg-query -W -f='${Package} ${Status}\\n' " + Sh.quote(pattern) + " 2>/dev/null")
	for line: String in raw.split("\n"):
		var parts := line.split(" ", false)
		if parts.size() >= 4 and parts[3] == "installed":
			found[str(parts[0])] = true
	return found


func _removal_candidates() -> Array:
	var candidates: Array = []
	for kernel: Dictionary in _kernels():
		if bool(kernel["removable"]):
			candidates.append(kernel)
	return candidates


# Removing linux-image alone leaves modules and headers behind, so collect the
# matching companion packages that are actually installed.
func _packages_for(kernels: Array) -> Array:
	var installed := _installed_packages("linux-*")
	var packages: Array = []
	for kernel: Dictionary in kernels:
		var version := str(kernel["version"])
		var candidates: Array[String] = [
			"linux-image-" + version,
			"linux-image-" + version + "-unsigned",
			"linux-image-unsigned-" + version,
			"linux-modules-" + version,
			"linux-modules-extra-" + version,
			"linux-latest-modules-" + version,
			"linux-headers-" + version,
			"linux-buildinfo-" + version,
			"linux-kbuild-" + version,
		]
		# Debian-style versions carry the architecture as the last segment,
		# while their shared -common header package drops it.
		var short_version := version.substr(0, version.rfind("-"))
		if short_version != version and not short_version.is_empty():
			candidates.append("linux-headers-" + short_version + "-common")
			candidates.append("linux-kbuild-" + short_version)
		for name: String in candidates:
			if installed.has(name):
				packages.append(name)
	return packages


func _show_kernels() -> void:
	var kernels := _kernels()
	if kernels.is_empty():
		notify("No kernels were found in /boot.")
		return
	var lines := PackedStringArray()
	for kernel: Dictionary in kernels:
		var marks: Array[String] = []
		if bool(kernel["running"]):
			marks.append("running")
		if bool(kernel["newest"]):
			marks.append("newest")
		var suffix := "" if marks.is_empty() else "  (" + ", ".join(marks) + ")"
		lines.append(str(kernel["version"]) + suffix)
	_show_text("Installed Kernels", "\n".join(lines))


func _show_parameters() -> void:
	var current := _grub_value("GRUB_CMDLINE_LINUX_DEFAULT", "")
	var permanent := _grub_value("GRUB_CMDLINE_LINUX", "")
	var lines := PackedStringArray()
	lines.append("Default kernel parameters:")
	lines.append(current if not current.is_empty() else "(none)")
	lines.append("")
	lines.append("Always-applied parameters:")
	lines.append(permanent if not permanent.is_empty() else "(none)")
	lines.append("")
	lines.append("These are advanced options. Change them with care: a typo can stop the system from starting.")
	_show_text("Kernel Parameters", "\n".join(lines))


func _show_text(title: String, text: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = title
	dialog.size = Vector2i(640, 420)
	var edit := TextEdit.new()
	edit.text = text
	edit.editable = false
	edit.custom_minimum_size = Vector2(600, 360)
	dialog.add_child(edit)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)


func _remove_dialog() -> void:
	var candidates := _removal_candidates()
	if candidates.is_empty():
		notify("There are no old kernels to remove.")
		return

	var dialog := ConfirmationDialog.new()
	dialog.title = "Remove Old Kernels"
	dialog.ok_button_text = "Remove Selected"
	dialog.add_cancel_button("Cancel")
	dialog.dialog_hide_on_ok = false

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 8)
	dialog.add_child(box)

	var hint := Label.new()
	hint.text = "Select the kernels to remove. The running kernel and the newest installed kernel are always kept."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	var checks: Array = []
	for kernel: Dictionary in candidates:
		var check := CheckBox.new()
		check.text = str(kernel["version"])
		box.add_child(check)
		checks.append(check)

	var error := Label.new()
	error.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(error)

	dialog.confirmed.connect(func() -> void:
		var selected: Array = []
		for i in checks.size():
			if (checks[i] as CheckBox).button_pressed:
				selected.append(candidates[i])
		if selected.is_empty():
			error.text = "Select at least one kernel to remove."
			return
		var packages := _packages_for(selected)
		if packages.is_empty():
			error.text = "No removable packages were found for that kernel."
			return
		var quoted: Array = []
		for name: String in packages:
			quoted.append(Sh.quote(name))
		var command := "apt-get purge -y " + " ".join(quoted) + " && /usr/sbin/update-grub"
		dialog.queue_free()
		run_async("pkexec sh -c " + Sh.quote(command), func(code: int, text: String) -> void:
			if code == 0:
				notify("Old kernels removed.")
			else:
				notify("Could not remove the selected kernels: " + _tail(text))
			_refresh()))

	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.canceled.connect(dialog.queue_free)


func _tail(text: String) -> String:
	var lines: PackedStringArray = text.strip_edges().split("\n")
	var out: Array[String] = []
	for i in range(maxi(0, lines.size() - 3), lines.size()):
		var line: String = lines[i].strip_edges()
		if not line.is_empty():
			out.append(line)
	return " ".join(out).substr(0, 240)
