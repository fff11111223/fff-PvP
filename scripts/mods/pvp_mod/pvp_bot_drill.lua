local BotDrill = {}
local attack_state = {}
local assigned_roles = {}

local ROLE_DEFEND = "defend"
local ROLE_HEAVY = "heavy"
local ROLE_LIGHT = "light"

local function enabled(mod)
	return mod:get("pvp_bot_drill") == true and Managers.player and Managers.player.is_server
end

local function assign_roles()
	local bots = {}
	for _, player in pairs(Managers.player:bots() or {}) do
		if player.player_unit and HEALTH_ALIVE[player.player_unit] then
			bots[#bots + 1] = player
		end
	end
	table.sort(bots, function(a, b)
		return a:local_player_id() < b:local_player_id()
	end)

	assigned_roles = {}
	if bots[1] then assigned_roles[bots[1].player_unit] = ROLE_DEFEND end
	if bots[2] then assigned_roles[bots[2].player_unit] = ROLE_HEAVY end
	if bots[3] then assigned_roles[bots[3].player_unit] = ROLE_LIGHT end

	return #bots
end

function BotDrill.hook(mod)
	if not rawget(_G, "PlayerBotInput") then
		return
	end

	mod:hook(PlayerBotInput, "_update_actions", function(func, self)
		if not enabled(mod) then
			return func(self)
		end

		local unit = self.unit
		local role = assigned_roles[unit]
		if role == ROLE_DEFEND then
			self:wield("slot_melee")
			self:defend()
		elseif role == ROLE_HEAVY or role == ROLE_LIGHT then
			self:wield("slot_melee")
			local now = Managers.time:time("game")
			local state = attack_state[unit] or {}
			attack_state[unit] = state
			if role == ROLE_LIGHT and now >= (state.next_attack or 0) then
				self:tap_attack()
				state.next_attack = now + 0.45
			elseif role == ROLE_HEAVY then
				if state.hold_until and now < state.hold_until then
					self:hold_attack()
				elseif state.hold_until then
					state.hold_until = nil
					state.next_attack = now + 0.8
				elseif now >= (state.next_attack or 0) then
					state.hold_until = now + 0.7
					self:hold_attack()
				end
			end
		end

		return func(self)
	end)
end

function BotDrill.update(mod)
	if not enabled(mod) then
		table.clear(assigned_roles)
		table.clear(attack_state)
		return
	end

	assign_roles()
end

function BotDrill.describe()
	return "Bot 1: 防禦；Bot 2: 重擊；Bot 3: 輕擊"
end

return BotDrill
