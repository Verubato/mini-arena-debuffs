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
	TextMaxWidth = 600,
}
addon.Framework = M

local function AddControlForRefresh(panel, control)
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

		if panel.OnMiniRefresh then
			panel:OnMiniRefresh()
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

		if text == "" or text == "-" or text:match("^%-?%d+$") then
			return
		end

		text = text:gsub("[^%d%-]", "")
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

	dialog.Title = dialog:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	dialog.Title:SetPoint("TOP", dialog, "TOP", 0, -8)
	dialog.Title:SetText("Notification")
	dialog.Title:SetTextColor(1, 0.82, 0)

	dialog.TitleDivider = dialog:CreateTexture(nil, "ARTWORK")
	dialog.TitleDivider:SetHeight(1)
	dialog.TitleDivider:SetPoint("TOPLEFT", dialog, "TOPLEFT", 8, -28)
	dialog.TitleDivider:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -8, -28)
	dialog.TitleDivider:SetColorTexture(1, 1, 1, 0.15)

	dialog.Text = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
	dialog.Text:SetPoint("TOPLEFT", 12, -40)
	dialog.Text:SetPoint("TOPRIGHT", -12, -40)
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

local function NilKeys(target)
	for k, v in pairs(target) do
		if type(v) == "table" then
			NilKeys(v)
		else
			target[k] = nil
		end
	end
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

function M:CopyValueOrTable(src)
	if type(src) ~= "table" then
		return src
	end

	return M:CopyTable(src)
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

function M:ClampFloat(v, minV, maxV, fallback)
	v = tonumber(v)

	if not v then
		return fallback
	end

	if v < minV then
		return minV
	end

	if v > maxV then
		return maxV
	end

	return v
end

function M:IsSecret(value)
	if not issecretvalue then
		return false
	end

	return issecretvalue(value)
end

function M:CanOpenOptionsDuringCombat()
	if LE_EXPANSION_LEVEL_CURRENT == nil or LE_EXPANSION_MIDNIGHT == nil then
		return true
	end

	return LE_EXPANSION_LEVEL_CURRENT < LE_EXPANSION_MIDNIGHT
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

function M:AddCategory(panel)
	if not panel then
		error("AddCategory - panel must not be nil.")
	end

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
	if not parentCategory then
		error("AddSubCategory - parentCategory must not be nil.")
	end

	if not panel then
		error("AddSubCategory - panel must not be nil.")
	end

	if Settings and Settings.RegisterCanvasLayoutSubcategory then
		Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, panel.name)
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	end
end

function M:WireTabNavigation(controls)
	if not controls then
		error("WireTabNavigation - controls must not be nil")
	end

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

---@param options TextLineOptions
---@return table control
function M:TextLine(options)
	if not options then
		error("TextLine - options must not be nil.")
	end

	if not options.Parent then
		error("TextLine - invalid options.")
	end

	local fstring = options.Parent:CreateFontString(nil, "ARTWORK", options.Font or "GameFontWhite")
	fstring:SetSpacing(0)
	fstring:SetWidth(M.TextMaxWidth)
	fstring:SetJustifyH("LEFT")
	fstring:SetText(options.Text or "")

	return fstring
end

---@param options TextBlockOptions
---@return table container
function M:TextBlock(options)
	if not options then
		error("TextBlock - options must not be nil.")
	end

	if not options.Parent or not options.Lines then
		error("TextBlock - invalid options.")
	end

	local verticalSpacing = options.VerticalSpacing or M.VerticalSpacing
	local container = CreateFrame("Frame", nil, options.Parent)
	container:SetWidth(M.TextMaxWidth)

	local anchor
	local totalHeight = 0

	for i, line in ipairs(options.Lines) do
		local fstring = M:TextLine({
			Text = line,
			Parent = container,
			Font = options.Font,
		})

		local gap = (i == 1) and 0 or (verticalSpacing / 2)

		if i == 1 then
			fstring:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
			totalHeight = totalHeight + fstring:GetStringHeight()
		else
			fstring:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
			totalHeight = totalHeight + gap + fstring:GetStringHeight()
		end

		anchor = fstring
	end

	container:SetHeight(math.max(1, totalHeight))

	return container
end

---Creates a horizontal line with a label.
---@param options DividerOptions
---@return table
function M:Divider(options)
	if not options then
		error("Divider - options must not be nil.")
	end

	if not options.Parent then
		error("Divider - invalid options.")
	end

	local container = CreateFrame("Frame", nil, options.Parent)
	container:SetHeight(26)

	local leftLine = container:CreateTexture(nil, "ARTWORK")
	leftLine:SetColorTexture(1, 1, 1, 0.15)
	PixelUtil.SetHeight(leftLine, 1)

	local rightLine = container:CreateTexture(nil, "ARTWORK")
	rightLine:SetColorTexture(1, 1, 1, 0.15)
	PixelUtil.SetHeight(rightLine, 1)

	local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	label:SetText(options.Text or "")
	label:SetTextColor(1, 1, 1, 1)
	label:SetPoint("CENTER", container, "CENTER")

	PixelUtil.SetPoint(leftLine, "LEFT", container, "LEFT", 0, 0)
	PixelUtil.SetPoint(leftLine, "RIGHT", label, "LEFT", -8, 0)

	PixelUtil.SetPoint(rightLine, "LEFT", label, "RIGHT", 8, 0)
	PixelUtil.SetPoint(rightLine, "RIGHT", container, "RIGHT", 0, 0)

	return container
end

---Creates an edit box with a label using the specified options.
---@param options EditboxOptions
---@return EditBoxReturn
function M:EditBox(options)
	if not options then
		error("EditBox - options must not be nil.")
	end

	if not options.Parent or not options.GetValue or not options.SetValue then
		error("EditBox - invalid options.")
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
	if not options then
		error("Dropdown - options must not be nil.")
	end

	if not options.Parent or not options.GetValue or not options.SetValue or not options.Items then
		error("Dropdown - invalid options.")
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
			local value = options.GetValue()
			local text = options.GetText and options.GetText(value) or tostring(value)
			ddSelf:SetText(text)
		end

		AddControlForRefresh(options.Parent, dd)

		return dd, true
	end

	local libDD = LibStub and LibStub:GetLibrary("LibUIDropDownMenu-4.0", true)

	if libDD then
		local dd = libDD:Create_UIDropDownMenu(addonName .. "Dropdown" .. dropDownId, options.Parent)
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

	if UIDropDownMenu_Initialize then
		local dd = CreateFrame("Frame", addonName .. "Dropdown" .. dropDownId, options.Parent, "UIDropDownMenuTemplate")
		dropDownId = dropDownId + 1

		UIDropDownMenu_Initialize(dd, function()
			for _, value in ipairs(options.Items) do
				local info = UIDropDownMenu_CreateInfo()
				info.text = options.GetText and options.GetText(value) or tostring(value)
				info.value = value

				info.checked = function()
					return options.GetValue() == value
				end

				info.func = function()
					local text = options.GetText and options.GetText(value) or tostring(value)
					local id = dd:GetID(info)

					UIDropDownMenu_SetSelectedID(dd, id)
					UIDropDownMenu_SetText(dd, text)

					options.SetValue(value)
				end

				UIDropDownMenu_AddButton(info, 1)

				if options.GetValue() == value then
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
function M:Checkbox(options)
	if not options then
		error("Checkbox - options must not be nil.")
	end

	if not options or not options.Parent or not options.GetValue or not options.SetValue then
		error("Checkbox - invalid options.")
	end

	local checkbox = CreateFrame("CheckButton", nil, options.Parent, "UICheckButtonTemplate")
	checkbox.Text:SetText(" " .. options.LabelText)
	checkbox.Text:SetFontObject("GameFontNormal")
	checkbox:SetChecked(options.GetValue())
	checkbox:HookScript("OnClick", function()
		options.SetValue(checkbox:GetChecked())

		checkbox:SetChecked(options.GetValue())
	end)

	if options.Tooltip then
		checkbox:SetScript("OnEnter", function(chkSelf)
			GameTooltip:SetOwner(chkSelf, "ANCHOR_RIGHT")
			local tooltipTitle = options.LabelText
			if not tooltipTitle or tooltipTitle:match("^%s*$") then
				tooltipTitle = "Information"
			end
			GameTooltip:SetText(tooltipTitle, 1, 0.82, 0)
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
function M:Slider(options)
	if not options then
		error("Slider - options must not be nil.")
	end

	if
		not options.Parent
		or not options.GetValue
		or not options.SetValue
		or not options.Min
		or not options.Max
		or not options.Step
	then
		error("Slider - invalid options.")
	end

	local slider = CreateFrame("Slider", addonName .. "Slider" .. sliderId, options.Parent, "OptionsSliderTemplate")
	sliderId = sliderId + 1

	local label = slider:CreateFontString(nil, "ARTWORK", "GameFontNormal")
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

	local text = _G[slider:GetName() .. "Text"]
	if text then
		text:Hide()
	end

	local hasFloat = math.floor(options.Step) ~= options.Step

	local function GetDecimalPlaces(step)
		local s = tostring(step)
		local dot = s:find("%.")
		if not dot then
			return 0
		end
		return #s - dot
	end

	local function GetMaxLetters(min, max, step)
		local decimals = GetDecimalPlaces(step)
		local maxAbs = math.max(math.abs(min), math.abs(max))
		local intDigits = #tostring(math.floor(maxAbs))
		local letters = intDigits
		if decimals > 0 then
			letters = letters + 1 + decimals
		end
		if min < 0 then
			letters = letters + 1
		end
		return letters
	end

	local box = CreateFrame("EditBox", nil, slider, "InputBoxTemplate")

	if not hasFloat then
		ConfigureNumbericBox(box, options.Min < 0)
	end

	box:SetPoint("CENTER", slider, "CENTER", 0, 30)
	box:SetFontObject("GameFontWhite")
	box:SetSize(50, 20)
	box:SetAutoFocus(false)
	box:SetMaxLetters(GetMaxLetters(options.Min, options.Max, options.Step))
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

---Creates a generic list of items
---@param options ListOptions
---@return ListReturn
function M:List(options)
	local scroll = CreateFrame("ScrollFrame", nil, options.Parent, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, 0)
	scroll:SetPoint("BOTTOMRIGHT", options.Parent, "BOTTOMRIGHT", 0, 0)

	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)

	local rows = {}
	local items = {}

	local function RefreshScrollbar()
		local visibleHeight = scroll:GetHeight()
		local contentHeight = content:GetHeight()

		if contentHeight <= visibleHeight then
			if scroll.ScrollBar then
				scroll.ScrollBar:Hide()
			end
		else
			if scroll.ScrollBar then
				scroll.ScrollBar:Show()
			end
		end
	end

	local function Refresh()
		for _, row in ipairs(rows) do
			row:Hide()
		end

		table.sort(items)

		local y = options.RowGap or -2

		for i, item in ipairs(items) do
			local row = rows[i]

			if not row then
				row = CreateFrame("Button", nil, content)
				row:SetSize(options.RowWidth, options.RowHeight)

				row.Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
				row.Text:SetPoint("LEFT", 0, 0)

				row.Remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
				row.Remove:SetSize(options.RemoveButtonWidth or 80, options.RowHeight - 2)
				row.Remove:SetPoint("RIGHT", 0, 0)
				row.Remove:SetText("Remove")

				rows[i] = row
			end

			row:SetPoint("TOPLEFT", 0, y)
			row.Text:SetText(item)
			row:Show()

			row.Remove:SetScript("OnClick", function()
				for idx, v in ipairs(items) do
					if v == item then
						table.remove(items, idx)
						break
					end
				end

				if options.OnRemove then
					options.OnRemove(item)
				end

				Refresh()
			end)

			y = y - options.RowHeight
		end

		content:SetHeight(math.max(1, -y + 10))
		RefreshScrollbar()
	end

	content:HookScript("OnShow", RefreshScrollbar)

	local api = {}

	function api.Add(_, item)
		table.insert(items, item)
		Refresh()
	end

	function api.SetItems(_, newItems)
		items = newItems or {}
		Refresh()
	end

	function api.GetItems(_)
		return items
	end

	api.ScrollFrame = scroll
	api.Content = content

	return api
end

---@param options DialogOptions
function M:ShowDialog(options)
	if not options then
		error("ShowDialog - options must not be nil.")
	end

	if not options.Text then
		error("ShowDialog - invalid options.")
	end

	local dlg = GetOrCreateDialog()

	local width = options.Width or 360
	dlg:SetWidth(width)

	dlg.Title:SetText(options.Title or "Notification")
	dlg.Text:SetWidth(width - 40)
	dlg.Text:SetText(options.Text)
	dlg.Text:SetWordWrap(true)

	local textHeight = dlg.Text:GetStringHeight()
	local paddingTop = 70
	local paddingBottom = 40

	dlg:SetHeight(textHeight + paddingTop + paddingBottom)
	dlg:ClearAllPoints()
	dlg:SetPoint("CENTER", UIParent, "CENTER")
	dlg:Show()
end

function M:HideDialog()
	if dialog then
		dialog:Hide()
	end
end

function M:RegisterSlashCommand(category, panel, commands)
	if not category then
		error("RegisterSlashCommand - category must not be nil.")
	end
	if not panel then
		error("RegisterSlashCommand - panel must not be nil.")
	end

	local upper = string.upper(addonName)

	SlashCmdList[upper] = function()
		M:OpenSettings(category, panel)
	end

	if commands and #commands > 0 then
		local addonUpper = string.upper(addonName)

		for i, command in ipairs(commands) do
			_G["SLASH_" .. addonUpper .. i] = command
		end
	end
end

function M:OpenSettings(category, panel)
	if not category then
		error("OpenSettings - category must not be nil.")
	end

	if not panel then
		error("OpenSettings - panel must not be nil.")
	end

	if Settings and Settings.OpenToCategory then
		if not InCombatLockdown() or M:CanOpenOptionsDuringCombat() then
			Settings.OpenToCategory(category:GetID())
		else
			M:NotifyCombatLockdown()
		end
	elseif InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(panel)
		InterfaceOptionsFrame_OpenToCategory(panel)
	end
end

function M:WaitForAddonLoad(callback)
	if not callback then
		error("WaitForAddonLoad - callback must not be nil.")
	end

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

function M:GetCharacterSavedVars(defaults)
	local name = addonName .. "CharDB"
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

	NilKeys(vars)

	if defaults then
		return M:CopyTable(defaults, vars)
	end

	return vars
end

---Removes any erroneous values from the options table.
---@param target table the target table to clean
---@param template table what the table should look like
---@param cleanValues any whether or not to clean non-table values
---@param recurse any whether to recursively clean the table
function M:CleanTable(target, template, cleanValues, recurse)
	if type(target) ~= "table" or type(template) ~= "table" then
		return
	end

	for key, value in pairs(target) do
		local templateValue = template[key]

		if cleanValues and templateValue == nil then
			target[key] = nil
		elseif cleanValues and type(value) == "table" and type(templateValue) ~= "table" then
			target[key] = templateValue
		elseif recurse and type(value) == "table" and type(templateValue) == "table" then
			M:CleanTable(value, templateValue, cleanValues, recurse)
		end
	end
end

function M:ColumnWidth(columns, padding, spacingColumns)
	local settingsWidth = M.ContentWidth or (select(1, M:SettingsSize()))
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

---@class SliderReturn
---@field Label table
---@field EditBox table
---@field Slider table

---@class TextLineOptions
---@field Text string
---@field Parent table
---@field Font string?

---@class TextBlockOptions
---@field Lines string[]
---@field Parent table
---@field Font string?
---@field VerticalSpacing number?

---@class DialogOptions
---@field Title string?
---@field Text string
---@field Width number?

---@class DividerOptions
---@field Parent table
---@field Text string

---@class ListOptions
---@field Parent table
---@field RowGap number?
---@field RowWidth number
---@field RowHeight number
---@field RemoveButtonWidth number?
---@field OnRemove fun(item: any)

---@class ListReturn
---@field ScrollFrame table
---@field Content table
---@field Add fun(self: table, item: any)
---@field SetItems fun(self: table, items: table)
---@field GetItems fun(self: table): table
