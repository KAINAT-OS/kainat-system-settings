extends SettingsPanel
# Input Methods: Install and configure IMEs for CJK, Arabic, and other languages.
# Uses fcitx5 as the primary input method framework.

var _installed_engines: Dictionary = {}


func build() -> void:
	page_header("Input Methods", "Install and configure input method editors for your language.")
	
	_check_installed()
	_build_ui()


func _check_installed() -> void:
	_installed_engines["fcitx5"] = Sh.is_package_installed("fcitx5")
	_installed_engines["fcitx5-googlepinyin"] = Sh.is_package_installed("fcitx5-googlepinyin")
	_installed_engines["fcitx5-mozc"] = Sh.is_package_installed("fcitx5-mozc")
	_installed_engines["fcitx5-table-extra"] = Sh.is_package_installed("fcitx5-table-extra")
	_installed_engines["ibus"] = Sh.is_package_installed("ibus")
	_installed_engines["ibus-pinyin"] = Sh.is_package_installed("ibus-pinyin")
	_installed_engines["ibus-mozc"] = Sh.is_package_installed("ibus-mozc")
	
	# Check current input method
	var current_im := Sh.run_capture("echo $GTK_IM_MODULE").strip_edges()
	if current_im.is_empty():
		current_im = Sh.run_capture("echo $QT_IM_MODULE").strip_edges()
	if current_im.is_empty():
		current_im = Sh.kde_read("kdeglobals", "KDE", "IMModule", "").strip_edges()


func _build_ui() -> void:
	# Framework selector
	section("Input Method Framework")
	var c := card()

	action_row(c, "Input Framework", "Choose the input method framework.", "F", "Select", func() -> void:
		var fw: String = "fcitx5" if _installed_engines["fcitx5"] else "ibus"
		Sh.set_input_method_framework(fw)
		notify("Input framework set to " + fw + ". Log out and back in to apply."))
	
	# Chinese (Simplified) - Pinyin
	section("Chinese (Simplified) / 中文 (简体)")
	c = card()
	
	if _installed_engines["fcitx5-googlepinyin"]:
		info_row(c, "Google Pinyin (fcitx5)", "Installed")
	else:
		info_row(c, "Google Pinyin (fcitx5)", "Not installed")
		action_row(c, "Install Google Pinyin", "Smart Pinyin input with cloud suggestions.", "G", "Install", func():
			notify("Installing fcitx5-googlepinyin...")
			Sh.install_cjk_support()
			notify("Installed. Restart session to activate.")
			_check_installed()
			_build_ui()  # Rebuild
		)
	
	if _installed_engines["ibus-pinyin"]:
		info_row(c, "Pinyin (IBus)", "Installed")
	else:
		info_row(c, "Pinyin (IBus)", "Not installed")
		action_row(c, "Install IBus Pinyin", "Standard Pinyin for IBus.", "P", "Install", func():
			notify("Installing ibus-pinyin...")
			Sh.run_wait("pkexec apt install -y ibus-pinyin")
			notify("Installed. Restart session to activate.")
		)
	
	# Chinese (Traditional) / 日本語
	section("Chinese (Traditional) / 日本語")
	c = card()
	
	if _installed_engines["fcitx5-mozc"]:
		info_row(c, "Mozc (Japanese)", "Installed")
	else:
		info_row(c, "Mozc (Japanese)", "Not installed")
		action_row(c, "Install Mozc", "Japanese input (Hiragana/Katakana/Kanji).", "M", "Install", func():
			notify("Installing fcitx5-mozc...")
			Sh.install_cjk_support()
			notify("Installed. Restart session to activate.")
		)
	
	if _installed_engines["ibus-mozc"]:
		info_row(c, "Mozc (IBus)", "Installed")
	else:
		info_row(c, "Mozc (IBus)", "Not installed")
		action_row(c, "Install IBus Mozc", "Japanese input for IBus.", "M", "Install", func():
			notify("Installing ibus-mozc...")
			Sh.run_wait("pkexec apt install -y ibus-mozc")
			notify("Installed. Restart session to activate.")
		)
	
	# Korean / 한국어
	section("Korean / 한국어")
	c = card()
	
	if _installed_engines["fcitx5-table-extra"]:
		info_row(c, "Hangul (fcitx5)", "Available via table-extra")
	else:
		info_row(c, "Hangul (fcitx5)", "Not installed")
		action_row(c, "Install Hangul Tables", "Korean input tables for fcitx5.", "H", "Install", func():
			notify("Installing fcitx5-table-extra...")
			Sh.install_cjk_support()
			notify("Installed. Restart session to activate.")
		)
	
	# Arabic / العربية
	section("Arabic / العربية")
	c = card()
	
	if _installed_engines["fcitx5-table-extra"]:
		info_row(c, "Arabic (fcitx5)", "Available via table-extra")
	else:
		info_row(c, "Arabic (fcitx5)", "Not installed")
		action_row(c, "Install Arabic Tables", "Arabic keyboard layouts and tables.", "A", "Install", func():
			notify("Installing fcitx5-table-extra...")
			Sh.install_arabic_support()
			notify("Installed. Restart session to activate.")
		)
	
	# Configuration & Tools
	section("Configuration")
	c = card()
	
	if Sh.has_tool("fcitx5-configtool"):
		kcm_row(c, "Fcitx5 Configuration", "Configure input methods, keyboards, and addons.", "F", "kcm_fcitx5")
	elif Sh.has_tool("fcitx5-config-qt"):
		action_row(c, "Fcitx5 Configuration", "Open Fcitx5 configuration tool.", "F", "Open", func():
			Sh.launch("fcitx5-config-qt")
		)
	
	if Sh.has_tool("ibus-setup"):
		kcm_row(c, "IBus Configuration", "Configure IBus engines and preferences.", "I", "kcm_ibus")
	
	action_row(c, "Restart Input Method", "Restart fcitx5/IBus after installing new engines.", "R", "Restart", func():
		Sh.run("pkill -f fcitx5; fcitx5 -d &")
		Sh.run("ibus restart &")
		notify("Input methods restarted.")
	)
	
	# Current status
	section("Current Session")
	c = card()
	var current_im := Sh.run_capture("echo $GTK_IM_MODULE").strip_edges()
	if current_im.is_empty():
		current_im = Sh.run_capture("echo $QT_IM_MODULE").strip_edges()
	if current_im.is_empty():
		current_im = "Unknown (system default)"
	info_row(c, "Active IM Module", current_im)
	
	var fcitx_status := "Not running"
	if not Sh.run_capture("pgrep fcitx5").strip_edges().is_empty():
		fcitx_status = "Running (fcitx5)"
	elif not Sh.run_capture("pgrep ibus-daemon").strip_edges().is_empty():
		fcitx_status = "Running (IBus)"
	info_row(c, "Daemon Status", fcitx_status)
	
	info_row(c, "Note", "Changes require logging out and back in, or restarting the session.")