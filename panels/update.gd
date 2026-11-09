extends SettingsPanel
# Updates: configure update behaviour and trigger a system upgrade.


func build() -> void:
	page_header("Updates", "Keep Kainat OS and its packages up to date.")

	section("Software Updates")
	var c := card()
	info_row(c, "Distribution", str(Sh.os_release().get("PRETTY_NAME", "Kainat OS")))
	kcm_row(c, "Update Settings", "Choose how and when updates are applied.", "S", "kcm_updates")

	section("Package Maintenance")
	var c2 := card()
	action_row(c2, "Check for Updates", "Refresh the package lists.", "C", "Run", func() -> void:
		notify("Refreshing package lists…")
		Sh.run("pkexec apt-get update"))
	action_row(c2, "Upgrade All Packages", "Install all available updates.", "U", "Upgrade", func() -> void:
		notify("Upgrading packages…")
		Sh.run("pkexec apt-get -y upgrade"))
	action_row(c2, "Remove Unused Packages", "Clean up dependencies and cache.", "R", "Clean", func() -> void:
		notify("Cleaning up…")
		Sh.run("pkexec apt-get -y autoremove && pkexec apt-get -y autoclean"))

	section("Sources")
	var c3 := card()
	action_row(c3, "Software Sources", "Manage repositories.", "P", "Open", _open_software_sources)


func _open_software_sources() -> void:
	for tool in ["software-properties-qt", "software-properties-gtk", "plasma-discover"]:
		if Sh.has_tool(tool):
			if tool == "plasma-discover":
				Sh.launch(tool, ["--mode", "sources"])
			else:
				Sh.launch(tool)
			return
	Sh._notify_missing("software-properties-qt or plasma-discover", "Software sources", notify)
