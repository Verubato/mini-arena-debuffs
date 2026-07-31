---@type string, Addon
local addonName, addon = ...
local wowEx = addon.WoWEx
local frameIdCounter = 0
local groupKey = "debuffs"
local filter = "HARMFUL|PLAYER"
local liveDisplays = {}
local editModePreviewActive = false
local providerSwitchListener = nil

-- 12.1 AuraContainer-backed debuff display. Wraps a CreateFrame("AuraContainer") with a single
-- aura group (the player's harmful auras on the unit) and styles the container-created
-- AuraButtons to match the legacy IconSlotContainer look (icon + cooldown swipe/countdown).
--
-- Constraints inherited from the AuraContainer system:
-- - AuraButtons are forbidden while auras are secret (combat/arena): all button styling must
--   happen in the initializeFrame callback or out of combat. Style setters store the desired
--   state and apply it to buttons lazily once styling is allowed again.
-- - Aura groups can't be removed, only reconfigured, so displays are kept per anchor and
--   reconfigured on refresh.
-- - Nothing may be anchored to the container frame itself, and the container's size can be
--   secret; callers must not do math with it.
--
-- This file is only used when addon.WoWEx:UseAuraContainers() is true; on 12.0 clients nothing
-- here runs (CreateFrame("AuraContainer") does not exist there).
--
-- The legacy pandemic glow/desaturate options have no 12.1 equivalent (they need per-aura
-- remaining duration), but 12.1.5 adds engine-side pandemic glow support - restore the feature
-- here through that API when it ships.

---@class AuraContainerDisplay
local M = {}
M.__index = M

addon.AuraContainerDisplay = M

-- Maps the legacy sort settings onto AuraContainer sort methods: INDEX approximates the old
-- unsorted/application order via aura instance IDs, TIME sorts purely by expiration.
local sortMethodMap = {
	INDEX = "AuraInstanceIDOnly",
	TIME = "ExpirationOnly",
}

-- Grow direction -> flow layout. The first icon always sits nearest the container's anchored
-- edge, matching the legacy InvertLayout behaviour. CENTER is not offered on 12.1 (the
-- container's size can be secret, so a centred row can't be positioned).
local growLayouts = {
	LEFT = { anchorPoint = "RIGHT", h = "Left" },
	RIGHT = { anchorPoint = "LEFT", h = "Right" },
}

local function NextFrameName(frameType)
	frameIdCounter = frameIdCounter + 1
	return addonName .. "_AC_" .. frameType .. "_" .. frameIdCounter
end

-- Edit Mode preview suppression.
--
-- Blizzard force-feeds every AuraContainer a fake data provider while Edit Mode is open, so
-- our containers fill up with placeholder auras ("Poison 1", "Buff 1", ... with random spellbook
-- icons) that have nothing to do with the tracked unit. There is no opt-out: the container
-- registers AURA_DATA_PROVIDER_SWITCH as a *static* event in OnLoad_Intrinsic (so SetEnabled and
-- visibility don't gate it), and the switch flips ManagedAuraContainerPrivateMixin's aura source
-- list to AuraContainerAuraSourceLists.EditMode. SetUseEditModeSource lives on the private mixin
-- only, so addons can't call it.
--
-- Hiding the container does work, and is the intended escape hatch: dirty processing runs under
-- Enum.OnUpdateMode.RunWhenVisibleOnce, so a hidden container never parses the fake auras at all,
-- and OnShow_Intrinsic issues a full refresh from live data on the way back out.
--
-- Displays are re-anchored constantly, so suppression can't live on an intermediate holder frame.
-- Instead every display remembers the visibility the addon asked for and the real frame shows
-- only when the preview isn't running.

---@param instance AuraContainerDisplay
local function ApplyShownState(instance)
	instance.Frame:SetShown(instance.DesiredShown and not editModePreviewActive)
end

local function OnAuraDataProviderSwitch(useRealDataProvider)
	local previewActive = useRealDataProvider ~= true
	if editModePreviewActive == previewActive then
		return
	end

	editModePreviewActive = previewActive

	for _, instance in ipairs(liveDisplays) do
		ApplyShownState(instance)
	end
end

---Starts listening for the Edit Mode data provider switch. Called from New rather than at load,
---because the event only exists on clients that have the AuraContainer system.
local function EnsureProviderSwitchListener()
	if providerSwitchListener then
		return
	end

	providerSwitchListener = CreateFrame("Frame")
	providerSwitchListener:RegisterEvent("AURA_DATA_PROVIDER_SWITCH")
	providerSwitchListener:SetScript("OnEvent", function(_, _, useRealDataProvider)
		OnAuraDataProviderSwitch(useRealDataProvider)
	end)
end

local function GetCooldownFontString(cd)
	if cd.FontRegion then
		return cd.FontRegion
	end
	for i = 1, cd:GetNumRegions() do
		local region = select(i, cd:GetRegions())
		if region and region.GetObjectType and region:GetObjectType() == "FontString" then
			cd.FontRegion = region
			return region
		end
	end
	return nil
end

local function UpdateCooldownFontSize(cd, iconSize, fontScale)
	local region = GetCooldownFontString(cd)
	if not region then
		return
	end
	local font, _, flags = region:GetFont()
	if not font then
		return
	end
	local fontSize = math.max(1, math.floor(iconSize * 0.4 * (fontScale or 1.0)))
	region:SetFont(font, fontSize, flags)
end

-- Applies the stored style (size, cooldown settings) to one button. Safe only while buttons
-- are not forbidden (initializeFrame or out of combat).
---@param instance AuraContainerDisplay
---@param button table
local function StyleButton(instance, button)
	local style = instance.Style
	local cd = instance.ButtonCooldowns[button]

	if not cd then
		return
	end

	button:SetSize(instance.Size, instance.Size)
	cd:SetReverse(style.ReverseCooldown or false)
	cd:SetDrawSwipe(not style.HideSwipe)
	cd:SetHideCountdownNumbers(style.HideNumbers or false)
	UpdateCooldownFontSize(cd, instance.Size, style.FontScale)

	-- No tooltips or click-to-cancel: the icons sit over arena frames and must not eat clicks.
	button:EnableMouse(false)
end

---@param instance AuraContainerDisplay
---@param button table
local function InitializeButton(instance, button)
	-- Icon on the lowest layer with the swipe above, matching IconSlotContainer's slots.
	local icon = button:CreateTexture(nil, "BACKGROUND", nil, 1)
	icon:SetAllPoints(button)
	button:SetIcon(icon)

	local cd = CreateFrame("Cooldown", NextFrameName("Cooldown"), button, "CooldownFrameTemplate")
	cd:SetAllPoints(button)
	cd:SetDrawEdge(false)
	cd:SetDrawBling(false)
	cd:SetSwipeColor(0, 0, 0, 0.8)
	button:SetDurationCooldown(cd)

	instance.ButtonCooldowns[button] = cd
	instance.Buttons[#instance.Buttons + 1] = button

	StyleButton(instance, button)
end

---@param instance AuraContainerDisplay
local function ApplyFlowLayout(instance)
	local layout = growLayouts[instance.Grow] or growLayouts.RIGHT
	local frame = instance.Frame
	frame:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
	frame:SetFlowLayoutAnchorPoint(layout.anchorPoint)
	frame:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection[layout.h], AnchorUtil.FlowDirection.Down)
end

---Builds the group layout table. Spacing keys are passed under BOTH the older and newer PTR
---spellings (elementSpacing/lineSpacing was renamed to elementSpacingX/elementSpacingY in a
---later 12.1 build); validators ignore unknown keys, so this works on either build.
---@param instance AuraContainerDisplay
---@return table
local function BuildGroupLayout(instance)
	return {
		elementSpacing = instance.Spacing,
		lineSpacing = instance.Spacing,
		elementSpacingX = instance.Spacing,
		elementSpacingY = instance.Spacing,
		elementWidth = instance.Size,
		elementHeight = instance.Size,
	}
end

---Creates a new AuraContainer-backed display tracking the player's debuffs on a unit.
---@param parent table Frame to parent the container to.
---@param unit string? Unit token to track.
---@param maxIcons number Icon budget.
---@param size number Icon size in pixels.
---@param spacing number Spacing between icons.
---@return AuraContainerDisplay
function M:New(parent, unit, maxIcons, size, spacing)
	local instance = setmetatable({}, M)

	instance.Size = size or 36
	instance.Spacing = spacing or 2
	instance.MaxIcons = maxIcons or 6
	instance.Grow = "RIGHT"
	instance.Style = {}
	instance.Buttons = {}
	-- button -> Cooldown widget for restyling.
	instance.ButtonCooldowns = {}
	instance.HideUnimportant = false
	-- Visibility the addon last asked for; frames are created shown.
	instance.DesiredShown = true

	local frame = CreateFrame("AuraContainer", NextFrameName("Container"), parent, "CustomAuraContainerTemplate")
	frame:SetIgnoreParentScale(true)
	frame:SetIgnoreParentAlpha(true)
	instance.Frame = frame

	EnsureProviderSwitchListener()
	liveDisplays[#liveDisplays + 1] = instance
	ApplyShownState(instance)

	frame:SetUnit(unit or "none")
	ApplyFlowLayout(instance)

	frame:AddAuraGroup(groupKey, filter, {
		maxFrameCount = instance.MaxIcons,
		candidateFilters = {},
		sortMethod = AuraContainerSortMethod.AuraInstanceIDOnly,
		sortDirection = AuraContainerSortDirection.Normal,
		initializeFrame = function(button)
			InitializeButton(instance, button)
		end,
		layout = BuildGroupLayout(instance),
	})

	return instance
end

---@param unit string?
function M:SetUnit(unit)
	self.Frame:SetUnit(unit or "none")
end

---Shows or hides the display. Always use this instead of touching Frame:SetShown directly, so
---the Edit Mode placeholder auras stay suppressed (see EnsureProviderSwitchListener).
---@param shown boolean
function M:SetShown(shown)
	self.DesiredShown = shown == true
	ApplyShownState(self)
end

function M:Show()
	self:SetShown(true)
end

function M:Hide()
	self:SetShown(false)
end

---The visibility the addon asked for, which is not the frame's actual state while the Edit Mode
---preview is suppressing it.
---@return boolean
function M:IsShown()
	return self.DesiredShown
end

---@param maxIcons number
function M:SetMaxIcons(maxIcons)
	maxIcons = tonumber(maxIcons)
	if not maxIcons or maxIcons < 0 or self.MaxIcons == maxIcons then
		return
	end

	self.MaxIcons = maxIcons
	self.Frame:SetAuraGroupMaxFrameCount(groupKey, maxIcons)
end

---@param newSize number
function M:SetIconSize(newSize)
	newSize = tonumber(newSize)
	if not newSize or newSize <= 0 or self.Size == newSize then
		return
	end

	self.Size = newSize
	self.Frame:SetAuraGroupLayout(groupKey, BuildGroupLayout(self))
	self:RestyleButtons()
end

---@param newSpacing number
function M:SetSpacing(newSpacing)
	newSpacing = tonumber(newSpacing)
	if not newSpacing or newSpacing < 0 or self.Spacing == newSpacing then
		return
	end

	self.Spacing = newSpacing
	self.Frame:SetAuraGroupLayout(groupKey, BuildGroupLayout(self))
end

---@param grow string "LEFT"|"RIGHT" (anything else falls back to RIGHT)
function M:SetGrow(grow)
	grow = growLayouts[grow] and grow or "RIGHT"
	if self.Grow == grow then
		return
	end

	self.Grow = grow
	ApplyFlowLayout(self)
end

---@param method string "INDEX"|"TIME"
---@param direction string "+"|"-"
function M:SetSortMethod(method, direction)
	local signature = tostring(method) .. tostring(direction)
	if self.SortSignature == signature then
		return
	end

	self.SortSignature = signature
	self.Frame:SetAuraGroupSortMethod(
		groupKey,
		AuraContainerSortMethod[sortMethodMap[method] or "AuraInstanceIDOnly"],
		direction == "-" and AuraContainerSortDirection.Reverse or AuraContainerSortDirection.Normal
	)
end

---Shows only debuffs Blizzard flags nameplateShowPersonal when enabled (the 12.1 replacement
---for the legacy per-aura alpha trick - boolean candidate filters are not identity-gated).
---@param hide boolean
function M:SetHideUnimportant(hide)
	hide = hide and true or false
	if self.HideUnimportant == hide then
		return
	end

	self.HideUnimportant = hide
	self.Frame:SetAuraGroupCandidateFilters(groupKey, hide and { nameplateShowPersonal = true } or {})
end

---Stores the per-button style and applies it to existing buttons when possible. Skipped
---entirely when nothing changed - this runs on every refresh.
---@param style AuraDisplayStyle
function M:SetStyle(style)
	self.Style = style or {}

	local signature = table.concat({
		tostring(self.Style.ReverseCooldown),
		tostring(self.Style.HideSwipe),
		tostring(self.Style.HideNumbers),
		tostring(self.Style.FontScale),
	}, "|")
	if signature == self.StyleSignature and not self.RestylePending then
		return
	end
	self.StyleSignature = signature

	self:RestyleButtons()
end

---Re-applies the stored style to all created buttons. Buttons are forbidden while auras are
---secret (in combat, but also out-of-combat inside M+/encounters/PvP matches), so this is
---deferred then: the pending flag makes the next SetStyle/RestyleButtons retry even when the
---style itself is unchanged.
function M:RestyleButtons()
	if wowEx:IsAuraStylingRestricted() then
		self.RestylePending = true
		return
	end
	self.RestylePending = false

	for _, button in ipairs(self.Buttons) do
		StyleButton(self, button)
	end
end

---@class AuraDisplayStyle
---@field ReverseCooldown boolean?
---@field HideSwipe boolean?
---@field HideNumbers boolean?
---@field FontScale number?

---@class AuraContainerDisplay
---@field Frame table The AuraContainer frame (anchor/show/hide through this).
---@field Size number
---@field Spacing number
---@field MaxIcons number
---@field Grow string
---@field Style AuraDisplayStyle
---@field Buttons table[]
---@field ButtonCooldowns table<table, table>
---@field HideUnimportant boolean
---@field DesiredShown boolean
