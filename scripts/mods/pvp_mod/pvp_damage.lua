local Damage = {}

local function enabled(mod)
	return mod:get("pvp_enabled") ~= false
end

local function attack_class(damage_profile)
	local charge_value = damage_profile and damage_profile.charge_value
	if charge_value == "light_attack" then
		return "light"
	elseif charge_value == "heavy_attack" then
		return "heavy"
	end

	return nil
end

local function weapon_class(unit)
	local weapon = unit and ScriptUnit.has_extension(unit, "weapon_system") and ScriptUnit.extension(unit, "weapon_system")
	local template = weapon and weapon.get_weapon_template and weapon:get_weapon_template()
	local buff_type = template and template.buff_type
	if buff_type == "MELEE_1H" or buff_type == "MELEE_2H" then
		return buff_type
	end

	return nil
end

local function current_attack_class(unit)
	local weapon = unit and ScriptUnit.has_extension(unit, "weapon_system") and ScriptUnit.extension(unit, "weapon_system")
	local action = weapon and (weapon.current_action_settings or weapon.temporary_action_settings)
	if not action or (action.kind ~= "sweep" and action.kind ~= "melee_start") then
		return nil
	end

	local profile_name = action.damage_profile or action.damage_profile_inner or action.damage_profile_outer
	local profile = type(profile_name) == "table" and profile_name or profile_name and DamageProfileTemplates[profile_name]
	return attack_class(profile)
end

local function block_fatigue_type(attacker_unit, damage_profile)
	local attack_type = attack_class(damage_profile)
	if attack_type == "light" then
		return "blocked_attack"
	elseif attack_type == "heavy" then
		return weapon_class(attacker_unit) == "MELEE_2H" and "blocked_sv_cleave" or "blocked_sv_sweep"
	end

	return "blocked_attack"
end

function Damage.hook(mod, settings)
	-- ActionSweep filters allies before it reaches the normal block/damage path.
	-- Temporarily expose allied player units as enemy units for this call only.
	if rawget(_G, "ActionSweep") then
		mod:hook(ActionSweep, "_do_overlap", function(func, self, dt, t, unit, owner_unit, current_action, physics_world, is_within_damage_window, current_position, current_rotation)
			if not enabled(mod) then
				return func(self, dt, t, unit, owner_unit, current_action, physics_world, is_within_damage_window, current_position, current_rotation)
			end
			local side = Managers.state and Managers.state.side
			local lookup = side and side.enemy_units_lookup
			local added = {}
			if lookup and side.side_by_unit[owner_unit] then
				local own_side = side.side_by_unit[owner_unit]
				for _, target in pairs(own_side.PLAYER_AND_BOT_UNITS or {}) do
					if target ~= owner_unit and not lookup[target] and HEALTH_ALIVE[target] then
						lookup[target] = true
						added[#added + 1] = target
					end
				end
			end
			local result = {func(self, dt, t, unit, owner_unit, current_action, physics_world, is_within_damage_window, current_position, current_rotation)}
			for i = 1, #added do lookup[added[i]] = nil end
			return unpack(result)
		end)

		-- Native hero blocking only sets the blocked flag for melee sweeps. Run
		-- the native block checker for PVP heroes as well, preserving block arc,
		-- outer-arc multiplier, perfect-block handling, and network replication.
		mod:hook(ActionSweep, "_play_character_impact", function(func, self, is_server, attacker_unit, hit_unit, breed, hit_position, hit_zone_name, current_action, damage_profile, target_index, power_level, attack_direction, blocking, boost_curve_multiplier, is_critical_strike, backstab_multiplier)
			if not enabled(mod) then
				return func(self, is_server, attacker_unit, hit_unit, breed, hit_position, hit_zone_name, current_action, damage_profile, target_index, power_level, attack_direction, blocking, boost_curve_multiplier, is_critical_strike, backstab_multiplier)
			end
			if blocking and attacker_unit and hit_unit and DamageUtils.is_player_unit(attacker_unit) and DamageUtils.is_player_unit(hit_unit) then
				-- Let the native checker decide the arc and consume fatigue. Its
				-- return value is also the authoritative blocking result.
				blocking = DamageUtils.check_block(attacker_unit, hit_unit, block_fatigue_type(attacker_unit, damage_profile))
			end
			local result = {func(self, is_server, attacker_unit, hit_unit, breed, hit_position, hit_zone_name, current_action, damage_profile, target_index, power_level, attack_direction, blocking, boost_curve_multiplier, is_critical_strike, backstab_multiplier)}
			return unpack(result)
		end)
	end

	-- This is intentionally separate from friendly_fire_multiplier. It applies
	-- only to player-v-player damage and remains live when the slider changes.
	if rawget(_G, "DamageUtils") then
		mod:hook(DamageUtils, "calculate_damage", function(func, damage_output, target_unit, attacker_unit, hit_zone_name, original_power_level, boost_curve, boost_damage_multiplier, is_critical_strike, damage_profile, target_index, backstab_multiplier, damage_source)
			local value, secondary = func(damage_output, target_unit, attacker_unit, hit_zone_name, original_power_level, boost_curve, boost_damage_multiplier, is_critical_strike, damage_profile, target_index, backstab_multiplier, damage_source)
			if not enabled(mod) then
				return value, secondary
			end
			-- Attack/action classification is deliberately not used to zero damage.
			-- DamageUtils.calculate_damage is reached only after the weapon sweep
			-- has actually hit a player, so a real player hit must still deal damage.
			-- A simultaneous attack may be a weapon clash, but it must not suppress
			-- a hit whose weapon volume also reached the player's body.
			local pvp_units = target_unit and attacker_unit and DamageUtils.is_player_unit(target_unit) and DamageUtils.is_player_unit(attacker_unit)
			local attacker_class = attack_class(damage_profile)
			local target_class = current_attack_class(target_unit)
			local attacker_weapon_class = weapon_class(attacker_unit)
			local target_weapon_class = weapon_class(target_unit)
			local simultaneous_melee = pvp_units and attacker_class and target_class and attacker_weapon_class and target_weapon_class
			-- Keep this calculation explicit for future clash effects. It must not
			-- alter `value`: only the sweep hit decides whether damage is dealt.
			if simultaneous_melee then
				local same_attack = attacker_class == target_class
				local light_meets_heavy = attacker_class == "light" and target_class == "heavy"
				local heavy_meets_light = attacker_class == "heavy" and target_class == "light"
				local _is_weapon_clash = same_attack or light_meets_heavy or heavy_meets_light
			end
			if pvp_units and Managers.state.side:is_ally(attacker_unit, target_unit) then
				local multiplier = settings.get_damage_multiplier(mod)
				return value * multiplier, secondary
			end
			return value, secondary
		end)
	end
end

return Damage
