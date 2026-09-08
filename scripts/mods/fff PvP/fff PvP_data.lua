local mod = get_mod("fff PvP")

return {
	name = "fff PvP",
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "pvp_enabled",
				type = "checkbox",
				text = "PVP Enabled",
				tooltip = "啟用 PVP 規則；關閉時完全使用原本遊戲規則",
				default_value = true,
			},
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
