local addonName, addon = ...
local loader = CreateFrame("Frame")
local loaded = false
local onLoadCallbacks = {}
local dropDownId = 1

---@class MiniFramework
local M = {}
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

function M:CreateEditBox(parent, numeric, labelText, width, getValue, setValue)
	local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	label:SetText(labelText)

	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(width or 80, 20)
	box:SetAutoFocus(false)

	if numeric then
		-- can't use SetNumeric(true) because it doesn't allow negatives
		box:SetScript("OnTextChanged", function(boxSelf, userInput)
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

	local function Commit()
		local new = box:GetText()

		setValue(new)

		box:SetText(tostring(getValue()))
		box:SetCursorPosition(0)
	end

	box:SetScript("OnEnterPressed", function(boxSelf)
		boxSelf:ClearFocus()
		Commit()
	end)

	box:SetScript("OnEditFocusLost", Commit)

	function box.MiniRefresh(boxSelf)
		boxSelf:SetText(tostring(getValue()))
		boxSelf:SetCursorPosition(0)
	end

	box:MiniRefresh()

	AddControlForRefresh(parent, box)

	return label, box
end

---Creates a dropdown menu using the selected parameters.
---@param parent table the parent frame
---@param items any[] list of items
---@param getValue fun(): any
---@param setSelected fun(value: any)
---@param getText? fun(value: any): string
---@return table the dropdown menu control
---@return boolean true if used a modern dropdown, otherwise false
function M:Dropdown(parent, items, getValue, setSelected, getText)
	if MenuUtil and MenuUtil.CreateRadioMenu then
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

		function dd.MiniRefresh(ddSelf)
			ddSelf:Update()
		end

		AddControlForRefresh(parent, dd)

		return dd, true
	end

	local libDD = LibStub and LibStub:GetLibrary("LibUIDropDownMenu-4.0", false)

	if libDD then
		-- needs a name to not bug out
		local dd = libDD:Create_UIDropDownMenu("MiniArenaDebuffsDropdown" .. dropDownId, parent)
		dropDownId = dropDownId + 1

		libDD:UIDropDownMenu_Initialize(dd, function()
			for i, value in ipairs(items) do
				local info = libDD:UIDropDownMenu_CreateInfo()
				info.text = getText and getText(value) or tostring(value)
				info.value = value

				info.checked = function()
					return getValue() == value
				end

				local id = dd:GetID(info)

				-- onclick handler
				info.func = function()
					local text = getText and getText(value) or tostring(value)

					print(i, id)

					libDD:UIDropDownMenu_SetSelectedID(dd, id)
					libDD:UIDropDownMenu_SetText(dd, text)

					setSelected(value)
				end

				libDD:UIDropDownMenu_AddButton(info, 1)

				if getValue() == value then
					libDD:UIDropDownMenu_SetSelectedID(dd, id)
				end
			end
		end)

		function dd.MiniRefresh()
			local value = getValue()
			local text = getText and getText(value) or tostring(value)
			libDD:UIDropDownMenu_SetText(dd, text)
		end

		AddControlForRefresh(parent, dd)

		return dd, false
	end

	-- UIDropDownMenuTemplate is nil, but still usable
	if UIDropDownMenu_Initialize then
		local dd = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")

		UIDropDownMenu_Initialize(dd, function()
			for _, value in ipairs(items) do
				local info = UIDropDownMenu_CreateInfo()
				info.text = getText and getText(value) or tostring(value)
				info.value = value

				info.checked = function()
					return getValue() == value
				end

				-- onclick handler
				info.func = function()
					local text = getText and getText(value) or tostring(value)
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
			local value = getValue()
			local text = getText and getText(value) or tostring(value)
			UIDropDownMenu_SetText(dd, text)
		end

		AddControlForRefresh(parent, dd)

		return dd, false
	end

	error("Failed to create a dropdown control")
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

---comment
---@param parent table
---@param setting CheckboxSetting
---@return table checkbox
function M:CreateSettingCheckbox(parent, setting)
	local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	checkbox.Text:SetText(" " .. setting.Name)
	checkbox.Text:SetFontObject("GameFontNormal")
	checkbox:SetChecked(setting.Enabled())
	checkbox:HookScript("OnClick", function()
		setting.OnChanged(checkbox:GetChecked())
	end)

	checkbox:SetScript("OnEnter", function(chkSelf)
		GameTooltip:SetOwner(chkSelf, "ANCHOR_RIGHT")
		GameTooltip:SetText(setting.Name, 1, 0.82, 0)
		GameTooltip:AddLine(setting.Tooltip, 1, 1, 1, true)
		GameTooltip:Show()
	end)

	checkbox:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	function checkbox.MiniRefresh()
		checkbox:SetChecked(setting.Enabled())
	end

	AddControlForRefresh(parent, checkbox)

	return checkbox
end

function M:RegisterSlashCommand(category, panel)
	local upper = string.upper(addonName)

	SlashCmdList[upper] = function()
		M:OpenSettings(category, panel)
	end
end

function M:OpenSettings(category, panel)
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

---@class CheckboxSetting
---@field Name string
---@field Tooltip string
---@field Enabled fun(): boolean
---@field OnChanged fun(enabled: boolean)
