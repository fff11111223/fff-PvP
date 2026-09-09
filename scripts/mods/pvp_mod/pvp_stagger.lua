local Stagger = {}
local push_stagger_until = setmetatable({}, { __mode = "k" })

local function enabled(mod)
	return mod:get("pvp_enabled") ~= false
end

-- Current VT2 status extensions do not all expose get_in_ghost_mode(), while
-- DamageUtils.stagger_player still calls it unconditionally. Preserve the
-- native stagger-value write and network flag, but guard that optional API.
local function write_native_stagger(unit, breed, stagger_direction, stagger_length, stagger_type, stagger_duration, stagger_animation_scale, t, stagger_value, always_stagger, is_push, should_play_push_sound)
	local status = ScriptUnit.has_extension(unit, "status_system") and ScriptUnit.extension(unit, "status_system")
	if not status or stagger_type <= 0 then
		return
	end
	local breed_action = status:breed_action()
	if breed_action and breed_action.stagger_prohibited then
		return
	end
	if status.get_in_ghost_mode and status:get_in_ghost_mode() then
		return
	end

	stagger_value = stagger_value or 1
	stagger_animation_scale = stagger_animation_scale or 1
	local difficulty_modifier = Managers.state.difficulty:get_difficulty_settings().stagger_modifier
	-- Player status does not expose the AI-only accumulated stagger state.
	-- Pass the value calculated for this hit directly through the native player
	-- stagger setter; do not create an AI-style counter for PvP players.
	status:set_stagger_values(stagger_type, stagger_direction, stagger_length, stagger_value, stagger_duration * difficulty_modifier, stagger_animation_scale, always_stagger, true)

	if should_play_push_sound then
		local sound_event = breed.push_sound_event or "Play_generic_pushed_impact_small"
		Managers.state.entity:system("audio_system"):play_audio_unit_event(sound_event, unit)
	end
end

-- Follow the native player stagger route used by AI pushes. stagger_player()
-- writes status_extension:set_stagger_values(..., true), selecting the normal
-- player stagger state and replicating it to every client.
local function apply_native_push_stagger(target_unit, attacker_unit, minimum_duration)
	if not target_unit or not attacker_unit or not HEALTH_ALIVE[target_unit] or not HEALTH_ALIVE[attacker_unit] then
		return
	end
	if not Managers.player.is_server or not DamageUtils.is_player_unit(target_unit) then
		return
	end

	local blackboard = BLACKBOARDS and BLACKBOARDS[target_unit]
	local breed = blackboard and blackboard.breed
	local profile = DamageProfileTemplates and DamageProfileTemplates.medium_push
	if not breed or not profile then
		return
	end

	local power_level = 1
	local career = ScriptUnit.has_extension(attacker_unit, "career_system") and ScriptUnit.extension(attacker_unit, "career_system")
	if career then
		power_level = career:get_career_power_level()
	end

	local stagger_type, stagger_duration, stagger_length, stagger_value = DamageUtils.calculate_stagger_player(ImpactTypeOutput, target_unit, attacker_unit, "torso", power_level, nil, false, profile, 1, false, "damage_push")
	if not stagger_type or stagger_type <= 0 then
		return
	end

	local target_position = POSITION_LOOKUP[target_unit] or Unit.world_position(target_unit, 0)
	local attacker_position = POSITION_LOOKUP[attacker_unit] or Unit.world_position(attacker_unit, 0)
	local direction = Vector3.normalize(target_position - attacker_position)
	write_native_stagger(target_unit, breed, direction, stagger_length, stagger_type, math.max(stagger_duration, minimum_duration or 0), 1, Managers.time:time("game"), stagger_value, true, true, true)
end

local function player_is_attacking(unit)
	local inventory = unit and ScriptUnit.has_extension(unit, "inventory_system") and ScriptUnit.extension(unit, "inventory_system")
	local weapon_unit = inventory and (inventory.get_weapon_unit and inventory:get_weapon_unit() or inventory.get_weapon_unit_3p and inventory:get_weapon_unit_3p())
	local weapon_extension = weapon_unit and ScriptUnit.has_extension(weapon_unit, "weapon_system") and ScriptUnit.extension(weapon_unit, "weapon_system")
	local action = weapon_extension and weapon_extension.get_current_action_settings and weapon_extension:get_current_action_settings()

	return action and (action.kind == "sweep" or action.kind == "melee_start") or false
end

function Stagger.apply_push(target_unit, attacker_unit)
	if not target_unit or not attacker_unit or not DamageUtils.is_player_unit(target_unit) or not DamageUtils.is_player_unit(attacker_unit) then
		return
	end
	if player_is_attacking(target_unit) then
		return
	end

	local now = Managers.time:time("game")
	if push_stagger_until[target_unit] and now < push_stagger_until[target_unit] then
		return
	end

	push_stagger_until[target_unit] = now + 1
	apply_native_push_stagger(target_unit, attacker_unit, 1)
end

function Stagger.update(mod)
	-- Native player stagger owns its own expiry and cleanup.
end

function Stagger.clear(unit)
	-- Compatibility no-op for the damage hook. Native stagger must finish via
	-- the status extension, rather than manual overpowered-state cleanup.
end

function Stagger.hook(mod)
	if rawget(_G, "DamageUtils") then
		mod:hook(DamageUtils, "stagger_player", function(func, unit, breed, stagger_direction, stagger_length, stagger_type, stagger_duration, stagger_animation_scale, t, stagger_value, always_stagger, is_push, should_play_push_sound)
			if not enabled(mod) or not DamageUtils.is_player_unit(unit) then
				return func(unit, breed, stagger_direction, stagger_length, stagger_type, stagger_duration, stagger_animation_scale, t, stagger_value, always_stagger, is_push, should_play_push_sound)
			end
			return write_native_stagger(unit, breed, stagger_direction, stagger_length, stagger_type, stagger_duration, stagger_animation_scale, t, stagger_value, always_stagger, is_push, should_play_push_sound)
		end)
	end

	if rawget(_G, "GenericStatusExtension") then
		mod:hook(GenericStatusExtension, "blocked_attack", function(func, self, fatigue_type, attacking_unit, fatigue_multiplier, improved_block, attack_direction)
			if not enabled(mod) then
				return func(self, fatigue_type, attacking_unit, fatigue_multiplier, improved_block, attack_direction)
			end
			local now = Managers.time:time("game")
			local was_timed_block = self.timed_block and now < self.timed_block
			local result = { func(self, fatigue_type, attacking_unit, fatigue_multiplier, improved_block, attack_direction) }
			if was_timed_block and attacking_unit and DamageUtils.is_player_unit(attacking_unit) and self.unit then
				apply_native_push_stagger(attacking_unit, self.unit, 3)
			end
			return unpack(result)
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
