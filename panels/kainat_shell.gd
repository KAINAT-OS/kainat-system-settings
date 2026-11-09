class_name KainatShell
# KainatShell.gd
# Small helper layer for interacting with the Debian/Kainat OS system from
# GDScript panels. Keeps every panel free of shell-quoting boilerplate.
#
# All helpers are static so panels can call them without an instance.

const KCM_FALLBACK_TOOLS: Array[String] = ["kcmshell6", "kcmshell5", "kcmshell", "systemsettings"]

static var _tool_cache: Dictionary = {}


# --- process helpers -------------------------------------------------------

static func run(command: String) -> int:
	# Fire-and-forget shell command.
	return OS.create_process("bash", ["-c", command])


# Blocking variant of run(): waits for the command to finish and returns its
# exit code. Use where the caller needs the *outcome* — confirming a toggle
# really took effect, or telling the user a mode change failed — instead of
# firing and hoping. Keep it off the UI path for anything slow (apt upgrade,
# pkexec authentication) and keep plain run() for slider/drag spam.
static func run_wait(command: String, read_stderr: bool = false) -> int:
	var output: Array = []
	return OS.execute("bash", ["-c", command], output, read_stderr)


static func run_capture(command: String, read_stderr: bool = false) -> String:
	var output: Array = []
	OS.execute("bash", ["-c", command], output, read_stderr)
	if output.is_empty():
		return ""
	return str(output[0])


static func run_lines(command: String) -> PackedStringArray:
	var raw: String = run_capture(command)
	var lines := PackedStringArray()
	for line in raw.split("\n"):
		var stripped: String = line.strip_edges()
		if not stripped.is_empty():
			lines.append(stripped)
	return lines


static func has_tool(tool: String) -> bool:
	if _tool_cache.has(tool):
		return _tool_cache[tool]
	var found: bool = not run_capture("command -v " + quote(tool) + " 2>/dev/null").strip_edges().is_empty()
	_tool_cache[tool] = found
	return found


# Drop the lookup memo so a tool installed mid-session (an "Install" button in
# a settings panel) is seen on the next probe instead of only after a restart.
static func clear_tool_cache() -> void:
	_tool_cache.clear()


static func quote(value: String) -> String:
	# POSIX single-quote escaping.
	return "'" + value.replace("'", "'\\''") + "'"


# --- launching external tools ----------------------------------------------

static func launch(tool: String, args: Array = []) -> void:
	if not has_tool(tool):
		push_warning("[KainatShell] Tool not found: " + tool)
		return
	var string_args := PackedStringArray()
	for arg in args:
		string_args.append(str(arg))
	OS.create_process(tool, string_args)


# --- KDE KCM fallback (only used for complex subsystems) -------------------

static func open_kcm(module: String) -> void:
	for tool in KCM_FALLBACK_TOOLS:
		if has_tool(tool):
			OS.create_process(tool, [module])
			return
	push_warning("[KainatShell] No KCM launcher available for: " + module)


# --- privileged writes ------------------------------------------------------

static func write_system_file(path: String, content: String) -> void:
	run("pkexec sh -c " + quote("printf %s " + quote(content) + " > " + quote(path)))


static func set_hostname(name: String) -> void:
	if has_tool("hostnamectl"):
		run("pkexec hostnamectl set-hostname " + quote(name))
	else:
		write_system_file("/etc/hostname", name)


# --- config helpers ---------------------------------------------------------

static func read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not file:
		return ""
	# Read in chunks instead of get_as_text(). get_as_text() relies on the
	# reported file length, which is 0 for pseudo-files such as /proc/cpuinfo
	# and /proc/meminfo, so it returns an empty string for them.
	var bytes := PackedByteArray()
	while true:
		var chunk: PackedByteArray = file.get_buffer(1 << 16)
		if chunk.is_empty():
			break
		bytes.append_array(chunk)
	file.close()
	return bytes.get_string_from_utf8()


static func read_lines(path: String) -> PackedStringArray:
	var result := PackedStringArray()
	for line in read_text(path).split("\n"):
		var stripped: String = line.strip_edges()
		if not stripped.is_empty() and not stripped.begins_with("#"):
			result.append(stripped)
	return result


static func home() -> String:
	var h: String = OS.get_environment("HOME")
	return h if not h.is_empty() else OS.get_user_data_dir()


# --- KDE config (used sparingly while KDE is still the base) ----------------

# `subgroup` is for nested KConfig groups (e.g. powerdevilrc [AC][SuspendAndShutdown]).
static func kde_read(file: String, group: String, key: String, default_value: String = "",
		subgroup: String = "") -> String:
	if has_tool("kreadconfig6"):
		var cmd := "kreadconfig6 --file " + quote(file) + " --group " + quote(group)
		if not subgroup.is_empty():
			cmd += " --group " + quote(subgroup)
		cmd += " --key " + quote(key)
		var value: String = run_capture(cmd).strip_edges()
		return value if not value.is_empty() else default_value
	return default_value


static func kde_write(file: String, group: String, key: String, value: String,
		subgroup: String = "") -> void:
	if has_tool("kwriteconfig6"):
		var cmd := "kwriteconfig6 --file " + quote(file) + " --group " + quote(group)
		if not subgroup.is_empty():
			cmd += " --group " + quote(subgroup)
		cmd += " --key " + quote(key) + " " + quote(value)
		# Synchronous: callers rely on the value being on disk before they
		# notify/reload dependent services (e.g. PowerDevil reparseConfiguration).
		run_capture(cmd)


# --- favorites (kdeglobals [KainatSettings] Favorites = "panel:Row Title;...") ---

static var _fav_cache: Array = []
static var _fav_loaded: bool = false


# Rows the user starred, as [{panel, title}]. Cached: nav rows query this once
# per row and a kreadconfig6 spawn per row would stall panel builds.
# Returns a copy so callers can safely iterate it while set_favorite() runs.
static func favorites() -> Array:
	_load_favorites()
	return _fav_cache.duplicate()


static func _load_favorites() -> void:
	if _fav_loaded:
		return
	_fav_loaded = true
	_fav_cache.clear()
	var raw: String = kde_read("kdeglobals", "KainatSettings", "Favorites")
	for entry in raw.split(";"):
		var item := entry.strip_edges()
		if item.is_empty():
			continue
		var idx := item.find(":")
		if idx <= 0:
			continue
		_fav_cache.append({
			"panel": item.substr(0, idx),
			"title": item.substr(idx + 1),
		})


static func is_favorite(panel: String, title: String) -> bool:
	for item in favorites():
		if str(item["panel"]) == panel and str(item["title"]) == title:
			return true
	return false


static func set_favorite(panel: String, title: String, on: bool) -> void:
	_load_favorites()
	var list := _fav_cache
	var found := -1
	for i in list.size():
		if str(list[i]["panel"]) == panel and str(list[i]["title"]) == title:
			found = i
			break
	if on and found == -1:
		list.append({"panel": panel, "title": title})
	elif not on and found != -1:
		list.remove_at(found)

	var joined := ""
	for i in list.size():
		if i > 0:
			joined += ";"
		joined += str(list[i]["panel"]) + ":" + str(list[i]["title"])
	kde_write("kdeglobals", "KainatSettings", "Favorites", joined)


# --- KWin virtual desktops --------------------------------------------------
# Live control must go through KWin's VirtualDesktopManager. Verified on this
# machine: writing Number=3 to kwinrc and calling org.kde.KWin.reconfigure does
# NOT change the running session (count stayed 1), whereas createDesktop over
# D-Bus takes effect immediately and KWin writes Number/Id_N back to kwinrc for
# us. kwinrc is only the fallback for when KWin is not on the bus.

const KWIN_VDM_PATH := "/VirtualDesktopManager"
const KWIN_VDM_IFACE := "org.kde.KWin.VirtualDesktopManager"
const KWIN_MAX_DESKTOPS := 12


# KWin desktop operations go through bash -c like the rest of this file, so
# every argument must be POSIX single-quote wrapped (Sh.quote). Verified: gdbus
# accepts a space-containing string such as 'Desktop A' fine, and a GVariant
# like '<uint32 3>' likewise — but embedding double quotes inside single quotes
# makes bash report an unterminated quote, so never nest them here.

static func _vdm_call(method: String, args: Array = []) -> String:
	if not has_tool("gdbus"):
		return ""
	var cmd := "gdbus call --session --dest org.kde.KWin"
	cmd += " --object-path " + KWIN_VDM_PATH
	cmd += " --method " + KWIN_VDM_IFACE + "." + method
	# Quote every argument here rather than trusting callers to do it.
	for a in args:
		cmd += " " + quote(str(a))
	return run_capture(cmd + " 2>/dev/null").strip_edges()


static func _vdm_prop(prop: String, value: String = "") -> String:
	if not has_tool("gdbus"):
		return ""
	var cmd := "gdbus call --session --dest org.kde.KWin"
	cmd += " --object-path " + KWIN_VDM_PATH
	cmd += " --method org.freedesktop.DBus.Properties."
	if value.is_empty():
		cmd += "Get " + quote(KWIN_VDM_IFACE) + " " + quote(prop)
	else:
		cmd += "Set " + quote(KWIN_VDM_IFACE) + " " + quote(prop) + " " + quote(value)
	return run_capture(cmd + " 2>/dev/null").strip_edges()


static func _parse_uint(raw: String) -> int:
	var i := raw.find("uint32 ")
	if i < 0:
		return -1
	var digits := ""
	for c in raw.substr(i + 7):
		if c < "0" or c > "9":
			break
		digits += c
	return int(digits) if not digits.is_empty() else -1


# Live desktop count, or -1 when KWin is not reachable.
static func kwin_desktop_count() -> int:
	return _parse_uint(_vdm_prop("count"))


# Live grid row count, or -1 when KWin is not reachable.
static func kwin_desktop_rows() -> int:
	return _parse_uint(_vdm_prop("rows"))


# Desktop ids in layout order; shrinking trims from the tail.
static func kwin_desktop_ids() -> PackedStringArray:
	var out := PackedStringArray()
	var re := RegEx.new()
	if re.compile("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}") != OK:
		return out
	for m in re.search_all(_vdm_prop("desktops")):
		out.append(m.get_string())
	return out


# Grid rows can never exceed the desktop count: KWin accepts the Set but then
# keeps the old value (verified: rows stayed 1 when asked for 5 on 3 desktops),
# so clamp first and confirm by reading the property back rather than trusting
# gdbus's "()" acknowledgement.
static func kwin_set_desktop_rows(rows: int) -> bool:
	if rows < 1:
		return false
	var count := kwin_desktop_count()
	if count < 0:
		kde_write("kwinrc", "Desktops", "Rows", str(clampi(rows, 1, KWIN_MAX_DESKTOPS)))
		_kwin_reconfigure()
		return true
	rows = clampi(rows, 1, count)
	_vdm_prop("rows", "<uint32 %d>" % rows)
	return kwin_desktop_rows() == rows


# Grow or shrink the live desktop set. Returns false only when KWin is absent
# AND the config fallback could not be written.
static func kwin_set_desktop_count(count: int) -> bool:
	count = clampi(count, 1, KWIN_MAX_DESKTOPS)
	var current := kwin_desktop_count()

	if current < 0:
		# KWin not on the bus: write kwinrc so it applies at next login.
		if not has_tool("kwriteconfig6"):
			return false
		kde_write("kwinrc", "Desktops", "Number", str(count))
		_kwin_reconfigure()
		return true

	if count > current:
		for i in range(current, count):
			_vdm_call("createDesktop", [i, "Desktop %d" % (i + 1)])
	elif count < current:
		# Snapshot before mutating: removing shifts nothing, but be explicit.
		var ids := kwin_desktop_ids()
		for i in range(count, current):
			var idx := ids.size() - (i - count) - 1
			if idx >= 0:
				_vdm_call("removeDesktop", [ids[idx]])

	var rows := kwin_desktop_rows()
	if rows > count:
		kwin_set_desktop_rows(count)
	return kwin_desktop_count() == count


static func _kwin_reconfigure() -> void:
	if not has_tool("gdbus"):
		return
	run_capture("gdbus call --session --dest org.kde.KWin --object-path /KWin"
			+ " --method org.kde.KWin.reconfigure 2>/dev/null")


# --- misc -------------------------------------------------------------------

# Standardized response for a feature whose backing tool is missing: logs a
# warning for the developer and (optionally) shows the user the same toast a
# panel would. Pass the panel's `notify` method as `notify`. Returns the
# message so callers can append their own guidance.
static func _notify_missing(tool: String, feature: String,
		notify: Callable = Callable()) -> String:
	var message: String = feature + " unavailable (" + tool + " is not installed)."
	push_warning("[KainatShell] " + message)
	if notify.is_valid():
		notify.call(message)
	return message


static func os_release() -> Dictionary:
	var info: Dictionary = {}
	for line in read_text("/etc/os-release").split("\n"):
		var stripped: String = line.strip_edges()
		if "=" in stripped:
			var idx: int = stripped.find("=")
			var k: String = stripped.substr(0, idx).strip_edges()
			var v: String = stripped.substr(idx + 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
			info[k] = v
	return info