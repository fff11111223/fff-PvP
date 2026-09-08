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
			{
				setting_id = "pvp_bot_drill",
				type = "checkbox",
				text = "PVP Bot Drill (Host only)",
				tooltip = "進入私人任務後控制三名既有 Bot：防禦、重擊、輕擊。大廳只會保留開關，不會生成不完整的 Bot。",
				default_value = false,
			},
		},
	},
}
