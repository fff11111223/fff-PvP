local mod = get_mod("fff PvP")

-- Keep the project entry point in the native build-detected folder.
-- The implementation modules are loaded from the same package below.
local Damage = mod:dofile("scripts/mods/pvp_mod/pvp_damage")
local Settings = mod:dofile("scripts/mods/pvp_mod/pvp_settings")
local Tracker = mod:dofile("scripts/mods/pvp_mod/pvp_weapon_tracker")
local Clash = mod:dofile("scripts/mods/pvp_mod/pvp_weapon_clash")
local BotDrill = mod:dofile("scripts/mods/pvp_mod/pvp_bot_drill")

Damage.hook(mod, Settings, Tracker, Clash)
BotDrill.hook(mod)
mod.update = function()
	Tracker.update(mod)
	BotDrill.update(mod)
end

local function broadcast_pvp_rules()
	local damage = math.clamp(tonumber(mod:get("pvp_damage")) or 25, 1, 200)
	local messages = {
		"[PVP] PVP 模式已啟用！",
		string.format("[PVP] 玩家傷害：%d%%", damage),
		"[PVP] 輕擊格擋：1 體力",
		"[PVP] 單手重擊格擋：4 體力",
		"[PVP] 雙手重擊格擋：16 體力",
		"[PVP] 普通攻擊：ATK / BLOCK / PARRY 使用原生流程",
		"[PVP] 滿蓄 Heavy：穿透玩家 Block / Parry",
		"[PVP] Push：完全使用原生流程",
		"[PVP] 武器碰撞：輕輕 / 重重互撞；輕重碰撞時重擊繼續",
	}

	for i = 1, #messages do
		local message = messages[i]
		local sent = false
		pcall(function()
			if Managers.chat and Managers.chat:has_channel(1) then
				Managers.chat:send_chat_message(1, 1, message)
				sent = true
			end
		end)
		if not sent then
			mod:echo(message)
		end
	end
end

-- VMF invokes this field directly after a setting is changed.  It is not a
-- registration method, so calling it with ':' fails on current VMF builds.
mod.on_setting_changed = function(setting_id)
	if setting_id == "pvp_enabled" and mod:get(setting_id) == true then
		broadcast_pvp_rules()
	elseif setting_id == "pvp_damage" and mod:get("pvp_enabled") ~= false then
		mod:echo(string.format("PVP Damage: %d%%", math.clamp(tonumber(mod:get(setting_id)) or 25, 1, 200)))
	elseif setting_id == "pvp_bot_drill" then
		mod:echo(mod:get(setting_id) == true and "PVP Bot 測試已啟用：" .. BotDrill.describe() or "PVP Bot 測試已關閉")
	end
end
