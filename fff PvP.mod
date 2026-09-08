return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`fff PvP` mod must be lower than Vermintide Mod Framework in your launcher's load order.")

		new_mod("fff PvP", {
			mod_script       = "scripts/mods/fff PvP/fff PvP",
			mod_data         = "scripts/mods/fff PvP/fff PvP_data",
			mod_localization = "scripts/mods/fff PvP/fff PvP_localization",
		})
	end,
	packages = {
		"resource_packages/fff PvP/fff PvP",
	},
}
