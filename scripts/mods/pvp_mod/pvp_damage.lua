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

local function weapon_extension(unit)
	local inventory = unit and ScriptUnit.has_extension(unit, "inventory_system") and ScriptUnit.extension(unit, "inventory_system")
	local weapon_unit = inventory and inventory.get_weapon_unit and inventory:get_weapon_unit()
	return weapon_unit and ScriptUnit.has_extension(weapon_unit, "weapon_system") and ScriptUnit.extension(weapon_unit, "weapon_system") or nil
end

local function is_full_heavy(unit)
	local extension = weapon_extension(unit)
	return extension and extension._pvp_full_heavy == true or false
end

local function pvp_units(attacker_unit, target_unit)
	return attacker_unit and target_unit and DamageUtils.is_player_unit(attacker_unit) and DamageUtils.is_player_unit(target_unit)
end

local function replace_blocking_argument(parameters, value)
	local result = {}
	for i = 1, #parameters do
		result[i] = parameters[i]
		if parameters[i] == "blocking" and i < #parameters then
			result[i + 1] = value
		end
	end
	return result
end

function Damage.hook(mod, settings, tracker, clash)
	if rawget(_G, "WeaponUnitExtension") then
		-- The native melee-start action exposes each weapon's own release window
		-- through allowed_chain_actions.  Reaching the heavy release window is
		-- the game's full-charge boundary; no common time constant is introduced.
		mod:hook(WeaponUnitExtension, "start_action", function(func, self, action_name, sub_action_name, actions, t, power_level, action_init_data)
			if not settings.is_enabled(mod) then
				self._pvp_full_heavy = false
				return func(self, action_name, sub_action_name, actions, t, power_level, action_init_data)
			end
			local previous = self.current_action_settings
			local reached_heavy_release = false
			if previous and previous.kind == "melee_start" and self.action_time_started then
				local held_time = t - self.action_time_started
				for i = 1, #(previous.allowed_chain_actions or {}) do
					local chain = previous.allowed_chain_actions[i]
					if chain.input == "action_one_release" and chain.start_time then
						local next_settings = self:get_action(chain.action, chain.sub_action, actions)
						if next_settings and next_settings.charge_value == "heavy_attack" then
							local scale = self.action_time_scale or ActionUtils.get_action_time_scale(self.owner_unit, previous)
							reached_heavy_release = held_time >= chain.start_time / scale
							break
						end
					end
				end
			end

			local result = {func(self, action_name, sub_action_name, actions, t, power_level, action_init_data)}
			local current = self.current_action_settings
			self._pvp_full_heavy = reached_heavy_release and current and current.charge_value == "heavy_attack" or false
			return unpack(result)
		end)
	end

	if rawget(_G, "ActionSweep") then
		-- ActionSweep rejects every unit that is absent from enemy_units_lookup
		-- before it reaches _play_character_impact. Temporarily expose the other
		-- heroes on our side as enemies, then restore the lookup immediately.
		-- This includes both human teammates and AI bots.
		mod:hook(ActionSweep, "_do_overlap", function(func, self, dt, t, unit, owner_unit, current_action, physics_world, is_within_damage_window, current_position, current_rotation)
			if not settings.is_enabled(mod) then
				return func(self, dt, t, unit, owner_unit, current_action, physics_world, is_within_damage_window, current_position, current_rotation)
			end

			local side_manager = Managers.state and Managers.state.side
			local side = side_manager and side_manager.side_by_unit[owner_unit]
			local enemy_lookup = side and side.enemy_units_lookup
			local added = {}
			if enemy_lookup then
				for _, target_unit in pairs(side.PLAYER_AND_BOT_UNITS or {}) do
					if target_unit ~= owner_unit and HEALTH_ALIVE[target_unit] and not enemy_lookup[target_unit] then
						enemy_lookup[target_unit] = true
						added[#added + 1] = target_unit
					end
				end
			end

			local result = { func(self, dt, t, unit, owner_unit, current_action, physics_world, is_within_damage_window, current_position, current_rotation) }
			for i = 1, #added do
				enemy_lookup[added[i]] = nil
			end
			return unpack(result)
		end)

		-- Native hero blocking only sets the blocked flag for melee sweeps. Run
		-- the native block checker for PVP heroes as well, preserving block arc,
		-- outer-arc multiplier, perfect-block handling, and network replication.
		mod:hook(ActionSweep, "_play_character_impact", function(func, self, is_server, attacker_unit, hit_unit, breed, hit_position, hit_zone_name, current_action, damage_profile, target_index, power_level, attack_direction, blocking, boost_curve_multiplier, is_critical_strike, backstab_multiplier)
			if not settings.is_enabled(mod) then
				return func(self, is_server, attacker_unit, hit_unit, breed, hit_position, hit_zone_name, current_action, damage_profile, target_index, power_level, attack_direction, blocking, boost_curve_multiplier, is_critical_strike, backstab_multiplier)
			end
			if blocking and pvp_units(attacker_unit, hit_unit) then
				if is_full_heavy(attacker_unit) then
					-- A fully charged Heavy is the PvP anti-defense property: keep
					-- the native sweep and hit reaction, but do not enter block/parry.
					blocking = false
					self._pvp_anti_defense_hit = true
					self._pvp_blocked_hit = nil
				else
					-- Let the native checker decide the arc and consume fatigue. Its
					-- return value is also the authoritative blocking result.
					blocking = DamageUtils.check_block(attacker_unit, hit_unit, block_fatigue_type(attacker_unit, damage_profile, clash))
					self._pvp_blocked_hit = blocking
				end
			end
			-- PvP light hits always use the weapon-clash impact feedback.  The
			-- server-side clash result below also suppresses their damage; PvE and
			-- every Heavy hit remain unchanged.
			if pvp_units(attacker_unit, hit_unit) and damage_profile and damage_profile.charge_value == "light_attack" then
				self._pvp_blocked_hit = true
			end
			local result = {func(self, is_server, attacker_unit, hit_unit, breed, hit_position, hit_zone_name, current_action, damage_profile, target_index, power_level, attack_direction, blocking, boost_curve_multiplier, is_critical_strike, backstab_multiplier)}
			return unpack(result)
		end)

		-- Feed the authoritative PVP block result into ActionSweep's native
		-- attacker hit-stop/abort animation path.
		mod:hook(ActionSweep, "_play_hit_animations", function(func, self, owner_unit, current_action, abort_attack, hit_zone_name, armor_type, blocking, killed_unit)
			if not settings.is_enabled(mod) then
				self._pvp_blocked_hit = nil
				self._pvp_anti_defense_hit = nil
				return func(self, owner_unit, current_action, abort_attack, hit_zone_name, armor_type, blocking, killed_unit)
			end
			if self._pvp_anti_defense_hit then
				blocking = false
				self._pvp_anti_defense_hit = nil
			end
			if self._pvp_blocked_hit then
				blocking = true
				self._pvp_blocked_hit = nil
			end
			return func(self, owner_unit, current_action, abort_attack, hit_zone_name, armor_type, blocking, killed_unit)
		end)

		-- The native sweep passes the block result again in its attack-hit RPC.
		-- Remove it only for a fully charged Heavy PvP hit; all other native
		-- block/parry data is left untouched.
		mod:hook(ActionSweep, "_send_attack_hit", function(func, self, t, damage_source_id, attacker_unit_id, hit_unit_id, hit_zone_id, hit_position, attack_direction, damage_profile_id, ...)
			local optional = {...}
			local attacker = self.owner_unit
			local hit_unit = Managers.state.network:game_object_or_level_unit(hit_unit_id)
			if settings.is_enabled(mod) and pvp_units(attacker, hit_unit) and is_full_heavy(attacker) then
				optional = replace_blocking_argument(optional, false)
			end
			return func(self, t, damage_source_id, attacker_unit_id, hit_unit_id, hit_zone_id, hit_position, attack_direction, damage_profile_id, unpack(optional))
		end)
	end

	-- This is intentionally separate from friendly_fire_multiplier. It applies
	-- only to player-v-player damage and remains live when the slider changes.
	if rawget(_G, "DamageUtils") then
		mod:hook(DamageUtils, "server_apply_hit", function(func, t, attacker_unit, target_unit, hit_zone_name, hit_position, attack_direction, hit_ragdoll_actor, damage_source, power_level, damage_profile, target_index, boost_curve_multiplier, is_critical_strike, can_damage, can_stagger, blocking, shield_breaking_hit, backstab_multiplier, first_hit, total_hits, source_attacker_unit, optional_predicted_damage)
			if not settings.is_enabled(mod) then
				return func(t, attacker_unit, target_unit, hit_zone_name, hit_position, attack_direction, hit_ragdoll_actor, damage_source, power_level, damage_profile, target_index, boost_curve_multiplier, is_critical_strike, can_damage, can_stagger, blocking, shield_breaking_hit, backstab_multiplier, first_hit, total_hits, source_attacker_unit, optional_predicted_damage)
			end
			local clash_result = clash and clash.check(tracker, attacker_unit, target_unit, damage_profile)
			if clash_result and clash_result.available and clash_result.clash and clash_result.attacker_blocked and not blocking then
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

	-- PlayerUnitHealthExtension is the native hand-off point for hero hit
	-- reactions.  DamageUtils.add_damage_network_player deliberately passes a
	-- nil hit_react_type for normal melee profiles, so provide only the native
	-- light/heavy name for successful PvP hero damage.  The health extension
	-- then stores it and includes NetworkLookup.hit_react_types in its normal
	-- rpc_add_damage path.
	if rawget(_G, "PlayerUnitHealthExtension") then
		mod:hook(PlayerUnitHealthExtension, "add_damage", function(func, self, attacker_unit, damage_amount, hit_zone_name, damage_type, hit_position, damage_direction, damage_source_name, hit_ragdoll_actor, source_attacker_unit, hit_react_type, is_critical_strike, added_dot, first_hit, total_hits, attack_type, backstab_multiplier, target_index)
			if settings.is_enabled(mod) and pvp_units(attacker_unit, self.unit) then
				if attack_type == "light_attack" then
					hit_react_type = "light"
				elseif attack_type == "heavy_attack" then
					hit_react_type = "heavy"
				end
			end

			return func(self, attacker_unit, damage_amount, hit_zone_name, damage_type, hit_position, damage_direction, damage_source_name, hit_ragdoll_actor, source_attacker_unit, hit_react_type, is_critical_strike, added_dot, first_hit, total_hits, attack_type, backstab_multiplier, target_index)
		end)
	end

	-- WeaponSystem re-resolves the damage profile when it receives the melee
	-- hit RPC. Many normal hero profiles omit fatigue_type because allies are
	-- ordinarily never valid melee targets. PVP makes that path valid, so give
	-- blocked PVP hits a concrete, network-registered fatigue type.
	if rawget(_G, "WeaponSystem") then
		mod:hook(WeaponSystem, "rpc_attack_hit", function(func, self, channel_id, damage_source_id, attacker_unit_id, hit_unit_id, hit_zone_id, hit_position, attack_direction, damage_profile_id, power_level, target_index, boost_curve_multiplier, is_critical_strike, can_damage, can_stagger, hit_ragdoll_actor_id, blocking, shield_break_procced, backstab_multiplier, attacker_is_level_unit, first_hit, total_hits)
			if not settings.is_enabled(mod) or not blocking then
				return func(self, channel_id, damage_source_id, attacker_unit_id, hit_unit_id, hit_zone_id, hit_position, attack_direction, damage_profile_id, power_level, target_index, boost_curve_multiplier, is_critical_strike, can_damage, can_stagger, hit_ragdoll_actor_id, blocking, shield_break_procced, backstab_multiplier, attacker_is_level_unit, first_hit, total_hits)
			end

			local attacker_unit = self.network_manager:game_object_or_level_unit(attacker_unit_id, attacker_is_level_unit)
			local hit_unit = self.unit_storage:unit(hit_unit_id)
			local is_pvp_hit = attacker_unit and hit_unit and DamageUtils.is_player_unit(attacker_unit) and DamageUtils.is_player_unit(hit_unit)
			if is_pvp_hit and is_full_heavy(attacker_unit) then
				blocking = false
			end
			local profile_name = NetworkLookup.damage_profiles[damage_profile_id]
			local profile = profile_name and DamageProfileTemplates[profile_name]
			if not is_pvp_hit or not profile then
				return func(self, channel_id, damage_source_id, attacker_unit_id, hit_unit_id, hit_zone_id, hit_position, attack_direction, damage_profile_id, power_level, target_index, boost_curve_multiplier, is_critical_strike, can_damage, can_stagger, hit_ragdoll_actor_id, blocking, shield_break_procced, backstab_multiplier, attacker_is_level_unit, first_hit, total_hits)
			end

			local original_fatigue_type = profile.fatigue_type
			profile.fatigue_type = block_fatigue_type(attacker_unit, profile, clash)
			local result = { func(self, channel_id, damage_source_id, attacker_unit_id, hit_unit_id, hit_zone_id, hit_position, attack_direction, damage_profile_id, power_level, target_index, boost_curve_multiplier, is_critical_strike, can_damage, can_stagger, hit_ragdoll_actor_id, blocking, shield_break_procced, backstab_multiplier, attacker_is_level_unit, first_hit, total_hits) }
			profile.fatigue_type = original_fatigue_type
			return unpack(result)
		end)
	end
end

return Damage
