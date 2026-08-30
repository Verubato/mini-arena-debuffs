-- Which frame each display hangs off. The player can name one, several arena addons provide
-- their own, and Blizzard's own frames are the fallback.

local fw = require("TestFramework")
local Arena = require("Arena")

fw.describe("MiniArenaDebuffs - anchor resolution", function()
	local env

	fw.before_each(function()
		env = Arena.Build()
	end)

	fw.it("hangs off the Blizzard arena frame when the player has named nothing", function()
		env.Blizzard(1)
		env.Refresh()

		fw.eq(env.AnchoredTo(env.Displays[1]), _G.CompactArenaFrameMember1, "the default frame")
	end)

	fw.it("prefers the frame the player named over the default", function()
		env.Blizzard(1)

		local chosen = env.Frame("MyArenaFrame1", 1)

		env.Db.Anchor1 = "MyArenaFrame1"
		env.Refresh()

		fw.eq(env.AnchoredTo(env.Displays[1]), chosen, "the override won")
	end)

	fw.it("falls back to the default and says so when the named frame is not there", function()
		env.Blizzard(1)

		env.Db.Anchor1 = "NoSuchFrame"
		env.Refresh()

		fw.eq(env.AnchoredTo(env.Displays[1]), _G.CompactArenaFrameMember1, "fell back to the default")
		fw.truthy(env.Chat():find("NoSuchFrame", 1, true) ~= nil, "the bad anchor was named in chat")
	end)

	fw.it("prefers another arena addon's frames to Blizzard's", function()
		env.Blizzard(1)

		local sarena = env.Frame("sArenaEnemyFrame1", 1)

		env.Refresh()

		fw.eq(env.AnchoredTo(env.Displays[1]), sarena, "the other addon's frame won")
	end)

	-- Blizzard's frames are hidden while another arena addon is driving them, so anchoring to one
	-- would put the icons somewhere the player cannot see.
	fw.it("stops at the slots that other addon has, rather than mixing in Blizzard's", function()
		env.Blizzard(3)
		env.Frame("sArenaEnemyFrame1", 1)
		env.Refresh()

		fw.eq(#env.Displays, 1, "only the one slot that other addon provides")
	end)

	fw.it("builds one display per arena slot", function()
		env.Blizzard(3)
		env.Refresh()

		fw.eq(#env.Displays, 3, "one for each frame")

		for i = 1, 3 do
			fw.eq(env.AnchoredTo(env.Displays[i]), _G["CompactArenaFrameMember" .. i], "slot " .. i)
		end
	end)
end)
