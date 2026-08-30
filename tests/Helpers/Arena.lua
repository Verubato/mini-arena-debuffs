-- Builds a mocked client with arena frames to anchor to. Everything the addon computes lands on
-- an AuraContainerDisplay it never hands back, so New is wrapped to collect them.

local harness = require("AddonHarness")
local WowMock = require("WowMock")

local M = {}

---@return table env
function M.Build()
	local env = { Displays = {} }

	-- Saved variables outlive an Install, so another file's profile would otherwise be the one
	-- under test here.
	_G.MiniArenaDebuffsDB = nil

	env.Context = harness.Load("MiniArenaDebuffs")
	harness.Login(env.Context)

	env.Addon = env.Context.Addon
	env.Db = _G.MiniArenaDebuffsDB

	local displayClass = env.Addon.AuraContainerDisplay
	local New = displayClass.New

	displayClass.New = function(class, ...)
		local instance = New(class, ...)
		env.Displays[#env.Displays + 1] = instance

		return instance
	end

	---Creates a frame the addon can anchor to, carrying the unit it stands for.
	---@param name string
	---@param index number
	---@return table
	function env.Frame(name, index)
		local frame = _G.CreateFrame("Frame", name, _G.UIParent)
		frame:SetAttribute("unit", "arena" .. index)
		WowMock.State.Units["arena" .. index] = true

		return frame
	end

	---The Blizzard arena frames, which are what the addon anchors to by default.
	---@param count number
	function env.Blizzard(count)
		for i = 1, count do
			env.Frame("CompactArenaFrameMember" .. i, i)
		end
	end

	function env.Refresh()
		env.Addon:Refresh()
		WowMock.RunTimers()
	end

	---What the given display's frame is pinned to.
	---@param display table
	---@return table? relativeTo
	function env.AnchoredTo(display)
		local _, relativeTo = display.Frame:GetPoint(1)

		return relativeTo
	end

	---Everything the addon printed to chat, as one string.
	---@return string
	function env.Chat()
		return table.concat(WowMock.State.Prints, "\n")
	end

	return env
end

return M
