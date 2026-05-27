---@type string, Addon
local addonName, addon = ...
local Masque = LibStub and LibStub("Masque", true)
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
-- Debounce table keyed by group object: one deferred ReSkin per group per frame
local masqueReskinPending = {}

-- Pandemic step curve: alpha 1 at <=30% remaining, alpha 0 above. Built once if the API exists.
local pandemicPercentage = 0.3
local pandemicCurve
if C_CurveUtil and Enum and Enum.LuaCurveType then
	pandemicCurve = C_CurveUtil.CreateCurve()
	pandemicCurve:SetType(Enum.LuaCurveType.Step)
	pandemicCurve:AddPoint(0, 1)
	pandemicCurve:AddPoint(pandemicPercentage, 0)
end

-- All live IconSlotContainer instances; iterated by the shared pandemic ticker.
local instances = {}
local pandemicTicker

-- Reused across Layout() calls to avoid table allocation on the hot path
local layoutScratch = {}
local frameIdCounter = 0
local function NextFrameName(frameType)
	frameIdCounter = frameIdCounter + 1
	return addonName .. "_" .. frameType .. "_" .. frameIdCounter
end

---@class IconSlotContainer
local M = {}
M.__index = M

addon.IconSlotContainer = M

local function ScheduleMasqueReSkin(group)
	if not group or masqueReskinPending[group] then
		return
	end
	masqueReskinPending[group] = true
	C_Timer.After(0, function()
		masqueReskinPending[group] = nil
		group:ReSkin()
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
	if not cd or not iconSize then
		return
	end
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

---Returns the pandemic alpha (0 or 1) for a slot, or nil if no usable duration data.
local function GetPandemicAlpha(slot)
	if slot.DurationObject and pandemicCurve and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
		return C_CurveUtil.EvaluateColorValueFromBoolean(
			slot.DurationObject:IsZero(),
			0,
			slot.DurationObject:EvaluateRemainingPercent(pandemicCurve)
		)
	end
	if slot.StartTime and slot.Duration and slot.Duration > 0 then
		local remaining = (slot.StartTime + slot.Duration) - GetTime()
		if remaining <= slot.Duration * pandemicPercentage and remaining > 0 then
			return 1
		end
		return 0
	end
	return nil
end

local procGlowOptions = { key = "pandemic", startAnim = false }

local function StartGlow(slot)
	if not LCG or slot.IsGlowing then
		return
	end
	LCG.ProcGlow_Start(slot.Frame, procGlowOptions)
	slot.IsGlowing = true
end

local function StopGlow(slot)
	if not LCG or not slot.IsGlowing then
		return
	end
	LCG.ProcGlow_Stop(slot.Frame, "pandemic")
	slot.IsGlowing = false
end

local function SetDesaturated(slot, desaturated)
	if slot.IsDesaturated == desaturated then
		return
	end
	slot.Icon:SetDesaturated(desaturated and true or nil)
	slot.IsDesaturated = desaturated
end

local function UpdatePandemicForSlot(slot, glowEnabled, desaturateEnabled)
	if not slot.IsUsed or slot.IsCC or (not glowEnabled and not desaturateEnabled) then
		StopGlow(slot)
		SetDesaturated(slot, false)
		return
	end
	local alpha = GetPandemicAlpha(slot)
	local inPandemic = alpha and alpha > 0
	if glowEnabled and inPandemic then
		StartGlow(slot)
	else
		StopGlow(slot)
	end
	SetDesaturated(slot, desaturateEnabled and inPandemic or false)
end

local function TickPandemic()
	for i = 1, #instances do
		local inst = instances[i]
		local visible = inst.Frame:IsShown()
		local glow = inst.PandemicGlow and visible
		local desat = inst.PandemicDesaturate and visible
		for j = 1, inst.Count do
			local slot = inst.Slots[j]
			if slot then
				UpdatePandemicForSlot(slot, glow, desat)
			end
		end
	end
end

local function EnsurePandemicTicker()
	if pandemicTicker then
		return
	end
	pandemicTicker = C_Timer.NewTicker(0.1, TickPandemic)
end

---Creates a new IconSlotContainer instance.
---@param parent table frame to attach to
---@param count number of icon slots (default: 3)
---@param size number icon size in pixels (default: 20)
---@param spacing number gap between icons (default: 2)
---@param groupName string? Masque sub-group name; omit to skip Masque
---@return IconSlotContainer
function M:New(parent, count, size, spacing, groupName)
	local instance = setmetatable({}, M)

	count = count or 3
	size = size or 20
	spacing = spacing or 2

	instance.Frame = CreateFrame("Frame", NextFrameName("Container"), parent)
	instance.Frame:SetIgnoreParentScale(true)
	instance.Frame:SetIgnoreParentAlpha(true)
	instance.Slots = {}
	instance.Count = 0
	instance.Size = size
	instance.Spacing = spacing
	instance.FontScale = 1.0
	instance.GrowDown = false
	instance.InvertLayout = false
	instance.PandemicGlow = false
	instance.PandemicDesaturate = false
	instance.MasqueGroup = Masque and groupName and Masque:Group(addonName, groupName) or nil

	instance:SetCount(count)

	instances[#instances + 1] = instance
	EnsurePandemicTicker()

	return instance
end

---Enables or disables the pandemic-window glow for this container's slots.
---@param enabled boolean
function M:SetPandemicGlow(enabled)
	enabled = enabled and true or false
	if self.PandemicGlow == enabled then
		return
	end
	self.PandemicGlow = enabled
	if not enabled then
		for i = 1, self.Count do
			local slot = self.Slots[i]
			if slot then
				StopGlow(slot)
			end
		end
	end
end

---Enables or disables desaturating icons during the pandemic window.
---@param enabled boolean
function M:SetPandemicDesaturate(enabled)
	enabled = enabled and true or false
	if self.PandemicDesaturate == enabled then
		return
	end
	self.PandemicDesaturate = enabled
	if not enabled then
		for i = 1, self.Count do
			local slot = self.Slots[i]
			if slot then
				SetDesaturated(slot, false)
			end
		end
	end
end

function M:Layout()
	local n = 0
	for i = 1, self.Count do
		if self.Slots[i] and self.Slots[i].IsUsed then
			n = n + 1
			layoutScratch[n] = i
		end
	end

	local sig = self.Size
		.. ":"
		.. (self.InvertLayout and "1" or "0")
		.. ":"
		.. (self.GrowDown and "D" or "H")
		.. ":"
		.. table.concat(layoutScratch, ",", 1, n)

	if self.LayoutSignature == sig then
		for i = n + 1, #layoutScratch do
			layoutScratch[i] = nil
		end
		return
	end
	self.LayoutSignature = sig

	for i = n + 1, #layoutScratch do
		layoutScratch[i] = nil
	end

	local usedCount = n

	if usedCount == 0 then
		self.Frame:SetSize(self.Size, self.Size)
	elseif self.GrowDown then
		-- Vertical single column, growing downward
		local totalHeight = usedCount * self.Size + (usedCount - 1) * self.Spacing
		self.Frame:SetSize(self.Size, totalHeight)
		self.Frame:SetAlpha(1)

		for displayIndex = 1, usedCount do
			local slot = self.Slots[layoutScratch[displayIndex]]
			local y = (totalHeight / 2) - (self.Size / 2) - (displayIndex - 1) * (self.Size + self.Spacing)
			slot.Frame:ClearAllPoints()
			slot.Frame:SetPoint("CENTER", self.Frame, "CENTER", 0, y)
			slot.Frame:SetSize(self.Size, self.Size)
			slot.Frame:Show()
		end
	else
		-- Single horizontal row
		local totalWidth = usedCount * self.Size + (usedCount - 1) * self.Spacing
		self.Frame:SetSize(totalWidth, self.Size)
		self.Frame:SetAlpha(1)

		for displayIndex = 1, usedCount do
			local slot = self.Slots[layoutScratch[displayIndex]]
			-- InvertLayout: slot 1 is rightmost, fills right-to-left
			local effIndex = self.InvertLayout and (usedCount - displayIndex + 1) or displayIndex
			local x = (effIndex - 1) * (self.Size + self.Spacing) - (totalWidth / 2) + (self.Size / 2)
			slot.Frame:ClearAllPoints()
			slot.Frame:SetPoint("CENTER", self.Frame, "CENTER", x, 0)
			slot.Frame:SetSize(self.Size, self.Size)
			slot.Frame:Show()
		end
	end

	-- Hide unused active slots
	for i = 1, self.Count do
		local slot = self.Slots[i]
		if slot and not slot.IsUsed then
			slot.Frame:Hide()
		end
	end

	-- Hide inactive pooled slots
	for i = self.Count + 1, #self.Slots do
		local slot = self.Slots[i]
		if slot then
			slot.IsUsed = false
			slot.Frame:Hide()
		end
	end

	ScheduleMasqueReSkin(self.MasqueGroup)
end

---Sets the spacing between slots.
---@param newSpacing number
function M:SetSpacing(newSpacing)
	newSpacing = tonumber(newSpacing)
	if not newSpacing or newSpacing < 0 then
		return
	end
	if self.Spacing == newSpacing then
		return
	end
	self.Spacing = newSpacing
	self.LayoutSignature = nil
	self:Layout()
end

---Switches to vertical single-column layout growing downward.
---@param enabled boolean
function M:SetGrowDown(enabled)
	enabled = enabled and true or false
	if self.GrowDown == enabled then
		return
	end
	self.GrowDown = enabled
	self.LayoutSignature = nil
	self:Layout()
end

---When true, slot 1 is placed at the rightmost position (fills right-to-left).
---@param inverted boolean
function M:SetInvertLayout(inverted)
	inverted = inverted and true or false
	if self.InvertLayout == inverted then
		return
	end
	self.InvertLayout = inverted
	self.LayoutSignature = nil
	self:Layout()
end

---Sets the icon size for all slots.
---@param newSize number
function M:SetIconSize(newSize)
	newSize = tonumber(newSize)
	if not newSize or newSize <= 0 then
		return
	end
	if self.Size == newSize then
		return
	end
	self.Size = newSize

	for i = 1, self.Count do
		local slot = self.Slots[i]
		if slot and slot.Frame then
			slot.Frame:SetSize(self.Size, self.Size)
			if slot.Cooldown then
				UpdateCooldownFontSize(slot.Cooldown, self.Size, self.FontScale)
			end
		end
	end

	ScheduleMasqueReSkin(self.MasqueGroup)
	self.LayoutSignature = nil
	self:Layout()
end

---Sets the font scale for cooldown countdown text.
---@param newScale number multiplier (1.0 = default)
function M:SetFontScale(newScale)
	newScale = tonumber(newScale)
	if not newScale or newScale <= 0 then
		return
	end
	if self.FontScale == newScale then
		return
	end
	self.FontScale = newScale
	for i = 1, self.Count do
		local slot = self.Slots[i]
		if slot and slot.Cooldown then
			UpdateCooldownFontSize(slot.Cooldown, self.Size, self.FontScale)
		end
	end
end

---Sets the total number of icon slots.
---@param newCount number
function M:SetCount(newCount)
	newCount = math.max(0, newCount or 0)
	if newCount == self.Count then
		return
	end

	if newCount < self.Count then
		for i = newCount + 1, #self.Slots do
			local slot = self.Slots[i]
			if slot then
				slot.IsUsed = false
				self:ClearSlot(i)
				slot.Frame:Hide()
			end
		end
	end

	self.Count = newCount

	for i = #self.Slots + 1, newCount do
		local slotFrame = CreateFrame(self.MasqueGroup and "Button" or "Frame", NextFrameName("Slot"), self.Frame)
		slotFrame:SetSize(self.Size, self.Size)
		slotFrame:EnableMouse(false)

		local icon = slotFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
		icon:SetAllPoints()

		local cd = CreateFrame("Cooldown", NextFrameName("Cooldown"), slotFrame, "CooldownFrameTemplate")
		cd:SetAllPoints()
		cd:SetDrawEdge(false)
		cd:SetDrawBling(false)
		cd:SetSwipeColor(0, 0, 0, 0.8)
		UpdateCooldownFontSize(cd, self.Size, self.FontScale)

		if self.MasqueGroup then
			self.MasqueGroup:AddButton(slotFrame, {
				Icon = icon,
				Cooldown = cd,
			})
		end

		self.Slots[i] = {
			Frame = slotFrame,
			Icon = icon,
			Cooldown = cd,
			IsUsed = false,
		}
	end

	self:Layout()
end

---Sets an icon on a specific slot.
---@param slotIndex number 1-based slot index
---@param options IconSlotOptions
---@class IconSlotOptions
---@field Texture string Texture path or ID
---@field DurationObject table? From C_UnitAuras.GetAuraDuration — drives the cooldown swipe
---@field StartTime number? Used with Duration for synthetic timers (e.g. test mode)
---@field Duration number? Used with StartTime for synthetic timers (e.g. test mode)
---@field HideSwipe boolean? Suppress the cooldown swipe animation
---@field ReverseCooldown boolean? Reverse the swipe animation direction
---@field HideNumbers boolean? Hide the cooldown countdown numbers
---@field NameplateShowPersonal boolean? When provided, passed to SetAlphaFromBoolean to hide unimportant auras
---@field IsCC boolean? Marks the aura as crowd-control so pandemic-window visuals are skipped
function M:SetSlot(slotIndex, options)
	if slotIndex < 1 or slotIndex > self.Count then
		return
	end
	if not options.Texture then
		return
	end

	local slot = self.Slots[slotIndex]
	if not slot then
		return
	end

	if not slot.IsUsed then
		slot.IsUsed = true
		self:Layout()
	end

	if options.NameplateShowPersonal ~= nil then
		slot.Frame:SetAlphaFromBoolean(options.NameplateShowPersonal, 1, 0)
	else
		slot.Frame:SetAlpha(1)
	end
	slot.IsCC = options.IsCC and true or false
	slot.Icon:SetTexture(options.Texture)
	slot.Cooldown:SetReverse(options.ReverseCooldown or false)
	slot.Cooldown:SetHideCountdownNumbers(options.HideNumbers or false)

	local drawSwipe = not options.HideSwipe
	if options.DurationObject then
		slot.Cooldown:SetCooldownFromDurationObject(options.DurationObject)
		slot.Cooldown:SetDrawSwipe(drawSwipe)
		slot.DurationObject = options.DurationObject
		slot.StartTime = nil
		slot.Duration = nil
	elseif options.StartTime and options.Duration then
		slot.Cooldown:SetCooldown(options.StartTime, options.Duration)
		slot.Cooldown:SetDrawSwipe(drawSwipe)
		slot.DurationObject = nil
		slot.StartTime = options.StartTime
		slot.Duration = options.Duration
	else
		slot.Cooldown:Clear()
		slot.Cooldown:SetDrawSwipe(false)
		slot.DurationObject = nil
		slot.StartTime = nil
		slot.Duration = nil
	end
end

---Clears icon data on a slot without changing its used state.
---@param slotIndex number
function M:ClearSlot(slotIndex)
	if slotIndex < 1 or slotIndex > #self.Slots then
		return
	end
	local slot = self.Slots[slotIndex]
	if not slot then
		return
	end
	slot.Frame:SetAlpha(1)
	slot.Icon:SetTexture(nil)
	slot.Cooldown:Clear()
	slot.DurationObject = nil
	slot.StartTime = nil
	slot.Duration = nil
	slot.IsCC = false
	StopGlow(slot)
	SetDesaturated(slot, false)
end

---Marks a slot as unused and triggers a layout update.
---@param slotIndex number
function M:SetSlotUnused(slotIndex)
	if slotIndex < 1 or slotIndex > self.Count then
		return
	end
	local slot = self.Slots[slotIndex]
	if not slot then
		return
	end
	if slot.IsUsed then
		slot.IsUsed = false
		self:ClearSlot(slotIndex)
		self:Layout()
	end
end

---Resets all slots to unused.
function M:ResetAllSlots()
	local needsLayout = false
	for i = 1, self.Count do
		local slot = self.Slots[i]
		if slot and slot.IsUsed then
			slot.IsUsed = false
			self:ClearSlot(i)
			needsLayout = true
		end
	end
	if needsLayout then
		self:Layout()
	end
end

---@class IconSlotContainer
---@field Frame table
---@field MasqueGroup table?
---@field Slots table[]
---@field Count number
---@field Size number
---@field Spacing number
---@field FontScale number
---@field GrowDown boolean
---@field InvertLayout boolean
---@field PandemicGlow boolean
---@field PandemicDesaturate boolean
---@field SetCount fun(self: IconSlotContainer, count: number)
---@field SetSpacing fun(self: IconSlotContainer, spacing: number)
---@field SetGrowDown fun(self: IconSlotContainer, enabled: boolean)
---@field SetInvertLayout fun(self: IconSlotContainer, inverted: boolean)
---@field SetIconSize fun(self: IconSlotContainer, size: number)
---@field SetFontScale fun(self: IconSlotContainer, scale: number)
---@field SetPandemicGlow fun(self: IconSlotContainer, enabled: boolean)
---@field SetPandemicDesaturate fun(self: IconSlotContainer, enabled: boolean)
---@field SetSlot fun(self: IconSlotContainer, slotIndex: number, options: IconSlotOptions)
---@field ClearSlot fun(self: IconSlotContainer, slotIndex: number)
---@field SetSlotUnused fun(self: IconSlotContainer, slotIndex: number)
---@field ResetAllSlots fun(self: IconSlotContainer)
