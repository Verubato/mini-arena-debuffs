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
local columnWidth = mini:ColumnWidth(columns, 0, 0)
---@type Db
local db

---@class Db
local dbDefaults = {
	Version = 5,

	SortMethod = "INDEX",
	SortDirection = "+",

	Grow = "RIGHT",

	Anchor = {
		Offset = {
			X = 60,
			Y = 0,
		},
	},

	---@class IconOptions
	Icons = {
		Size = 36,
		Spacing = 0,
		ReverseCooldown = false,
		HideSwipe = false,
		HideNumbers = false,
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

	return vars
end

local function ApplySettings()
	if InCombatLockdown() then
		mini:Notify("Can't apply settings during combat.")
		return
	end

	addon:Refresh()
end

function M:Init()
	db = GetAndUpgradeDb()

	local panel = CreateFrame("Frame")
	panel.name = addonName

	local category = mini:AddCategory(panel)

	if not category then
		return
	end

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
	title:SetPoint("TOPLEFT", 0, -verticalSpacing)
	title:SetText(string.format("%s - %s", addonName, version))

	local lines = mini:TextBlock({
		Parent = panel,
		Lines = {
			"Shows your debuffs on arena frames.",
		},
	})

	lines:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)

	-- Icons

	local iconsDivider = mini:Divider({ Parent = panel, Text = "Icons" })
	iconsDivider:SetPoint("LEFT", panel, "LEFT")
	iconsDivider:SetPoint("RIGHT", panel, "RIGHT", -horizontalSpacing, 0)
	iconsDivider:SetPoint("TOP", lines, "BOTTOM", 0, -verticalSpacing)

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
	iconSize.Slider:SetPoint("TOPLEFT", iconsDivider, "BOTTOMLEFT", 0, -verticalSpacing * 3)

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
	reverseSwipe:SetPoint("TOPLEFT", maxIcons.Slider, "BOTTOMLEFT", -4, -verticalSpacing)

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
	hideSwipe:SetPoint("TOPLEFT", maxIcons.Slider, "BOTTOMLEFT", columnWidth - 4, -verticalSpacing)

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
	hideNumbers:SetPoint("TOPLEFT", maxIcons.Slider, "BOTTOMLEFT", columnWidth * 2 - 4, -verticalSpacing)

	-- Positioning

	local posDivider = mini:Divider({ Parent = panel, Text = "Positioning" })
	posDivider:SetPoint("LEFT", panel, "LEFT")
	posDivider:SetPoint("RIGHT", panel, "RIGHT", -horizontalSpacing, 0)
	posDivider:SetPoint("TOP", reverseSwipe, "BOTTOM", 0, -verticalSpacing)

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
	growLbl:SetPoint("TOPLEFT", posDivider, "BOTTOMLEFT", 0, -verticalSpacing)
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

	-- Sort

	local sortDivider = mini:Divider({ Parent = panel, Text = "Sort" })
	sortDivider:SetPoint("LEFT", panel, "LEFT")
	sortDivider:SetPoint("RIGHT", panel, "RIGHT", -horizontalSpacing, 0)
	sortDivider:SetPoint("TOP", offsetX.Slider, "BOTTOM", 0, -verticalSpacing * 2)

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
	resetBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -verticalSpacing)
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
				mini:Notify("Settings reset to default.")
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

	addon.CustomAnchors:Init(category)
end
