local Clash = {}

-- Dimensions of the native wpn_damage geometry, expressed as half extents.
-- The remote husk has the visual weapon unit but not the local damage unit.
local DEFAULT_HALF_EXTENTS = Vector3(0.06, 0.06, 0.75)

local function axes(rotation)
	return Quaternion.right(rotation), Quaternion.forward(rotation), Quaternion.up(rotation)
end

local function dot(a, b)
	return a.x * b.x + a.y * b.y + a.z * b.z
end

local function cross(a, b)
	return Vector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
end

local function length(v)
	return math.sqrt(dot(v, v))
end

local function overlap(a, b, extents)
	local aa1, aa2, aa3 = axes(a.rotation)
	local bb1, bb2, bb3 = axes(b.rotation)
	local aa = { aa1, aa2, aa3 }
	local bb = { bb1, bb2, bb3 }
	local center_delta = b.position - a.position
	local ea = extents
	local eb = extents

	local function separated(axis)
		local axis_length = length(axis)
		if axis_length < 0.000001 then
			return false
		end
		axis = axis / axis_length
		local ra = math.abs(dot(axis, aa[1])) * ea.x + math.abs(dot(axis, aa[2])) * ea.y + math.abs(dot(axis, aa[3])) * ea.z
		local rb = math.abs(dot(axis, bb[1])) * eb.x + math.abs(dot(axis, bb[2])) * eb.y + math.abs(dot(axis, bb[3])) * eb.z
		return math.abs(dot(center_delta, axis)) > ra + rb
	end

	for i = 1, 3 do
		if separated(aa[i]) or separated(bb[i]) then
			return false
		end
	end
	for i = 1, 3 do
		for j = 1, 3 do
			if separated(cross(aa[i], bb[j])) then
				return false
			end
		end
	end
	return true
end

local function class_from_profile(profile)
	local charge = profile and profile.charge_value
	return charge == "light_attack" and "light" or charge == "heavy_attack" and "heavy" or nil
end

local function current_attack_class(unit)
	local inventory = unit and ScriptUnit.has_extension(unit, "inventory_system") and ScriptUnit.extension(unit, "inventory_system")
	local weapon = inventory and (inventory:get_weapon_unit() or inventory:get_weapon_unit_3p())
	local extension = weapon and ScriptUnit.has_extension(weapon, "weapon_system") and ScriptUnit.extension(weapon, "weapon_system")
	local tracked = extension and extension._pvp_attack_class
	if tracked == "light_attack" then
		return "light"
	elseif tracked == "heavy_attack" then
		return "heavy"
	end
	local action = extension and extension.get_current_action_settings and extension:get_current_action_settings()
	local profile_name = action and (action.damage_profile or action.damage_profile_inner or action.damage_profile_outer)
	local profile = type(profile_name) == "table" and profile_name or profile_name and DamageProfileTemplates[profile_name]
	if action and (action.kind == "sweep" or action.kind == "melee_start") then
		return class_from_profile(profile)
	end
	return nil
end

local function weapon_class(unit)
	local inventory = unit and ScriptUnit.has_extension(unit, "inventory_system") and ScriptUnit.extension(unit, "inventory_system")
	local slot = inventory and inventory:get_slot_data("slot_melee")
	local template = inventory and inventory:get_item_template(slot)
	local buff_type = template and template.buff_type
	return buff_type == "MELEE_1H" and buff_type or buff_type == "MELEE_2H" and buff_type or nil
end

function Clash.weapon_class(unit)
	return weapon_class(unit)
end

function Clash.check(tracker, attacker_unit, target_unit, damage_profile)
	if not attacker_unit or not target_unit or attacker_unit == target_unit then
		return nil
	end
	if not DamageUtils.is_player_unit(attacker_unit) or not DamageUtils.is_player_unit(target_unit) then
		return nil
	end
	if not tracker then
		return { available = false, reason = "tracker_unavailable" }
	end
	local attacker_class = class_from_profile(damage_profile)
	local target_class = current_attack_class(target_unit)
	if not attacker_class or not weapon_class(attacker_unit) or not weapon_class(target_unit) then
		return { available = false, reason = "target_attack_state_unavailable" }
	end
	-- PvP light attacks are deliberately clash attacks whenever they hit a
	-- Hero Player.  This is evaluated only after the native sweep has produced
	-- the actual player hit; it does not create a per-frame collision test.
	if attacker_class == "light" then
		return { available = true, clash = true, attacker_blocked = true, target_blocked = target_class == "light" }
	end
	if not target_class then
		return { available = false, reason = "target_attack_state_unavailable" }
	end
	local a = tracker.pose(attacker_unit)
	local b = tracker.pose(target_unit)
	if not a or not b then
		return { available = false, reason = "weapon_pose_unavailable" }
	end
	if not overlap(a, b, DEFAULT_HALF_EXTENTS) then
		return { available = true, clash = false }
	end
	if attacker_class == target_class then
		return { available = true, clash = true, attacker_blocked = true, target_blocked = true }
	end
	if attacker_class == "light" and target_class == "heavy" then
		return { available = true, clash = true, attacker_blocked = true, target_blocked = false }
	end
	return { available = true, clash = true, attacker_blocked = false, target_blocked = true }
end

return Clash
