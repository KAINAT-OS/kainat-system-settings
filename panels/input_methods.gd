extends SettingsPanel
# Input Methods: install and configure IMEs for CJK, Arabic and other scripts.
# fcitx5 is the recommended framework; IBus is offered as the alternative.

var _installed: Dictionary = {}


func build() -> void:
	page_header("Input Methods", "Install and configure input method editors for your language.")
	_check_installed()
	_build_ui()


func _check_installed() -> void:
	for package in [
		"fcitx5", "fcitx5-chinese-addons", "fcitx5-mozc", "fcitx5-table-extra",
		"fcitx5-hangul", "ibus", "ibus-pinyin", "ibus-mozc",
	]:
		_installed[package] = Sh.is_package_installed(package)


# Rebuild after an install so the rows switch from "Install" to "Installed".
func _rebuild() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	_check_installed()
	_build_ui()


func _build_ui() -> void:
	section("Input Method Framework")
	var c := card()
	var frameworks: Array = ["fcitx5 (recommended)", "IBus"]
	var current := Sh.get_input_method_framework()
	choice_row(c, "Framework", "Engine that handles typing in other languages.", "F",
		frameworks, 0 if current == "fcitx5" else 1, func(index: int) -> void:
			var fw := "fcitx5" if index == 0 else "ibus"
			Sh.set_input_method_framework(fw)
			notify("Framework set to " + fw + ". Log out and back in to apply."))

	_add_engine_section("Chinese (Simplified) / 中文 (简体)", [
		{"title": "Pinyin (fcitx5)", "package": "fcitx5-chinese-addons", "hint": "Pinyin, Shuangpin and Wubi input."},
		{"title": "Pinyin (IBus)", "package": "ibus-pinyin", "hint": "Pinyin input for IBus."},
	])
	_add_engine_section("Japanese / 日本語", [
		{"title": "Mozc (fcitx5)", "package": "fcitx5-mozc", "hint": "Hiragana, Katakana and Kanji input."},
		{"title": "Mozc (IBus)", "package": "ibus-mozc", "hint": "Japanese input for IBus."},
	])
	_add_engine_section("Korean / 한국어", [
		{"title": "Hangul (fcitx5)", "package": "fcitx5-hangul", "hint": "Hangul input for fcitx5."},
	])
	_add_engine_section("Arabic / العربية", [
		{"title": "Arabic tables (fcitx5)", "package": "fcitx5-table-extra", "hint": "Arabic keyboard tables for fcitx5."},
	])

	section("Configuration")
	c = card()
	if Sh.has_tool("fcitx5-configtool"):
		action_row(c, "Fcitx5 Configuration", "Add engines, switch hotkeys, tune addons.", "F", "Open", func() -> void:
			Sh.launch("fcitx5-configtool"))
	if Sh.has_tool("ibus-setup"):
		action_row(c, "IBus Configuration", "Manage engines and preferences.", "I", "Open", func() -> void:
			Sh.launch("ibus-setup"))
	action_row(c, "Restart Input Methods", "Pick up newly installed engines now.", "R", "Restart", func() -> void:
		_restart_daemons())
	if not Sh.has_tool("fcitx5-configtool") and not Sh.has_tool("ibus-setup"):
		info_row(c, "No configuration tool", "Install fcitx5 or IBus first.")

	section("Current Session")
	c = card()
	info_row(c, "Active Framework", Sh.get_input_method_framework())
	info_row(c, "Daemon", _daemon_status())
	info_row(c, "Note", "Log out and back in after installing a framework.")


func _add_engine_section(title: String, engines: Array) -> void:
	section(title)
	var c := card()
	for engine in engines:
		var package: String = str(engine["package"])
		if bool(_installed.get(package, false)):
			info_row(c, str(engine["title"]), "Installed")
			continue
		info_row(c, str(engine["title"]), "Not installed")
		action_row(c, "Install " + str(engine["title"]), str(engine["hint"]), "I", "Install", func() -> void:
			_install(package))


func _install(package: String) -> void:
	notify("Installing " + package + "... This may take a few minutes.")
	run_async(Sh.install_command(package), func(code: int) -> void:
		if code != 0:
			notify("Could not install " + package + ". Check your internet connection.")
			return
		notify(package + " installed.")
		_rebuild())


func _restart_daemons() -> void:
	if Sh.has_tool("fcitx5"):
		Sh.run("pkill -x fcitx5 >/dev/null 2>&1; fcitx5 -d >/dev/null 2>&1 &")
	if Sh.has_tool("ibus-daemon"):
		Sh.run("ibus restart >/dev/null 2>&1 &")
	notify("Input methods restarted.")


func _daemon_status() -> String:
	if not Sh.run_capture("pgrep -x fcitx5").strip_edges().is_empty():
		return "Running (fcitx5)"
	if not Sh.run_capture("pgrep -x ibus-daemon").strip_edges().is_empty():
		return "Running (IBus)"
	return "Not running"
