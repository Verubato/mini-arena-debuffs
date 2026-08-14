---@type string, Addon
local addonName, addon = ...
local Masque = LibStub and LibStub("Masque", true)
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
local iconUtil = addon.IconUtil
-- Debounce table keyed by container: one deferred ReSkin per container per frame
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

-- Cooldowns whose countdown text is being coloured by remaining time, mapped to their expiry.
-- Only cooldowns with an addon-known expiry land here (synthetic test timers), so secret aura
-- durations are never read. One shared ticker serves every container.
local coloredCooldowns = {}
local colorTicker

-- Reused across Layout() calls to avoid table allocation on the hot path
local layoutScratch = {}
local frameIdCounter = 0
---@class IconSlotContainer
local M = {}
M.__index = M

addon.IconSlotContainer = M

local procGlowOptions = { key = "pandemic", startAnim = false }

local function NextFrameName(frameType)
	frameIdCounter = frameIdCounter + 1
	return addonName .. "_" .. frameType .. "_" .. frameIdCounter
end

---Re-fits the skin to this container's current icon size, one pass per container per frame.
---Scoped to the slots it owns: the group is shared with the 12.1 aura displays, whose buttons
---belong to the engine and must only be touched from their own restriction-gated restyle.
---@param instance IconSlotContainer
local function ScheduleMasqueReSkin(instance)
	local group = instance.MasqueGroup

	if not group or masqueReskinPending[instance] then
		return
	end
	masqueReskinPending[instance] = true
	C_Timer.After(0, function()
		masqueReskinPending[instance] = nil
		for i = 1, instance.Count do
			local slot = instance.Slots[i]
			if slot then
				group:ReSkin(slot.Frame)
			end
		end
	end)
end

local function GetCooldownFontString(cd)
	if cd.FontRegion then
		return cd.FontRegion
	end
	-- The scan below picks the first fontstring it finds, which is the countdown on today's
	-- template but only by luck; clients that expose the getter answer for certain.
	if cd.GetCountdownFontString then
		cd.FontRegion = cd:GetCountdownFontString()
		if cd.FontRegion then
			return cd.FontRegion
		end
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

local function UpdateStackFontSize(stackText, iconSize, fontScale)
	local font, _, flags = stackText:GetFont()
	if font then
		stackText:SetFont(font, math.max(1, math.floor(iconSize * 0.35 * (fontScale or 1.0))), flags)
	end
end

---Colour bands by remaining seconds; must match COUNTDOWN_COLOR_STOPS in AuraContainerDisplay
---so test icons show exactly what the curve-bound 12.1 aura icons show.
local function ApplyCountdownColor(cd, remaining)
	local band = (remaining < 5 and 1) or (remaining < 60 and 2) or 3

	if cd.ColorBand == band then
		return
	end

	local text = GetCooldownFontString(cd)

	if not text then
		return
	end

	cd.ColorBand = band

	if band == 1 then
		text:SetTextColor(1, 0, 0)
	elseif band == 2 then
		text:SetTextColor(1, 0.8, 0)
	else
		text:SetTextColor(1, 1, 1)
	end
end

local function ResetCountdownColor(cd)
	coloredCooldowns[cd] = nil

	if cd.ColorBand then
		cd.ColorBand = nil
		local text = GetCooldownFontString(cd)
		if text then
			text:SetTextColor(1, 1, 1)
		end
	end
end

local function OnColorTick()
	local now = GetTime()
	local any = false

	for cd, expiry in pairs(coloredCooldowns) do
		if expiry - now <= 0 then
			ResetCountdownColor(cd)
		else
			ApplyCountdownColor(cd, expiry - now)
			any = true
		end
	end

	if not any and colorTicker then
		colorTicker:Cancel()
		colorTicker = nil
	end
end

---Starts colouring a cooldown's countdown by its remaining time. The expiry must be an
---addon-known number on the GetTime clock, never a secret aura value.
local function RegisterCountdownColor(cd, expiry)
	local remaining = expiry and expiry - GetTime()

	if not remaining or remaining <= 0 then
		ResetCountdownColor(cd)
		return
	end

	coloredCooldowns[cd] = expiry
	ApplyCountdownColor(cd, remaining)

	if not colorTicker then
		-- Bands only change at the 60s and 5s edges, so a coarse tick is plenty.
		colorTicker = C_Timer.NewTicker(0.5, OnColorTick)
	end
end

---The refresh-window border ring, built on first use. Alpha-gated by the pandemic ticker;
---asset and default tint must match the engine-driven ring in AuraContainerDisplay so test
---mode previews exactly what real 12.1 icons show.
local function EnsurePandemicRing(inst, slot)
	local ring = slot.PandemicRing

	if not ring then
		ring = CreateFrame("Frame", NextFrameName("PandemicRing"), slot.Frame)
		ring:SetPoint("TOPLEFT", slot.Frame, "TOPLEFT", -2, 2)
		ring:SetPoint("BOTTOMRIGHT", slot.Frame, "BOTTOMRIGHT", 2, -2)
		ring:SetFrameLevel(slot.Cooldown:GetFrameLevel() + 6)
		ring:SetAlpha(0)

		local texture = ring:CreateTexture(nil, "OVERLAY")
		texture:SetAllPoints(ring)
		texture:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
		texture:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
		texture:SetVertexColor(inst.PandemicColorR or 1, inst.PandemicColorG or 0.6, inst.PandemicColorB or 0.1, 1)
		ring.Texture = texture

		slot.PandemicRing = ring
	end

	return ring
end

-- Glow is hosted on slot.PandemicOverlay so its visibility can be gated by SetAlpha
-- without dimming the icon. The animation loops continuously while started; the
-- secret-number curve alpha (which we cannot compare) drives the overlay's alpha.
local function StartGlow(slot)
	if not LCG or slot.IsGlowing or not slot.PandemicOverlay then
		return
	end
	LCG.ProcGlow_Start(slot.PandemicOverlay, procGlowOptions)
	slot.IsGlowing = true
end

local function StopGlow(slot)
	if not LCG or not slot.IsGlowing or not slot.PandemicOverlay then
		return
	end
	LCG.ProcGlow_Stop(slot.PandemicOverlay, "pandemic")
	slot.IsGlowing = false
end

-- Returns the pandemic alpha for a slot. Pattern from Platynator: the value may be
-- a secret number when DurationObject is in play, so it must only flow into setters
-- (SetAlpha, SetDesaturation) — never into comparisons.
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
		if remaining > 0 and remaining <= slot.Duration * pandemicPercentage then
			return 1
		end
	end
	return 0
end

local function UpdatePandemicForSlot(inst, slot, glowEnabled, desaturateEnabled, borderEnabled)
	local overlay = slot.PandemicOverlay
	if not slot.IsUsed or slot.IsCC or (not glowEnabled and not desaturateEnabled and not borderEnabled) then
		StopGlow(slot)
		if overlay then
			overlay:SetAlpha(0)
		end
		if slot.PandemicRing then
			slot.PandemicRing:SetAlpha(0)
		end
		slot.Icon:SetDesaturation(0)
		return
	end
	-- Toggle the glow animation strictly off the user setting; never test the secret value.
	if glowEnabled then
		StartGlow(slot)
	else
		StopGlow(slot)
	end
	local alpha = GetPandemicAlpha(slot)
	if overlay then
		if glowEnabled then
			overlay:SetAlpha(alpha)
		else
			overlay:SetAlpha(0)
		end
	end
	if borderEnabled then
		EnsurePandemicRing(inst, slot):SetAlpha(alpha)
	elseif slot.PandemicRing then
		slot.PandemicRing:SetAlpha(0)
	end
	if desaturateEnabled then
		slot.Icon:SetDesaturation(alpha)
	else
		slot.Icon:SetDesaturation(0)
	end
end

local function TickPandemic()
	local any = false

	for i = 1, #instances do
		local inst = instances[i]
		local visible = inst.Frame:IsShown()
		local glow = inst.PandemicGlow and visible
		local desat = inst.PandemicDesaturate and visible
		local border = inst.PandemicBorder and visible
		if glow or desat or border then
			any = true
		end
		for j = 1, inst.Count do
			local slot = inst.Slots[j]
			if slot then
				UpdatePandemicForSlot(inst, slot, glow, desat, border)
			end
		end
	end

	-- This pass has just cleared whatever the last one drew, so there is nothing left to do until
	-- a container comes back or a toggle goes on. On 12.1 that is nearly all the time: the engine
	-- drives the real icons' reveal and only test mode runs through here.
	if not any and pandemicTicker then
		pandemicTicker:Cancel()
		pandemicTicker = nil
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
	instance.PandemicBorder = false
	instance.IconZoom = true
	instance.MasqueGroup = Masque and groupName and Masque:Group(addonName, groupName) or nil

	instance:SetCount(count)

	instances[#instances + 1] = instance

	return instance
end

---Shows or hides the container. Mirrors AuraContainerDisplay's setter so callers holding either
---kind of container can use the same call.
---@param shown boolean
function M:SetShown(shown)
	shown = shown == true
	self.Frame:SetShown(shown)

	-- The ticker stops itself once nothing needs it, so coming back into view is one of the
	-- moments that has to start it again.
	if shown and (self.PandemicGlow or self.PandemicDesaturate or self.PandemicBorder) then
		EnsurePandemicTicker()
	end
end

function M:Show()
	self:SetShown(true)
end

function M:Hide()
	self:SetShown(false)
end

---@return boolean
function M:IsShown()
	return self.Frame:IsShown() == true
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
				if slot.PandemicOverlay then
					slot.PandemicOverlay:SetAlpha(0)
				end
			end
		end
	else
		EnsurePandemicTicker()
	end
end

---Tints the pandemic-window border ring; nil components fall back to the built-in amber.
---@param r number?
---@param g number?
---@param b number?
function M:SetPandemicBorderColor(r, g, b)
	if self.PandemicColorR == r and self.PandemicColorG == g and self.PandemicColorB == b then
		return
	end
	self.PandemicColorR = r
	self.PandemicColorG = g
	self.PandemicColorB = b
	for i = 1, #self.Slots do
		local slot = self.Slots[i]
		if slot and slot.PandemicRing then
			slot.PandemicRing.Texture:SetVertexColor(r or 1, g or 0.6, b or 0.1, 1)
		end
	end
end

---Enables or disables the pandemic-window border ring, matching the engine-driven ring real
---12.1 icons carry.
---@param enabled boolean
function M:SetPandemicBorder(enabled)
	enabled = enabled and true or false
	if self.PandemicBorder == enabled then
		return
	end
	self.PandemicBorder = enabled
	if not enabled then
		for i = 1, self.Count do
			local slot = self.Slots[i]
			if slot and slot.PandemicRing then
				slot.PandemicRing:SetAlpha(0)
			end
		end
	else
		EnsurePandemicTicker()
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
				slot.Icon:SetDesaturation(0)
			end
		end
	else
		EnsurePandemicTicker()
	end
end

---Crops Blizzard's baked border off the slot icons, or puts it back. A Masque skin owns the
---icon's shape, so a skinned container is left alone: its slots take the skin's crop when they
---are added to the group, and re-cropping them here would fight it.
---@param zoomed boolean
function M:SetIconZoom(zoomed)
	zoomed = zoomed ~= false
	if self.IconZoom == zoomed then
		return
	end
	self.IconZoom = zoomed
	if self.MasqueGroup then
		return
	end
	local left, right, top, bottom = iconUtil:TexCoord(zoomed)
	for i = 1, #self.Slots do
		local slot = self.Slots[i]
		if slot then
			slot.Icon:SetTexCoord(left, right, top, bottom)
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

	ScheduleMasqueReSkin(self)
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
			if slot.StackText then
				UpdateStackFontSize(slot.StackText, self.Size, self.FontScale)
			end
		end
	end

	ScheduleMasqueReSkin(self)
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
		if slot and slot.StackText then
			UpdateStackFontSize(slot.StackText, self.Size, self.FontScale)
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
		-- Composite the slot's icon/cooldown/text regions in a single render pass. Per slot so
		-- an animating swipe only re-composites its own icon rather than the whole row.
		slotFrame:SetFlattensRenderLayers(true)

		local icon = slotFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
		icon:SetAllPoints()
		icon:SetTexCoord(iconUtil:TexCoord(self.IconZoom))

		local cd = CreateFrame("Cooldown", NextFrameName("Cooldown"), slotFrame, "CooldownFrameTemplate")
		cd:SetAllPoints()
		cd:SetDrawEdge(false)
		cd:SetDrawBling(false)
		cd:SetSwipeColor(0, 0, 0, 0.8)
		iconUtil:SquareSwipe(cd)
		UpdateCooldownFontSize(cd, self.Size, self.FontScale)

		-- Glow lives on this overlay so we can SetAlpha it with the pandemic curve's
		-- secret-number result without dimming the icon underneath.
		local pandemicOverlay = CreateFrame("Frame", NextFrameName("Pandemic"), slotFrame)
		pandemicOverlay:SetAllPoints()
		pandemicOverlay:SetFrameLevel(cd:GetFrameLevel() + 5)
		pandemicOverlay:SetAlpha(0)

		-- Own child frame levelled above the cooldown, which otherwise covers parent regions.
		local textOverlay = CreateFrame("Frame", nil, slotFrame)
		textOverlay:SetAllPoints()
		textOverlay:SetFrameLevel(cd:GetFrameLevel() + 5)

		-- Built with the slot rather than on first use, so a skin can be handed the count region
		-- it is going to position: Masque only ever sees a button once, when it is added.
		local stackText = textOverlay:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		stackText:SetPoint("BOTTOMRIGHT", slotFrame, "BOTTOMRIGHT", -1, 1)
		stackText:SetJustifyH("RIGHT")
		stackText:Hide()

		-- Skinned as an aura, strictly, exactly like the 12.1 aura buttons in the same group: the
		-- test icons are meant to preview what a real match draws, skin included.
		if self.MasqueGroup then
			self.MasqueGroup:AddButton(slotFrame, {
				Icon = icon,
				Cooldown = cd,
				Count = stackText,
			}, "Aura", true)
		end

		self.Slots[i] = {
			Frame = slotFrame,
			Icon = icon,
			Cooldown = cd,
			StackText = stackText,
			PandemicOverlay = pandemicOverlay,
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
---@field ShowMilliseconds boolean? Show tenths of a second under 5s; clock-driven cooldowns only
---@field ColorCountdown boolean? Colour the countdown by remaining time; needs StartTime+Duration
---@field StackText string|number? Stack count drawn in the icon's corner; nil hides it
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
	if slot.Cooldown.SetCountdownMillisecondsThreshold then
		-- Only affects clock-driven cooldowns (test mode); duration objects ignore it.
		slot.Cooldown:SetCountdownMillisecondsThreshold(options.ShowMilliseconds and 5 or 0)
	end

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

	-- Colour by remaining time only when the expiry is addon-known (synthetic test timers);
	-- aura duration objects keep their remaining time secret.
	if options.ColorCountdown and slot.StartTime and slot.Duration then
		RegisterCountdownColor(slot.Cooldown, slot.StartTime + slot.Duration)
	else
		ResetCountdownColor(slot.Cooldown)
	end

	if options.StackText then
		UpdateStackFontSize(slot.StackText, self.Size, self.FontScale)
		slot.StackText:SetText(options.StackText)
		slot.StackText:Show()
	else
		slot.StackText:Hide()
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
	ResetCountdownColor(slot.Cooldown)
	if slot.StackText then
		slot.StackText:Hide()
	end
	slot.DurationObject = nil
	slot.StartTime = nil
	slot.Duration = nil
	slot.IsCC = false
	StopGlow(slot)
	if slot.PandemicOverlay then
		slot.PandemicOverlay:SetAlpha(0)
	end
	slot.Icon:SetDesaturation(0)
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
---@field PandemicBorder boolean
---@field IconZoom boolean
---@field SetCount fun(self: IconSlotContainer, count: number)
---@field SetSpacing fun(self: IconSlotContainer, spacing: number)
---@field SetGrowDown fun(self: IconSlotContainer, enabled: boolean)
---@field SetInvertLayout fun(self: IconSlotContainer, inverted: boolean)
---@field SetIconSize fun(self: IconSlotContainer, size: number)
---@field SetFontScale fun(self: IconSlotContainer, scale: number)
---@field SetPandemicGlow fun(self: IconSlotContainer, enabled: boolean)
---@field SetPandemicBorder fun(self: IconSlotContainer, enabled: boolean)
---@field SetPandemicBorderColor fun(self: IconSlotContainer, r: number?, g: number?, b: number?)
---@field SetPandemicDesaturate fun(self: IconSlotContainer, enabled: boolean)
---@field SetIconZoom fun(self: IconSlotContainer, zoomed: boolean)
---@field SetSlot fun(self: IconSlotContainer, slotIndex: number, options: IconSlotOptions)
---@field ClearSlot fun(self: IconSlotContainer, slotIndex: number)
---@field SetSlotUnused fun(self: IconSlotContainer, slotIndex: number)
---@field ResetAllSlots fun(self: IconSlotContainer)
