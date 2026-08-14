---@type string, Addon
local _, addon = ...

---@class WoWEx
local M = {}

addon.WoWEx = M

---True when the client can drive pandemic (refresh-window) regions on aura buttons, which
---arrived after 12.1.0. Probes the C_UnitAuras functions the engine computes the window from
---rather than the button mixin, which lives in the secure environment and is not a readable
---global.
---@return boolean
function M:HasPandemicRegions()
	return C_UnitAuras ~= nil
		and C_UnitAuras.GetRefreshExtendedDuration ~= nil
		and C_UnitAuras.GetAuraBaseDuration ~= nil
end

---True while AuraButton styling is blocked: button APIs Lua-error from addon code whenever
---auras are secret, which covers combat but ALSO out-of-combat moments inside M+/encounters/
---PvP matches - so InCombatLockdown alone is not a sufficient guard.
---@return boolean
function M:IsAuraStylingRestricted()
	if InCombatLockdown() then
		return true
	end
	if C_Secrets and C_Secrets.ShouldAurasBeSecret then
		return C_Secrets.ShouldAurasBeSecret()
	end
	return false
end
