-- Masque on both icon paths: the 12.1 aura buttons the engine creates inside its own callback,
-- and the slot icons test mode draws. Both share one group, so both have to hand Masque the same
-- regions and ask for the same skin, or a match and its preview come out looking different.

local fw = require("TestFramework")
local harness = require("AddonHarness")
local WowMock = require("WowMock")

---Registers a stub Masque, then loads the addon against it. Loading has to come second: each
---file captures the library at file scope, the way it would with the real one installed.
---@param log string[] call log the group appends to, for the calls whose order matters
---@return table group the sub-group the addon asks for, recording what it was handed
---@return table context the loaded addon
local function LoadWithMasque(log)
	WowMock.Install()
	dofile("src/Libs/LibStub/LibStub.lua")

	local group = { Buttons = {}, ReSkins = {} }

	function group:AddButton(button, regions, buttonType, strict)
		log[#log + 1] = "masque"
		self.Buttons[#self.Buttons + 1] = {
			Button = button,
			Regions = regions,
			Type = buttonType,
			Strict = strict,
		}
	end

	function group:ReSkin(button)
		-- false rather than nil for a whole-group re-skin, so the record keeps its length.
		self.ReSkins[#self.ReSkins + 1] = button or false
	end

	local masque = LibStub:NewLibrary("Masque", 90000)

	function masque:Group(addon, subGroup)
		group.Addon = addon
		group.SubGroup = subGroup

		return group
	end

	local context = harness.Load("MiniArenaDebuffs", { install = false })
	harness.Login(context)

	return group, context
end

---A stand-in for the AuraButton the engine hands to initializeFrame. Only the methods the display
---calls on it, plus a log of the calls whose order matters.
---@param log string[]
---@return table
local function CreateAuraButton(log)
	local button = CreateFrame("Button", nil, UIParent)

	function button:SetIcon() end

	function button:SetDurationCooldown() end

	function button:SetApplicationCount() end

	function button:AddPandemicRegion()
		log[#log + 1] = "pandemic"
	end

	return button
end

---@return table? frame the addon's aura container
local function FindAuraContainer()
	for _, frame in ipairs(WowMock.Frames) do
		if frame.HasAuraGroup and frame:HasAuraGroup("debuffs") then
			return frame
		end
	end

	return nil
end

---Asserts a skinned button carries everything a skin needs to draw an aura icon.
---@param skinned table
---@param label string
local function CheckAuraRegions(skinned, label)
	fw.eq(skinned.Type, "Aura", label .. " button type")
	fw.eq(skinned.Strict, true, label .. " strict region matching")
	fw.not_nil(skinned.Regions.Icon, label .. " icon region")
	fw.not_nil(skinned.Regions.Cooldown, label .. " cooldown region")
	fw.not_nil(skinned.Regions.Count, label .. " count region")
end

fw.describe("MiniArenaDebuffs - Masque", function()
	fw.it("hands each aura button to Masque before its pandemic region", function()
		local log = {}
		local group, context = LoadWithMasque(log)

		-- The pandemic reveal is what makes a button's size secret, so the ordering under test
		-- only exists on a client that has it.
		C_UnitAuras.GetRefreshExtendedDuration = function() end
		C_UnitAuras.GetAuraBaseDuration = function() end

		local anchor = CreateFrame("Frame", "CompactArenaFrameMember1", UIParent)
		anchor:SetAttribute("unit", "arena1")
		WowMock.State.Units.arena1 = true

		context.Addon:Refresh()
		WowMock.RunTimers()

		fw.eq(group.Addon, "MiniArenaDebuffs", "Masque addon name")
		fw.eq(group.SubGroup, "MiniArenaDebuffs", "Masque sub-group name")

		local container = FindAuraContainer()

		fw.not_nil(container, "the addon created no aura container")

		-- Declaring the group already ran initializeFrame over the button the container built.
		-- The order things are registered in is what this case is about, so the record starts
		-- clean and the callback is driven again with a button that reports what it was asked.
		for index = #group.Buttons, 1, -1 do
			group.Buttons[index] = nil
		end

		for index = #log, 1, -1 do
			log[index] = nil
		end

		local button = CreateAuraButton(log)

		container:GetAuraGroup("debuffs").Options.initializeFrame(button)

		fw.eq(#group.Buttons, 1, "buttons handed to Masque")
		fw.eq(group.Buttons[1].Button, button, "the skinned button")
		CheckAuraRegions(group.Buttons[1], "aura")
		-- Masque reads the button's size, which registering the pandemic region takes away.
		fw.eq(table.concat(log, ","), "masque,pandemic", "skin and pandemic registration order")
	end)

	fw.it("skins the test mode icons the same way", function()
		local log = {}
		local group, context = LoadWithMasque(log)

		context.Addon:ToggleTest()
		WowMock.RunTimers()

		fw.truthy(#group.Buttons > 0, "test mode handed Masque no buttons")

		for index, skinned in ipairs(group.Buttons) do
			CheckAuraRegions(skinned, "test slot " .. index)
		end

		-- Named buttons only: the group is shared with the aura displays, and a whole-group
		-- re-skin would reach into engine-owned buttons the addon must not touch here.
		fw.truthy(#group.ReSkins > 0, "the test icons were never re-skinned")

		for index, button in ipairs(group.ReSkins) do
			fw.neq(button, false, "re-skin " .. index .. " asked for the whole group")
		end
	end)
end)
