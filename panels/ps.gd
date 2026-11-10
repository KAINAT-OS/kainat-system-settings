extends SettingsPanel
# Power Settings: native CPU governor + power profiles, KCMs for the rest.

var _profile_card: VBoxContainer
var _cpu_card: VBoxContainer
var _lid_card: VBoxContainer


func build() -> void:
	page_header("Power Settings", "CPU performance, power profiles, battery and energy use.")

	section("Power Profile")
	_profile_card = card()

	section("CPU")
	_cpu_card = card()

	section("Power Management")
	var c3 := card()
	kcm_row(c3, "Power Management", "Suspend, display and button behaviour.", "M", "kcm_powerdevilprofilesconfig")
	kcm_row(c3, "Energy Statistics", "Power use per component.", "E", "kcm_energyinfo")

	section("Suspend Session")
	_lid_card = card()

	section("Screen Locking")
	var c4 := card()
	toggle_row(c4, "Lock on Suspend", "Lock the screen when suspending.", "S", _is_lock_on_suspend(),
		func(on: bool) -> void:
			Sh.kde_write("kdeglobals", "ScreenLock", "LockOnSuspend", "true" if on else "false")
			notify("Lock on suspend " + ("enabled" if on else "disabled")))
	slider_row(c4, "Idle Timeout", "Minutes before the screen locks.", "I", 0, 60, _idle_timeout(),
		func(v: float) -> void:
			Sh.kde_write("kdeglobals", "ScreenLock", "IdleTimeout", str(int(v)))
			notify("Idle timeout: %d min" % int(v)), " min")
	kcm_row(c4, "Screen Locking", "Lock timings and appearance.", "L", "kcm_screenlocker")

	defer(_populate)


func _populate() -> void:
	_populate_profile()
	_populate_cpu()
	_populate_lid()


func _populate_profile() -> void:
	var c: VBoxContainer = _profile_card
	if Sh.has_tool("powerprofilesctl"):
		var profiles: Array = []
		for line in Sh.run_lines("powerprofilesctl list 2>/dev/null"):
			if line.ends_with(":"):
				profiles.append(line.trim_suffix(":").strip_edges())
		if profiles.is_empty():
			profiles = ["power-saver", "balanced", "performance"]
		var current: String = Sh.run_capture("powerprofilesctl get 2>/dev/null").strip_edges()
		var selected: int = profiles.find(current)
		choice_row(c, "Profile", "Balance performance and battery life.", "P", profiles,
			selected, func(index: int) -> void:
				Sh.run("powerprofilesctl set " + Sh.quote(str(profiles[index])))
				notify("Power profile: " + str(profiles[index])))
	else:
		unavailable_row(c, "Power Profiles", "power-profiles-daemon is not installed")


func _populate_cpu() -> void:
	var c2: VBoxContainer = _cpu_card
	var governors: Array = _governors()
	if not governors.is_empty():
		var current_gov: String = Sh.run_capture("cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null").strip_edges()
		choice_row(c2, "CPU Governor", "Scaling strategy for the processor.", "C", governors,
			governors.find(current_gov), func(index: int) -> void:
				var mode: String = str(governors[index])
				# The governor name is written inside a pkexec shell command, so
				# quote the whole inner command rather than nesting quotes.
				Sh.run("pkexec sh -c " + Sh.quote("echo " + mode + " | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"))
				notify("CPU governor: " + mode))
	else:
		unavailable_row(c2, "CPU Governor", "The kernel does not expose cpufreq")
	info_row(c2, "Battery", _battery())


func _populate_lid() -> void:
	var c: VBoxContainer = _lid_card
	var can_suspend: bool = _pd_action_supported("Suspend")
	var can_hibernate: bool = _pd_action_supported("Hibernate")

	# Same option set as KDE's lidActionModel, filtered by capability.
	var labels: Array = ["Do nothing"]
	var values: Array = [0]
	if can_suspend:
		labels.append("Sleep")
		values.append(1)
	if can_hibernate:
		labels.append("Hibernate")
		values.append(2)
	labels.append("Shut down")
	values.append(8)
	labels.append("Lock screen")
	values.append(32)
	labels.append("Turn off screen")
	values.append(64)

	var current: int = _lid_action()
	var selected: int = values.find(current)
	if selected == -1:
		# Previously configured action is unsupported now - keep it visible.
		labels.append(_lid_action_label(current) + " (unsupported)")
		values.append(current)
		selected = values.size() - 1

	choice_row(c, "When Laptop Lid Closes", "Applies on AC and battery power.", "L", labels, selected,
		func(index: int) -> void:
			_set_lid_action(int(values[index]))
			notify("Lid close action: " + str(labels[index])))
	toggle_row(c, "Even with External Monitor", "Run the lid action when an external display is connected.", "E",
		not _inhibit_lid_external(),
		func(on: bool) -> void:
			_set_inhibit_lid_external(not on)
			notify("Lid action with external monitor " + ("enabled" if on else "disabled")))
	info_row(c, "Lid", "Detected" if _lid_present() else "Not detected")


func _governors() -> Array:
	var raw: String = Sh.run_capture("cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors 2>/dev/null").strip_edges()
	if raw.is_empty():
		return []
	return Array(raw.split(" "))


func _battery() -> String:
	for line in Sh.run_lines("upower -e 2>/dev/null"):
		if line.contains("battery") or line.contains("BAT"):
			for detail in Sh.run_lines("upower -i " + line + " 2>/dev/null"):
				if detail.contains("percentage"):
					return detail.split(":", true, 1)[1].strip_edges()
	return "No battery (desktop)"


func _is_lock_on_suspend() -> bool:
	return Sh.kde_read("kdeglobals", "ScreenLock", "LockOnSuspend", "true").strip_edges() == "true"


func _idle_timeout() -> float:
	var raw := Sh.kde_read("kdeglobals", "ScreenLock", "IdleTimeout", "5").strip_edges()
	return float(raw) if not raw.is_empty() else 5.0


# --- lid close (PowerDevil: powerdevilrc [AC|Battery|LowBattery][SuspendAndShutdown]) ---

const _LID_PROFILES: Array = ["AC", "Battery", "LowBattery"]
const _LID_LABELS: Dictionary = {
	0: "Do nothing", 1: "Sleep", 2: "Hibernate", 8: "Shut down",
	16: "Show logout screen", 32: "Lock screen", 64: "Turn off screen",
	128: "Toggle screen on/off",
}


func _pd_call(method: String, args: String = "") -> String:
	var cmd := "gdbus call --session --dest org.kde.Solid.PowerManagement"
	cmd += " --object-path /org/kde/Solid/PowerManagement"
	cmd += " --method org.kde.Solid.PowerManagement." + method
	if not args.is_empty():
		cmd += " " + args
	return Sh.run_capture(cmd + " 2>/dev/null").strip_edges()


func _pd_action_supported(action: String) -> bool:
	return _pd_call("isActionSupported", Sh.quote(action)).begins_with("(true")


func _lid_present() -> bool:
	return _pd_call("isLidPresent").begins_with("(true")


# Tell PowerDevil to re-read powerdevilrc (exposed D-Bus method on the daemon).
func _reload_powerdevil() -> void:
	_pd_call("reparseConfiguration")


func _lid_action() -> int:
	for profile in _LID_PROFILES:
		var raw := Sh.kde_read("powerdevilrc", profile, "LidAction", "", "SuspendAndShutdown").strip_edges()
		if raw.is_valid_int():
			return int(raw)
	return _lid_action_default()


func _lid_action_default() -> int:
	# ProfileDefaults::defaultLidAction(isVM, canSuspend): VM -> 0, suspend -> 1, else -> 64.
	if Sh.run_capture("systemd-detect-virt 2>/dev/null").strip_edges() not in ["", "none"]:
		return 0
	return 1 if _pd_action_supported("Suspend") else 64


func _lid_action_label(value: int) -> String:
	return str(_LID_LABELS.get(value, str(value)))


func _set_lid_action(value: int) -> void:
	for profile in _LID_PROFILES:
		Sh.kde_write("powerdevilrc", profile, "LidAction", str(value), "SuspendAndShutdown")
	_reload_powerdevil()


func _inhibit_lid_external() -> bool:
	for profile in _LID_PROFILES:
		var raw := Sh.kde_read("powerdevilrc", profile,
				"InhibitLidActionWhenExternalMonitorPresent", "", "SuspendAndShutdown").strip_edges()
		if raw.is_valid_int() or raw in ["true", "false"]:
			return raw in ["1", "true"]
	return true  # KConfig default: inhibit (i.e. our "even when connected" toggle is off)


func _set_inhibit_lid_external(trigger: bool) -> void:
	for profile in _LID_PROFILES:
		Sh.kde_write("powerdevilrc", profile,
				"InhibitLidActionWhenExternalMonitorPresent",
				"false" if trigger else "true", "SuspendAndShutdown")
	_reload_powerdevil()

