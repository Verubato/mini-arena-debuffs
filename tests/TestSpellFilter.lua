-- The spell filter is a mode and a line of text the player types, parsed into the id maps the
-- display hands to the engine.

local fw = require("TestFramework")
local Arena = require("Arena")

local function Count(map)
	local count = 0

	for _ in pairs(map) do
		count = count + 1
	end

	return count
end

fw.describe("MiniArenaDebuffs - the spell filter", function()
	local env
	local display

	---@param mode string
	---@param spells string
	local function Filter(mode, spells)
		env.Db.SpellFilter = { Mode = mode, Spells = spells }
		env.Refresh()
	end

	fw.before_each(function()
		env = Arena.Build()
		env.Blizzard(1)
		env.Refresh()
		display = env.Displays[1]
	end)

	fw.it("shows only the listed spells in include mode", function()
		Filter("INCLUDE", "118 6770")

		fw.eq(display.IncludeSpellIDs[118], true, "the first id")
		fw.eq(display.IncludeSpellIDs[6770], true, "the second")
		fw.eq(Count(display.IncludeSpellIDs), 2, "and nothing else")
		fw.is_nil(display.ExcludeSpellIDs, "nothing is excluded")
	end)

	fw.it("hides the listed spells in exclude mode", function()
		Filter("EXCLUDE", "118, 6770")

		fw.eq(display.ExcludeSpellIDs[118], true, "the first id")
		fw.eq(display.ExcludeSpellIDs[6770], true, "the second")
		fw.is_nil(display.IncludeSpellIDs, "nothing is included")
	end)

	fw.it("filters nothing with the mode off, however long the list is", function()
		Filter("OFF", "118 6770")

		fw.is_nil(display.IncludeSpellIDs, "no include map")
		fw.is_nil(display.ExcludeSpellIDs, "no exclude map")
	end)

	fw.it("filters nothing on an empty list, which would otherwise hide every debuff", function()
		Filter("INCLUDE", "")

		fw.is_nil(display.IncludeSpellIDs, "an empty include list is no filter at all")
		fw.is_nil(display.ExcludeSpellIDs, "and nothing is excluded either")
	end)

	fw.it("filters nothing on a list with no ids in it", function()
		Filter("INCLUDE", "Polymorph, Sap")

		fw.is_nil(display.IncludeSpellIDs, "words are not spell ids")
	end)

	fw.it("keeps one entry for an id the player typed twice", function()
		Filter("EXCLUDE", "118 118 118")

		fw.eq(Count(display.ExcludeSpellIDs), 1, "the same id is one entry")
		fw.eq(display.ExcludeSpellIDs[118], true, "and it is the one that was typed")
	end)

	fw.it("moves an id from one map to the other when the mode flips", function()
		Filter("INCLUDE", "118")

		fw.eq(display.IncludeSpellIDs[118], true, "included first")

		Filter("EXCLUDE", "118")

		fw.is_nil(display.IncludeSpellIDs, "no longer included")
		fw.eq(display.ExcludeSpellIDs[118], true, "excluded instead")
	end)

	fw.it("hands back the same map while the mode and the list are unchanged", function()
		Filter("INCLUDE", "118")

		local first = display.IncludeSpellIDs

		env.Refresh()

		fw.eq(display.IncludeSpellIDs, first, "an unchanged refresh re-filters nothing")

		Filter("INCLUDE", "118 6770")

		fw.neq(display.IncludeSpellIDs, first, "a changed list is a real re-filter")
	end)
end)
