---@type string, Addon
local _, addon = ...

---@class WoWEx
local M = {}

addon.WoWEx = M

-- 12.1 removes addon access to aura data (UnitAura APIs return secrets/nil) and replaces it
-- with the AuraContainer system. True when running on a 12.1+ client, where aura display must
-- go through AuraContainers.
-- TEMPORARY dual-path support: remove the 12.0 path once 12.1 is live everywhere.
local interfaceVersion = select(4, GetBuildInfo())
M.IsAuraContainerEra = interfaceVersion >= 120100

---@return boolean
function M:UseAuraContainers()
	return M.IsAuraContainerEra
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
