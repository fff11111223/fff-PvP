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
				tooltip = "启用 PVP 规则；关闭时完全使用原本游戏规则",
				default_value = true,
			},
			{
				setting_id = "pvp_damage",
				type = "numeric",
				text = "PVP Damage (%)",
				tooltip = "玩家对玩家近战伤害倍率（1% - 2000%）",
				default_value = 25,
				range = {1, 2000},
			},
			{
				setting_id = "pvp_bot_drill",
				type = "checkbox",
				text = "PVP Bot Drill (Host only)",
				tooltip = "进入私人任务后控制三名既有 Bot：防御、重击、轻击。大厅只会保留开关，不会生成不完整的 Bot。",
				default_value = false,
			},
		},
	},
}
