extends RefCounted
class_name KainatShell
# KainatShell.gd
# Small helper layer for interacting with the Debian/Kainat OS system from
# GDScript panels. Keeps every panel free of shell-quoting boilerplate.
#
# All helpers are static so panels can call them without an instance.
#
# NOTE: this is a library, not an entry point. Run the project
# (main-panel.tscn); launching this file directly (editor F6 / --script)
# reports "doesn't inherit from SceneTree or MainLoop" by design.

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


# --- disk helpers -----------------------------------------------------------

static func file_exists(path: String) -> bool:
	return FileAccess.file_exists(path)


static func dir_exists(path: String) -> bool:
	return DirAccess.dir_exists_absolute(path)


# --- driver helpers ---------------------------------------------------------

static func get_pci_devices() -> PackedStringArray:
	var output: String = run_capture("lspci -nn")
	var lines := output.split("\n")
	var devices := PackedStringArray()
	for line in lines:
		var stripped: String = line.strip_edges()
		if not stripped.is_empty():
			devices.append(stripped)
	return devices


static func has_nvidia_gpu() -> bool:
	var output: String = run_capture("lspci | grep -i nvidia")
	return not output.strip_edges().is_empty()


static func is_package_installed(package: String) -> bool:
	var output: String = run_capture("dpkg -l " + quote(package) + " 2>/dev/null | grep ^ii")
	return not output.strip_edges().is_empty()


static func install_command(package: String) -> String:
	# One authorisation prompt for both steps; `;` so a stale list update still
	# lets the install attempt run and report its own error.
	return "pkexec sh -c " + quote("apt-get update; apt-get install -y " + quote(package))


static func install_package(package: String) -> int:
	return run_wait(install_command(package))


static func remove_command(package: String) -> String:
	return "pkexec apt-get remove -y -- " + quote(package)


# --- disk manager helpers ---------------------------------------------------

static func list_block_devices() -> Array:
	# Returns array of dicts with: name, mountpoint, size, type, children
	var output: String = run_capture("lsblk -o NAME,MOUNTPOINT,SIZE,TYPE -n -J")
	var json: JSON = JSON.new()
	var err: int = json.parse(output)
	if err != OK:
		return []
	var data: Variant = json.data
	var devices: Array = data.get("blockdevices", []) if data is Dictionary else []
	return devices


static func get_disk_usage(mountpoint: String) -> Dictionary:
	var result: Dictionary = {"total": 0, "used": 0, "available": 0, "percent": 0}
	if mountpoint.is_empty():
		return result
	var output: String = run_capture("df -h " + quote(mountpoint) + " | tail -1")
	# df pads columns with runs of spaces, so empty fields must be collapsed.
	var parts := output.strip_edges().split(" ", false)
	if parts.size() >= 5:
		result["total"] = parts[1]
		result["used"] = parts[2]
		result["available"] = parts[3]
		result["percent"] = int(parts[4].trim_suffix("%"))
	return result


# Unmount a whole device and every partition below it. udisksctl refuses to
# unmount a disk that still has mounted partitions, so walk the tree first.
static func unmount_device(device: String) -> void:
	run_capture("udisksctl unmount -b " + quote(device) + " 2>/dev/null")
	for name in run_lines("lsblk -ln -o NAME " + quote(device) + " 2>/dev/null"):
		if name != device.get_file():
			run_capture("udisksctl unmount -b " + quote("/dev/" + name) + " 2>/dev/null")


static func eject_drive(device: String) -> int:
	# device is like /dev/sdb
	unmount_device(device)
	return run_wait("udisksctl power-off -b " + quote(device))


# Command form so a caller can run it non-blocking; format_drive() is the
# blocking convenience wrapper.
static func format_command(device: String, fs: String) -> String:
	# fs: vfat (FAT32), ntfs, ext4
	var cmd: String = ""
	match fs:
		"vfat":
			cmd = "mkfs.vfat -F 32 " + quote(device)
		"ntfs":
			cmd = "mkfs.ntfs -f " + quote(device)
		"ext4":
			cmd = "mkfs.ext4 -F " + quote(device)
		_:
			return ""
	return "pkexec " + cmd


static func format_drive(device: String, fs: String) -> int:
	var command := format_command(device, fs)
	if command.is_empty():
		return -1
	return run_wait(command)


# --- VPN helpers ------------------------------------------------------------

static func start_openvpn(config_path: String) -> int:
	return run_wait("pkexec openvpn --config " + quote(config_path) + " --daemon")


static func stop_openvpn() -> void:
	run("pkexec pkill -f 'openvpn --config'")


static func list_vpn_configs(dir: String) -> PackedStringArray:
	var output: String = run_capture("ls " + quote(dir) + "*.ovpn 2>/dev/null")
	var lines := PackedStringArray()
	for line in output.split("\n"):
		var stripped: String = line.strip_edges()
		if not stripped.is_empty():
			lines.append(stripped.get_file())
	return lines


# --- SSH helpers ------------------------------------------------------------

static func generate_ssh_key(key_path: String, key_type: String = "ed25519") -> int:
	# -N '' = no passphrase
	return run_wait("ssh-keygen -t " + quote(key_type) + " -f " + quote(key_path) + " -N ''")


static func get_ssh_public_key(key_path: String) -> String:
	var pub_path := key_path + ".pub"
	if not file_exists(pub_path):
		return ""
	return read_text(pub_path).strip_edges()


# --- input method helpers ---------------------------------------------------

static func install_cjk_support() -> int:
	# fcitx5-chinese-addons is the Debian package that ships Pinyin; there is no
	# fcitx5-googlepinyin package in Debian and asking for it fails the install.
	return run_wait("pkexec apt install -y fcitx5 fcitx5-chinese-addons fcitx5-mozc fcitx5-table-extra")


static func install_arabic_support() -> int:
	return run_wait("pkexec apt install -y fcitx5 fcitx5-table-extra")


# --- hotspot helpers --------------------------------------------------------

static func create_wifi_hotspot(ssid: String, password: String) -> int:
	# nmcli refuses to reuse an existing profile name, so drop a stale one first.
	return run_wait(
		"nmcli con delete 'Kainat-Hotspot' >/dev/null 2>&1; "
		+ "nmcli dev wifi hotspot con-name 'Kainat-Hotspot' ssid " + quote(ssid)
		+ " password " + quote(password)
	)


static func stop_wifi_hotspot() -> int:
	# `;` rather than `&&`: an already-down profile must still be deleted.
	return run_wait(
		"nmcli con down 'Kainat-Hotspot' >/dev/null 2>&1; "
		+ "nmcli con delete 'Kainat-Hotspot' >/dev/null 2>&1"
	)


# --- proxy helpers ----------------------------------------------------------

static func set_system_proxy(mode: String, host: String = "", port: String = "") -> void:
	# mode: "manual", "auto", "none"
	# Plasma apps read kioslaverc, GTK apps read the GNOME proxy schema, so both
	# are written; otherwise half the desktop would ignore the setting.
	var proxy_type := "0"
	if mode == "manual":
		proxy_type = "1"
	elif mode == "auto":
		proxy_type = "2"
	kde_write("kioslaverc", "Proxy Settings", "ProxyType", proxy_type)

	var p := port if not port.is_empty() else "8080"
	if mode == "manual" and not host.is_empty():
		# KIO stores "scheme://host port" in a single value.
		var endpoint := "http://" + host + " " + p
		kde_write("kioslaverc", "Proxy Settings", "httpProxy", endpoint)
		kde_write("kioslaverc", "Proxy Settings", "httpsProxy", endpoint)
		kde_write("kioslaverc", "Proxy Settings", "ftpProxy", endpoint)
		kde_write("kioslaverc", "Proxy Settings", "socksProxy", "socks://" + host + " " + p)

	run("gsettings set org.gnome.system.proxy mode " + quote(mode))
	if mode == "manual" and not host.is_empty():
		run("gsettings set org.gnome.system.proxy use-same-proxy true")
		for scheme in ["http", "https", "socks"]:
			run("gsettings set org.gnome.system.proxy." + scheme + " host " + quote(host))
			run("gsettings set org.gnome.system.proxy." + scheme + " port " + quote(p))

	# Running KIO jobs cache the old configuration until told to re-read it.
	run("dbus-send --type=signal /KIO/Scheduler "
		+ "org.kde.KIO.Scheduler.reparseSlaveConfiguration string:'' >/dev/null 2>&1")


static func get_system_proxy() -> Dictionary:
	var mode := kde_read("kioslaverc", "Proxy Settings", "ProxyType", "")
	if mode == "1":
		mode = "manual"
	elif mode == "2":
		mode = "auto"
	elif mode != "0":
		mode = run_capture("gsettings get org.gnome.system.proxy mode").strip_edges().trim_prefix("'").trim_suffix("'")
	else:
		mode = "none"

	var host := ""
	var port := ""
	var endpoint := kde_read("kioslaverc", "Proxy Settings", "httpProxy", "")
	if not endpoint.is_empty():
		endpoint = endpoint.trim_prefix("http://").trim_prefix("https://")
		var cut: int = endpoint.rfind(" ")
		if cut > 0:
			host = endpoint.substr(0, cut).strip_edges()
			port = endpoint.substr(cut + 1).strip_edges()
		else:
			host = endpoint.strip_edges()
	if host.is_empty():
		host = run_capture("gsettings get org.gnome.system.proxy.http host").strip_edges().trim_prefix("'").trim_suffix("'")
		port = run_capture("gsettings get org.gnome.system.proxy.http port").strip_edges()
	return {"mode": mode, "host": host, "port": port}


# --- repo helpers -----------------------------------------------------------

static func list_apt_sources() -> Array:
	var sources_dir := "/etc/apt/sources.list.d/"
	var output: String = run_capture("ls " + quote(sources_dir) + "*.list 2>/dev/null")
	var result := Array()
	for line in output.split("\n"):
		var stripped: String = line.strip_edges()
		if not stripped.is_empty():
			var content: String = read_text(stripped)
			var enabled := not content.begins_with("#")
			result.append({"file": stripped, "name": stripped.get_file(), "content": content, "enabled": enabled})
	return result


static func toggle_apt_source(file_path: String, enabled: bool) -> int:
	var content: String = read_text(file_path)
	if enabled:
		# Enable: uncomment lines starting with # deb
		content = content.replace("# deb", "deb")
		content = content.replace("# deb-src", "deb-src")
	else:
		# Disable: comment out deb lines
		var lines := content.split("\n")
		var new_lines := PackedStringArray()
		for l in lines:
			var stripped := l.strip_edges()
			if stripped.begins_with("deb ") or stripped.begins_with("deb-src "):
				new_lines.append("# " + l)
			else:
				new_lines.append(l)
		content = "\n".join(new_lines)
	# Build the whole inner command first, then quote it once: nesting
	# quote() inside a hand-written '...' wrapper breaks as soon as the
	# content itself contains a single quote.
	return run_wait("pkexec sh -c " + quote("printf %s " + quote(content) + " > " + quote(file_path)))


# --- universal installer helpers --------------------------------------------

# Command strings are exposed so callers can run the long installs through
# SettingsPanel.run_async() instead of freezing the window.
static func deb_install_command(path: String) -> String:
	# One authorisation prompt. `;` (not `&&`) because apt-get -f still has to
	# repair dependencies when dpkg itself reports an error.
	return "pkexec sh -c " + quote("dpkg -i " + quote(path) + "; apt-get install -f -y")


static func install_deb_file(path: String) -> int:
	return run_wait(deb_install_command(path))


static func rpm_install_command(path: String) -> String:
	# alien is installed only when missing, so repeat runs need one prompt.
	return "pkexec sh -c " + quote(
		"command -v alien >/dev/null 2>&1 || apt-get install -y alien; alien -i " + quote(path)
	)


static func install_rpm_file(path: String) -> int:
	return run_wait(rpm_install_command(path))


static func run_appimage(path: String) -> int:
	# Launch detached: the app may run for hours and must not block the caller.
	var code := run_wait("chmod +x " + quote(path))
	if code != 0:
		return code
	run(quote(path) + " >/dev/null 2>&1 &")
	return 0


static func run_wine_exe(path: String, prefix: String = "") -> int:
	# Wine must run as the user: a root-owned prefix breaks the user's setup.
	if not has_tool("wine"):
		return 127
	var command := "wine " + quote(path)
	if not prefix.is_empty():
		command = "WINEPREFIX=" + quote(prefix) + " " + command
	run(command + " >/dev/null 2>&1 &")
	return 0


# --- system reset helpers ---------------------------------------------------

static var _last_reset_backup: String = ""


# Where the most recent reset parked the old configuration, or "" if nothing
# was moved. Callers surface this so a reset can always be undone by hand.
static func last_reset_backup() -> String:
	return _last_reset_backup


static func reset_user_settings() -> int:
	# Reset configuration without destroying anything: every entry is moved into
	# a timestamped backup folder instead of being deleted. A user who resets by
	# accident (or misses a browser profile / keyring) can copy the files back.
	var stamp := str(int(Time.get_unix_time_from_system()))
	var backup: String = home() + "/kainat-settings-backup-" + stamp
	var dirs: Array[String] = [
		home() + "/.config",
		home() + "/.local/share/config"
	]
	if run_wait("mkdir -p " + quote(backup)) != 0:
		_last_reset_backup = ""
		return -1

	var moved_any := false
	var exit_code := 0
	for dir in dirs:
		if not dir_exists(dir):
			continue
		var target: String = backup + dir.trim_prefix(home())
		if run_wait("mkdir -p " + quote(target)) != 0:
			exit_code = -1
			continue
		# -exec ... + batches many entries per mv call, so this stays quick even
		# with thousands of files. Dotfiles are included by default.
		var code := run_wait(
			"find " + quote(dir) + " -mindepth 1 -maxdepth 1"
			+ " -exec mv -t " + quote(target) + " -- {} +"
		)
		if code != 0:
			exit_code = code
		else:
			moved_any = true

	_last_reset_backup = backup if moved_any else ""
	return exit_code


# --- accessibility helpers --------------------------------------------------

# Plasma ships high contrast as a color scheme, so switching it is a normal
# scheme change (no plasmashell restart, no lost windows). GTK apps follow the
# GNOME setting instead, so both are updated.
static func _high_contrast_scheme() -> String:
	for base in ["/usr/share/color-schemes", home() + "/.local/share/color-schemes"]:
		for candidate in ["BreezeHighContrast", "Breeze High Contrast", "HighContrast", "High Contrast"]:
			if FileAccess.file_exists(base.path_join(candidate + ".colors")):
				return candidate
	return ""


static func set_high_contrast(enabled: bool) -> void:
	run("gsettings set org.gnome.desktop.interface high-contrast-enabled "
		+ ("true" if enabled else "false"))

	var scheme := _high_contrast_scheme()
	if scheme.is_empty() or not has_tool("plasma-apply-colorscheme"):
		return
	if enabled:
		var current := kde_read("kdeglobals", "General", "ColorScheme", "")
		if not current.is_empty() and current != scheme:
			kde_write("kdeglobals", "KainatSettings", "SchemeBeforeHighContrast", current)
		run("plasma-apply-colorscheme " + quote(scheme))
	else:
		var previous := kde_read("kdeglobals", "KainatSettings", "SchemeBeforeHighContrast", "BreezeDark")
		run("plasma-apply-colorscheme " + quote(previous))


static func get_high_contrast() -> bool:
	var scheme := _high_contrast_scheme()
	if not scheme.is_empty():
		return kde_read("kdeglobals", "General", "ColorScheme", "") == scheme
	var val := run_capture("gsettings get org.gnome.desktop.interface high-contrast-enabled").strip_edges().trim_prefix("'").trim_suffix("'")
	return val == "true"


# --- display scaling --------------------------------------------------------

# Output names as reported by KScreen, or an empty list when kscreen-doctor is
# unavailable. Used for scale changes, which are per-output in Plasma.
static func _output_names() -> Array[String]:
	var names: Array[String] = []
	var raw := run_capture("kscreen-doctor -j 2>/dev/null")
	if raw.strip_edges().is_empty():
		return names
	var data: Variant = JSON.parse_string(raw)
	if not (data is Dictionary):
		return names
	var outputs: Variant = data.get("outputs", [])
	if not (outputs is Array):
		return names
	for output in outputs:
		if output is Dictionary:
			var name: Variant = output.get("name", null)
			if name is String and not str(name).is_empty():
				names.append(str(name))
	return names


# Scale of the first output (all outputs are kept in sync), or -1 if unknown.
static func ui_scale() -> float:
	var raw := run_capture("kscreen-doctor -j 2>/dev/null")
	if raw.strip_edges().is_empty():
		return -1.0
	var data: Variant = JSON.parse_string(raw)
	if not (data is Dictionary):
		return -1.0
	var outputs: Variant = data.get("outputs", [])
	if not (outputs is Array):
		return -1.0
	for output in outputs:
		if output is Dictionary:
			var scale: Variant = output.get("scale", null)
			if scale is float or scale is int:
				return float(scale)
	return -1.0


# Apply one scale factor to every connected output. False means kscreen-doctor
# is missing or refused the change.
static func set_ui_scale(scale: float) -> bool:
	var names := _output_names()
	if names.is_empty():
		return false
	var applied := false
	for name in names:
		var cmd := "kscreen-doctor output." + name + ".scale." + str(scale) + " 2>/dev/null"
		if run_wait(cmd) == 0:
			applied = true
	return applied


# --- input method helpers ---------------------------------------------------

static func get_input_method_framework() -> String:
	var configured := kde_read("kdeglobals", "KDE", "IMModule", "")
	if configured == "fcitx5" or configured == "ibus":
		return configured
	if not run_capture("pgrep -x fcitx5").strip_edges().is_empty():
		return "fcitx5"
	if not run_capture("pgrep -x ibus-daemon").strip_edges().is_empty():
		return "ibus"
	var env := run_capture("printenv QT_IM_MODULE")
	if env.contains("fcitx"):
		return "fcitx5"
	if env.contains("ibus"):
		return "ibus"
	return "fcitx5"


static func set_input_method_framework(framework: String) -> void:
	var fw := framework.strip_edges()
	if fw != "fcitx5" and fw != "ibus":
		fw = "fcitx5"
	kde_write("kdeglobals", "KDE", "IMModule", fw)
	var dir := home() + "/.config/environment.d"
	if not dir_exists(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(dir + "/90-input-method.conf", FileAccess.WRITE)
	if file != null:
		var xmod := "@im=fcitx" if fw == "fcitx5" else "@im=ibus"
		file.store_line("GTK_IM_MODULE=" + fw)
		file.store_line("QT_IM_MODULE=" + fw)
		file.store_line("XMODIFIERS=" + xmod)
		file.close()


# --- diagnostics helpers ----------------------------------------------------

static func get_cpu_temp() -> int:
	# Use raw string to avoid escape issues with the complex awk command
	var cmd: String = "sensors 2>/dev/null | grep -i 'package id 0:' | head -1 | awk '{print $4}' | cut -d'+' -f2 | cut -d'.' -f1"
	var output: String = run_capture(cmd)
	if output.is_empty():
		# Fallback to /sys
		var hwmon_dir := DirAccess.open("/sys/class/hwmon")
		if hwmon_dir:
			var paths := hwmon_dir.get_directories()
			for p in paths:
				var label := read_text("/sys/class/hwmon/" + p + "/name").strip_edges()
				if "coretemp" in label or "k10temp" in label:
					var temp_str := read_text("/sys/class/hwmon/" + p + "/temp1_input").strip_edges()
					if temp_str.is_valid_int():
						return int(temp_str) / 1000
		return -1
	return int(output.strip_edges())


static func get_ram_usage() -> Dictionary:
	var output: String = run_capture("free -m | grep Mem")
	# "Mem:" is followed by runs of spaces; collapse them or every field is "".
	var parts := output.strip_edges().split(" ", false)
	var result: Dictionary = {"total": 0, "used": 0, "free": 0, "percent": 0.0}
	if parts.size() >= 3:
		result["total"] = int(parts[1])
		result["used"] = int(parts[2])
		result["free"] = int(parts[3]) if parts.size() > 3 else 0
		if result["total"] > 0:
			result["percent"] = float(result["used"]) / float(result["total"]) * 100.0
	return result


static func get_disk_health() -> String:
	# Check root partition
	var cmd: String = "df -h / | tail -1 | awk '{print $5}'"
	var output: String = run_capture(cmd).strip_edges()
	return output