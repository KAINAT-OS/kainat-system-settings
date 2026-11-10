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
		if Sh.has_tool("fwupdmgr"):
			notify("Checking for firmware updates...")
			Sh.run("pkexec fwupdmgr refresh && pkexec fwupdmgr update")
		else:
			Sh._notify_missing("fwupdmgr", "Firmware update", notify))


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
				var code := Sh.install_package(nvidia_pkg)
				if code == 0:
					notify("NVIDIA driver installed. Reboot required.")
				else:
					notify("Installation failed. Check internet connection.")
			)
		else:
			action_row(c, "Reinstall Driver", "Reinstall the NVIDIA driver.", "R", "Reinstall", func():
				notify("Reinstalling " + nvidia_pkg + "...")
				var code := Sh.install_package(nvidia_pkg)
				if code == 0:
					notify("Reinstalled. Reboot required.")
			)
	
	# Wi-Fi Detection (common chips)
	var wifi_info := _detect_wifi()
	if not wifi_info["driver"].is_empty():
		drivers_found = true
		var c := _driver_card()
		info_row(c, "Wi-Fi Adapter: " + wifi_info["device"], "Driver: " + wifi_info["driver"] + " — " + wifi_info["status"])
		
		if wifi_info["status"] == "Missing Firmware":
			action_row(c, "Install Wi-Fi Firmware", "Install " + wifi_info["package"] + " for " + wifi_info["device"], "W", "Install", func():
				notify("Installing " + wifi_info["package"] + "...")
				var code := Sh.install_package(wifi_info["package"])
				if code == 0:
					notify("Firmware installed. Reboot may be required.")
				else:
					notify("Installation failed.")
			)
	
	# AMD GPU (open source usually works, but check for firmware)
	var amd_info := _detect_amd_gpu()
	if not amd_info["missing"].is_empty():
		drivers_found = true
		var c := _driver_card()
		info_row(c, "AMD GPU Firmware", "Missing: " + amd_info["missing"])
		action_row(c, "Install AMD Firmware", "Install linux-firmware for full AMD GPU support.", "A", "Install", func():
			notify("Installing linux-firmware...")
			var code := Sh.install_package("linux-firmware")
			if code == 0:
				notify("Firmware installed. Reboot required.")
		)
	
	if not drivers_found:
		info_row(content, "All drivers up to date", "No missing proprietary drivers detected.")


func _get_recommended_nvidia_driver() -> String:
	# Try to get the recommended driver from ubuntu-drivers
	var output := Sh.run_capture("ubuntu-drivers list 2>/dev/null | grep nvidia | head -1")
	if not output.strip_edges().is_empty():
		return output.strip_edges()
	
	# Fallback to common package
	var kernel := Sh.run_capture("uname -r").strip_edges()
	if kernel.begins_with("6."):
		return "nvidia-driver-550"
	elif kernel.begins_with("5."):
		return "nvidia-driver-535"
	return "nvidia-driver-535"


func _detect_wifi() -> Dictionary:
	var result: Dictionary = {"device": "", "driver": "", "status": "", "package": ""}
	
	var output := Sh.run_capture("lspci -nn | grep -i network")
	for line in output.split("\n"):
		var stripped := line.strip_edges()
		if stripped.is_empty():
			continue
		
		result["device"] = stripped
		
		# Check for common chips
		if "Realtek" in stripped and "8822" in stripped:
			result["driver"] = "rtw88"
			result["package"] = "firmware-realtek"
			if not Sh.is_package_installed("firmware-realtek"):
				result["status"] = "Missing Firmware"
			else:
				result["status"] = "OK"
		elif "Intel" in stripped and ("Wi-Fi" in stripped or "Wireless" in stripped):
			result["driver"] = "iwlwifi"
			result["package"] = "firmware-iwlwifi"
			if not Sh.is_package_installed("firmware-iwlwifi"):
				result["status"] = "Missing Firmware"
			else:
				result["status"] = "OK"
		elif "Broadcom" in stripped:
			result["driver"] = "broadcom-sta"
			result["package"] = "broadcom-sta-dkms"
			if not Sh.is_package_installed("broadcom-sta-dkms"):
				result["status"] = "Missing Driver"
			else:
				result["status"] = "OK"
		break
	
	return result


func _detect_amd_gpu() -> Dictionary:
	var result: Dictionary = {"missing": ""}
	
	# Check if amdgpu is loaded but firmware missing
	var dmesg := Sh.run_capture("dmesg | grep -i amdgpu | grep -i firmware | head -5")
	if not dmesg.strip_edges().is_empty():
		result["missing"] = "amdgpu firmware (see dmesg)"
	elif Sh.run_capture("lsmod | grep amdgpu").strip_edges().is_empty() and Sh.has_nvidia_gpu() == false:
		# Has AMD GPU but no driver loaded
		var lspci := Sh.run_capture("lspci | grep -i amd | grep -i vga")
		if not lspci.strip_edges().is_empty():
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