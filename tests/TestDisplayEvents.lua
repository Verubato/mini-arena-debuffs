-- Two events the addon never asked for but has to survive: combat starting under a preview, and
-- Edit Mode force-feeding every aura container placeholder auras.

local fw = require("TestFramework")
local Arena = require("Arena")
local WowMock = require("WowMock")

fw.describe("MiniArenaDebuffs - combat and the preview", function()
	local env

	fw.before_each(function()
		env = Arena.Build()
	end)

	fw.it("takes the preview down when combat starts", function()
		env.Addon:ToggleTest()
		WowMock.RunTimers()

		local testFrame = _G.MiniArenaDebuffsTestFrame1

		fw.not_nil(testFrame, "the preview built its stand-in arena frames")
		fw.truthy(testFrame:IsShown(), "shown while the preview runs")

		WowMock.FireEvent("PLAYER_REGEN_DISABLED")

		fw.falsy(testFrame:IsShown(), "combat took the preview down")
	end)

	fw.it("puts the real displays back when combat ends the preview", function()
		env.Blizzard(1)
		env.Refresh()

		local display = env.Displays[1]

		env.Addon:ToggleTest()
		WowMock.RunTimers()

		fw.falsy(display:IsShown(), "the real display stood down for the preview")

		WowMock.FireEvent("PLAYER_REGEN_DISABLED")

		fw.truthy(display:IsShown(), "and came back with combat")
	end)
end)

fw.describe("MiniArenaDebuffs - the Edit Mode data provider", function()
	local env
	local display

	fw.before_each(function()
		env = Arena.Build()
		env.Blizzard(1)
		env.Refresh()
		display = env.Displays[1]
	end)

	fw.it("hides the display while Edit Mode feeds it placeholder auras", function()
		fw.truthy(display.Frame:IsShown(), "on screen before Edit Mode opens")

		WowMock.FireEvent("AURA_DATA_PROVIDER_SWITCH", false)

		fw.falsy(display.Frame:IsShown(), "off screen while the placeholders are being fed")
		fw.truthy(display:IsShown(), "though the addon still wants it shown")
	end)

	fw.it("puts it back when the real aura source returns", function()
		WowMock.FireEvent("AURA_DATA_PROVIDER_SWITCH", false)
		WowMock.FireEvent("AURA_DATA_PROVIDER_SWITCH", true)

		fw.truthy(display.Frame:IsShown(), "back on screen")
	end)

	fw.it("keeps a display the addon had hidden hidden through the whole switch", function()
		display:Hide()

		WowMock.FireEvent("AURA_DATA_PROVIDER_SWITCH", false)
		WowMock.FireEvent("AURA_DATA_PROVIDER_SWITCH", true)

		fw.falsy(display.Frame:IsShown(), "Edit Mode leaving does not show what the addon parked")
	end)
end)
