local mod = get_mod("fff PvP")

return {
	name = "fff PvP",
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "pvp_damage",
				type = "numeric",
				text = "PVP Damage (%)",
				tooltip = "玩家對玩家近戰傷害倍率（1% - 200%）",
				default_value = 25,
				range = {1, 200},
			},
		},
	},
}
