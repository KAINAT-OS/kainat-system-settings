extends SettingsPanel
# Applications: defaults, startup, file associations and a native app manager.

# On-disk cache of `apt-cache pkgnames` (85k+ names, ~0.4s to regenerate).
# Header carries the count (so the "type at least 2 characters" hint needs no
# full read) and /var/lib/apt/lists' mtime (so an `apt update` invalidates it).
const _PKG_CACHE := "user://package-names.cache"
const _PKG_MAGIC := "#kainat-pkgcache v1"

var _package_cache: PackedStringArray = []
var _package_lower: PackedStringArray = []
var _apt_stamp: int = -1
var _results: ItemList
var _app_defaults_card: VBoxContainer
var _install_btn: Button = null
var _remove_btn: Button = null


func build() -> void:
	page_header("Applications", "Default apps, file associations, startup and software.")
	_build_static()
	defer(_populate_defaults)


func _build_static() -> void:
	section("Defaults")
	var c := card()
	_app_defaults_card = c
	kcm_row(c, "Default Applications", "Assign handlers for common tasks.", "D", "kcm_componentchooser")
	kcm_row(c, "File Associations", "Choose which app opens each file type.", "F", "kcm_filetypes")

	section("Startup")
	var c2 := card()
	kcm_row(c2, "Startup Applications", "Programs launched when you log in.", "S", "kcm_autostart")
	kcm_row(c2, "Background Services", "Services started with the session.", "B", "kcm_kded")
	kcm_row(c2, "Recent Files", "History used by recent-file menus.", "R", "kcm_recentFiles")

	section("Management")
	var c3 := card()
	nav_row(c3, "Application Manager", "Search, install and remove packages.", "A",
		func() -> void: _show_app_manager())
	kcm_row(c3, "Software Updates", "Configure update behaviour.", "U", "kcm_updates")
	kcm_row(c3, "Install Fonts", "Manage and preview system fonts.", "T", "kcm_fontinst")

	section("Application Style")
	var c4 := card()
	kcm_row(c4, "Application Style", "Window, widget and theme style.", "Y", "kcm_style")
	kcm_row(c4, "Qt Quick Settings", "Qt Quick Controls appearance.", "Q", "kcm_qtquicksettings")


func _default_handler(command: String) -> String:
	var out: String = Sh.run_capture(command + " 2>/dev/null").strip_edges()
	return out if not out.is_empty() else UNAVAILABLE


func _populate_defaults() -> void:
	info_row(_app_defaults_card, "Default Web Browser", _default_handler("xdg-settings get default-web-browser"))
	info_row(_app_defaults_card, "Default File Manager", _default_handler("xdg-mime query default inode/directory"))
	# Move the resolved defaults above the configuration rows.
	var count: int = _app_defaults_card.get_child_count()
	if count >= 2:
		_app_defaults_card.move_child(_app_defaults_card.get_child(count - 2), 0)
		_app_defaults_card.move_child(_app_defaults_card.get_child(count - 1), 1)


# --- native package manager ------------------------------------------------

func _show_app_manager() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Application Manager"
	dialog.size = Vector2i(780, 600)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(740, 540)
	dialog.add_child(box)

	var search := LineEdit.new()
	search.placeholder_text = "Search packages (e.g. firefox, gimp, editor)…"
	box.add_child(search)

	_results = ItemList.new()
	_results.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_results.custom_minimum_size = Vector2(0, 420)
	box.add_child(_results)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 8)
	box.add_child(actions)

	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh list"
	actions.add_child(refresh_btn)

	var remove_btn := Button.new()
	remove_btn.text = "Remove selected"
	remove_btn.disabled = true
	actions.add_child(remove_btn)
	_remove_btn = remove_btn

	var install_btn := Button.new()
	install_btn.text = "Install selected"
	install_btn.disabled = true
	actions.add_child(install_btn)
	_install_btn = install_btn

	search.text_changed.connect(func(text: String) -> void: _search_packages(text))
	search.text_submitted.connect(func(text: String) -> void: _search_packages(text))
	_results.item_selected.connect(func(_i: int) -> void:
		install_btn.disabled = false
		remove_btn.disabled = false)
	_results.nothing_selected.connect(func() -> void:
		install_btn.disabled = true
		remove_btn.disabled = true)
	install_btn.pressed.connect(_install_selected)
	remove_btn.pressed.connect(_remove_selected)
	refresh_btn.pressed.connect(func() -> void:
		if _rebuild_package_cache():
			notify("Package list refreshed (%d packages)." % _package_cache.size())
		else:
			notify("Could not read the package list — keeping the cached copy.")
		_search_packages(search.text))

	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)

	_search_packages("")


func _search_packages(query: String) -> void:
	_results.clear()
	_set_busy(false)
	var trimmed := query.strip_edges()
	if trimmed.length() < 2:
		# Header-only read: no need to load 85k names just for this hint.
		var hint := _package_count_hint()
		if hint > 0:
			_results.add_item("Type at least 2 characters to search %d available packages." % hint)
		else:
			_results.add_item("Type at least 2 characters to search available packages.")
		return

	var packages := _ensure_packages()
	if packages.is_empty():
		_results.add_item("Could not read the package list. Use \"Refresh list\" to rebuild it.")
		return

	var needle := trimmed.to_lower()
	var count: int = 0
	for i in packages.size():
		if _package_lower[i].contains(needle):
			_results.add_item(packages[i])
			count += 1
			if count >= 300:
				break
	if count == 0:
		_results.add_item("No packages match \"" + trimmed + "\".")


# --- package list cache -----------------------------------------------------

func _ensure_packages() -> PackedStringArray:
	if _package_cache.is_empty():
		_package_cache = _read_package_cache()
		if _package_cache.is_empty():
			_package_cache = Sh.run_lines("apt-cache pkgnames 2>/dev/null")
			_write_package_cache(_package_cache)
	if _package_lower.size() != _package_cache.size():
		_index_package_names()
	return _package_cache


# Rebuild from apt and overwrite the cache. Refuses to clobber a good cache
# with an empty run, so a transient apt failure can't wipe it.
func _rebuild_package_cache() -> bool:
	_apt_stamp = -1  # re-stat apt's lists so the fresh stamp gets stored
	var fresh: PackedStringArray = Sh.run_lines("apt-cache pkgnames 2>/dev/null")
	if fresh.is_empty():
		return false
	_package_cache = fresh
	_write_package_cache(_package_cache)
	_index_package_names()
	return true


# Index lowercase spellings once. Debian policy forces lowercase names (0 of
# the 85188 on this machine have an uppercase letter) but a foreign repo need
# not obey it, so both forms are kept rather than trusting that. Measured: a
# to_lower() per row cost 23.4ms per keystroke vs 4.05ms with this index,
# built once for 27ms.
func _index_package_names() -> void:
	_package_lower = PackedStringArray()
	_package_lower.resize(_package_cache.size())
	for i in _package_cache.size():
		_package_lower[i] = _package_cache[i].to_lower()


func _package_count_hint() -> int:
	if not _package_cache.is_empty():
		return _package_cache.size()
	var f := FileAccess.open(_PKG_CACHE, FileAccess.READ)
	if f == null:
		return -1
	var header := f.get_line()
	f.close()
	if not header.begins_with(_PKG_MAGIC):
		return -1
	return _header_int(header, "count")


func _read_package_cache() -> PackedStringArray:
	var f := FileAccess.open(_PKG_CACHE, FileAccess.READ)
	if f == null:
		return PackedStringArray()
	var lines := f.get_as_text().split("\n")
	f.close()
	if lines.is_empty() or not lines[0].begins_with(_PKG_MAGIC):
		return PackedStringArray()
	if _header_int(lines[0], "aptlists") != _apt_lists_stamp():
		return PackedStringArray()  # `apt update` landed since this was cached
	var names := lines.slice(1)
	if names.size() > 0 and names[names.size() - 1].is_empty():
		names.resize(names.size() - 1)  # trailing newline from the last row
	return names


func _write_package_cache(names: PackedStringArray) -> void:
	var f := FileAccess.open(_PKG_CACHE, FileAccess.WRITE)
	if f == null:
		push_warning("[KainatSettings] cannot write " + _PKG_CACHE)
		return
	f.store_string("%s count=%d aptlists=%d\n" % [_PKG_MAGIC, names.size(), _apt_lists_stamp()])
	if names.size() > 0:
		f.store_string("\n".join(names) + "\n")
	f.close()


# One stat() per session: /var/lib/apt/lists' mtime moves whenever apt adds or
# removes a package list, which is exactly when `apt-cache pkgnames` changes.
func _apt_lists_stamp() -> int:
	if _apt_stamp >= 0:
		return _apt_stamp
	_apt_stamp = 0
	if Sh.has_tool("stat"):
		var raw: String = Sh.run_capture("stat -c %Y /var/lib/apt/lists 2>/dev/null").strip_edges()
		if raw.is_valid_int():
			_apt_stamp = int(raw)
	return _apt_stamp


func _header_int(header: String, key: String) -> int:
	for part in header.split(" "):
		if part.begins_with(key + "="):
			var value: String = part.trim_prefix(key + "=")
			return int(value) if value.is_valid_int() else -1
	return -1


func _install_selected() -> void:
	var name := _selected_package()
	if name.is_empty():
		return
	notify("Installing " + name + "…")
	_set_busy(true)
	run_async("pkexec apt-get install -y -- " + Sh.quote(name), func(code: int) -> void:
		_set_busy(false)
		if code == 0:
			notify(name + " installed.")
		else:
			notify("Could not install " + name + "."))


func _remove_selected() -> void:
	var name := _selected_package()
	if name.is_empty():
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Remove Package?"
	dialog.text = "Remove " + name + " from this computer?\n\n" \
		+ "Packages that depend on it may be removed too."
	dialog.ok_text = "Remove"
	dialog.add_cancel_button("Cancel")
	dialog.confirmed.connect(func() -> void:
		notify("Removing " + name + "…")
		_set_busy(true)
		run_async(Sh.remove_command(name), func(code: int) -> void:
			_set_busy(false)
			if code == 0:
				notify(name + " removed.")
			else:
				notify("Could not remove " + name + ".")))
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


# The selected row as a validated package name, or "" for placeholder rows
# ("No packages match …") which are selectable too.
func _selected_package() -> String:
	if _results == null or not is_instance_valid(_results):
		return ""
	var selected: PackedInt32Array = _results.get_selected_items()
	if selected.is_empty():
		return ""
	var name: String = _results.get_item_text(selected[0]).strip_edges()
	# Quoting alone still lets a leading '-' be read as an option.
	if not _valid_package_name(name):
		notify("Not a package name: " + name)
		return ""
	return name


func _set_busy(busy: bool) -> void:
	if _install_btn != null and is_instance_valid(_install_btn):
		_install_btn.disabled = busy
	if _remove_btn != null and is_instance_valid(_remove_btn):
		_remove_btn.disabled = busy


# Debian policy package names: start alphanumeric, then [a-z0-9+.-], with an
# optional architecture qualifier (`foo:amd64` — `_` allowed there too, so a
# well-formed qualifier like `x86_64` is never rejected). Anything outside
# that — an option like `-y`, a path, a newline, a shell metacharacter — is
# rejected before it can reach apt, so safety never depends on quoting alone.
# Verified against the live repo: 0 of 85 188 names are rejected.
func _valid_package_name(name: String) -> bool:
	if name.is_empty() or name.length() > 256:
		return false
	var re := RegEx.new()
	if re.compile("\\A[a-z0-9][a-z0-9+.-]*(?::[a-z0-9][a-z0-9_-]*)?\\z") != OK:
		return false
	return re.search(name) != null