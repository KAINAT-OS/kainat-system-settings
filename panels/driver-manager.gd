extends SettingsPanel
# Driver Manager: Smart driver detection + installation, plus KCM fallbacks.
# Auto-detects NVIDIA, AMD, Intel GPUs and Wi-Fi, offers one-click install.

var _driver_cards: Array[Node] = []
var _scan_card: Node = null


func build() -> void:
	page_header("Driver Manager", "Manage hardware drivers, firmware, and peripherals.")
	
	# Smart Driver Installer Section
	section("Smart Driver Installer")
	var c := card()
	_scan_card = c.get_parent()
	info_row(c, "Scanning...", "Detecting hardware and checking for missing drivers")
	
	defer(_populate_drivers)
	
	# Traditional KCM sections
	section("Graphics")
	var c2 := card()
	info_row(c2, "GPU", _gpu())
	kcm_row(c2, "OpenGL Information", "Installed OpenGL stack.", "G", "kcm_glx")
	kcm_row(c2, "Vulkan Information", "Vulkan drivers and devices.", "V", "kcm_vulkan")
	kcm_row(c2, "OpenCL Information", "Compute platform details.", "C", "kcm_opencl")
	if _driver_tool_available():
		action_row(c2, "Additional Drivers", "Browse every driver offered by the distribution.", "D", "Open", _open_driver_tool)
	
	section("Peripherals")
	var c3 := card()
	kcm_row(c3, "Thunderbolt", "Authorize and manage Thunderbolt devices.", "T", "kcm_bolt")
	kcm_row(c3, "Printer Manager", "Add and configure printers.", "P", "kcm_printer_manager")
	kcm_row(c3, "Camera", "Digital camera connection settings.", "A", "kcm_kamera")
	kcm_row(c3, "Auto-mount Devices", "Mounting of removable disks.", "M", "kcm_device_automounter")
	kcm_row(c3, "Device Actions", "Actions offered when devices connect.", "E", "kcm_solid_actions")
	
	section("Firmware")
	var c4 := card()
	kcm_row(c4, "Firmware Security", "Secure Boot and firmware state.", "F", "kcm_firmware_security")
	action_row(c4, "Update Firmware", "Apply firmware updates via fwupd.", "U", "Update", func() -> void:
		if not Sh.has_tool("fwupdmgr"):
			Sh._notify_missing("fwupdmgr", "Firmware update", notify)
			return
		notify("Checking for firmware updates…")
		run_async("pkexec sh -c 'fwupdmgr refresh --force; fwupdmgr update'", func(code: int) -> void:
			notify("Firmware is up to date." if code == 0 else "Firmware update finished with warnings — see the output above.")))


func _driver_card() -> VBoxContainer:
	var box := card()
	_driver_cards.append(box.get_parent())
	return box


func _populate_drivers() -> void:
	# Drop the placeholder and anything a previous scan produced, so repeated
	# scans replace their results instead of stacking duplicates.
	if is_instance_valid(_scan_card):
		content.remove_child(_scan_card)
		_scan_card.queue_free()
	_scan_card = null
	for old in _driver_cards:
		if is_instance_valid(old):
			content.remove_child(old)
			old.queue_free()
	_driver_cards.clear()
	
	var drivers_found := false
	
	# NVIDIA GPU Detection
	if Sh.has_nvidia_gpu():
		drivers_found = true
		var nvidia_pkg := _get_recommended_nvidia_driver()
		var installed := Sh.is_package_installed(nvidia_pkg)
		
		var c := _driver_card()
		var status := "Installed" if installed else "Not Installed (Recommended)"
		
		info_row(c, "NVIDIA GPU Detected", "Recommended driver: " + nvidia_pkg + " — " + status)
		
		if not installed:
			action_row(c, "Install NVIDIA Driver", "Install " + nvidia_pkg + " for best performance.", "I", "Install", func():
				notify("Installing " + nvidia_pkg + "... This may take a few minutes.")
				run_async(Sh.install_command(nvidia_pkg), func(code: int) -> void:
					notify("NVIDIA driver installed. Reboot required." if code == 0
						else "Installation failed. Check your internet connection."))
			)
		else:
			action_row(c, "Reinstall Driver", "Reinstall the NVIDIA driver.", "R", "Reinstall", func():
				notify("Reinstalling " + nvidia_pkg + "...")
				run_async(Sh.install_command(nvidia_pkg), func(code: int) -> void:
					notify("Reinstalled. Reboot required." if code == 0
						else "Reinstall failed. Check your internet connection."))
			)
	
	# Wi-Fi Detection (common chips)
	var wifi_info := _detect_wifi()
	if not wifi_info["driver"].is_empty():
		drivers_found = true
		var c := _driver_card()
		info_row(c, "Wi-Fi Adapter: " + wifi_info["device"], "Driver: " + wifi_info["driver"] + " — " + wifi_info["status"])
		
		if wifi_info["status"] == "Missing Firmware":
			action_row(c, "Install Wi-Fi Firmware", "Install " + wifi_info["package"] + " for " + wifi_info["device"], "W", "Install", func():
				notify("Installing " + str(wifi_info["package"]) + "...")
				run_async(Sh.install_command(str(wifi_info["package"])), func(code: int) -> void:
					notify("Firmware installed. Reboot may be required." if code == 0
						else "Installation failed. Check your internet connection."))
			)
	
	# AMD GPU (open source usually works, but check for firmware)
	var amd_info := _detect_amd_gpu()
	if not amd_info["missing"].is_empty():
		drivers_found = true
		var c := _driver_card()
		info_row(c, "AMD GPU Firmware", "Missing: " + amd_info["missing"])
		action_row(c, "Install AMD Firmware", "Install linux-firmware for full AMD GPU support.", "A", "Install", func():
			notify("Installing linux-firmware...")
			run_async(Sh.install_command("linux-firmware"), func(code: int) -> void:
				notify("Firmware installed. Reboot required." if code == 0
					else "Installation failed. Check your internet connection."))
		)
	
	if not drivers_found:
		var c := _driver_card()
		info_row(c, "All drivers up to date", "No missing proprietary drivers or firmware detected.")
		if _driver_tool_available():
			action_row(c, "Browse All Drivers", "Open the distribution driver manager for more options.", "B", "Open", _open_driver_tool)


func _driver_tool_available() -> bool:
	for tool in ["kubuntu-driver-manager", "driver-manager", "software-properties-qt", "gnome-software"]:
		if Sh.has_tool(tool):
			return true
	return false


func _get_recommended_nvidia_driver() -> String:
	# ubuntu-drivers prints one package per line, sometimes followed by a
	# comma and a comment. Keep only the package name.
	var output := Sh.run_capture("ubuntu-drivers list 2>/dev/null")
	for line in output.split("\n"):
		var token: String = line.strip_edges().split(",", false)[0].strip_edges()
		if token.begins_with("nvidia-driver"):
			return token

	# Debian/Kainat OS ship versioned packages; pick the highest version the
	# archive actually offers instead of guessing from the kernel version.
	var best := ""
	var best_version := -1
	for line in Sh.run_capture("apt-cache search --names-only '^nvidia-driver-[0-9]+$' 2>/dev/null").split("\n"):
		var parts: PackedStringArray = line.strip_edges().split(" ", false)
		if parts.is_empty():
			continue
		var name: String = parts[0]
		var suffix := name.substr("nvidia-driver-".length())
		if not suffix.is_valid_int():
			continue
		if int(suffix) > best_version:
			best_version = int(suffix)
			best = name
	if not best.is_empty():
		return best
	return "nvidia-driver"


func _detect_wifi() -> Dictionary:
	var result: Dictionary = {"device": "", "driver": "", "status": "", "package": ""}

	# lspci -nnk gives us the device line plus the "Kernel driver in use"
	# line directly underneath it, which is the most reliable signal.
	var device := ""
	var driver := ""
	var in_network := false
	for line in Sh.run_capture("lspci -nnk 2>/dev/null").split("\n"):
		var is_detail := line.begins_with("\t") or line.begins_with(" ")
		if not is_detail:
			in_network = line.contains("Network controller") or line.contains("Wireless")
			if in_network:
				device = line.strip_edges()
			continue
		if in_network and line.contains("Kernel driver in use:"):
			driver = line.split(":", false)[-1].strip_edges()
	if device.is_empty():
		return result

	result["device"] = device
	result["driver"] = driver if not driver.is_empty() else "none"

	var package := ""
	if device.contains("Realtek"):
		package = "firmware-realtek"
	elif device.contains("Intel"):
		package = "firmware-iwlwifi"
	elif device.contains("Broadcom"):
		package = "broadcom-sta-dkms"
	elif device.contains("MEDIATEK") or device.contains("MediaTek"):
		package = "firmware-mediatek"
	elif device.contains("Qualcomm") or device.contains("Atheros"):
		package = "firmware-atheros"
	result["package"] = package

	if driver.is_empty():
		result["status"] = "No driver loaded"
	elif package.is_empty():
		result["status"] = "OK"
	elif Sh.is_package_installed(package):
		result["status"] = "OK"
	else:
		result["status"] = "Missing Firmware"
	return result


func _detect_amd_gpu() -> Dictionary:
	var result: Dictionary = {"missing": ""}

	var gpu := Sh.run_capture("lspci 2>/dev/null | grep -iE 'VGA|3D|Display' | grep -iE 'AMD|ATI'")
	if gpu.strip_edges().is_empty():
		return result

	if not Sh.run_capture("lsmod 2>/dev/null | grep -w amdgpu").strip_edges().is_empty():
		# "direct-loading firmware ..." is a normal, successful message, so
		# only real failures count as missing firmware.
		var failures := Sh.run_capture("dmesg 2>/dev/null | grep -i amdgpu | grep -iE 'failed|error|not found|missing|no firmware' | head -5")
		if not failures.strip_edges().is_empty():
			result["missing"] = "amdgpu reported errors (run journalctl -k to see them)"
		return result

	# Module not loaded: only a problem if nothing else drives the card.
	var bound := Sh.run_capture("lspci -nnk 2>/dev/null | grep -iE 'AMD|ATI' -A3 | grep -i 'Kernel driver in use'")
	if bound.strip_edges().is_empty():
		result["missing"] = "amdgpu kernel module not loaded"
	return result


func _open_driver_tool() -> void:
	for tool in ["kubuntu-driver-manager", "driver-manager", "software-properties-qt", "gnome-software"]:
		if Sh.has_tool(tool):
			Sh.launch(tool)
			return
	Sh._notify_missing("kubuntu-driver-manager", "Driver manager", notify)


func _gpu() -> String:
	for line in Sh.run_lines("lspci 2>/dev/null"):
		if line.contains("VGA compatible controller") or line.contains("3D controller"):
			var idx: int = line.find(":")
			if idx != -1:
				return line.substr(idx + 1).strip_edges()
	return "Unknown graphics"