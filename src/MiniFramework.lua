local addonName, addon = ...
local loader = CreateFrame("Frame")
local loaded = false
local onLoadCallbacks = {}
local dropDownId = 1
local sliderId = 1
local dialog

---@class MiniFramework
local M = {
	VerticalSpacing = 16,
	HorizontalSpacing = 20,
}
addon.Framework = M

local function AddControlForRefresh(panel, control)
	-- store controls for refresh behaviour
	panel.MiniControls = panel.MiniControls or {}
	panel.MiniControls[#panel.MiniControls + 1] = control

	if panel.MiniRefresh then
		return
	end

	panel.MiniRefresh = function(panelSelf)
		for _, c in ipairs(panelSelf.MiniControls or {}) do
			if c.MiniRefresh then
				c:MiniRefresh()
			end
		end
	end
end

local function ConfigureNumbericBox(box, allowNegative)
	if not allowNegative then
		box:SetNumeric(true)
		return
	end

	box:HookScript("OnTextChanged", function(boxSelf, userInput)
		if not userInput then
			return
		end

		local text = boxSelf:GetText()

		-- allow: "", "-", "-123", "123"
		if text == "" or text == "-" or text:match("^%-?%d+$") then
			return
		end

		-- strip invalid chars
		text = text:gsub("[^%d%-]", "")
		-- only one leading '-'
		text = text:gsub("%-+", "-")

		if text:sub(1, 1) ~= "-" then
			text = text:gsub("%-", "")
		else
			text = "-" .. text:sub(2):gsub("%-", "")
		end

		boxSelf:SetText(text)
	end)
end

local function GetOrCreateDialog()
	if dialog then
		return dialog
	end

	dialog = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	dialog:SetSize(360, 140)
	dialog:SetFrameStrata("DIALOG")
	dialog:SetClampedToScreen(true)
	dialog:SetMovable(true)
	dialog:EnableMouse(true)
	dialog:RegisterForDrag("LeftButton")
	dialog:SetScript("OnDragStart", dialog.StartMoving)
	dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
	dialog:Hide()

	dialog:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	dialog:SetBackdropColor(0, 0, 0, 0.9)

	dialog.Text = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
	dialog.Text:SetPoint("TOPLEFT", 12, -12)
	dialog.Text:SetPoint("TOPRIGHT", -12, -12)
	dialog.Text:SetJustifyH("LEFT")
	dialog.Text:SetJustifyV("TOP")

	dialog.CloseButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	dialog.CloseButton:SetSize(80, 22)
	dialog.CloseButton:SetPoint("BOTTOM", 0, 12)
	dialog.CloseButton:SetText(CLOSE)
	dialog.CloseButton:SetScript("OnClick", function()
		dialog:Hide()
	end)

	return dialog
end

function M:Notify(msg, ...)
	local formatted = string.format(msg, ...)
	print(addonName .. " - " .. formatted)
end

function M:NotifyCombatLockdown()
	M:Notify("Can't do that during combat.")
end

function M:CopyTable(src, dst)
	if type(dst) ~= "table" then
		dst = {}
	end

	for k, v in pairs(src) do
		if type(v) == "table" then
			dst[k] = M:CopyTable(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end

	return dst
end

function M:ClampInt(v, minV, maxV, fallback)
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

function M:CanOpenOptionsDuringCombat()
	if LE_EXPANSION_LEVEL_CURRENT == nil or LE_EXPANSION_MIDNIGHT == nil then
		return true
	end

	return LE_EXPANSION_LEVEL_CURRENT < LE_EXPANSION_MIDNIGHT
end

function M:AddCategory(panel)
	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
		Settings.RegisterAddOnCategory(category)

		return category
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)

		return panel
	end

	return nil
end

function M:AddSubCategory(parentCategory, panel)
	if Settings and Settings.RegisterCanvasLayoutSubcategory then
		Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, panel.name)
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	end
end

function M:CreateDivider(parent, text)
	local container = CreateFrame("Frame", nil, parent)
	container:SetHeight(20)

	local leftLine = container:CreateTexture(nil, "ARTWORK")
	leftLine:SetColorTexture(1, 1, 1, 0.15)
	leftLine:SetHeight(1)

	local rightLine = container:CreateTexture(nil, "ARTWORK")
	rightLine:SetColorTexture(1, 1, 1, 0.15)
	rightLine:SetHeight(1)

	local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetText(text or "")
	label:SetPoint("CENTER", container, "CENTER")

	leftLine:SetPoint("LEFT", 16, 0)
	leftLine:SetPoint("RIGHT", label, "LEFT", -8, 0)

	rightLine:SetPoint("LEFT", label, "RIGHT", 8, 0)
	rightLine:SetPoint("RIGHT", -16, 0)

	return container
end

function M:SettingsSize()
	local settingsContainer = SettingsPanel and SettingsPanel.Container

	if settingsContainer then
		return settingsContainer:GetWidth(), settingsContainer:GetHeight()
	end

	if InterfaceOptionsFramePanelContainer then
		return InterfaceOptionsFramePanelContainer:GetWidth(), InterfaceOptionsFramePanelContainer:GetHeight()
	end

	return 600, 600
end

function M:WireTabNavigation(controls)
	for i, control in ipairs(controls) do
		control:EnableKeyboard(true)

		control:SetScript("OnTabPressed", function(ctl)
			if ctl.ClearFocus then
				ctl:ClearFocus()
			end

			if ctl.HighlightText then
				ctl:HighlightText(0, 0)
			end

			local backwards = IsShiftKeyDown()
			local nextIndex = i + (backwards and -1 or 1)

			-- wrap around
			if nextIndex < 1 then
				nextIndex = #controls
			elseif nextIndex > #controls then
				nextIndex = 1
			end

			local next = controls[nextIndex]
			if next then
				if next.SetFocus then
					next:SetFocus()
				end

				if next.HighlightText then
					next:HighlightText()
				end
			end
		end)
	end
end

---Creates an edit box with a label using the specified options.
---@param options EditboxOptions
---@return EditBoxReturn
function M:CreateEditBox(options)
	if not options.Parent or not options.GetValue or not options.SetValue then
		error("Invalid edit box options")
	end

	local label = options.Parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	label:SetText(options.LabelText or "")

	local box = CreateFrame("EditBox", nil, options.Parent, "InputBoxTemplate")
	box:SetSize(options.Width or 80, options.Height or 20)
	box:SetAutoFocus(false)

	if options.Numeric then
		ConfigureNumbericBox(box, options.AllowNegatives)
	end

	local function Commit()
		local new = box:GetText()

		options.SetValue(new)

		local value = options.GetValue() or ""

		box:SetText(tostring(value))
		box:SetCursorPosition(0)
	end

	box:SetScript("OnEnterPressed", function(boxSelf)
		boxSelf:ClearFocus()
		Commit()
	end)

	box:SetScript("OnEditFocusLost", Commit)

	function box.MiniRefresh(boxSelf)
		local value = options.GetValue()
		boxSelf:SetText(tostring(value))
		boxSelf:SetCursorPosition(0)
	end

	box:MiniRefresh()

	AddControlForRefresh(options.Parent, box)

	return { EditBox = box, Label = label }
end

---Creates a dropdown menu using the specified options.
---@param options DropdownOptions
---@return table the dropdown menu control
---@return boolean true if used a modern dropdown, otherwise false
function M:Dropdown(options)
	if not options.Parent or not options.GetValue or not options.SetValue or not options.Items then
		error("Invalid dropdown options")
	end

	if MenuUtil and MenuUtil.CreateRadioMenu then
		local dd = CreateFrame("DropdownButton", nil, options.Parent, "WowStyle1DropdownTemplate")
		dd:SetupMenu(function(_, rootDescription)
			for _, value in ipairs(options.Items) do
				local text = options.GetText and options.GetText(value) or tostring(value)

				rootDescription:CreateRadio(text, function(x)
					return x == options.GetValue()
				end, function()
					options.SetValue(value)
				end, value)
			end
		end)

		function dd.MiniRefresh(ddSelf)
			ddSelf:Update()
		end

		AddControlForRefresh(options.Parent, dd)

		return dd, true
	end

	local libDD = LibStub and LibStub:GetLibrary("LibUIDropDownMenu-4.0", false)

	if libDD then
		-- needs a name to not bug out
		local dd = libDD:Create_UIDropDownMenu("MiniArenaDebuffsDropdown" .. dropDownId, options.Parent)
		dropDownId = dropDownId + 1

		libDD:UIDropDownMenu_Initialize(dd, function()
			for _, value in ipairs(options.Items) do
				local info = libDD:UIDropDownMenu_CreateInfo()
				info.text = options.GetText and options.GetText(value) or tostring(value)
				info.value = value

				info.checked = function()
					return options.GetValue() == value
				end

				local id = dd:GetID(info)

				-- onclick handler
				info.func = function()
					local text = options.GetText and options.GetText(value) or tostring(value)

					libDD:UIDropDownMenu_SetSelectedID(dd, id)
					libDD:UIDropDownMenu_SetText(dd, text)

					options.SetValue(value)
				end

				libDD:UIDropDownMenu_AddButton(info, 1)

				if options.GetValue() == value then
					libDD:UIDropDownMenu_SetSelectedID(dd, id)
				end
			end
		end)

		function dd.MiniRefresh()
			local value = options.GetValue()
			local text = options.GetText and options.GetText(value) or tostring(value)
			libDD:UIDropDownMenu_SetText(dd, text)
		end

		AddControlForRefresh(options.Parent, dd)

		return dd, false
	end

	-- UIDropDownMenuTemplate is nil, but still usable
	if UIDropDownMenu_Initialize then
		local dd = CreateFrame("Frame", name, options.Parent, "UIDropDownMenuTemplate")

		UIDropDownMenu_Initialize(dd, function()
			for _, value in ipairs(options.Items) do
				local info = UIDropDownMenu_CreateInfo()
				info.text = options.GetText and options.GetText(value) or tostring(value)
				info.value = value

				info.checked = function()
					return options.GetValue() == value
				end

				-- onclick handler
				info.func = function()
					local text = options.GetText and options.GetText(value) or tostring(value)
					local id = dd:GetID(info)

					UIDropDownMenu_SetSelectedID(dd, id)
					UIDropDownMenu_SetText(dd, text)

					setSelected(value)
				end

				UIDropDownMenu_AddButton(info, 1)

				if getValue() == value then
					local id = dd:GetID(info)
					UIDropDownMenu_SetSelectedID(dd, id)
				end
			end
		end)

		function dd.MiniRefresh()
			local value = options.GetValue()
			local text = options.GetText and options.GetText(value) or tostring(value)
			UIDropDownMenu_SetText(dd, text)
		end

		AddControlForRefresh(options.Parent, dd)

		return dd, false
	end

	error("Failed to create a dropdown control")
end

---Creates a checkbox using the specified options.
---@param options CheckboxOptions
---@return table checkbox
function M:CreateSettingCheckbox(options)
	if not options or not options.Parent or not options.GetValue or not options.SetValue then
		error("Invalid checkbox settings")
	end

	local checkbox = CreateFrame("CheckButton", nil, options.Parent, "UICheckButtonTemplate")
	checkbox.Text:SetText(" " .. options.LabelText)
	checkbox.Text:SetFontObject("GameFontNormal")
	checkbox:SetChecked(options.GetValue())
	checkbox:HookScript("OnClick", function()
		options.SetValue(checkbox:GetChecked())

		-- check the value changed at the source
		checkbox:SetChecked(options.GetValue())
	end)

	if options.Tooltip then
		checkbox:SetScript("OnEnter", function(chkSelf)
			GameTooltip:SetOwner(chkSelf, "ANCHOR_RIGHT")
			GameTooltip:SetText(options.LabelText, 1, 0.82, 0)
			GameTooltip:AddLine(options.Tooltip, 1, 1, 1, true)
			GameTooltip:Show()
		end)

		checkbox:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
	end

	function checkbox.MiniRefresh()
		checkbox:SetChecked(options.GetValue())
	end

	AddControlForRefresh(options.Parent, checkbox)

	return checkbox
end

---Creates a slider using the specified options.
---@param options SliderOptions
---@return SliderReturn
function M:CreateSlider(options)
	if
		not options.Parent
		or not options.GetValue
		or not options.SetValue
		or not options.Min
		or not options.Max
		or not options.Step
	then
		error("Invalid slider options")
	end

	local slider = CreateFrame("Slider", addonName .. "Slider" .. sliderId, options.Parent, "OptionsSliderTemplate")
	sliderId = sliderId + 1

	local label = slider:CreateFontString(nil, "ARTWORK", "GameFontWhite")
	label:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 8)
	label:SetText(options.LabelText)

	slider:SetOrientation("HORIZONTAL")
	slider:SetMinMaxValues(options.Min, options.Max)
	slider:SetValue(options.GetValue())
	slider:SetValueStep(options.Step)
	slider:SetObeyStepOnDrag(true)
	slider:SetHeight(20)
	slider:SetWidth(options.Width or 400)

	local low = _G[slider:GetName() .. "Low"]
	local high = _G[slider:GetName() .. "High"]

	if low and high then
		low:SetText(options.Min)
		high:SetText(options.Max)
	end

	local box = CreateFrame("EditBox", nil, options.Parent, "InputBoxTemplate")
	ConfigureNumbericBox(box, options.Min < 0)

	box:SetPoint("CENTER", slider, "CENTER", 0, 30)
	box:SetFontObject("GameFontWhite")
	box:SetSize(50, 20)
	box:SetAutoFocus(false)
	box:SetMaxLetters(math.log(options.Max, 10) + 1)
	box:SetText(tostring(options.GetValue()))
	box:SetJustifyH("CENTER")
	box:SetCursorPosition(0)

	slider:SetScript("OnValueChanged", function(_, sliderValue, userInput)
		if userInput ~= nil and not userInput then
			return
		end

		box:SetText(tostring(sliderValue))

		options.SetValue(sliderValue)
	end)

	box:SetScript("OnTextChanged", function(_, userInput)
		if not userInput then
			return
		end

		local value = tonumber(box:GetText())

		-- don't clamp values here, because they might still be typing out a number
		if not value then
			return
		end

		slider:SetValue(value)
		options.SetValue(value)
	end)

	function box.MiniRefresh(boxSelf)
		local value = options.GetValue()
		boxSelf:SetText(tostring(value))
		boxSelf:SetCursorPosition(0)
	end

	function slider.MiniRefresh(sliderSelf)
		local value = options.GetValue()
		sliderSelf:SetValue(value)
	end

	AddControlForRefresh(options.Parent, slider)
	AddControlForRefresh(options.Parent, box)

	return { Slider = slider, EditBox = box, Label = label }
end

---@param text string
---@param width number?
---@param height number?
function M:ShowDialog(text, width, height)
	local dlg = GetOrCreateDialog()

	if width then
		dlg:SetWidth(width)
	end

	if height then
		dlg:SetHeight(height)
	end

	dlg.Text:SetText(text)

	dlg:ClearAllPoints()
	dlg:SetPoint("CENTER", UIParent, "CENTER")

	dlg:Show()
end

function M:HideDialog()
	if dialog then
		dialog:Hide()
	end
end

function M:RegisterSlashCommand(category, panel)
	local upper = string.upper(addonName)

	SlashCmdList[upper] = function()
		M:OpenSettings(category, panel)
	end
end

function M:OpenSettings(category, panel)
	if Settings and Settings.OpenToCategory then
		if not InCombatLockdown() or M:CanOpenOptionsDuringCombat() then
			Settings.OpenToCategory(category:GetID())
		else
			M:NotifyCombatLockdown()
		end
	elseif InterfaceOptionsFrame_OpenToCategory then
		-- workaround the classic bug where the first call opens the Game interface
		-- and a second call is required
		InterfaceOptionsFrame_OpenToCategory(panel)
		InterfaceOptionsFrame_OpenToCategory(panel)
	end
end

function M:WaitForAddonLoad(callback)
	onLoadCallbacks[#onLoadCallbacks + 1] = callback

	if loaded then
		callback()
	end
end

function M:GetSavedVars(defaults)
	local name = addonName .. "DB"
	local vars = _G[name] or {}

	_G[name] = vars

	if defaults then
		return M:CopyTable(defaults, vars)
	end

	return vars
end

function M:ResetSavedVars(defaults)
	local name = addonName .. "DB"
	local vars = _G[name] or {}

	-- don't create a new table because we're referencing that in the addon
	-- instead clear the existing keys and return the same instance (if one existed to begin with)
	for k in pairs(vars) do
		vars[k] = nil
	end

	if defaults then
		return M:CopyTable(defaults, vars)
	end

	return vars
end

function M:ColumnWidth(columns, padding, spacingColumns)
	local settingsWidth, _ = M:SettingsSize()
	-- add padding to the left and right
	local usableWidth = settingsWidth - (padding * 2)
	local width = math.floor(usableWidth / (columns + spacingColumns))

	return width
end

local function OnAddonLoaded(_, _, name)
	if name ~= addonName then
		return
	end

	loaded = true
	loader:UnregisterEvent("ADDON_LOADED")

	for _, callback in ipairs(onLoadCallbacks) do
		callback()
	end
end

loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", OnAddonLoaded)

---@class CheckboxOptions
---@field Parent table
---@field LabelText string
---@field Tooltip string?
---@field GetValue fun(): boolean
---@field SetValue fun(value: boolean)

---@class EditboxOptions
---@field Parent table
---@field LabelText string
---@field Tooltip string?
---@field Numeric boolean?
---@field AllowNegatives boolean?
---@field Width number?
---@field Height number?
---@field GetValue fun(): string|number
---@field SetValue fun(value: string|number)

---@class EditBoxReturn
---@field EditBox table
---@field Label table

---@class SliderReturn
---@field Label table
---@field EditBox table
---@field Slider table

---@class DropdownOptions
---@field Parent table
---@field Items any[]
---@field Tooltip string?
---@field GetValue fun(): string
---@field SetValue fun(value: string)
---@field GetText? fun(value: any): string

---@class SliderOptions
---@field Parent table
---@field LabelText string
---@field Tooltip string?
---@field Min number
---@field Max number
---@field Step number
---@field Width number?
---@field GetValue fun(): number
---@field SetValue fun(value: number)
