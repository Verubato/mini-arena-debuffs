local addonName, addon = ...
---@type MiniFramework
local mini = addon.Framework
local verticalSpacing = 16
local horizontalSpacing = 20
local dropdownWidth = 200
local anchorPoints = {
	"TOPLEFT",
	"TOP",
	"TOPRIGHT",
	"LEFT",
	"CENTER",
	"RIGHT",
	"BOTTOMLEFT",
	"BOTTOM",
	"BOTTOMRIGHT",
}

---@type Db
local db

---@class Db
local dbDefaults = {
	IconSize = 32,
	IconPaddingX = 2,
	IconPaddingY = 2,
	IconsPerRow = 5,
	Rows = 1,

	ContainerAnchorPoint = "BOTTOMLEFT",
	ContainerRelativePoint = "BOTTOMRIGHT",
	ContainerOffsetX = 2,
	ContainerOffsetY = 0,

	Filter = "HARMFUL|PLAYER",
	SortMethod = "TIME",

	ArenaFrame1Anchor = "CompactArenaFrameMember1",
	ArenaFrame2Anchor = "CompactArenaFrameMember2",
	ArenaFrame3Anchor = "CompactArenaFrameMember3",
}

local M = {
	DbDefaults = dbDefaults,
}

addon.Config = M

local function ApplySettings()
	if InCombatLockdown() then
		addon:Notify("Can't apply settings during combat.")
		return
	end

	addon:Refresh()
end

function M:Init()
	db = mini:GetSavedVars(dbDefaults)

	local scroll = CreateFrame("ScrollFrame", nil, nil, "UIPanelScrollFrameTemplate")
	scroll.name = addonName

	local category = mini:AddCategory(scroll)

	if not category then
		return
	end

	local panel = CreateFrame("Frame", nil, scroll)
	local width, height = mini:SettingsSize()

	panel:SetWidth(width)
	panel:SetHeight(height)

	scroll:SetScrollChild(panel)

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 0, -16)
	title:SetText(addonName)

	local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontWhite")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	subtitle:SetText("Shows debuffs on arena frames.")

	local iconSize = mini:EditBox({
		Parent = panel,
		Numeric = true,
		LabelText = "Icon Size",
		GetValue = function()
			return db.IconSize
		end,
		SetValue = function(v)
			db.IconSize = mini:ClampInt(v, 10, 80, dbDefaults.IconSize)
		end,
	})

	iconSize.Label:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -verticalSpacing)
	iconSize.EditBox:SetPoint("TOPLEFT", iconSize.Label, "BOTTOMLEFT", 4, -4)

	local iconsPerRow = mini:EditBox({
		Parent = panel,
		Numeric = true,
		LabelText = "Icons Per Row",
		GetValue = function()
			return db.IconsPerRow
		end,
		SetValue = function(v)
			db.IconsPerRow = mini:ClampInt(v, 1, 10, dbDefaults.IconsPerRow)
			ApplySettings()
		end,
	})

	iconsPerRow.Label:SetPoint("LEFT", iconSize.EditBox, "RIGHT", horizontalSpacing, iconSize.EditBox:GetHeight())
	iconsPerRow.EditBox:SetPoint("TOPLEFT", iconsPerRow.Label, "BOTTOMLEFT", 4, -4)

	local rows = mini:EditBox({
		Parent = panel,
		Numeric = true,
		LabelText = "Rows",
		GetValue = function()
			return db.Rows
		end,
		SetValue = function(v)
			db.Rows = mini:ClampInt(v, 1, 5, dbDefaults.Rows)
			ApplySettings()
		end,
	})

	rows.Label:SetPoint("LEFT", iconsPerRow.EditBox, "RIGHT", horizontalSpacing, iconsPerRow.EditBox:GetHeight())
	rows.EditBox:SetPoint("TOPLEFT", rows.Label, "BOTTOMLEFT", 4, -4)

	local containerX = mini:EditBox({
		Parent = panel,
		Numeric = true,
		AllowNegatives = true,
		LabelText = "Offset X",
		GetValue = function()
			return db.ContainerOffsetX
		end,
		SetValue = function(v)
			db.ContainerOffsetX = mini:ClampInt(v, -200, 200, dbDefaults.ContainerOffsetX)
			ApplySettings()
		end,
	})

	containerX.Label:SetPoint("TOPLEFT", iconSize.EditBox, "BOTTOMLEFT", -4, -verticalSpacing)
	containerX.EditBox:SetPoint("TOPLEFT", containerX.Label, "BOTTOMLEFT", 4, -4)

	local containerY = mini:EditBox({
		Parent = panel,
		Numeric = true,
		AllowNegatives = true,
		LabelText = "Offset Y",
		GetValue = function()
			return db.ContainerOffsetY
		end,
		SetValue = function(v)
			db.ContainerOffsetY = mini:ClampInt(v, -200, 200, dbDefaults.ContainerOffsetY)
			ApplySettings()
		end,
	})

	containerY.Label:SetPoint("LEFT", containerX.EditBox, "RIGHT", horizontalSpacing, containerX.EditBox:GetHeight())
	containerY.EditBox:SetPoint("TOPLEFT", containerY.Label, "BOTTOMLEFT", 4, -4)

	local pointDdlLbl = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	pointDdlLbl:SetText("Anchor Point")

	local pointDdl, modernDdl = mini:Dropdown({
		Parent = panel,
		Items = anchorPoints,
		GetValue = function()
			return db.ContainerAnchorPoint
		end,
		SetValue = function(value)
			if db.ContainerAnchorPoint ~= value then
				db.ContainerAnchorPoint = value
				ApplySettings()
			end
		end,
	})

	pointDdl:SetWidth(dropdownWidth)
	pointDdlLbl:SetPoint("TOPLEFT", containerX.EditBox, "BOTTOMLEFT", -4, -verticalSpacing)
	-- no idea why by default it's off by 16 points
	pointDdl:SetPoint("TOPLEFT", pointDdlLbl, "BOTTOMLEFT", modernDdl and 0 or -16, -8)

	local relativeToLbl = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	relativeToLbl:SetText("Relative to")

	local relativeToDdl = mini:Dropdown({
		Parent = panel,
		Items = anchorPoints,
		GetValue = function()
			return db.ContainerRelativePoint
		end,
		SetValue = function(value)
			if db.ContainerRelativePoint ~= value then
				db.ContainerRelativePoint = value
				ApplySettings()
			end
		end,
	})

	relativeToDdl:SetWidth(dropdownWidth)
	relativeToDdl:SetPoint("LEFT", pointDdl, "RIGHT", horizontalSpacing, 0)
	relativeToLbl:SetPoint("BOTTOMLEFT", relativeToDdl, "TOPLEFT", 0, 8)

	local onlyMineChk = mini:Checkbox({
		Parent = panel,
		LabelText = "Only my debuffs",
		GetValue = function()
			return (db.Filter or ""):find("PLAYER") ~= nil
		end,
		SetValue = function(enabled)
			db.Filter = enabled and "HARMFUL|PLAYER" or "HARMFUL"
			ApplySettings()
		end,
		Tooltip = "Only show your debuffs (as opposed to the debuffs of everyone).",
	})

	onlyMineChk:SetPoint("TOPLEFT", pointDdl, "BOTTOMLEFT", modernDdl and 0 or 16, -verticalSpacing)

	local anchorWidth = 300
	local arena1 = mini:EditBox({
		Parent = panel,

		LabelText = "Arena 1 Frame",
		Width = anchorWidth,
		GetValue = function()
			return tostring(db.ArenaFrame1Anchor)
		end,
		SetValue = function(v)
			db.ArenaFrame1Anchor = v
			ApplySettings()
		end,
	})

	arena1.Label:SetPoint("TOPLEFT", onlyMineChk, "BOTTOMLEFT", 0, -verticalSpacing)
	arena1.EditBox:SetPoint("TOPLEFT", arena1.Label, "BOTTOMLEFT", 4, -8)

	local arena2 = mini:EditBox({
		Parent = panel,

		LabelText = "Arena 2 Frame",
		Width = anchorWidth,
		GetValue = function()
			return tostring(db.ArenaFrame2Anchor)
		end,
		SetValue = function(v)
			db.ArenaFrame2Anchor = v
			ApplySettings()
		end,
	})

	arena2.Label:SetPoint("TOPLEFT", arena1.EditBox, "BOTTOMLEFT", -4, -verticalSpacing)
	arena2.EditBox:SetPoint("TOPLEFT", arena2.Label, "BOTTOMLEFT", 4, -8)

	local arena3 = mini:EditBox({
		Parent = panel,

		LabelText = "Arena 2 Frame",
		Width = anchorWidth,
		GetValue = function()
			return tostring(db.ArenaFrame3Anchor)
		end,
		SetValue = function(v)
			db.ArenaFrame3Anchor = v
			ApplySettings()
		end,
	})

	arena3.Label:SetPoint("TOPLEFT", arena2.EditBox, "BOTTOMLEFT", -4, -verticalSpacing)
	arena3.EditBox:SetPoint("TOPLEFT", arena3.Label, "BOTTOMLEFT", 4, -8)

	local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	resetBtn:SetSize(120, 26)
	resetBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 16)
	resetBtn:SetText("Reset")
	resetBtn:SetScript("OnClick", function()
		if InCombatLockdown() then
			mini:NotifyCombatLockdown()
			return
		end

		db = mini:ResetSavedVars(dbDefaults)

		panel:MiniRefresh()
		addon:Refresh()
		mini:Notify("Settings reset to default.")
	end)

	local testBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	testBtn:SetSize(120, 26)
	testBtn:SetPoint("LEFT", resetBtn, "RIGHT", 10, 0)
	testBtn:SetText("Test")
	testBtn:SetScript("OnClick", function()
		addon:ToggleTest()
	end)

	panel:SetScript("OnShow", function()
		panel:MiniRefresh()
	end)

	mini:WireTabNavigation({
		iconSize.EditBox,
		iconsPerRow.EditBox,
		rows.EditBox,
		containerX.EditBox,
		containerY.EditBox,
		arena1.EditBox,
		arena2.EditBox,
		arena3.EditBox,
	})

	SLASH_MINIARENADEBUFFS1 = "/miniarenadebuffs"
	SLASH_MINIARENADEBUFFS2 = "/miniad"

	SlashCmdList.MINIARENADEBUFFS = function(msg)
		-- normalize input
		msg = msg and msg:lower():match("^%s*(.-)%s*$") or ""

		if msg == "test" then
			addon:ToggleTest()
			return
		end

		mini:OpenSettings(category, panel)
	end
end
