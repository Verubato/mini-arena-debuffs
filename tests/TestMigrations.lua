-- The upgrade path runs on every login against whatever shape the profile was last saved in, so
-- a step that misfires quietly rewrites settings the player chose.

local fw = require("TestFramework")
local harness = require("AddonHarness")

local CURRENT_VERSION = 7

---Logs in against a saved-variables table at an older shape and returns what the upgrade left.
---@param saved table
---@return table
local function Upgrade(saved)
	local context = harness.Load("MiniArenaDebuffs")

	_G.MiniArenaDebuffsDB = saved

	harness.Login(context)

	return _G.MiniArenaDebuffsDB
end

fw.describe("MiniArenaDebuffs - saved variable upgrades", function()
	fw.it("clears an anchor override that only ever named the default frame", function()
		local db = Upgrade({ Version = 2, Anchor1 = "CompactArenaFrameMember1", Anchor2 = "MyArenaFrame2" })

		fw.eq(db.Anchor1, "", "the override that matched the default is gone")
		fw.eq(db.Anchor2, "MyArenaFrame2", "a real choice is left alone")
		fw.eq(db.Version, CURRENT_VERSION, "upgraded the whole way in one login")
	end)

	fw.it("renames icon padding to spacing and drops the fields that went with the old modes", function()
		local db = Upgrade({
			Version = 3,
			Icons = { Padding = { X = 5 }, Size = 48 },
			SimpleMode = { Enabled = true, Offset = { X = 10, Y = 20 } },
			Rows = 2,
		})

		fw.eq(db.Icons.Spacing, 5, "the padding the player set became the spacing")
		fw.is_nil(db.Icons.Padding, "the old key is gone")
		fw.eq(db.Icons.Size, 48, "an untouched icon setting survived")
		fw.is_nil(db.SimpleMode, "the mode table is gone")
		fw.is_nil(db.Rows, "so is the row count")
	end)

	fw.it("carries a version three profile's anchor offset, icon count, and grow direction forward", function()
		local db = Upgrade({
			Version = 3,
			IconsPerRow = 4,
			GrowDirection = "LEFT",
			SimpleMode = { Enabled = true, Offset = { X = 10, Y = 20 } },
		})

		fw.eq(db.MaxIcons, 4, "the icon count moved to its new key")
		fw.is_nil(db.IconsPerRow, "the old key is gone")
		fw.eq(db.Anchor.Offset.X, 10, "the offset the player had set carried over")
		fw.eq(db.Anchor.Offset.Y, 20, "both halves of it")
		fw.eq(db.Grow, "LEFT", "and so did the grow direction")
	end)

	fw.it("renames the grow direction and drops the anchor points, keeping the offset", function()
		local db = Upgrade({
			Version = 4,
			GrowDirection = "CENTER",
			Anchor = { Point = "TOPLEFT", RelativePoint = "TOPRIGHT", Offset = { X = 3, Y = -4 } },
		})

		fw.eq(db.Grow, "CENTER", "the direction moved to its new key")
		fw.is_nil(db.GrowDirection, "the old key is gone")
		fw.is_nil(db.Anchor.Point, "the fixed anchor point is gone")
		fw.is_nil(db.Anchor.RelativePoint, "so is its relative point")
		fw.eq(db.Anchor.Offset.X, 3, "the offset the player nudged survived")
		fw.eq(db.Anchor.Offset.Y, -4, "both halves of it")
	end)

	fw.it("folds the old pandemic border into the one glow toggle", function()
		local db = Upgrade({ Version = 5, Icons = { PandemicBorder = true } })

		fw.eq(db.Icons.PandemicGlow, true, "whichever cue the client offered carried over")
		fw.is_nil(db.Icons.PandemicBorder, "the old key is gone")
	end)

	fw.it("leaves the glow alone when it was already the chosen cue", function()
		local db = Upgrade({ Version = 5, Icons = { PandemicGlow = true, PandemicBorder = false } })

		fw.eq(db.Icons.PandemicGlow, true, "the player's own choice is not overwritten")
	end)

	fw.it("drops the desaturate option that lost its data source", function()
		-- is_nil on the final value alone would pass even without the step's own line, since
		-- CleanTable strips any key the defaults no longer carry. Watching CleanTable's own
		-- call catches the value before that blanket cleanup can take credit for the step.
		local context = harness.Load("MiniArenaDebuffs")
		local framework = context.Addon.Framework
		local originalCleanTable = framework.CleanTable
		local captured = false
		local sawBeforeClean

		function framework:CleanTable(target, template, cleanValues, recurse)
			if not captured and target.Icons then
				captured = true
				sawBeforeClean = target.Icons.PandemicDesaturate
			end
			return originalCleanTable(self, target, template, cleanValues, recurse)
		end

		_G.MiniArenaDebuffsDB = { Version = 6, Icons = { PandemicDesaturate = true, ShowStacks = false } }
		harness.Login(context)
		local db = _G.MiniArenaDebuffsDB

		fw.is_nil(sawBeforeClean, "the step cleared it before the generic cleanup ran")
		fw.is_nil(db.Icons.PandemicDesaturate, "the option is gone")
		fw.eq(db.Icons.ShowStacks, false, "a neighbouring choice is untouched")
		fw.eq(db.Version, CURRENT_VERSION, "stamped current")
	end)

	fw.it("takes a version one profile all the way and keeps the offset it held", function()
		local db = Upgrade({ Version = 1, SimpleMode = { Offset = { X = 9, Y = 9 } } })

		fw.eq(db.Version, CURRENT_VERSION, "upgraded the whole way")
		fw.is_nil(db.SimpleMode, "the version one mode table is gone")
		fw.eq(db.Anchor.Offset.X, 9, "its offset reached the anchor")
	end)

	fw.it("does not resurrect the offset of a version one mode the profile says was off", function()
		local db = Upgrade({ Version = 1, SimpleMode = { Enabled = false, Offset = { X = 9, Y = 9 } } })

		fw.eq(db.Anchor.Offset.X, 0, "the offset of a mode that was off stays behind")
	end)

	fw.it("runs the whole chain for a profile that carries no version", function()
		local db = Upgrade({ Anchor1 = "CompactArenaFrameMember1" })

		fw.eq(db.Version, CURRENT_VERSION, "stamped current")
		fw.eq(db.Anchor1, "", "the step that clears a default-named override ran")
	end)

	fw.it("carries every setting the player chose across the whole chain", function()
		local db = Upgrade({
			Version = 2,
			MaxIcons = 3,
			SortMethod = "TIME",
			SortDirection = "-",
			Anchor2 = "MyArenaFrame2",
			Icons = { Size = 48, Spacing = 4, FontScale = 1.5, ShowStacks = false, HideSwipe = true },
			SpellFilter = { Mode = "EXCLUDE", Spells = "118 6770" },
		})

		fw.eq(db.MaxIcons, 3, "icon count")
		fw.eq(db.SortMethod, "TIME", "sort method")
		fw.eq(db.SortDirection, "-", "sort direction")
		fw.eq(db.Anchor2, "MyArenaFrame2", "anchor override")
		fw.eq(db.Icons.Size, 48, "icon size")
		fw.eq(db.Icons.Spacing, 4, "icon spacing")
		fw.eq(db.Icons.FontScale, 1.5, "font scale")
		fw.eq(db.Icons.ShowStacks, false, "stacks toggle")
		fw.eq(db.Icons.HideSwipe, true, "swipe toggle")
		fw.eq(db.SpellFilter.Mode, "EXCLUDE", "filter mode")
		fw.eq(db.SpellFilter.Spells, "118 6770", "filter list")
	end)

	fw.it("leaves a profile already at the current version untouched", function()
		local db = Upgrade({ Version = CURRENT_VERSION, MaxIcons = 4, Icons = { Size = 20 } })

		fw.eq(db.Version, CURRENT_VERSION, "still current")
		fw.eq(db.MaxIcons, 4, "settings untouched")
		fw.eq(db.Icons.Size, 20, "including nested ones")
	end)

	fw.it("leaves a profile stamped ahead of this build alone", function()
		local db = Upgrade({ Version = 99, MaxIcons = 4, FutureKey = "keep" })

		fw.eq(db.Version, 99, "the stamp a newer build wrote is kept")
		fw.eq(db.MaxIcons, 4, "so are the settings beside it")
		fw.eq(db.FutureKey, "keep", "including a key this build knows nothing about")
	end)

	fw.it("leaves a profile whose version this build cannot step alone", function()
		local db = Upgrade({ Version = "9", MaxIcons = 3 })

		fw.eq(db.Version, "9", "the stamp is left as it was found")
		fw.eq(db.MaxIcons, 3, "and the settings beside it")
	end)

	fw.it("runs no step at all for a brand new profile", function()
		-- The end state is the same either way, so counting the cleanups is what shows the
		-- chain was skipped.
		local context = harness.Load("MiniArenaDebuffs")
		local framework = context.Addon.Framework
		local originalCleanTable = framework.CleanTable
		local cleans = 0

		function framework:CleanTable(target, template, cleanValues, recurse)
			cleans = cleans + 1
			return originalCleanTable(self, target, template, cleanValues, recurse)
		end

		_G.MiniArenaDebuffsDB = nil
		harness.Login(context)
		local db = _G.MiniArenaDebuffsDB

		fw.eq(cleans, 0, "nothing was cleaned")
		fw.eq(db.Version, CURRENT_VERSION, "stamped current")
	end)
end)
