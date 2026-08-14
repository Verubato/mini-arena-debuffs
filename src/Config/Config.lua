---@type string, Addon
local addonName, addon = ...
local mini = addon.Framework
local dropdownWidth = 200
local growOptions = { "RIGHT", "LEFT", "CENTER" }
local sortMethods = { "INDEX", "TIME" }
local sortDirections = { "+", "-" }
local verticalSpacing = mini.VerticalSpacing
local horizontalSpacing = mini.HorizontalSpacing
local columns = 4
-- The half-spacing padding keeps the last column off the settings window's right edge.
local columnWidth = mini:ColumnWidth(columns, horizontalSpacing / 2, 0)
local SPELL_ICON_SIZE = 18
local SPELL_ROW_HEIGHT = 26
local SPELL_COLUMNS = 2
local SPELL_COLUMN_WIDTH = 290
local SUGGESTION_ROWS = 8
local SUGGESTION_ROW_HEIGHT = 24
---@type Db
local db

---@class Db
local dbDefaults = {
	Version = 7,

	SortMethod = "INDEX",
	SortDirection = "+",

	Grow = "RIGHT",

	Anchor = {
		Offset = {
			X = 0,
			Y = 0,
		},
	},

	---@class IconOptions
	Icons = {
		Size = 36,
		Spacing = 0,
		FontScale = 1.0,
		ReverseCooldown = false,
		HideSwipe = false,
		HideNumbers = false,
		HideUnimportant = false,
		PandemicGlow = false,
		PandemicColor = { R = 1, G = 0.6, B = 0.1 },
		ShowStacks = true,
		ShowMilliseconds = false,
		ColorCountdown = false,
		-- Crops Blizzard's silver border off every icon. Off gives the stock art back.
		Zoom = true,
	},

	-- Mode INCLUDE shows only the listed spells, EXCLUDE hides them; Spells is the raw id text
	-- the user typed.
	SpellFilter = {
		Mode = "OFF",
		Spells = "",
	},

	MaxIcons = 6,

	Anchor1 = "",
	Anchor2 = "",
	Anchor3 = "",
}

---@class Config
local M = {
	DbDefaults = dbDefaults,
}

addon.Config = M

local function GetAndUpgradeDb()
	local vars = mini:GetSavedVars(dbDefaults)

	-- v1 -> v2
	if not vars.Version or vars.Version == 1 then
		vars.SimpleMode = vars.SimpleMode or {}
		vars.SimpleMode.Enabled = true
		vars.Version = 2
		mini:CleanTable(vars, dbDefaults, true, true)
	end

	-- v2 -> v3: clear default anchor overrides
	if vars.Version == 2 then
		for i = 1, 3 do
			local key = "Anchor" .. i
			if vars[key] == "CompactArenaFrameMember" .. i then
				vars[key] = ""
			end
		end
		vars.Version = 3
	end

	-- v3 -> v4: collapse SimpleMode/AdvancedMode, rename padding -> spacing, add new fields
	if vars.Version == 3 then
		-- Migrate anchor from old modes
		if not vars.Anchor then
			if vars.SimpleMode and vars.SimpleMode.Enabled then
				vars.Anchor = {
					Point = "CENTER",
					RelativePoint = "CENTER",
					Offset = {
						X = (vars.SimpleMode.Offset and vars.SimpleMode.Offset.X) or 0,
						Y = (vars.SimpleMode.Offset and vars.SimpleMode.Offset.Y) or 0,
					},
				}
			elseif vars.AdvancedMode then
				vars.Anchor = {
					Point = vars.AdvancedMode.Point or "TOPLEFT",
					RelativePoint = vars.AdvancedMode.RelativePoint or "TOPRIGHT",
					Offset = {
						X = (vars.AdvancedMode.Offset and vars.AdvancedMode.Offset.X) or 2,
						Y = (vars.AdvancedMode.Offset and vars.AdvancedMode.Offset.Y) or 0,
					},
				}
			end
		end

		-- Migrate padding.X -> spacing
		if vars.Icons and vars.Icons.Padding then
			vars.Icons.Spacing = vars.Icons.Padding.X or 2
			vars.Icons.Padding = nil
		end

		-- Migrate IconsPerRow -> MaxIcons
		if vars.IconsPerRow and not vars.MaxIcons then
			vars.MaxIcons = vars.IconsPerRow
			vars.IconsPerRow = nil
		end

		-- Remove obsolete fields
		vars.SimpleMode = nil
		vars.AdvancedMode = nil
		vars.Rows = nil
		vars.GrowDirection = vars.GrowDirection or "RIGHT"

		vars.Version = 4
		mini:CleanTable(vars, dbDefaults, true, true)
	end

	-- v4 -> v5: rename GrowDirection -> Grow; remove Anchor.Point/RelativePoint
	if vars.Version == 4 then
		vars.Grow = vars.GrowDirection or "RIGHT"
		vars.GrowDirection = nil
		if vars.Anchor then
			vars.Anchor.Point = nil
			vars.Anchor.RelativePoint = nil
		end
		vars.Version = 5
		mini:CleanTable(vars, dbDefaults, true, true)
	end

	-- v5 -> v6: the pandemic border and glow drew the same cue, so they are one option now. The
	-- two were per-path, so whichever the character's client offered is the one that carries over.
	if vars.Version == 5 then
		if vars.Icons then
			vars.Icons.PandemicGlow = vars.Icons.PandemicGlow or vars.Icons.PandemicBorder or false
			vars.Icons.PandemicBorder = nil
		end
		vars.Version = 6
		mini:CleanTable(vars, dbDefaults, true, true)
	end

	-- v6 -> v7: 12.0 is gone, and with it desaturating on pandemic, which needed the aura's own
	-- remaining duration.
	if vars.Version == 6 then
		if vars.Icons then
			vars.Icons.PandemicDesaturate = nil
		end
		vars.Version = 7
		mini:CleanTable(vars, dbDefaults, true, true)
	end

	return vars
end

local function ApplySettings()
	if InCombatLockdown() then
		mini:NotifyWithPrefix("Can't apply settings during combat.")
		return
	end

	addon:Refresh()
end

---The Zoom Icons toggle. Built by the caller so it can be dropped into whichever gap the row of
---checkboxes has on this client, which differs between the two display paths.
---@param panel table
---@return table
local function BuildZoomIcons(panel)
	return mini:Checkbox({
		Parent = panel,
		LabelText = "Zoom Icons",
		Tooltip = "Crops the silver border off spell icons. Turn it off to show the icons exactly as Blizzard draws them. A Masque skin brings its own crop and ignores this.",
		GetValue = function()
			return db.Icons.Zoom ~= false
		end,
		SetValue = function(v)
			db.Icons.Zoom = v
			ApplySettings()
		end,
	})
end

---The Glow on Pandemic toggle. Built by the caller so the two display paths can each place it.
---@param panel table
---@return table
local function BuildPandemicGlow(panel)
	return mini:Checkbox({
		Parent = panel,
		LabelText = "Glow on Pandemic",
		Tooltip = "Glows icons while a debuff is in its refresh window (the last stretch where re-casting carries the remaining time over).",
		GetValue = function()
			return db.Icons.PandemicGlow
		end,
		SetValue = function(v)
			db.Icons.PandemicGlow = v
			ApplySettings()
		end,
	})
end

local function InitPositionPanel(category)
	local panel = CreateFrame("Frame")
	panel.name = "Position & Sort"

	mini:AddSubCategory(category, panel)

	local header = mini:PanelHeader({
		Parent = panel,
		Title = "Position & Sort",
		Lines = {
			"Where the icon row sits relative to each arena frame, and the order icons appear in.",
		},
	})

	local growLbl = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	growLbl:SetText("Grow")

	local growDdl, modernDdl = mini:Dropdown({
		Parent = panel,
		Items = growOptions,
		Width = columnWidth,
		GetValue = function()
			return db.Grow
		end,
		SetValue = function(value)
			if db.Grow ~= value then
				db.Grow = value
				ApplySettings()
			end
		end,
	})
	growDdl:SetWidth(dropdownWidth)
	growLbl:SetPoint("TOPLEFT", header.Anchor, "BOTTOMLEFT", 0, -verticalSpacing)
	growDdl:SetPoint("TOPLEFT", growLbl, "BOTTOMLEFT", modernDdl and 0 or -16, -8)

	local offsetX = mini:Slider({
		Parent = panel,
		Min = -250,
		Max = 250,
		Step = 1,
		Width = columnWidth * 2 - horizontalSpacing,
		LabelText = "Offset X",
		GetValue = function()
			return db.Anchor.Offset.X
		end,
		SetValue = function(v)
			db.Anchor.Offset.X = mini:ClampInt(v, -250, 250, dbDefaults.Anchor.Offset.X)
			ApplySettings()
		end,
	})
	offsetX.Slider:SetPoint("TOPLEFT", growDdl, "BOTTOMLEFT", modernDdl and 0 or 16, -verticalSpacing * 3)

	local offsetY = mini:Slider({
		Parent = panel,
		Min = -250,
		Max = 250,
		Step = 1,
		Width = columnWidth * 2 - horizontalSpacing,
		LabelText = "Offset Y",
		GetValue = function()
			return db.Anchor.Offset.Y
		end,
		SetValue = function(v)
			db.Anchor.Offset.Y = mini:ClampInt(v, -250, 250, dbDefaults.Anchor.Offset.Y)
			ApplySettings()
		end,
	})
	offsetY.Slider:SetPoint("LEFT", offsetX.Slider, "RIGHT", horizontalSpacing, 0)

	local sortDivider = mini:Divider({ Parent = panel, Text = "Sort" })
	sortDivider:SetPoint("LEFT", panel, "LEFT")
	sortDivider:SetPoint("RIGHT", panel, "RIGHT", -horizontalSpacing, 0)
	sortDivider:SetPoint("TOP", offsetX.Slider, "BOTTOM", 0, -verticalSpacing)

	local sortMethodLbl = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	sortMethodLbl:SetText("Sort Method")

	local sortMethodDdl
	sortMethodDdl, modernDdl = mini:Dropdown({
		Parent = panel,
		Items = sortMethods,
		Width = columnWidth,
		GetValue = function()
			return db.SortMethod
		end,
		SetValue = function(value)
			if db.SortMethod ~= value then
				db.SortMethod = value
				ApplySettings()
			end
		end,
	})
	sortMethodDdl:SetWidth(dropdownWidth)
	sortMethodLbl:SetPoint("TOPLEFT", sortDivider, "BOTTOMLEFT", 0, -verticalSpacing)
	sortMethodDdl:SetPoint("TOPLEFT", sortMethodLbl, "BOTTOMLEFT", modernDdl and 0 or -16, -8)

	local sortDirLbl = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	sortDirLbl:SetText("Sort Direction")

	local sortDirDdl = mini:Dropdown({
		Parent = panel,
		Items = sortDirections,
		Width = columnWidth,
		GetText = function(v)
			return v == "+" and "Ascending (+)" or "Descending (-)"
		end,
		GetValue = function()
			return db.SortDirection
		end,
		SetValue = function(value)
			if db.SortDirection ~= value then
				db.SortDirection = value
				ApplySettings()
			end
		end,
	})
	sortDirDdl:SetWidth(dropdownWidth)
	sortDirDdl:SetPoint("LEFT", sortMethodDdl, "RIGHT", horizontalSpacing, 0)
	sortDirLbl:SetPoint("BOTTOMLEFT", sortDirDdl, "TOPLEFT", 0, 8)

	panel:SetScript("OnShow", function()
		panel:MiniRefresh()
	end)
end

---A spell icon with the standard tooltip; set .SpellId and .Icon's texture per use.
local function CreateSpellIcon(parent)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(SPELL_ICON_SIZE, SPELL_ICON_SIZE)

	button.Icon = button:CreateTexture(nil, "ARTWORK")
	button.Icon:SetAllPoints()
	button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	button:SetScript("OnEnter", function(buttonSelf)
		if not buttonSelf.SpellId then
			return
		end

		GameTooltip:SetOwner(buttonSelf, "ANCHOR_RIGHT")
		GameTooltip:SetSpellByID(buttonSelf.SpellId)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	return button
end

---A small remove cross with the standard tooltip; the caller positions it.
local function CreateRemoveButton(parent, onClick)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(SPELL_ICON_SIZE, SPELL_ICON_SIZE)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")

	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")

	button:SetScript("OnEnter", function(buttonSelf)
		GameTooltip:SetOwner(buttonSelf, "ANCHOR_RIGHT")
		GameTooltip:SetText(REMOVE or "Remove", 1, 0.82, 0)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	button:SetScript("OnClick", onClick)

	return button
end

local function SpellLabel(spellId)
	return ("%s |cff888888(%d)|r"):format(C_Spell.GetSpellName(spellId) or "?", spellId)
end

---An edit box that suggests spells as you type; picking one (click or Enter) calls onAccept
---with its id. Ported from MiniAuras' spell picker.
local function CreateSpellPicker(panel, onAccept)
	local spellSearch = addon.SpellSearch
	local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
	mini:FlattenEditBox(box)
	box:SetSize(dropdownWidth, 22)
	box:SetAutoFocus(false)
	local suggestionRows = {}

	-- Edit boxes have no placeholder of their own, so it is a font string behind the caret that
	-- goes away as soon as there is anything to read.
	local placeholder = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	placeholder:SetPoint("LEFT", box, "LEFT", 2, 0)
	placeholder:SetText("Spell ID / name")

	local function UpdatePlaceholder()
		placeholder:SetShown(box:GetText() == "" and not box:HasFocus())
	end

	local popup = CreateFrame("Frame", nil, panel, "BackdropTemplate")
	popup:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -6, -2)
	popup:SetWidth(280)
	popup:SetFrameStrata("DIALOG")
	-- Above every row it drops over, not just its immediate parent.
	popup:SetFrameLevel(panel:GetFrameLevel() + 20)
	popup:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	popup:SetBackdropColor(0, 0, 0, 0.95)
	popup:Hide()
	-- Clicks on the padding close it; the focus handler below has already fired by then.
	popup:EnableMouse(true)
	popup:SetScript("OnMouseDown", function(popupSelf)
		popupSelf:Hide()
	end)

	-- Which suggestion the arrow keys have walked to, zero for none. Enter takes this one when
	-- there is one, and the best match otherwise.
	local highlighted = 0
	local shownRows = 0

	local function ApplyHighlight()
		for index = 1, shownRows do
			suggestionRows[index].Selected:SetShown(index == highlighted)
		end
	end

	local function HidePopup()
		popup:Hide()
		highlighted = 0
	end

	---@param step number -1 for up, 1 for down.
	local function MoveHighlight(step)
		if shownRows == 0 then
			return
		end

		if highlighted == 0 then
			-- Entering the list from the box: down starts at the top, up at the bottom.
			highlighted = step > 0 and 1 or shownRows
		else
			highlighted = (highlighted + step - 1) % shownRows + 1
		end

		ApplyHighlight()
	end

	local function ShowSuggestions()
		local results = spellSearch:Search(box:GetText(), SUGGESTION_ROWS)
		local y = -6

		for index, entry in ipairs(results) do
			local row = suggestionRows[index]

			if not row then
				row = CreateFrame("Button", nil, popup)
				row:SetSize(268, SUGGESTION_ROW_HEIGHT)
				row.Icon = CreateSpellIcon(row)
				row.Icon:SetPoint("LEFT", row, "LEFT", 6, 0)
				row.Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
				row.Text:SetPoint("LEFT", row.Icon, "RIGHT", 6, 0)

				local highlight = row:CreateTexture(nil, "HIGHLIGHT")
				highlight:SetAllPoints()
				highlight:SetColorTexture(1, 1, 1, 0.08)

				-- Separate from the hover highlight, which the mouse owns.
				row.Selected = row:CreateTexture(nil, "ARTWORK")
				row.Selected:SetAllPoints()
				row.Selected:SetColorTexture(1, 0.82, 0, 0.2)
				row.Selected:Hide()

				suggestionRows[index] = row
			end

			row.SpellId = entry.Id
			row.Icon.SpellId = entry.Id
			row.Icon.Icon:SetTexture(C_Spell.GetSpellTexture(entry.Id))
			row.Text:SetText(SpellLabel(entry.Id))
			row:SetPoint("TOPLEFT", popup, "TOPLEFT", 0, y)
			row:SetScript("OnClick", function()
				box:SetText("")
				box:ClearFocus()
				HidePopup()
				onAccept(entry.Id)
			end)
			row:Show()

			y = y - SUGGESTION_ROW_HEIGHT
		end

		for index = #results + 1, #suggestionRows do
			suggestionRows[index]:Hide()
		end

		shownRows = #results

		if shownRows == 0 then
			HidePopup()
			return
		end

		-- A new query invalidates wherever the arrows had walked to.
		highlighted = 0
		ApplyHighlight()

		popup:SetHeight(-y + 6)
		popup:Show()
	end

	box:SetScript("OnTextChanged", function(_, userInput)
		-- Fires for SetText as well as typing, so every path that clears the box lands here.
		UpdatePlaceholder()

		if userInput then
			ShowSuggestions()
		end
	end)

	box:SetScript("OnEditFocusGained", UpdatePlaceholder)

	-- Up and down walk the suggestions. Left and right are the caret's, so they fall through.
	box:SetScript("OnArrowPressed", function(_, key)
		if key == "DOWN" then
			MoveHighlight(1)
		elseif key == "UP" then
			MoveHighlight(-1)
		end
	end)

	box:SetScript("OnEnterPressed", function(boxSelf)
		-- Whatever the arrows landed on, else the best suggestion, which for a fully typed id
		-- is that id.
		local row = highlighted > 0 and suggestionRows[highlighted]
		local spellId = row and row.SpellId

		if not spellId then
			local results = spellSearch:Search(boxSelf:GetText(), 1)

			spellId = results[1] and results[1].Id
		end

		boxSelf:SetText("")
		boxSelf:ClearFocus()
		HidePopup()

		if spellId then
			onAccept(spellId)
		end
	end)

	box:SetScript("OnEscapePressed", function(boxSelf)
		boxSelf:SetText("")
		boxSelf:ClearFocus()
		HidePopup()
	end)

	box:SetScript("OnEditFocusLost", function()
		UpdatePlaceholder()

		-- A click pulls focus on mouse DOWN, before the row sees it on mouse up. Hiding here
		-- would take the row out from under the cursor. The row closes the popup itself.
		if popup:IsMouseOver() then
			return
		end

		HidePopup()
	end)

	UpdatePlaceholder()

	return box
end

-- Filtering by spell id is the AuraContainer's candidate filters and nothing else: an addon
-- reading auras itself gets the spell id back as a secret value that can never be matched
-- against a tracked id, so the engine has to do the matching.
local function InitSpellFilterPanel(category)
	local spellSearch = addon.SpellSearch
	local panel = CreateFrame("Frame")
	panel.name = "Spell Filter"

	mini:AddSubCategory(category, panel)

	local header = mini:PanelHeader({
		Parent = panel,
		Title = "Spell Filter",
		Lines = {
			"Limits which of your debuffs are shown.",
			"Only Listed Spells shows just the spells below; All But Listed Spells hides them.",
			"Adding a spell also adds every spell ID that applies an aura under the same name.",
		},
	})

	---The stored filter as an ordered id list plus a lookup set.
	local function GetFilterIds()
		local ids, seen = {}, {}

		for id in (db.SpellFilter.Spells or ""):gmatch("%d+") do
			local spellId = tonumber(id)

			if spellId and spellId > 0 and not seen[spellId] then
				seen[spellId] = true
				ids[#ids + 1] = spellId
			end
		end

		return ids, seen
	end

	local function StoreFilterIds(ids)
		db.SpellFilter.Spells = table.concat(ids, ", ")
		ApplySettings()
	end

	---The stored ids grouped one row per spell name (a name's id variants collapse into it),
	---sorted by name so the list reads the same every time.
	local function GroupedFilterSpells()
		local ids = GetFilterIds()
		local groups, byName = {}, {}

		for _, spellId in ipairs(ids) do
			local name = C_Spell.GetSpellName(spellId) or tostring(spellId)
			local group = byName[name]

			if not group then
				group = { Name = name, Ids = {} }
				byName[name] = group
				groups[#groups + 1] = group
			end

			group.Ids[#group.Ids + 1] = spellId
		end

		table.sort(groups, function(a, b)
			return a.Name:lower() < b.Name:lower()
		end)

		return groups
	end

	local filterModeLbl = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	filterModeLbl:SetText("Mode")

	local filterModeText = {
		OFF = "Off",
		INCLUDE = "Only Listed Spells",
		EXCLUDE = "All But Listed Spells",
	}

	local filterModeDdl, modernDdl = mini:Dropdown({
		Parent = panel,
		Items = { "OFF", "INCLUDE", "EXCLUDE" },
		Width = columnWidth,
		GetText = function(v)
			return filterModeText[v] or v
		end,
		GetValue = function()
			return db.SpellFilter.Mode
		end,
		SetValue = function(value)
			if db.SpellFilter.Mode ~= value then
				db.SpellFilter.Mode = value
				ApplySettings()
			end
		end,
	})
	filterModeDdl:SetWidth(dropdownWidth)
	filterModeLbl:SetPoint("TOPLEFT", header.Anchor, "BOTTOMLEFT", 0, -verticalSpacing)
	filterModeDdl:SetPoint("TOPLEFT", filterModeLbl, "BOTTOMLEFT", modernDdl and 0 or -16, -8)

	local spellRows = {}
	local Populate

	local function AddSpell(spellId)
		local ids, seen = GetFilterIds()
		local added = false

		-- The picker offers one row per name; track every id variant behind it, because the id
		-- the game applies is often not the one the player looked up.
		for _, id in ipairs(spellSearch:GetVariants(spellId)) do
			if not seen[id] then
				seen[id] = true
				ids[#ids + 1] = id
				added = true
			end
		end

		if added then
			StoreFilterIds(ids)
			Populate()
		end
	end

	local function RemoveSpells(removeIds)
		local remove = {}

		for _, id in ipairs(removeIds) do
			remove[id] = true
		end

		local ids = {}

		for _, id in ipairs(GetFilterIds()) do
			if not remove[id] then
				ids[#ids + 1] = id
			end
		end

		StoreFilterIds(ids)
		Populate()
	end

	local pickerLbl = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	pickerLbl:SetText("Add Spell")

	local picker = CreateSpellPicker(panel, AddSpell)
	pickerLbl:SetPoint("TOPLEFT", filterModeDdl, "BOTTOMLEFT", modernDdl and 0 or 16, -verticalSpacing)
	picker:SetPoint("TOPLEFT", pickerLbl, "BOTTOMLEFT", 6, -8)

	local list = CreateFrame("Frame", nil, panel)
	list:SetPoint("TOPLEFT", picker, "BOTTOMLEFT", -6, -verticalSpacing)
	list:SetSize(1, 1)

	function Populate()
		local groups = GroupedFilterSpells()

		for index, group in ipairs(groups) do
			local row = spellRows[index]

			if not row then
				row = CreateFrame("Frame", nil, list)
				row:SetSize(SPELL_COLUMN_WIDTH - horizontalSpacing, SPELL_ROW_HEIGHT)
				row.Icon = CreateSpellIcon(row)
				row.Icon:SetPoint("LEFT", row, "LEFT", 0, 0)
				row.Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
				row.Text:SetPoint("LEFT", row.Icon, "RIGHT", 6, 0)
				row.Text:SetPoint("RIGHT", row, "RIGHT", -SPELL_ICON_SIZE - 6, 0)
				row.Text:SetJustifyH("LEFT")
				row.Text:SetWordWrap(false)
				row.Remove = CreateRemoveButton(row, function()
					RemoveSpells(row.RemoveIds)
				end)
				row.Remove:SetPoint("RIGHT", row, "RIGHT", 0, 0)
				spellRows[index] = row
			end

			local spellId = group.Ids[1]
			row.RemoveIds = group.Ids
			row.Icon.SpellId = spellId
			row.Icon.Icon:SetTexture(C_Spell.GetSpellTexture(spellId))
			row.Text:SetText(SpellLabel(spellId))
			row:SetPoint(
				"TOPLEFT",
				list,
				"TOPLEFT",
				((index - 1) % SPELL_COLUMNS) * SPELL_COLUMN_WIDTH,
				-math.floor((index - 1) / SPELL_COLUMNS) * SPELL_ROW_HEIGHT
			)
			row:Show()
		end

		for index = #groups + 1, #spellRows do
			spellRows[index]:Hide()
		end
	end

	panel:SetScript("OnShow", function()
		panel:MiniRefresh()
		Populate()
	end)
end

function M:Init()
	db = GetAndUpgradeDb()

	local panel = CreateFrame("Frame")
	panel.name = addonName

	local category = mini:AddCategory(panel)

	if not category then
		return
	end

	local header = mini:PanelHeader({
		Parent = panel,
		Lines = {
			"Shows your debuffs on arena frames.",
		},
		Gap = 6,
	})

	local reverseSwipe = mini:Checkbox({
		Parent = panel,
		LabelText = "Reverse Swipe",
		Tooltip = "Reverses the cooldown swipe animation direction.",
		GetValue = function()
			return db.Icons.ReverseCooldown
		end,
		SetValue = function(v)
			db.Icons.ReverseCooldown = v
			ApplySettings()
		end,
	})
	reverseSwipe:SetPoint("TOPLEFT", header.Anchor, "BOTTOMLEFT", -4, -verticalSpacing)

	local hideSwipe = mini:Checkbox({
		Parent = panel,
		LabelText = "Hide Swipe",
		Tooltip = "Hides the cooldown swipe animation on icons.",
		GetValue = function()
			return db.Icons.HideSwipe
		end,
		SetValue = function(v)
			db.Icons.HideSwipe = v
			ApplySettings()
		end,
	})
	hideSwipe:SetPoint("TOPLEFT", header.Anchor, "BOTTOMLEFT", columnWidth - 4, -verticalSpacing)

	local hideNumbers = mini:Checkbox({
		Parent = panel,
		LabelText = "Hide Numbers",
		Tooltip = "Hides the cooldown countdown numbers on icons.",
		GetValue = function()
			return db.Icons.HideNumbers
		end,
		SetValue = function(v)
			db.Icons.HideNumbers = v
			ApplySettings()
		end,
	})
	hideNumbers:SetPoint("TOPLEFT", header.Anchor, "BOTTOMLEFT", columnWidth * 2 - 4, -verticalSpacing)

	local hideUnimportant = mini:Checkbox({
		Parent = panel,
		LabelText = "Hide Unimportant",
		Tooltip = "Hides player-cast debuffs that Blizzard considers unimportant (nameplateShowPersonal = false).",
		GetValue = function()
			return db.Icons.HideUnimportant
		end,
		SetValue = function(v)
			db.Icons.HideUnimportant = v
			ApplySettings()
		end,
	})
	hideUnimportant:SetPoint("TOPLEFT", header.Anchor, "BOTTOMLEFT", columnWidth * 3 - 4, -verticalSpacing)

	local sliderAnchor
	local showStacks = mini:Checkbox({
		Parent = panel,
		LabelText = "Show Stacks",
		Tooltip = "Shows the stack count on debuffs with more than one application.",
		GetValue = function()
			return db.Icons.ShowStacks
		end,
		SetValue = function(v)
			db.Icons.ShowStacks = v
			ApplySettings()
		end,
	})
	showStacks:SetPoint("TOPLEFT", reverseSwipe, "BOTTOMLEFT", 0, -verticalSpacing)

	local showMilliseconds = mini:Checkbox({
		Parent = panel,
		LabelText = "Show Milliseconds",
		Tooltip = "Shows tenths of a second on countdowns under 5 seconds, e.g. 4.3.",
		GetValue = function()
			return db.Icons.ShowMilliseconds
		end,
		SetValue = function(v)
			db.Icons.ShowMilliseconds = v
			ApplySettings()
		end,
	})
	showMilliseconds:SetPoint("TOPLEFT", hideSwipe, "BOTTOMLEFT", 0, -verticalSpacing)

	local colorCountdown = mini:Checkbox({
		Parent = panel,
		LabelText = "Color Countdown",
		Tooltip = "Colors the countdown text by time remaining: red under 5 seconds, yellow under a minute.",
		GetValue = function()
			return db.Icons.ColorCountdown
		end,
		SetValue = function(v)
			db.Icons.ColorCountdown = v
			ApplySettings()
		end,
	})
	colorCountdown:SetPoint("TOPLEFT", hideNumbers, "BOTTOMLEFT", 0, -verticalSpacing)

	sliderAnchor = showStacks

	-- Pandemic regions arrived after 12.1.0 (feature-detected), so the reveal and its colour
	-- only show on clients that can actually drive it.
	local hasPandemicRegions = addon.WoWEx:HasPandemicRegions()

	if hasPandemicRegions then
		local pandemicGlow = BuildPandemicGlow(panel)
		pandemicGlow:SetPoint("TOPLEFT", showStacks, "BOTTOMLEFT", 0, -verticalSpacing)

		local pandemicColor = mini:ColorSwatch({
			Parent = panel,
			LabelText = "Pandemic Color",
			Tooltip = "Click to change the pandemic glow's colour.",
			HasOpacity = false,
			GetValue = function()
				local color = db.Icons.PandemicColor or {}
				return color.R or 1, color.G or 0.6, color.B or 0.1, 1
			end,
			SetValue = function(r, g, b)
				db.Icons.PandemicColor = { R = r, G = g, B = b }
				ApplySettings()
			end,
		})
		-- Beside the toggle it belongs to, one column over. Anchored by LEFT rather than the
		-- grid's TOPLEFT so the two line up through their middles: the swatch is a small
		-- square against a checkbox half again as tall.
		pandemicColor:SetPoint("LEFT", pandemicGlow, "LEFT", columnWidth, 0)
		-- The sliders hang off this, so it has to be the first column of the last row.
		sliderAnchor = pandemicGlow
	end

	local zoomIcons = BuildZoomIcons(panel)
	if hasPandemicRegions then
		-- The last column of the row above, which the pandemic pair left free by moving down
		-- together.
		zoomIcons:SetPoint("TOPLEFT", hideUnimportant, "BOTTOMLEFT", 0, -verticalSpacing)
	else
		zoomIcons:SetPoint("TOPLEFT", showStacks, "BOTTOMLEFT", 0, -verticalSpacing)
		sliderAnchor = zoomIcons
	end

	local iconSize = mini:Slider({
		Parent = panel,
		Min = 10,
		Max = 200,
		Step = 1,
		Width = columnWidth * 2 - horizontalSpacing,
		LabelText = "Icon Size",
		GetValue = function()
			return db.Icons.Size
		end,
		SetValue = function(v)
			db.Icons.Size = mini:ClampInt(v, 10, 200, dbDefaults.Icons.Size)
			ApplySettings()
		end,
	})
	iconSize.Slider:SetPoint("TOPLEFT", sliderAnchor, "BOTTOMLEFT", 4, -verticalSpacing * 3)

	local iconSpacing = mini:Slider({
		Parent = panel,
		Min = 0,
		Max = 50,
		Step = 1,
		Width = columnWidth * 2 - horizontalSpacing,
		LabelText = "Icon Spacing",
		GetValue = function()
			return db.Icons.Spacing
		end,
		SetValue = function(v)
			db.Icons.Spacing = mini:ClampInt(v, 0, 50, dbDefaults.Icons.Spacing)
			ApplySettings()
		end,
	})
	iconSpacing.Slider:SetPoint("LEFT", iconSize.Slider, "RIGHT", horizontalSpacing * 2, 0)

	local maxIcons = mini:Slider({
		Parent = panel,
		Min = 1,
		Max = 10,
		Step = 1,
		Width = columnWidth * 2 - horizontalSpacing,
		LabelText = "Max Icons",
		GetValue = function()
			return db.MaxIcons
		end,
		SetValue = function(v)
			db.MaxIcons = mini:ClampInt(v, 1, 10, dbDefaults.MaxIcons)
			ApplySettings()
		end,
	})
	maxIcons.Slider:SetPoint("TOPLEFT", iconSize.Slider, "BOTTOMLEFT", 0, -verticalSpacing * 3)

	local fontScale = mini:Slider({
		Parent = panel,
		Min = 0.5,
		Max = 1.5,
		Step = 0.05,
		Width = columnWidth * 2 - horizontalSpacing,
		LabelText = "Font Scale",
		GetValue = function()
			return db.Icons.FontScale or 1.0
		end,
		SetValue = function(v)
			db.Icons.FontScale = mini:ClampFloat(v, 0.5, 1.5, dbDefaults.Icons.FontScale)
			ApplySettings()
		end,
	})
	fontScale.Slider:SetPoint("LEFT", maxIcons.Slider, "RIGHT", horizontalSpacing * 2, 0)

	StaticPopupDialogs["MINIAD_CONFIRM"] = {
		text = "%s",
		button1 = YES,
		button2 = NO,
		OnAccept = function(_, data)
			if data and data.OnYes then
				data.OnYes()
			end
		end,
		OnCancel = function(_, data)
			if data and data.OnNo then
				data.OnNo()
			end
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}

	local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	resetBtn:SetSize(120, 26)
	resetBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -horizontalSpacing, -verticalSpacing)
	resetBtn:SetText("Reset")
	resetBtn:SetScript("OnClick", function()
		if InCombatLockdown() then
			mini:NotifyCombatLockdown()
			return
		end

		StaticPopup_Show("MINIAD_CONFIRM", "Are you sure you wish to reset to factory settings?", nil, {
			OnYes = function()
				db = mini:ResetSavedVars(dbDefaults)

				panel:MiniRefresh()
				addon:Refresh()
				mini:NotifyWithPrefix("Settings reset to default.")
			end,
		})
	end)

	local testBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	testBtn:SetSize(120, 26)
	testBtn:SetPoint("RIGHT", resetBtn, "LEFT", -horizontalSpacing, 0)
	testBtn:SetText("Test")
	testBtn:SetScript("OnClick", function()
		addon:ToggleTest()
	end)

	panel:SetScript("OnShow", function()
		panel:MiniRefresh()
	end)

	SLASH_MINIARENADEBUFFS1 = "/miniarenadebuffs"
	SLASH_MINIARENADEBUFFS2 = "/miniad"

	SlashCmdList.MINIARENADEBUFFS = function(msg)
		msg = msg and msg:lower():match("^%s*(.-)%s*$") or ""

		if msg == "test" then
			addon:ToggleTest()
			return
		end

		mini:OpenSettings(category, panel)
	end

	InitPositionPanel(category)
	InitSpellFilterPanel(category)
	addon.CustomAnchors:Init(category)
end
