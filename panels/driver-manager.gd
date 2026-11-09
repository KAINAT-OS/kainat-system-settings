extends SettingsPanel
# Driver Manager / Hardware: device management and firmware.


func build() -> void:
	page_header("Driver Manager", "Manage hardware devices, drivers and firmware.")

	section("Graphics")
	var c := card()
	info_row(c, "Graphics", _gpu())
	action_row(c, "Additional Drivers", "Install proprietary GPU drivers.", "D", "Open", func() -> void:
		_open_driver_tool())
	kcm_row(c, "OpenGL Information", "Installed OpenGL stack.", "G", "kcm_glx")
	kcm_row(c, "Vulkan Information", "Vulkan drivers and devices.", "V", "kcm_vulkan")
	kcm_row(c, "OpenCL Information", "Compute platform details.", "C", "kcm_opencl")

	section("Peripherals")
	var c2 := card()
	kcm_row(c2, "Thunderbolt", "Authorize and manage Thunderbolt devices.", "T", "kcm_bolt")
	kcm_row(c2, "Printer Manager", "Add and configure printers.", "P", "kcm_printer_manager")
	kcm_row(c2, "Camera", "Digital camera connection settings.", "A", "kcm_kamera")
	kcm_row(c2, "Auto-mount Devices", "Mounting of removable disks.", "M", "kcm_device_automounter")
	kcm_row(c2, "Device Actions", "Actions offered when devices connect.", "E", "kcm_solid_actions")

	section("Firmware")
	var c3 := card()
	kcm_row(c3, "Firmware Security", "Secure Boot and firmware state.", "F", "kcm_firmware_security")
	action_row(c3, "Update Firmware", "Apply firmware updates.", "U", "Update", func() -> void:
		if Sh.has_tool("fwupdmgr"):
			Sh.run("pkexec fwupdmgr refresh && pkexec fwupdmgr update")
		else:
			Sh._notify_missing("fwupdmgr", "Firmware update", notify))


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