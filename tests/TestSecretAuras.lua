-- Aura button APIs Lua-error from addon code whenever the client has made auras secret, which
-- happens out of combat too, so styling has to wait rather than be attempted and caught.

local fw = require("TestFramework")
local Arena = require("Arena")
local WowMock = require("WowMock")

fw.describe("MiniArenaDebuffs - when styling is blocked", function()
	local env

	fw.before_each(function()
		env = Arena.Build()
	end)

	fw.it("is free to style when the client is neither in combat nor keeping auras secret", function()
		fw.falsy(env.Addon.WoWEx:IsAuraStylingRestricted(), "nothing is in the way")
	end)

	fw.it("is blocked in combat", function()
		WowMock.State.InCombat = true

		fw.truthy(env.Addon.WoWEx:IsAuraStylingRestricted(), "combat blocks it")
	end)

	fw.it("is blocked out of combat while the client is keeping auras secret", function()
		_G.C_Secrets.ShouldAurasBeSecret = function()
			return true
		end

		fw.falsy(_G.InCombatLockdown(), "out of combat, so combat is not what blocks this")
		fw.truthy(env.Addon.WoWEx:IsAuraStylingRestricted(), "the secrecy alone blocks it")
	end)

	fw.it("is free to style on a client with no secrets api at all", function()
		_G.C_Secrets = nil

		fw.falsy(env.Addon.WoWEx:IsAuraStylingRestricted(), "nothing to ask, nothing to block it")
	end)

	fw.it("holds a restyle back while auras are secret, and settles it when they are not", function()
		env.Blizzard(1)
		env.Refresh()

		local display = env.Displays[1]

		fw.falsy(display.RestylePending, "nothing waiting to begin with")

		_G.C_Secrets.ShouldAurasBeSecret = function()
			return true
		end

		env.Db.Icons.Size = 48
		env.Refresh()

		fw.eq(display.Size, 48, "the new size was stored")
		fw.truthy(display.RestylePending, "but the buttons are still waiting for it")

		_G.C_Secrets.ShouldAurasBeSecret = function()
			return false
		end

		display:RestyleButtons()

		fw.falsy(display.RestylePending, "settled once the client let go of the auras")
	end)
end)
