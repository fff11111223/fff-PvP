local Damage = {}

local function attack_class(damage_profile)
	local charge_value = damage_profile and damage_profile.charge_value
	if charge_value == "light_attack" then
		return "light"
	elseif charge_value == "heavy_attack" then
		return "heavy"
	end

	return nil
end

local function block_fatigue_type(attacker_unit, damage_profile, clash)
	local attack_type = attack_class(damage_profile)
	if attack_type == "light" then
		return "blocked_attack"
	elseif attack_type == "heavy" then
		return clash.weapon_class(attacker_unit) == "MELEE_2H" and "blocked_sv_cleave" or "blocked_sv_sweep"
	end

	return "blocked_attack"
end

function Damage.hook(mod, settings, tracker, clash)
	if rawget(_G, "ActionSweep") then
		-- Native hero blocking only sets the blocked flag for melee sweeps. Run
		-- the native block checker for PVP heroes as well, preserving block arc,
		-- outer-arc multiplier, perfect-block handling, and network replication.
		mod:hook(ActionSweep, "_play_character_impact", function(func, self, is_server, attacker_unit, hit_unit, breed, hit_position, hit_zone_name, current_action, damage_profile, target_index, power_level, attack_direction, blocking, boost_curve_multiplier, is_critical_strike, backstab_multiplier)
			if not settings.is_enabled(mod) then
				return func(self, is_server, attacker_unit, hit_unit, breed, hit_position, hit_zone_name, current_action, damage_profile, target_index, power_level, attack_direction, blocking, boost_curve_multiplier, is_critical_strike, backstab_multiplier)
			end
			if blocking and attacker_unit and hit_unit and DamageUtils.is_player_unit(attacker_unit) and DamageUtils.is_player_unit(hit_unit) then
				-- Let the native checker decide the arc and consume fatigue. Its
				-- return value is also the authoritative blocking result.
				blocking = DamageUtils.check_block(attacker_unit, hit_unit, block_fatigue_type(attacker_unit, damage_profile, clash))
			end
			local result = {func(self, is_server, attacker_unit, hit_unit, breed, hit_position, hit_zone_name, current_action, damage_profile, target_index, power_level, attack_direction, blocking, boost_curve_multiplier, is_critical_strike, backstab_multiplier)}
			return unpack(result)
		end)
	end

	-- This is intentionally separate from friendly_fire_multiplier. It applies
	-- only to player-v-player damage and remains live when the slider changes.
	if rawget(_G, "DamageUtils") then
		mod:hook(DamageUtils, "server_apply_hit", function(func, t, attacker_unit, target_unit, hit_zone_name, hit_position, attack_direction, hit_ragdoll_actor, damage_source, power_level, damage_profile, target_index, boost_curve_multiplier, is_critical_strike, can_damage, can_stagger, blocking, shield_breaking_hit, backstab_multiplier, first_hit, total_hits, source_attacker_unit, optional_predicted_damage)
			if not settings.is_enabled(mod) then
				return func(t, attacker_unit, target_unit, hit_zone_name, hit_position, attack_direction, hit_ragdoll_actor, damage_source, power_level, damage_profile, target_index, boost_curve_multiplier, is_critical_strike, can_damage, can_stagger, blocking, shield_breaking_hit, backstab_multiplier, first_hit, total_hits, source_attacker_unit, optional_predicted_damage)
			end
			local result = clash and clash.check(tracker, attacker_unit, target_unit, damage_profile)
			if result and result.available and result.clash and result.attacker_blocked and not blocking then
				can_damage = false
			end
			return func(t, attacker_unit, target_unit, hit_zone_name, hit_position, attack_direction, hit_ragdoll_actor, damage_source, power_level, damage_profile, target_index, boost_curve_multiplier, is_critical_strike, can_damage, can_stagger, blocking, shield_breaking_hit, backstab_multiplier, first_hit, total_hits, source_attacker_unit, optional_predicted_damage)
		end)

		mod:hook(DamageUtils, "calculate_damage", function(func, damage_output, target_unit, attacker_unit, hit_zone_name, original_power_level, boost_curve, boost_damage_multiplier, is_critical_strike, damage_profile, target_index, backstab_multiplier, damage_source)
			local value, secondary = func(damage_output, target_unit, attacker_unit, hit_zone_name, original_power_level, boost_curve, boost_damage_multiplier, is_critical_strike, damage_profile, target_index, backstab_multiplier, damage_source)
			if not settings.is_enabled(mod) then
				return value, secondary
			end
			-- Attack/action classification is deliberately not used to zero damage.
			-- DamageUtils.calculate_damage is reached only after the weapon sweep
			-- has actually hit a player, so a real player hit must still deal damage.
			-- A simultaneous attack may be a weapon clash, but it must not suppress
			-- a hit whose weapon volume also reached the player's body.
			local pvp_units = target_unit and attacker_unit and DamageUtils.is_player_unit(target_unit) and DamageUtils.is_player_unit(attacker_unit)
			if pvp_units and Managers.state.side:is_ally(attacker_unit, target_unit) then
				local multiplier = settings.get_damage_multiplier(mod)
				return value * multiplier, secondary
			end
			return value, secondary
		end)
	end
end

return Damage
