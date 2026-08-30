-- Loads the whole addon into a mocked client and drives it through login.
-- The shared body lives in build/Lua/SmokeTest.lua.

local fw = require("TestFramework")
local smoke = require("SmokeTest")
local WowMock = require("WowMock")

---The section rule is built by the framework and never handed back to the addon, so a test
---finds it the way a player sees it, by its label.
---@param text string
---@return number
local function CountDividers(text)
	local count = 0

	for _, frame in ipairs(WowMock.Frames) do
		if frame.Label and frame.Label.GetText and frame.Label:GetText() == text then
			count = count + 1
		end
	end

	return count
end

---The framework owns both buttons, so a test reaches them by their labels.
---@param label string
---@return table?
local function FindButton(label)
	for _, frame in ipairs(WowMock.Frames) do
		if frame.GetText and frame:GetText() == label and frame.Click then
			return frame
		end
	end
end

smoke.Run("MiniArenaDebuffs", {
	extra = function(context)
		fw.eq(context.Addon.Framework.CustomStyling, true, "custom styling on")
		fw.eq(context.Addon.Framework.CustomStylingOverrides.Button, false, "stock buttons")
		-- Main panel, Position & Sort, Spell Filter and Custom Anchors each get one.
		fw.eq(CountDividers("SETTINGS"), 4, "a settings section rule under each panel's header")

		local testBtn = FindButton("Test")
		local resetBtn = FindButton("Reset to Defaults")

		fw.not_nil(testBtn, "the test button")
		fw.not_nil(resetBtn, "the reset button")

		local point, relativeTo, relativePoint = testBtn:GetPoint()

		fw.eq(point, "RIGHT", "the test button is anchored by its own right edge")
		fw.eq(relativeTo, resetBtn, "the test button hangs off the reset button")
		fw.eq(relativePoint, "LEFT", "the test button sits left of the reset button")
	end,
})
