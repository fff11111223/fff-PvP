local settings = {
	is_enabled = function(mod)
		return mod:get("pvp_enabled") ~= false
	end,

	get_damage_multiplier = function(mod)
		local value = mod:get("pvp_damage") or 25
		return math.clamp(tonumber(value) or 25, 1, 200) / 100
	end,
}

return settings
