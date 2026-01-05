local addonName, addon = ...
local verticalSpacing = 16
local horizontalSpacing = 20
local dropDownId = 0
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

local function CopyTable(src, dst)
	if type(dst) ~= "table" then
		dst = {}
	end
	for k, v in pairs(src) do
		if type(v) == "table" then
			dst[k] = CopyTable(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

local function ClampInt(v, minV, maxV, fallback)
	v = tonumber(v)
	if not v then
		return fallback
	end
	v = math.floor(v + 0.5)
	if v < minV then
		return minV
	end
	if v > maxV then
		return maxV
	end
	return v
end

function CanOpenOptionsDuringCombat()
	if LE_EXPANSION_LEVEL_CURRENT == nil or LE_EXPANSION_MIDNIGHT == nil then
		return true
	end

	return LE_EXPANSION_LEVEL_CURRENT < LE_EXPANSION_MIDNIGHT
end

local function AddCategory(panel)
	if Settings and Settings.RegisterCanvasLayoutCategory then
		local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
		Settings.RegisterAddOnCategory(category)
		return category
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
		return panel
	end
end

local function ApplySettings()
	if InCombatLockdown() then
		addon:Notify("Can't apply settings during combat.")
		return
	end

	addon:Refresh()
end

local function CreateEditBox(parent, numeric, labelText, width, getValue, setValue)
	local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	label:SetText(labelText)

	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(width or 80, 20)
	box:SetAutoFocus(false)

	if numeric then
		box:SetNumeric(true)
	end

	local function Commit()
		local old = tostring(getValue())
		local new = box:GetText()

		setValue(new)

		if tostring(getValue()) ~= old then
			ApplySettings()
		end

		box:SetText(tostring(getValue()))
		box:SetCursorPosition(0)
	end

	box:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		Commit()
	end)

	box:SetScript("OnEditFocusLost", Commit)

	function box:Refresh()
		box:SetText(tostring(getValue()))
		box:SetCursorPosition(0)
	end

	box:Refresh()

	return label, box
end

local function Dropdown(parent, items, getValue, setSelected, getText)
	local function HasModernDropdown()
		return WowStyle1DropdownTemplate ~= nil
	end

	if HasModernDropdown() then
		local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
		dd:SetupMenu(function(_, rootDescription)
			for _, value in ipairs(items) do
				rootDescription:CreateRadio(getText and getText(value) or tostring(value), function(x)
					return x == getValue()
				end, function()
					setSelected(value)
				end, value)
			end
		end)

		function dd.Refresh(ddSelf)
			ddSelf:Update()
		end

		return dd
	elseif LibStub then
		local libDD = LibStub:GetLibrary("LibUIDropDownMenu-4.0")
		-- needs a name to not bug out
		local dd = libDD:Create_UIDropDownMenu("MiniArenaDebuffsDropdown" .. dropDownId, parent)
		dropDownId = dropDownId + 1

		libDD:UIDropDownMenu_Initialize(dd, function()
			for _, value in ipairs(items) do
				local info = libDD:UIDropDownMenu_CreateInfo()
				info.text = getText and getText(value) or tostring(value)
				info.value = value

				info.checked = function()
					return getValue() == value
				end

				-- onclick handler
				info.func = function()
					libDD:UIDropDownMenu_SetSelectedID(dd, dd:GetID(info))
					libDD:UIDropDownMenu_SetText(dd, getText and getText(value) or tostring(value))
					setSelected(value)
				end

				libDD:UIDropDownMenu_AddButton(info, 1)

				-- if the config value matches this value, then set it as the selected item
				if getValue() == value then
					libDD:UIDropDownMenu_SetSelectedID(dd, dd:GetID(info))
				end
			end
		end)

		function dd.Refresh()
			local value = getValue()
			local text = getText and getText(value) or tostring(value)
			libDD:UIDropDownMenu_SetText(dd, text)
		end

		return dd
	else
		error("Failed to create dropdown menu.")
	end
end

local function SettingsSize()
	local settingsContainer = SettingsPanel and SettingsPanel.Container

	if settingsContainer then
		return settingsContainer:GetWidth(), settingsContainer:GetHeight()
	end

	if InterfaceOptionsFramePanelContainer then
		return InterfaceOptionsFramePanelContainer:GetWidth(), InterfaceOptionsFramePanelContainer:GetHeight()
	end

	return 600, 600
end

function M:Init()
	MiniArenaDebuffsDB = MiniArenaDebuffsDB or {}
	db = CopyTable(dbDefaults, MiniArenaDebuffsDB)

	local scroll = CreateFrame("ScrollFrame", nil, nil, "UIPanelScrollFrameTemplate")
	scroll.name = addonName

	local category = AddCategory(scroll)

	if not category then
		return
	end

	local panel = CreateFrame("Frame", nil, scroll)
	local width, height = SettingsSize()

	panel:SetWidth(width)
	panel:SetHeight(height)

	scroll:SetScrollChild(panel)

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 0, -16)
	title:SetText(addonName)

	local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontWhite")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	subtitle:SetText("Shows debuffs on arena frames.")

	local iconSizeLbl, iconSizeBox = CreateEditBox(panel, true, "Icon Size", 80, function()
		return db.IconSize
	end, function(v)
		db.IconSize = ClampInt(v, 10, 80, dbDefaults.IconSize)
	end)

	iconSizeLbl:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -verticalSpacing)
	iconSizeBox:SetPoint("TOPLEFT", iconSizeLbl, "BOTTOMLEFT", 4, -4)

	local iconsPerRowLbl, iconsPerRowBox = CreateEditBox(panel, true, "Icons Per Row", 80, function()
		return db.IconsPerRow
	end, function(v)
		db.IconsPerRow = ClampInt(v, 1, 10, dbDefaults.IconsPerRow)
	end)

	iconsPerRowLbl:SetPoint("LEFT", iconSizeBox, "RIGHT", horizontalSpacing, iconSizeBox:GetHeight())
	iconsPerRowBox:SetPoint("TOPLEFT", iconsPerRowLbl, "BOTTOMLEFT", 4, -4)

	local rowsLbl, rowsBox = CreateEditBox(panel, true, "Rows", 80, function()
		return db.Rows
	end, function(v)
		db.Rows = ClampInt(v, 1, 5, dbDefaults.Rows)
	end)

	rowsLbl:SetPoint("LEFT", iconsPerRowBox, "RIGHT", horizontalSpacing, iconsPerRowBox:GetHeight())
	rowsBox:SetPoint("TOPLEFT", rowsLbl, "BOTTOMLEFT", 4, -4)

	local containerXLbl, containerXBox = CreateEditBox(panel, true, "Offset X", 80, function()
		return db.ContainerOffsetX
	end, function(v)
		db.ContainerOffsetX = ClampInt(v, -200, 200, dbDefaults.ContainerOffsetX)
	end)

	containerXLbl:SetPoint("TOPLEFT", iconSizeBox, "BOTTOMLEFT", -4, -verticalSpacing)
	containerXBox:SetPoint("TOPLEFT", containerXLbl, "BOTTOMLEFT", 4, -4)

	local containerYLbl, containerYBox = CreateEditBox(panel, true, "Offset Y", 80, function()
		return db.ContainerOffsetY
	end, function(v)
		db.ContainerOffsetY = ClampInt(v, -200, 200, dbDefaults.ContainerOffsetY)
	end)

	containerYLbl:SetPoint("LEFT", containerXBox, "RIGHT", horizontalSpacing, containerXBox:GetHeight())
	containerYBox:SetPoint("TOPLEFT", containerYLbl, "BOTTOMLEFT", 4, -4)

	local pointDdlLbl = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	pointDdlLbl:SetText("Anchor Point")

	local pointDdl = Dropdown(panel, anchorPoints, function()
		return db.ContainerAnchorPoint
	end, function(value)
		if db.ContainerAnchorPoint ~= value then
			db.ContainerAnchorPoint = value
			ApplySettings()
		end
	end)

	pointDdlLbl:SetPoint("TOPLEFT", containerXBox, "BOTTOMLEFT", -4, -verticalSpacing)
	-- no idea why by default it's off by 16 points
	pointDdl:SetPoint("TOPLEFT", pointDdlLbl, "BOTTOMLEFT", -16, -8)

	local relativeToLbl = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	relativeToLbl:SetText("Relative to")

	local relativeToDdl = Dropdown(panel, anchorPoints, function()
		return db.ContainerRelativePoint
	end, function(value)
		if db.ContainerRelativePoint ~= value then
			db.ContainerRelativePoint = value
			ApplySettings()
		end
	end)

	relativeToLbl:SetPoint("LEFT", pointDdlLbl, "RIGHT", pointDdl:GetWidth() + horizontalSpacing * 2, 0)
	relativeToDdl:SetPoint("TOPLEFT", relativeToLbl, "BOTTOMLEFT", -16, -8)

	local onlyMineChk = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	onlyMineChk:SetPoint("TOPLEFT", pointDdl, "BOTTOMLEFT", 16, -verticalSpacing)
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
	local arena1AnchorLbl, arena1AnchorBox = CreateEditBox(panel, false, "Arena 1 Frame", anchorWidth, function()
		return db.ArenaFrame1Anchor
	end, function(v)
		db.ArenaFrame1Anchor = v
		ApplySettings()
	end)

	arena1AnchorLbl:SetPoint("TOPLEFT", onlyMineChk, "BOTTOMLEFT", 0, -verticalSpacing)
	arena1AnchorBox:SetPoint("TOPLEFT", arena1AnchorLbl, "BOTTOMLEFT", 4, -8)

	local arena2AnchorLbl, arena2AnchorBox = CreateEditBox(panel, false, "Arena 2 Frame", anchorWidth, function()
		return db.ArenaFrame2Anchor
	end, function(v)
		db.ArenaFrame2Anchor = v
		ApplySettings()
	end)

	arena2AnchorLbl:SetPoint("TOPLEFT", arena1AnchorBox, "BOTTOMLEFT", -4, -verticalSpacing)
	arena2AnchorBox:SetPoint("TOPLEFT", arena2AnchorLbl, "BOTTOMLEFT", 4, -8)

	local arena3AnchorLbl, arena3AnchorBox = CreateEditBox(panel, false, "Arena 3 Frame", anchorWidth, function()
		return db.ArenaFrame3Anchor
	end, function(v)
		db.ArenaFrame3Anchor = v
		ApplySettings()
	end)

	arena3AnchorLbl:SetPoint("TOPLEFT", arena2AnchorBox, "BOTTOMLEFT", -4, -verticalSpacing)
	arena3AnchorBox:SetPoint("TOPLEFT", arena3AnchorLbl, "BOTTOMLEFT", 4, -8)

	panel.Controls = {
		iconSizeBox,
		iconsPerRowBox,
		rowsBox,
		containerXBox,
		containerYBox,
		pointDdl,
		relativeToDdl,
		onlyMineChk,
		arena1AnchorBox,
		arena2AnchorBox,
		arena3AnchorBox,
	}

	function panel.Refresh()
		for _, c in ipairs(panel.Controls) do
			if c.Refresh then
				c:Refresh()
			end
		end
	end

	local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	resetBtn:SetSize(120, 26)
	resetBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 16)
	resetBtn:SetText("Reset")
	resetBtn:SetScript("OnClick", function()
		if InCombatLockdown() then
			addon:Notify("Can't reset during combat.")
			return
		end

		for k in pairs(db) do
			db[k] = nil
		end
		db = CopyTable(dbDefaults, db)
		MiniArenaDebuffsDB = db

		addon:Refresh()
		panel:Refresh()
		addon:Notify("Settings reset to default.")
	end)

	local testBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	testBtn:SetSize(120, 26)
	testBtn:SetPoint("LEFT", resetBtn, "RIGHT", 10, 0)
	testBtn:SetText("Test")
	testBtn:SetScript("OnClick", function()
		addon:ToggleTest()
	end)

	panel:SetScript("OnShow", function()
		panel:Refresh()
	end)

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
				addon:Notify("Can't open options during combat.")
			end
		elseif InterfaceOptionsFrame_OpenToCategory then
			-- workaround the classic bug where the first call opens the Game interface
			-- and a second call is required
			InterfaceOptionsFrame_OpenToCategory(panel)
			InterfaceOptionsFrame_OpenToCategory(panel)
		end
	end
end
