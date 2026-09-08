return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`fff PvP` must be lower than Vermintide Mod Framework in your launcher's load order.")
		new_mod("fff PvP", {
			mod_script = "scripts/mods/fff PvP/fff PvP",
			mod_data = "scripts/mods/fff PvP/fff PvP_data",
			mod_localization = "scripts/mods/fff PvP/fff PvP_localization",
		})
	end,
	-- Declare the package up front so VMF preloads it during mod setup.
	-- Without this, loading the Lua modules below causes a blocking sync load.
	packages = {
		"resource_packages/fff PvP/fff PvP",
	},
}
