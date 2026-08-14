-- The parts of an aura button's look the addon drives itself: which colour curve the countdown
-- text carries, and whether the icon art is cropped.

local fw = require("TestFramework")
local harness = require("AddonHarness")
local WowMock = require("WowMock")

---The client APIs the display probes before it will bind countdown text. The curve and enum
---halves the mock already has; these two it does not.
local function InstallCountdownText()
	_G.C_AuraContainerUtil = {
		ProcessCustomAuraButtonDurationTextOptions = function() end,
	}
	_G.C_StringUtil = {
		CreateNumericRuleFormatter = function()
			return { AddBreakpoint = function() end }
		end,
	}
end

---A stand-in for the AuraButton the engine hands to initializeFrame, recording the duration-text
---binding and the crop its icon was given.
---@return table
local function CreateAuraButton()
	local button = CreateFrame("Button", nil, UIParent)
	local createTexture = button.CreateTexture

	function button:CreateTexture(...)
		local texture = createTexture(self, ...)
		local setTexCoord = texture.SetTexCoord

		texture.SetTexCoord = function(target, left, right, top, bottom)
			target.Crop = left

			return setTexCoord(target, left, right, top, bottom)
		end

		-- The icon is the first texture the display builds.
		self.Icon = self.Icon or texture

		return texture
	end

	function button:SetIcon() end

	function button:SetDurationCooldown() end

	function button:SetApplicationCount() end

	function button:SetDurationText(_, options)
		self.DurationTextOptions = options
	end

	return button
end

---The colour curve currently bound to the button's countdown, or nil when none is.
---@param button table
---@return table?
local function BoundCurve(button)
	local options = button.DurationTextOptions

	return options and options.textColor and options.textColor.curve or nil
end

---Loads the addon into an arena with one opponent and returns the aura group's initializeFrame.
---@return table context, function initializeFrame, table db
local function LoadInArena()
	WowMock.Install()
	InstallCountdownText()

	-- Already installed above, and re-installing would wipe the stubs with it.
	local context = harness.Load("MiniArenaDebuffs", { install = false })
	harness.Login(context)

	local anchor = CreateFrame("Frame", "CompactArenaFrameMember1", UIParent)
	anchor:SetAttribute("unit", "arena1")
	WowMock.State.Units.arena1 = true

	local db = _G.MiniArenaDebuffsDB

	context.Addon:Refresh()
	WowMock.RunTimers()

	for _, frame in ipairs(WowMock.Frames) do
		if frame.HasAuraGroup and frame:HasAuraGroup("debuffs") then
			return context, frame:GetAuraGroup("debuffs").Options.initializeFrame, db
		end
	end

	error("the addon created no aura container")
end

fw.describe("MiniArenaDebuffs - icon style", function()
	fw.it("binds the countdown colour only while the text is the countdown", function()
		local context, initializeFrame, db = LoadInArena()

		db.Icons.ColorCountdown = true
		context.Addon:Refresh()

		local button = CreateAuraButton()
		initializeFrame(button)

		local ramp = BoundCurve(button)

		fw.not_nil(ramp, "colouring by time bound no curve")

		-- Off with the fractions still on: the fontstring is the countdown, so it has to be bound
		-- to something. Leaving the colour out would keep the ramp the engine is holding.
		db.Icons.ColorCountdown = false
		db.Icons.ShowMilliseconds = true
		context.Addon:Refresh()

		local plain = BoundCurve(button)

		fw.not_nil(plain, "the countdown lost its colour binding")
		fw.neq(plain, ramp, "the countdown kept the colour-by-time curve")

		-- Numbers off: the cooldown draws nothing and neither should the stand-in, which a bound
		-- colour would put back on screen.
		db.Icons.ShowMilliseconds = false
		db.Icons.HideNumbers = true
		db.Icons.ColorCountdown = true
		context.Addon:Refresh()

		fw.is_nil(BoundCurve(button), "a hidden countdown was still given a colour")
	end)

	fw.it("crops the icon art unless Zoom Icons is off", function()
		local context, initializeFrame, db = LoadInArena()

		local button = CreateAuraButton()
		initializeFrame(button)

		fw.truthy((button.Icon.Crop or 0) > 0, "the icon was not cropped by default")

		db.Icons.Zoom = false
		context.Addon:Refresh()

		fw.eq(button.Icon.Crop, 0, "turning Zoom Icons off left the icon cropped")
	end)
end)
