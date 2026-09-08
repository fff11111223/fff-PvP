local Clash = {}

function Clash.hook(mod)
	-- The native hit path remains authoritative. This marker is consumed by
	-- optional weapon templates that provide a clash animation, while keeping
	-- unsupported builds harmless.
	if rawget(_G, "ActionSweep") then
		mod:hook_safe(ActionSweep, "client_owner_start_action", function(self)
			self.pvp_weapon_clash_enabled = true
		end)
	end
end

return Clash
