local Stagger = {}
local active_until = {}

local function install_templates()
	if not rawget(_G, "PlayerUnitMovementSettings") then
		return
	end

	PlayerUnitMovementSettings.overpowered_templates = PlayerUnitMovementSettings.overpowered_templates or {}
	PlayerUnitMovementSettings.overpowered_templates.pvp_parry_stagger = {}
	PlayerUnitMovementSettings.overpowered_templates.pvp_push_stagger = {}
end

install_templates()

function Stagger.apply(unit, template, duration, attacker)
	if not unit or not HEALTH_ALIVE[unit] or not Managers.player.is_server then
		return
	end

	local status = ScriptUnit.has_extension(unit, "status_system") and ScriptUnit.extension(unit, "status_system")
	if not status then
		return
	end

	-- Do not refresh an existing push/parry stagger. This prevents push spam
	-- from extending the control duration indefinitely.
	if status:is_overpowered() then
		return
	end

	StatusUtils.set_overpowered_network(unit, true, template, attacker)
	active_until[unit] = (Managers.time and Managers.time:time("game") or 0) + duration
end

function Stagger.update()
	local now = Managers.time and Managers.time:time("game") or 0
	for unit, end_time in pairs(active_until) do
		if not HEALTH_ALIVE[unit] or now >= end_time then
			if HEALTH_ALIVE[unit] and Managers.player.is_server then
				StatusUtils.set_overpowered_network(unit, false, nil, nil)
			end
			active_until[unit] = nil
		end
	end
end

function Stagger.clear(unit)
	if not active_until[unit] or not HEALTH_ALIVE[unit] or not Managers.player.is_server then
		return
	end

	StatusUtils.set_overpowered_network(unit, false, nil, nil)
	active_until[unit] = nil
end

function Stagger.hook(mod)
	if rawget(_G, "DamageUtils") then
		mod:hook(DamageUtils, "server_apply_hit", function(func, t, attacker_unit, target_unit, hit_zone_name, hit_position, attack_direction, hit_ragdoll_actor, damage_source, power_level, damage_profile, target_index, boost_curve_multiplier, is_critical_strike, can_damage, can_stagger, blocking, shield_breaking_hit, backstab_multiplier, first_hit, total_hits, source_attacker_unit, optional_predicted_damage)
			local result = {func(t, attacker_unit, target_unit, hit_zone_name, hit_position, attack_direction, hit_ragdoll_actor, damage_source, power_level, damage_profile, target_index, boost_curve_multiplier, is_critical_strike, can_damage, can_stagger, blocking, shield_breaking_hit, backstab_multiplier, first_hit, total_hits, source_attacker_unit, optional_predicted_damage)}
			if can_damage and not blocking and target_unit and active_until[target_unit] then
				Stagger.clear(target_unit)
			end
			return unpack(result)
		end)
	end

	if rawget(_G, "GenericStatusExtension") then
		mod:hook(GenericStatusExtension, "blocked_attack", function(func, self, fatigue_type, attacking_unit, fatigue_multiplier, improved_block, attack_direction)
			local t = Managers.time and Managers.time:time("game") or 0
			local was_timed_block = self.timed_block and t < self.timed_block
			local result = {func(self, fatigue_type, attacking_unit, fatigue_multiplier, improved_block, attack_direction)}
			if was_timed_block and rawget(_G, "DamageUtils") and attacking_unit and DamageUtils.is_player_unit(attacking_unit) and self.unit then
				Stagger.apply(attacking_unit, "slow_bomb", 3, self.unit)
			end
			return unpack(result)
		end)
	end

	if rawget(_G, "ActionPushStagger") then
		mod:hook(ActionPushStagger, "client_owner_post_update", function(func, self, dt, t, world, can_damage)
			local side = Managers.state and Managers.state.side
			local owner = self.owner_unit
			local lookup = side and side.enemy_units_lookup
			local added = {}
			if lookup and side.side_by_unit[owner] then
				local own_side = side.side_by_unit[owner]
				for _, unit in pairs(own_side.PLAYER_AND_BOT_UNITS or {}) do
					if unit ~= owner and not lookup[unit] and HEALTH_ALIVE[unit] then
						lookup[unit] = true
						added[#added + 1] = unit
					end
				end
			end
			local result = {func(self, dt, t, world, can_damage)}
			for i = 1, #added do lookup[added[i]] = nil end
			for unit in pairs(self.push_units or {}) do
				if DamageUtils.is_player_unit(unit) then
					Stagger.apply(unit, "slow_bomb", 1, owner)
				end
			end
			return unpack(result)
		end)
	end
end

return Stagger
