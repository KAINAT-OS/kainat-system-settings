extends SettingsPanel
# Hardware inventory: read directly from /proc, /sys and ls*/lspci tools.

# Sentinel for "we have no reading at all" — a real sensor can read 0 °C.
const UNKNOWN_TEMP := -1000.0


func build() -> void:
	page_header("Hardware & System Information", "Live details about this Kainat OS machine.")
	defer(_populate)


func _populate() -> void:
	var cpu: String = _cpu_model()
	var cores: String = "%d threads" % OS.get_processor_count()
	var mem_total: String = _mem_total()
	var mem_used: String = _mem_used()
	var gpu: String = _gpu()
	var kernel: String = OS.get_version()
	var os_name: String = str(Sh.os_release().get("PRETTY_NAME", "Kainat OS"))
	var temps: Array = _temperature_readings()
	var cpu_c: float = _cpu_celsius(temps)
	var hot_c: float = _hottest_celsius(temps)
	var shown_c: float = cpu_c if cpu_c > UNKNOWN_TEMP else hot_c

	info_tiles([
		{"value": os_name, "label": "Operating system"},
		{"value": kernel, "label": "Kernel"},
		{"value": cores, "label": "Processor"},
		{"value": mem_total, "label": "Memory"},
		{"value": mem_used, "label": "Memory in use"},
		{"value": _uptime(), "label": "Uptime"},
		{"value": _temp_text(shown_c), "label": "Temperature"},
	])

	section("Overview")
	var c := card()
	info_row(c, "Processor", cpu)
	info_row(c, "Graphics", gpu)
	info_row(c, "Memory", "%s / %s" % [mem_used, mem_total])
	info_row(c, "Storage", _disk_summary())
	info_row(c, "Temperature", _temp_summary(cpu_c, hot_c))

	section("Components")
	var c2 := card()
	action_row(c2, "Disk Drives", "Block devices and partitions.", "D", "Inspect", func() -> void:
		_show_list("Storage Devices", _run_table("lsblk -o NAME,SIZE,TYPE,MOUNTPOINT")))
	action_row(c2, "PCI Devices", "Graphics, network and controllers.", "P", "Inspect", func() -> void:
		_show_list("PCI Devices", Sh.run_capture("lspci")))
	action_row(c2, "USB Devices", "Attached USB peripherals.", "U", "Inspect", func() -> void:
		_show_list("USB Devices", Sh.run_capture("lsusb")))
	action_row(c2, "Sensors", "Temperature and fan readings.", "T", "Inspect", func() -> void:
		var sensors: String = Sh.run_capture("sensors 2>/dev/null")
		_show_list("Sensors", sensors if not sensors.is_empty() else "No sensors detected."))

	section("System Monitor")
	var c3 := card()
	kcm_row(c3, "Resource Monitor", "Open the live process and resource monitor.", "R", "kcm_memory")
	nav_row(c3, "System Monitor", "Processes, CPU, memory and disk usage.", "S", func() -> void:
		if Sh.has_tool("plasma-systemmonitor"):
			Sh.launch("plasma-systemmonitor")
		else:
			notify("No system monitor installed."))
	kcm_row(c3, "Energy Statistics", "Power consumption per component.", "E", "kcm_energyinfo")

	section("Firmware")
	var c4 := card()
	kcm_row(c4, "Firmware Security", "Secure Boot and firmware status.", "F", "kcm_firmware_security")


func _show_list(title: String, text: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = title
	dialog.size = Vector2i(720, 520)
	var edit := TextEdit.new()
	edit.text = text.strip_edges()
	edit.editable = false
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.custom_minimum_size = Vector2(680, 460)
	dialog.add_child(edit)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


func _run_table(command: String) -> String:
	return Sh.run_capture(command)


func _cpu_model() -> String:
	for line in Sh.read_lines("/proc/cpuinfo"):
		if line.begins_with("model name"):
			return line.split(":", true, 1)[1].strip_edges()
	return "Unknown processor"


func _mem_total() -> String:
	var total: float = _mem_kb("MemTotal")
	return _mem_gb(total) if total > 0.0 else UNAVAILABLE


func _mem_used() -> String:
	var total: float = _mem_kb("MemTotal")
	if total <= 0.0:
		return UNAVAILABLE
	var available: float = _mem_kb("MemAvailable")
	return _mem_gb(maxf(total - available, 0.0))


func _mem_kb(key: String) -> float:
	for line in Sh.read_lines("/proc/meminfo"):
		if line.begins_with(key + ":"):
			var parts: PackedStringArray = line.split(" ", false)
			if parts.size() >= 2:
				return float(parts[1].replace("kB", ""))
	return 0.0


func _mem_gb(kb: float) -> String:
	return "%.1f GB" % (kb / 1024.0 / 1024.0)


func _gpu() -> String:
	for line in Sh.run_lines("lspci 2>/dev/null"):
		if line.contains("VGA compatible controller") or line.contains("3D controller") or line.contains("Display controller"):
			var idx: int = line.find(":")
			if idx != -1:
				return line.substr(idx + 1).strip_edges()
	return "Unknown graphics"


func _disk_summary() -> String:
	var lines: PackedStringArray = Sh.run_lines("df -h --output=size,avail / 2>/dev/null")
	if lines.size() > 1:
		return lines[1]
	return UNAVAILABLE


# --- temperatures ----------------------------------------------------------

# Native sensor read-out as [{chip, sensor, celsius}]. Prefers `sensors`
# (lm-sensors gives readable chip/label names) and falls back to the raw
# millidegree files under /sys so the tile still works without it.
func _temperature_readings() -> Array:
	var out: Array = []
	if Sh.has_tool("sensors"):
		var chip := ""
		for line in Sh.run_lines("sensors 2>/dev/null"):
			var t: String = line.strip_edges()
			if t.is_empty() or t.begins_with("Adapter:"):
				continue
			if not t.contains(":"):
				chip = t  # chip header line, e.g. "k10temp-pci-00c3"
				continue
			if not t.contains("°C"):
				continue  # fan RPM, power (W/kJ) and N/A lines
			var idx: int = t.find(":")
			var sensor: String = t.substr(0, idx).strip_edges()
			var body: String = t.substr(idx + 1)
			var deg: int = body.find("°C")
			if deg == -1:
				continue
			var num: String = body.substr(0, deg).strip_edges()
			if not num.is_valid_float():
				continue
			var c: float = num.to_float()
			if c <= -100.0 or c >= 200.0:
				continue
			out.append({"chip": chip, "sensor": sensor, "celsius": c})
	if out.is_empty():
		out = _sys_temps()
	return out


func _sys_temps() -> Array:
	var out: Array = []
	# DirAccess has get_files() but no get_dirs(), so walk with get_next()
	# and let DirAccess.open() reject non-directories.
	var hw := DirAccess.open("/sys/class/hwmon")
	if hw != null:
		hw.list_dir_begin()
		var entry: String = hw.get_next()
		while entry != "":
			if not entry.begins_with("."):
				var base: String = "/sys/class/hwmon/" + entry
				var sub := DirAccess.open(base)
				if sub != null:
					var chip: String = _first_line(base + "/name")
					for raw_name in sub.get_files():
						var f: String = str(raw_name)
						if not f.begins_with("temp") or not f.ends_with("_input"):
							continue
						var raw: String = _first_line(base + "/" + f)
						if not raw.is_valid_float():
							continue
						var c: float = raw.to_float() / 1000.0
						if c <= -100.0 or c >= 200.0:
							continue
						var n: String = f.trim_suffix("_input").trim_prefix("temp")
						var sensor := _first_line(base + "/temp" + n + "_label")
						out.append({"chip": chip, "sensor": sensor if not sensor.is_empty() else "temp" + n, "celsius": c})
			entry = hw.get_next()
		hw.list_dir_end()
	if out.is_empty():
		# Last resort: ACPI thermal zones (usually only the chassis).
		var tz := DirAccess.open("/sys/class/thermal")
		if tz != null:
			tz.list_dir_begin()
			var d: String = tz.get_next()
			while d != "":
				if d.begins_with("thermal_zone"):
					var base2: String = "/sys/class/thermal/" + d
					var raw2 := _first_line(base2 + "/temp")
					if raw2.is_valid_float():
						var c2: float = raw2.to_float() / 1000.0
						if c2 > -100.0 and c2 < 200.0:
							out.append({"chip": _first_line(base2 + "/type"), "sensor": "zone", "celsius": c2})
				d = tz.get_next()
			tz.list_dir_end()
	return out


# Processor heat: k10temp's Tctl or coretemp's package reading, else the
# hottest reading from a CPU chip, else any package/Tctl-like reading.
func _cpu_celsius(readings: Array) -> float:
	var from_chip := UNKNOWN_TEMP
	for r in readings:
		var chip: String = str(r["chip"]).to_lower()
		var sensor: String = str(r["sensor"]).to_lower()
		var c: float = float(r["celsius"])
		if sensor == "tctl" or sensor == "tdie" or sensor.begins_with("package id 0"):
			return c
		var cpu_chip: bool = chip.contains("k10temp") or chip.contains("k8temp") \
				or chip.contains("coretemp") or chip.contains("cpu-thermal")
		if cpu_chip and from_chip == UNKNOWN_TEMP:
			from_chip = c
	return from_chip


func _hottest_celsius(readings: Array) -> float:
	var hottest := UNKNOWN_TEMP
	for r in readings:
		hottest = maxf(hottest, float(r["celsius"]))
	return hottest


func _temp_text(c: float) -> String:
	if c <= UNKNOWN_TEMP:
		return UNAVAILABLE
	return "%d °C" % int(round(c))


# "CPU 52 °C · Hottest 58 °C" — drops whichever half we could not read and
# collapses to UNAVAILABLE when there is nothing at all.
func _temp_summary(cpu_c: float, hot_c: float) -> String:
	var parts: Array = []
	if cpu_c > UNKNOWN_TEMP:
		parts.append("CPU " + _temp_text(cpu_c))
	if hot_c > UNKNOWN_TEMP and (cpu_c <= UNKNOWN_TEMP or absf(hot_c - cpu_c) > 0.5):
		parts.append("Hottest " + _temp_text(hot_c))
	return " · ".join(parts) if not parts.is_empty() else UNAVAILABLE


func _first_line(path: String) -> String:
	var text: String = Sh.read_text(path)
	if text.is_empty():
		return ""
	return text.split("\n")[0].strip_edges()


func _uptime() -> String:
	var raw: String = Sh.read_text("/proc/uptime")
	if raw.is_empty():
		return UNAVAILABLE
	var seconds: float = float(raw.split(" ")[0])
	var hours: int = int(seconds / 3600.0)
	var minutes: int = int((seconds - hours * 3600) / 60.0)
	return "%dh %dm" % [hours, minutes]