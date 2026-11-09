extends Node
# SearchManager — autoload that indexes all settings rows across panels
# and provides search + highlight functionality.

var _index: Array = []  # [{panel, title, subtitle, glyph}]


func _ready() -> void:
	_build_index()


func _build_index() -> void:
	_index.clear()
	var dir := DirAccess.open("res://panels")
	if not dir:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.ends_with(".gd") and not entry.begins_with("."):
			var panel_name := entry.trim_suffix(".gd")
			_scan_panel(panel_name)
		entry = dir.get_next()


func _scan_panel(panel_name: String) -> void:
	var path := "res://panels/%s.gd" % panel_name
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var text := file.get_as_text()
	file.close()

	# Match row creation calls: kcm_row, nav_row, action_row, toggle_row,
	# slider_row, choice_row, info_row — extract title and subtitle.
	var regex := RegEx.new()
	regex.compile("(?:kcm_row|nav_row|action_row|toggle_row|slider_row|choice_row|info_row)\\([^,]+,\\s*\"([^\"]+)\"(?:,\\s*\"([^\"]*)\")?")
	# A row written as an if/else — a "no modes reported" fallback next to the
	# real control, or an installed branch next to its "not installed" one —
	# matches twice in the source but only ever renders once. Without this the
	# results list showed the same entry twice (e.g. "Resolution" in displays).
	var seen: Dictionary = {}
	for m in regex.search_all(text):
		var title := m.get_string(1)
		if seen.has(title):
			continue
		seen[title] = true
		var subtitle := m.get_string(2)
		_index.append({
			"panel": panel_name,
			"title": title,
			"subtitle": subtitle,
		})


func search(query: String) -> Array:
	if query.strip_edges().length() < 2:
		return []
	var needle := query.to_lower()
	var results: Array = []
	for item in _index:
		var title: String = item["title"]
		var subtitle: String = item["subtitle"]
		if title.to_lower().contains(needle) or subtitle.to_lower().contains(needle):
			results.append(item)
	# Sort: title matches first, then alphabetical
	results.sort_custom(func(a, b):
		var a_title: String = a["title"].to_lower()
		var b_title: String = b["title"].to_lower()
		var a_has := a_title.begins_with(needle)
		var b_has := b_title.begins_with(needle)
		if a_has != b_has:
			return a_has
		return a_title < b_title)
	return results


func get_index_size() -> int:
	return _index.size()
