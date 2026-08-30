-- Every icon setting reaches the engine through one style table, so a toggle that never lands
-- there is a toggle that does nothing.

local fw = require("TestFramework")
local Arena = require("Arena")

fw.describe("MiniArenaDebuffs - the display style", function()
	local env

	---@return table style
	local function Style()
		env.Blizzard(1)
		env.Refresh()

		return env.Displays[1].Style
	end

	fw.before_each(function()
		env = Arena.Build()
	end)

	fw.it("carries every icon toggle through to the style", function()
		env.Db.Icons.ReverseCooldown = true
		env.Db.Icons.HideSwipe = true
		env.Db.Icons.HideNumbers = true
		env.Db.Icons.FontScale = 1.5
		env.Db.Icons.ShowStacks = false
		env.Db.Icons.ShowMilliseconds = true
		env.Db.Icons.ColorCountdown = true
		env.Db.Icons.PandemicGlow = true

		local style = Style()

		fw.eq(style.ReverseCooldown, true, "reverse swipe")
		fw.eq(style.HideSwipe, true, "hide swipe")
		fw.eq(style.HideNumbers, true, "hide numbers")
		fw.eq(style.FontScale, 1.5, "font scale")
		fw.eq(style.ShowStacks, false, "show stacks")
		fw.eq(style.ShowMilliseconds, true, "show milliseconds")
		fw.eq(style.ColorCountdown, true, "colour countdown")
		fw.eq(style.PandemicGlow, true, "pandemic glow")
	end)

	fw.it("carries the size and spacing the player set", function()
		env.Db.Icons.Size = 48
		env.Db.Icons.Spacing = 4
		env.Db.MaxIcons = 3
		env.Db.Grow = "LEFT"

		env.Blizzard(1)
		env.Refresh()

		local display = env.Displays[1]

		fw.eq(display.Size, 48, "icon size")
		fw.eq(display.Spacing, 4, "icon spacing")
		fw.eq(display.MaxIcons, 3, "icon count")
		fw.eq(display.Grow, "LEFT", "grow direction")
	end)

	fw.it("passes the pandemic tint the player chose", function()
		env.Db.Icons.PandemicColor = { R = 0.2, G = 0.3, B = 0.4 }

		local style = Style()

		fw.eq(style.PandemicColorR, 0.2, "red")
		fw.eq(style.PandemicColorG, 0.3, "green")
		fw.eq(style.PandemicColorB, 0.4, "blue")
	end)

	fw.it("falls back to amber when no tint was ever saved", function()
		env.Db.Icons.PandemicColor = {}

		local style = Style()

		fw.eq(style.PandemicColorR, 1, "red")
		fw.eq(style.PandemicColorG, 0.6, "green")
		fw.eq(style.PandemicColorB, 0.1, "blue")
	end)

	fw.it("treats an unset zoom as cropping, and a font scale of nothing as one", function()
		env.Db.Icons.Zoom = nil
		env.Db.Icons.FontScale = nil

		local style = Style()

		fw.eq(style.Zoom, true, "icons are cropped unless the player turned it off")
		fw.eq(style.FontScale, 1.0, "the default font scale")
	end)

	fw.it("turns cropping off only when the player says so", function()
		env.Db.Icons.Zoom = false

		fw.eq(Style().Zoom, false, "the stock icon art")
	end)

	fw.it("passes the hide-unimportant toggle as an aura filter", function()
		env.Db.Icons.HideUnimportant = true

		env.Blizzard(1)
		env.Refresh()

		fw.eq(env.Displays[1].HideUnimportant, true, "the filter went with the maps")
	end)
end)
