local Damage = {}

function Damage.hook(mod, settings)
	-- ActionSweep filters allies before it reaches the normal block/damage path.
	-- Temporarily expose allied player units as enemy units for this call only.
	if rawget(_G, "ActionSweep") then
		mod:hook(ActionSweep, "_do_overlap", function(func, self, dt, t, unit, owner_unit, current_action, physics_world, is_within_damage_window, current_position, current_rotation)
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
	end

	-- This is intentionally separate from friendly_fire_multiplier. It applies
	-- only to player-v-player damage and remains live when the slider changes.
	if rawget(_G, "DamageUtils") then
		mod:hook(DamageUtils, "calculate_damage", function(func, damage_output, target_unit, attacker_unit, ...)
			local value, secondary = func(damage_output, target_unit, attacker_unit, ...)
			-- A sweep hitting another active melee action is a weapon clash. The
			-- damage calculation is the last common point for local prediction and
			-- the server, so cancelling here keeps both sides from losing health.
			local attacker_weapon = attacker_unit and ScriptUnit.has_extension(attacker_unit, "weapon_system") and ScriptUnit.extension(attacker_unit, "weapon_system")
			local target_weapon = target_unit and ScriptUnit.has_extension(target_unit, "weapon_system") and ScriptUnit.extension(target_unit, "weapon_system")
			local attacker_kind = attacker_weapon and attacker_weapon.current_action_settings and attacker_weapon.current_action_settings.kind
			local target_kind = target_weapon and target_weapon.current_action_settings and target_weapon.current_action_settings.kind
			local pvp_units = target_unit and attacker_unit and DamageUtils.is_player_unit(target_unit) and DamageUtils.is_player_unit(attacker_unit)
			if pvp_units and (attacker_kind == "sweep" or attacker_kind == "melee_start") and (target_kind == "sweep" or target_kind == "melee_start") then
				return 0, secondary
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
