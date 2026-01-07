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

	local iconSizeLbl, iconSizeBox = mini:CreateEditBox(panel, true, "Icon Size", 80, function()
		return db.IconSize
	end, function(v)
		db.IconSize = ClampInt(v, 10, 80, dbDefaults.IconSize)
	end)

	iconSizeLbl:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -verticalSpacing)
	iconSizeBox:SetPoint("TOPLEFT", iconSizeLbl, "BOTTOMLEFT", 4, -4)

	local iconsPerRowLbl, iconsPerRowBox = mini:CreateEditBox(panel, true, "Icons Per Row", 80, function()
		return db.IconsPerRow
	end, function(v)
		db.IconsPerRow = ClampInt(v, 1, 10, dbDefaults.IconsPerRow)
		ApplySettings()
	end)

	iconsPerRowLbl:SetPoint("LEFT", iconSizeBox, "RIGHT", horizontalSpacing, iconSizeBox:GetHeight())
	iconsPerRowBox:SetPoint("TOPLEFT", iconsPerRowLbl, "BOTTOMLEFT", 4, -4)

	local rowsLbl, rowsBox = mini:CreateEditBox(panel, true, "Rows", 80, function()
		return db.Rows
	end, function(v)
		db.Rows = ClampInt(v, 1, 5, dbDefaults.Rows)
		ApplySettings()
	end)

	rowsLbl:SetPoint("LEFT", iconsPerRowBox, "RIGHT", horizontalSpacing, iconsPerRowBox:GetHeight())
	rowsBox:SetPoint("TOPLEFT", rowsLbl, "BOTTOMLEFT", 4, -4)

	local containerXLbl, containerXBox = mini:CreateEditBox(panel, true, "Offset X", 80, function()
		return db.ContainerOffsetX
	end, function(v)
		db.ContainerOffsetX = ClampInt(v, -200, 200, dbDefaults.ContainerOffsetX)
		ApplySettings()
	end)

	containerXLbl:SetPoint("TOPLEFT", iconSizeBox, "BOTTOMLEFT", -4, -verticalSpacing)
	containerXBox:SetPoint("TOPLEFT", containerXLbl, "BOTTOMLEFT", 4, -4)

	local containerYLbl, containerYBox = mini:CreateEditBox(panel, true, "Offset Y", 80, function()
		return db.ContainerOffsetY
	end, function(v)
		db.ContainerOffsetY = ClampInt(v, -200, 200, dbDefaults.ContainerOffsetY)
		ApplySettings()
	end)

	containerYLbl:SetPoint("LEFT", containerXBox, "RIGHT", horizontalSpacing, containerXBox:GetHeight())
	containerYBox:SetPoint("TOPLEFT", containerYLbl, "BOTTOMLEFT", 4, -4)

	local pointDdlLbl = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	pointDdlLbl:SetText("Anchor Point")

	local pointDdl, modernDdl = mini:Dropdown(panel, anchorPoints, function()
		return db.ContainerAnchorPoint
	end, function(value)
		if db.ContainerAnchorPoint ~= value then
			db.ContainerAnchorPoint = value
			ApplySettings()
		end
	end)

	pointDdl:SetWidth(dropdownWidth)
	pointDdlLbl:SetPoint("TOPLEFT", containerXBox, "BOTTOMLEFT", -4, -verticalSpacing)
	-- no idea why by default it's off by 16 points
	pointDdl:SetPoint("TOPLEFT", pointDdlLbl, "BOTTOMLEFT", modernDdl and 0 or -16, -8)

	local relativeToLbl = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	relativeToLbl:SetText("Relative to")

	local relativeToDdl = mini:Dropdown(panel, anchorPoints, function()
		return db.ContainerRelativePoint
	end, function(value)
		if db.ContainerRelativePoint ~= value then
			db.ContainerRelativePoint = value
			ApplySettings()
		end
	end)

	relativeToDdl:SetWidth(dropdownWidth)
	relativeToDdl:SetPoint("LEFT", pointDdl, "RIGHT", horizontalSpacing, 0)
	relativeToLbl:SetPoint("BOTTOMLEFT", relativeToDdl, "TOPLEFT", 0, 8)

	local onlyMineChk = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	onlyMineChk:SetPoint("TOPLEFT", pointDdl, "BOTTOMLEFT", modernDdl and 0 or 16, -verticalSpacing)
	onlyMineChk.Text:SetText("Only my debuffs")
	onlyMineChk.Text:SetFontObject("GameFontWhite")
	onlyMineChk:SetChecked((db.Filter or ""):find("PLAYER") ~= nil)
	onlyMineChk:SetScript("OnClick", function()
		db.Filter = onlyMineChk:GetChecked() and "HARMFUL|PLAYER" or "HARMFUL"
		ApplySettings()
	end)
	onlyMineChk.Refresh = function()
		local checked = (db.Filter or ""):find("PLAYER") ~= nil
		onlyMineChk:SetChecked(checked)
	end

	local anchorWidth = 300
	local arena1AnchorLbl, arena1AnchorBox = mini:CreateEditBox(panel, false, "Arena 1 Frame", anchorWidth, function()
		return db.ArenaFrame1Anchor
	end, function(v)
		db.ArenaFrame1Anchor = v
		ApplySettings()
	end)

	arena1AnchorLbl:SetPoint("TOPLEFT", onlyMineChk, "BOTTOMLEFT", 0, -verticalSpacing)
	arena1AnchorBox:SetPoint("TOPLEFT", arena1AnchorLbl, "BOTTOMLEFT", 4, -8)

	local arena2AnchorLbl, arena2AnchorBox = mini:CreateEditBox(panel, false, "Arena 2 Frame", anchorWidth, function()
		return db.ArenaFrame2Anchor
	end, function(v)
		db.ArenaFrame2Anchor = v
		ApplySettings()
	end)

	arena2AnchorLbl:SetPoint("TOPLEFT", arena1AnchorBox, "BOTTOMLEFT", -4, -verticalSpacing)
	arena2AnchorBox:SetPoint("TOPLEFT", arena2AnchorLbl, "BOTTOMLEFT", 4, -8)

	local arena3AnchorLbl, arena3AnchorBox = mini:CreateEditBox(panel, false, "Arena 3 Frame", anchorWidth, function()
		return db.ArenaFrame3Anchor
	end, function(v)
		db.ArenaFrame3Anchor = v
		ApplySettings()
	end)

	arena3AnchorLbl:SetPoint("TOPLEFT", arena2AnchorBox, "BOTTOMLEFT", -4, -verticalSpacing)
	arena3AnchorBox:SetPoint("TOPLEFT", arena3AnchorLbl, "BOTTOMLEFT", 4, -8)

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
		iconSizeBox,
		iconsPerRowBox,
		rowsBox,
		containerXBox,
		containerYBox,
		arena1AnchorBox,
		arena2AnchorBox,
		arena3AnchorBox
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

		if Settings and Settings.OpenToCategory then
			if not InCombatLockdown() or CanOpenOptionsDuringCombat() then
				Settings.OpenToCategory(category:GetID())
			else
				mini:NotifyCombatLockdown()
			end
		elseif InterfaceOptionsFrame_OpenToCategory then
			-- workaround the classic bug where the first call opens the Game interface
			-- and a second call is required
			InterfaceOptionsFrame_OpenToCategory(panel)
			InterfaceOptionsFrame_OpenToCategory(panel)
		end
	end
end
