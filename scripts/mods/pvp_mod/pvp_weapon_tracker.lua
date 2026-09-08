local Tracker = {
	states = {},
}

local function alive(unit)
	return unit and HEALTH_ALIVE[unit] and Unit.alive(unit)
end

local function unit_alive(unit)
	return unit and Unit.alive(unit)
end

local function weapon_for(unit)
	local inventory = unit and ScriptUnit.has_extension(unit, "inventory_system") and ScriptUnit.extension(unit, "inventory_system")
	if not inventory then
		return nil
	end
	local weapon = inventory.get_weapon_unit_3p and inventory:get_weapon_unit_3p()
	return weapon or inventory:get_weapon_unit()
end

function Tracker.update(mod)
	if mod:get("pvp_enabled") == false or not Managers.player.is_server then
		return
	end
	local side = Managers.state and Managers.state.side
	local units = side and side.PLAYER_AND_BOT_UNITS
	if not units then
		return
	end
	local now = Managers.time:time("game")
	local seen = {}
	for _, player_unit in pairs(units) do
		if alive(player_unit) and DamageUtils.is_player_unit(player_unit) then
			seen[player_unit] = true
			local state = Tracker.states[player_unit] or {}
			local weapon = weapon_for(player_unit)
			if unit_alive(weapon) then
				local position = Unit.world_position(weapon, 0)
				local rotation = Unit.world_rotation(weapon, 0)
				state.previous_position = state.position
				state.previous_rotation = state.rotation
				state.position = position
				state.rotation = rotation
				state.timestamp = now
				state.weapon_unit = weapon
			else
				state.weapon_unit = nil
			end
			state.player_unit = player_unit
			Tracker.states[player_unit] = state
		end
	end
	for player_unit in pairs(Tracker.states) do
		if not seen[player_unit] then
			Tracker.states[player_unit] = nil
		end
	end
end

function Tracker.pose(unit)
	local state = Tracker.states[unit]
	if not state or not state.position or not state.rotation then
		return nil
	end
	return state
end

return Tracker
