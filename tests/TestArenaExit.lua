-- Leaving an arena has to take the icons with it. The arena frame globals stick around after
-- the match, so an anchor still being there is not proof there is an opponent to draw for.

local fw = require("TestFramework")
local harness = require("AddonHarness")
local WowMock = require("WowMock")

local arenaSize = 3

---Containers the addon has on screen, found by name so both the 12.1 aura-container displays
---and the legacy icon containers count.
---@return number
local function ShownContainers()
	local shown = 0

	for _, frame in ipairs(WowMock.Frames) do
		local name = frame.GetName and frame:GetName()

		if name and name:find("MiniArenaDebuffs", 1, true) and name:find("Container", 1, true) then
			if frame:IsShown() then
				shown = shown + 1
			end
		end
	end

	return shown
end

local function EnterArena()
	for i = 1, arenaSize do
		local unit = "arena" .. i
		local frame = CreateFrame("Frame", "CompactArenaFrameMember" .. i, UIParent)

		frame:SetAttribute("unit", unit)
		WowMock.State.Units[unit] = true
	end
end

---The frames outlive the match; only the units go away.
local function LeaveArena()
	for i = 1, arenaSize do
		WowMock.State.Units["arena" .. i] = nil
	end
end

fw.describe("MiniArenaDebuffs - arena exit", function()
	fw.it("hides the icons once the arena units are gone", function()
		local context = harness.Load("MiniArenaDebuffs")
		harness.Login(context)

		EnterArena()
		context.Addon:Refresh()
		WowMock.RunTimers()

		fw.eq(ShownContainers(), arenaSize, "containers shown in the arena")

		LeaveArena()
		WowMock.FireEvent("PLAYER_ENTERING_WORLD", false, false)
		WowMock.RunTimers()

		fw.eq(ShownContainers(), 0, "containers still shown after leaving the arena")
	end)
end)
