local Stagger = {}
local stagger_until = setmetatable({}, { __mode = "k" })

local function enabled(mod)
	return mod:get("pvp_enabled") ~= false
end

local function ensure_pvp_hit_react_settings(unit, name, duration, base_name)
	if not PlayerUnitMovementSettings or not PlayerUnitMovementSettings.get_movement_settings_table then
		return false
	end
	local movement = PlayerUnitMovementSettings.get_movement_settings_table(unit)
	local hit_react = movement and movement.hit_react_settings
	if not hit_react or hit_react[name] then
		return hit_react and hit_react[name] ~= nil
	end

	local base = hit_react[base_name]
	if not base then
		return false
	end

	local custom = {}
	for key, value in pairs(base) do
		custom[key] = value
	end
	custom.duration_function = function ()
		return duration
	end
	hit_react[name] = custom
	return true
end

local function player_is_attacking(unit)
	local inventory = unit and ScriptUnit.has_extension(unit, "inventory_system") and ScriptUnit.extension(unit, "inventory_system")
	local weapon_unit = inventory and (inventory.get_weapon_unit and inventory:get_weapon_unit() or inventory.get_weapon_unit_3p and inventory:get_weapon_unit_3p())
	local weapon_extension = weapon_unit and ScriptUnit.has_extension(weapon_unit, "weapon_system") and ScriptUnit.extension(weapon_unit, "weapon_system")
	local action = weapon_extension and weapon_extension.get_current_action_settings and weapon_extension:get_current_action_settings()

	return action and (action.kind == "sweep" or action.kind == "melee_start") or false
end

local function apply_native_control(unit, duration)
	local status = unit and ScriptUnit.has_extension(unit, "status_system") and ScriptUnit.extension(unit, "status_system")
	if not status then
		return false
	end
	if status._pvp_stagger_active then
		return false
	end

	-- The server owns the pushed flag. Clients only stage the duration metadata
	-- before the replicated native pushed status enters the character state.
	if not Managers.player.is_server then
		status._pvp_stagger_active = true
		status._pvp_stagger_hit_react_type = duration >= 3 and "pvp_perfect" or "pvp_push"
		return false
	end

	local now = Managers.time:time("game")
	if stagger_until[unit] and now < stagger_until[unit] then
		return false
	end

	stagger_until[unit] = now + duration
	status._pvp_stagger_active = true
	status._pvp_stagger_hit_react_type = duration >= 3 and "pvp_perfect" or "pvp_push"
	status:set_pushed(true, now)
	return true
end

function Stagger.apply_push(target_unit, attacker_unit)
	if not target_unit or not attacker_unit or not DamageUtils.is_player_unit(target_unit) or not DamageUtils.is_player_unit(attacker_unit) then
		return
	end
	if player_is_attacking(target_unit) then
		return
	end

	apply_native_control(target_unit, 1)
end

function Stagger.apply_perfect_block(unit)
	if unit and DamageUtils.is_player_unit(unit) then
		apply_native_control(unit, 3)
	end
end

function Stagger.update(mod)
	if not enabled(mod) then
		return
	end

	local now = Managers.time:time("game")
	for unit, end_time in pairs(stagger_until) do
		if end_time <= now then
			stagger_until[unit] = nil
		end
	end
end

function Stagger.clear(unit)
	local status = unit and ScriptUnit.has_extension(unit, "status_system") and ScriptUnit.extension(unit, "status_system")
	if not status then
		return
	end

	local was_active = status._pvp_stagger_active
	stagger_until[unit] = nil
	if not was_active then
		return
	end

	status._pvp_stagger_hit_react_type = nil
	status._pvp_stagger_active = nil
	local owner = Managers.player:owner(unit)
	if Managers.player.is_server or owner and owner.local_player then
		status._pvp_stagger_cancelled = true
		-- Clear the local state immediately on the owning client; the server's
		-- authoritative clear is replicated through the native pushed status.
		status:set_pushed(false)
	end
end

function Stagger.hook(mod)
	if rawget(_G, "GenericStatusExtension") then
		mod:hook(GenericStatusExtension, "blocked_attack", function(func, self, fatigue_type, attacking_unit, fatigue_multiplier, improved_block, attack_direction)
			if not enabled(mod) then
				return func(self, fatigue_type, attacking_unit, fatigue_multiplier, improved_block, attack_direction)
			end
			local now = Managers.time:time("game")
			local was_timed_block = self.timed_block and now < self.timed_block
			local result = { func(self, fatigue_type, attacking_unit, fatigue_multiplier, improved_block, attack_direction) }
			if was_timed_block and attacking_unit and DamageUtils.is_player_unit(attacking_unit) and self.unit then
				Stagger.apply_perfect_block(attacking_unit)
			end
			return unpack(result)
		end)
	end

	if rawget(_G, "PlayerCharacterStateStunned") then
		mod:hook(PlayerCharacterStateStunned, "on_enter", function(func, self, unit, input, dt, context, t, previous_state, params)
			if not enabled(mod) then
				return func(self, unit, input, dt, context, t, previous_state, params)
			end

			local status = ScriptUnit.has_extension(unit, "status_system") and ScriptUnit.extension(unit, "status_system")
			local hit_react_type = status and status._pvp_stagger_hit_react_type
			if hit_react_type then
				local duration = hit_react_type == "pvp_perfect" and 3 or 1
				local installed = ensure_pvp_hit_react_settings(unit, hit_react_type, duration, hit_react_type == "pvp_perfect" and "medium_push" or "light_push")
				if installed then
					params = params or {}
					params.hit_react_type = hit_react_type
					status._pvp_stagger_hit_react_type = nil
				end
			end

			local result = func(self, unit, input, dt, context, t, previous_state, params)
			return result
		end)

		mod:hook(PlayerCharacterStateStunned, "on_exit", function(func, self, unit, input, dt, context, t, next_state)
			local result = func(self, unit, input, dt, context, t, next_state)
			local status = ScriptUnit.has_extension(unit, "status_system") and ScriptUnit.extension(unit, "status_system")
			if status then
				status._pvp_stagger_active = nil
				status._pvp_stagger_hit_react_type = nil
			end
			return result
		end)

		mod:hook(PlayerCharacterStateStunned, "update", function(func, self, unit, input, dt, context, t)
			local status = ScriptUnit.has_extension(unit, "status_system") and ScriptUnit.extension(unit, "status_system")
			if status and status._pvp_stagger_cancelled then
				status._pvp_stagger_cancelled = nil
				self.csm:change_state("standing")
				return
			end

			return func(self, unit, input, dt, context, t)
		end)
	end

	if rawget(_G, "PlayerUnitHealthExtension") then
		mod:hook(PlayerUnitHealthExtension, "add_damage", function(func, self, attacker_unit, damage_amount, hit_zone_name, damage_type, hit_position, damage_direction, damage_source_name, hit_ragdoll_actor, source_attacker_unit, hit_react_type, is_critical_strike, added_dot, first_hit, total_hits, attack_type, backstab_multiplier, target_index)
			local result = func(self, attacker_unit, damage_amount, hit_zone_name, damage_type, hit_position, damage_direction, damage_source_name, hit_ragdoll_actor, source_attacker_unit, hit_react_type, is_critical_strike, added_dot, first_hit, total_hits, attack_type, backstab_multiplier, target_index)
			local target_unit = self.unit

			if enabled(mod) and attacker_unit and DamageUtils.is_player_unit(attacker_unit) and DamageUtils.is_player_unit(target_unit) then
				if damage_type == "push" then
					if Managers.player.is_server then
						Stagger.apply_push(target_unit, attacker_unit)
					else
						-- The server already decided whether the target was attacking;
						-- stage only the duration for the replicated native pushed state.
						apply_native_control(target_unit, 1)
					end
				elseif damage_amount and damage_amount > 0 then
					Stagger.clear(target_unit)
				end
			end

			return result
		end)
	end

	if rawget(_G, "ActionPushStagger") then
		mod:hook(ActionPushStagger, "client_owner_post_update", function(func, self, dt, t, world, can_damage)
			if not enabled(mod) then
				return func(self, dt, t, world, can_damage)
			end
			local side = Managers.state and Managers.state.side
			local owner = self.owner_unit
			local own_side = side and side.side_by_unit[owner]
			local lookup = own_side and own_side.enemy_units_lookup
			local added = {}
			if lookup then
				for _, unit in pairs(own_side.PLAYER_AND_BOT_UNITS or {}) do
					if unit ~= owner and HEALTH_ALIVE[unit] and not lookup[unit] then
						lookup[unit] = true
						added[#added + 1] = unit
					end
				end
			end
			local result = { func(self, dt, t, world, can_damage) }
			for i = 1, #added do
				lookup[added[i]] = nil
			end
			return unpack(result)
		end)
	end
end

return Stagger
