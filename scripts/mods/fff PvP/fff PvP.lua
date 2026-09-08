local mod = get_mod("fff PvP")

-- Keep the project entry point in the native build-detected folder.
-- The implementation modules are loaded from the same package below.
local Damage = mod:dofile("scripts/mods/pvp_mod/pvp_damage")
local Stagger = mod:dofile("scripts/mods/pvp_mod/pvp_stagger")
local Clash = mod:dofile("scripts/mods/pvp_mod/pvp_weapon_clash")
local Settings = mod:dofile("scripts/mods/pvp_mod/pvp_settings")

Damage.hook(mod, Settings)
Stagger.hook(mod)
Clash.hook(mod)

mod.update = function()
	Stagger.update()
end

mod:on_setting_changed(function(setting_id)
	if setting_id == "pvp_damage" then
		mod:echo(string.format("PVP Damage: %d%%", math.clamp(tonumber(mod:get(setting_id)) or 25, 1, 200)))
	end
end)
