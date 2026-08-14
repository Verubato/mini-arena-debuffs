---@type string, Addon
local addonName, addon = ...
local mini = addon.Framework
local wowEx = addon.WoWEx
local IconSlotContainer = addon.IconSlotContainer
local AuraContainerDisplay = addon.AuraContainerDisplay
-- TEMPORARY dual path: on 12.1+ real displays are AuraContainerDisplays (the engine tracks and
-- renders the auras); on 12.0 they are IconSlotContainers fed by legacy aura reads. Remove the
-- legacy path once 12.1 is live everywhere. Test mode always uses IconSlotContainers - it only
-- renders synthetic cooldowns, which needs no aura API on either client.
local useAuraContainers = wowEx:UseAuraContainers()
local eventsFrame
---@type { Container: IconSlotContainer|AuraContainerDisplay, Unit: string }
local entries = {}
---@type IconSlotContainer[]
local testContainers = {}
local testArenaFrames = {}
local testMode = false
local maxTestFrames = 3
---@type Db
local db
-- Durations are staggered so the colour-by-time preview crosses every band (red under 5s,
-- yellow to the minute, white above); the stack count previews the Show Stacks toggle.
local testSpells = {
	{ Spell = 8921, Duration = 6 },               -- Moonfire
	{ Spell = 34914, Duration = 12, Stacks = 2 }, -- Vampiric Touch
	{ Spell = 188389, Duration = 20 },            -- Flame Shock
	{ Spell = 1079, Duration = 45 },              -- Rip
	{ Spell = 1822, Duration = 75 },              -- Rake
}

local filter = "HARMFUL|PLAYER"
-- Masque sub-group both display paths skin through, so a chosen skin follows the icons whichever
-- one is drawing them.
local masqueGroup = "MiniArenaDebuffs"

-- Parsed spell filter maps, rebuilt only when the configured text or mode changes. The display
-- compares the maps by reference, so handing back the same tables makes an unchanged refresh
-- free and a changed one a real re-filter.
local spellFilterCache = {}

local function GetSpellFilterMaps()
	local sf = db.SpellFilter
	local mode = (sf and sf.Mode) or "OFF"
	local text = (sf and sf.Spells) or ""

	if spellFilterCache.Mode ~= mode or spellFilterCache.Text ~= text then
		spellFilterCache.Mode = mode
		spellFilterCache.Text = text
		spellFilterCache.Include = nil
		spellFilterCache.Exclude = nil

		if mode ~= "OFF" then
			local map, count = {}, 0
			for id in text:gmatch("%d+") do
				local spellId = tonumber(id)
				if spellId and spellId > 0 then
					map[spellId] = true
					count = count + 1
				end
			end

			-- An empty include map would hide every debuff, so an empty list means no filter.
			if count > 0 then
				if mode == "INCLUDE" then
					spellFilterCache.Include = map
				else
					spellFilterCache.Exclude = map
				end
			end
		end
	end

	return spellFilterCache.Include, spellFilterCache.Exclude
end

---The configured pandemic ring tint as the {r, g, b} array the display style expects.
---@return number[]
local function GetPandemicColor()
	local color = db.Icons.PandemicColor or {}
	return { color.R or 1, color.G or 0.6, color.B or 0.1 }
end

---@return AuraDisplayStyle
local function BuildStyle()
	return {
		ReverseCooldown = db.Icons.ReverseCooldown,
		HideSwipe = db.Icons.HideSwipe,
		HideNumbers = db.Icons.HideNumbers,
		FontScale = db.Icons.FontScale or 1.0,
		ShowStacks = db.Icons.ShowStacks,
		ShowMilliseconds = db.Icons.ShowMilliseconds,
		ColorCountdown = db.Icons.ColorCountdown,
		PandemicGlow = db.Icons.PandemicGlow,
		PandemicColor = GetPandemicColor(),
		Zoom = db.Icons.Zoom ~= false,
	}
end

local function GetSortRule()
	if db.SortMethod == "INDEX" then
		return Enum.UnitAuraSortRule.Unsorted
	end
	return Enum.UnitAuraSortRule.Expiration
end

local function GetSortDirection()
	if db.SortDirection == "-" then
		return Enum.UnitAuraSortDirection.Reverse
	end
	return Enum.UnitAuraSortDirection.Normal
end

local function ApplyGrowDirection(container)
	local grow = db.Grow or "RIGHT"
	container:SetGrowDown(false)
	container:SetInvertLayout(grow == "LEFT")
end

local function UpdateContainerOptions(container)
	container:SetCount(db.MaxIcons or 6)
	container:SetIconSize(db.Icons.Size or 36)
	container:SetSpacing(db.Icons.Spacing or 2)
	container:SetFontScale(db.Icons.FontScale or 1.0)
	container:SetPandemicGlow(db.Icons.PandemicGlow or false)
	container:SetPandemicDesaturate(db.Icons.PandemicDesaturate or false)
	local pandemicColor = GetPandemicColor()
	container:SetPandemicColor(pandemicColor[1], pandemicColor[2], pandemicColor[3])
	container:SetIconZoom(db.Icons.Zoom ~= false)
	ApplyGrowDirection(container)
end

local function CreateContainer()
	local container = IconSlotContainer:New(
		UIParent,
		db.MaxIcons or 6,
		db.Icons.Size or 36,
		db.Icons.Spacing or 2,
		masqueGroup
	)
	container:Hide()
	container:SetPandemicGlow(db.Icons.PandemicGlow or false)
	container:SetPandemicDesaturate(db.Icons.PandemicDesaturate or false)
	local pandemicColor = GetPandemicColor()
	container:SetPandemicColor(pandemicColor[1], pandemicColor[2], pandemicColor[3])
	container:SetIconZoom(db.Icons.Zoom ~= false)
	ApplyGrowDirection(container)
	return container
end

---Pushes the current settings onto a 12.1 AuraContainerDisplay; the engine handles the aura
---tracking itself, so this replaces both UpdateContainerOptions and UpdateContainer there.
local function UpdateDisplayOptions(display)
	display:SetMaxIcons(db.MaxIcons or 6)
	display:SetGrow(db.Grow or "RIGHT")
	display:SetSortMethod(db.SortMethod, db.SortDirection)
	local includeSpellIDs, excludeSpellIDs = GetSpellFilterMaps()
	display:SetAuraFilters(db.Icons.HideUnimportant or false, includeSpellIDs, excludeSpellIDs)
	display:ApplyConfig(db.Icons.Size or 36, db.Icons.Spacing or 2, BuildStyle())
end

local function UpdateContainer(container, unit)
	if not unit then
		container:ResetAllSlots()
		return
	end

	local auraList = C_UnitAuras.GetUnitAuras(unit, filter, container.Count, GetSortRule(), GetSortDirection())

	container:ResetAllSlots()

	if not auraList then
		return
	end

	for idx, aura in ipairs(auraList) do
		local durationObj = C_UnitAuras.GetAuraDuration(unit, aura.auraInstanceID)
		-- nameplateShowPersonal is a secret boolean in tainted contexts; assign without testing it
		local nameplateShowPersonal
		if db.Icons.HideUnimportant then
			nameplateShowPersonal = aura.nameplateShowPersonal
		end
		-- IsAuraFilteredOutByInstanceID returns false when the aura matches all filter terms.
		-- We already know it's HARMFUL, so a false result here means it's CC.
		local isCC = not C_UnitAuras.IsAuraFilteredOutByInstanceID(
			unit, aura.auraInstanceID, "HARMFUL|CROWD_CONTROL"
		)
		container:SetSlot(idx, {
			Texture = aura.icon,
			DurationObject = durationObj,
			HideSwipe = db.Icons.HideSwipe,
			ReverseCooldown = db.Icons.ReverseCooldown,
			HideNumbers = db.Icons.HideNumbers,
			NameplateShowPersonal = nameplateShowPersonal,
			IsCC = isCC,
		})
	end
end

local function GetDefaultAnchor(i)
	local sarena = _G["sArenaEnemyFrame" .. i]

	if sarena then
		return sarena
	end

	-- If sArena is running, don't fall back to Blizzard frames as they will be invisible
	if _G["sArenaEnemyFrame1"] then
		return nil
	end

	return _G["CompactArenaFrameMember" .. i]
end

local function GetOverrideAnchor(i)
	local anchor = db["Anchor" .. i]

	if not anchor or anchor == "" then
		return nil
	end

	local frame = _G[anchor]

	if not frame then
		mini:NotifyWithPrefix("Bad anchor '%s' for arena%d.", anchor, i)
		return nil
	end

	return frame
end

local function GetAnchor(i)
	local anchor = GetOverrideAnchor(i)

	if anchor then
		return anchor
	end

	return GetDefaultAnchor(i)
end

local function AnchorContainer(container, anchor)
	local grow = db.Grow or "RIGHT"
	if useAuraContainers and grow == "CENTER" then
		-- The container's size can be secret on 12.1, so a centred row can't be positioned.
		grow = "RIGHT"
	end
	local anchorPoint, relativePoint
	if grow == "LEFT" then
		anchorPoint = "RIGHT"
		relativePoint = "LEFT"
	elseif grow == "CENTER" then
		anchorPoint = "CENTER"
		relativePoint = "CENTER"
	else
		anchorPoint = "LEFT"
		relativePoint = "RIGHT"
	end
	container.Frame:ClearAllPoints()
	container.Frame:SetPoint(anchorPoint, anchor, relativePoint, db.Anchor.Offset.X, db.Anchor.Offset.Y)
	container.Frame:SetFrameLevel((anchor:GetFrameLevel() or 0) + 1)
end

local function GetCurrentAnchors()
	local anchors = {}
	local index = 1
	local anchor = GetAnchor(index)

	while anchor do
		anchors[index] = anchor
		index = index + 1
		anchor = GetAnchor(index)
	end

	return anchors
end

local function EnsureEntry(anchor)
	local unit = anchor.unit or anchor:GetAttribute("unit")

	if not unit then
		return nil
	end

	local entry = entries[anchor]

	if not entry then
		local container
		if useAuraContainers then
			-- The style rides along at creation: buttons are born styled in initializeFrame, and
			-- a display created inside an arena can't be restyled until the match ends.
			container = AuraContainerDisplay:New(
				UIParent, unit, db.MaxIcons or 6, db.Icons.Size or 36, db.Icons.Spacing or 2, BuildStyle(),
				masqueGroup
			)
			container:Hide()
		else
			container = CreateContainer()
		end
		entry = { Container = container, Unit = unit }
		entries[anchor] = entry
	else
		entry.Unit = unit
	end

	return entry
end

local function EnsureEntries()
	for _, anchor in ipairs(GetCurrentAnchors()) do
		EnsureEntry(anchor)
	end
end

local function UpdateTestContainer(container)
	local now = GetTime()
	local used = 0

	for _, spec in ipairs(testSpells) do
		if used >= container.Count then
			break
		end

		local texture = C_Spell.GetSpellTexture(spec.Spell)

		if texture then
			used = used + 1
			container:SetSlot(used, {
				Texture = texture,
				StartTime = now,
				Duration = spec.Duration,
				HideSwipe = db.Icons.HideSwipe,
				ReverseCooldown = db.Icons.ReverseCooldown,
				HideNumbers = db.Icons.HideNumbers,
				-- The extras preview 12.1-only settings; their toggles don't exist on 12.0.
				ShowMilliseconds = useAuraContainers and db.Icons.ShowMilliseconds or false,
				ColorCountdown = useAuraContainers and db.Icons.ColorCountdown or false,
				StackText = (useAuraContainers and db.Icons.ShowStacks and spec.Stacks) or nil,
			})
		end
	end

	for idx = used + 1, container.Count do
		container:SetSlotUnused(idx)
	end
end

local function EnsureTestContainer(i)
	local container = testContainers[i]

	if not container then
		container = CreateContainer()
		testContainers[i] = container
	else
		UpdateContainerOptions(container)
	end

	UpdateTestContainer(container)

	return container
end

local function CreateTestFrame(i)
	local frame = CreateFrame("Frame", addonName .. "TestFrame" .. i, UIParent, "BackdropTemplate")

	frame:SetSize(144, 72)

	local _, class = UnitClass("player")
	local colour = RAID_CLASS_COLORS[class] or NORMAL_FONT_COLOR

	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})

	frame:SetBackdropColor(colour.r, colour.g, colour.b, 0.9)
	frame:SetBackdropBorderColor(0, 0, 0, 1)

	frame.Text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.Text:SetPoint("CENTER")
	frame.Text:SetText(("arena%d"):format(i))
	frame.Text:SetTextColor(1, 1, 1)

	return frame
end

local function EnsureTestArenaFrames()
	for i = 1, maxTestFrames do
		local frame = testArenaFrames[i]

		if not frame then
			testArenaFrames[i] = CreateTestFrame(i)
			frame = testArenaFrames[i]
		end

		local anchor = GetAnchor(i)
		frame:ClearAllPoints()

		if anchor and anchor:GetWidth() > 0 and anchor:GetHeight() > 0 then
			frame:SetAllPoints(anchor)
			frame:SetFrameStrata(anchor:GetFrameStrata() or "DIALOG")
			frame:SetFrameLevel((anchor:GetFrameLevel() or 0) + 10)
		else
			frame:SetSize(144, 72)
			frame:SetPoint("CENTER", UIParent, "CENTER", 300, -i * frame:GetHeight())
		end
	end
end

local function RealMode()
	-- Hide all test containers
	for _, container in pairs(testContainers) do
		container:Hide()
	end

	for _, tf in ipairs(testArenaFrames) do
		tf:Hide()
	end

	-- Build set of currently active anchors
	local currentAnchors = {}
	for _, anchor in ipairs(GetCurrentAnchors()) do
		currentAnchors[anchor] = true
	end

	-- Update or hide each entry (hidden AuraContainers unregister their events, so Hide is
	-- also the cheap parked state on 12.1)
	for anchor, entry in pairs(entries) do
		local unit = currentAnchors[anchor] and (anchor.unit or anchor:GetAttribute("unit")) or nil
		-- The arena frames outlive the match, so an anchor still being there says nothing about
		-- whether there is an opponent to draw for. UnitExists is what ends the display, the same
		-- test Blizzard's own arena frames use: without it a 12.1 container keeps the last match's
		-- icons on screen, since a unit that no longer exists sends no aura event to clear them.
		if not unit or not UnitExists(unit) then
			entry.Container:Hide()
		else
			entry.Unit = unit

			if useAuraContainers then
				UpdateDisplayOptions(entry.Container)
				entry.Container:SetUnit(unit)
				AnchorContainer(entry.Container, anchor)
			else
				UpdateContainerOptions(entry.Container)
				AnchorContainer(entry.Container, anchor)
				UpdateContainer(entry.Container, entry.Unit)
			end
			entry.Container:Show()
		end
	end
end

local function TestMode()
	-- Hide real containers
	for _, entry in pairs(entries) do
		entry.Container:Hide()
	end

	-- Try to anchor onto real visible frames first
	local anchors = GetCurrentAnchors()
	local anyRealShown = false

	for i, anchor in ipairs(anchors) do
		if anchor:IsVisible() then
			anyRealShown = true
			local container = EnsureTestContainer(i)
			AnchorContainer(container, anchor)
			container:Show()
		end
	end

	if anyRealShown then
		for _, tf in ipairs(testArenaFrames) do
			tf:Hide()
		end

		-- Hide any extra test containers not used
		for i = #anchors + 1, maxTestFrames do
			if testContainers[i] then
				testContainers[i]:Hide()
			end
		end

		return
	end

	-- No real frames visible — show fake arena frames
	EnsureTestArenaFrames()

	for i = 1, maxTestFrames do
		local container = EnsureTestContainer(i)
		local testFrame = testArenaFrames[i]
		AnchorContainer(container, testFrame)
		container:Show()
		testFrame:Show()
	end
end

local function UpdateUnitAuraRegistration()
	-- 12.1: AuraContainers react to aura changes internally; the addon never reads UNIT_AURA.
	if useAuraContainers then
		return
	end

	eventsFrame:UnregisterEvent("UNIT_AURA")
	local seen = {}
	local unitList = {}
	for _, entry in pairs(entries) do
		local unit = entry.Unit
		if unit and not seen[unit] then
			seen[unit] = true
			unitList[#unitList + 1] = unit
		end
	end
	if #unitList > 0 then
		eventsFrame:RegisterUnitEvent("UNIT_AURA", unpack(unitList))
	end
end

local function HasRelevantAuraChanges(unit, auraData)
	if auraData.isFullUpdate then
		return true
	end
	if auraData.addedAuras then
		for _, aura in ipairs(auraData.addedAuras) do
			if not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, aura.auraInstanceID, filter) then
				return true
			end
		end
	end
	if auraData.updatedAuraInstanceIDs then
		for _, auraInstanceID in ipairs(auraData.updatedAuraInstanceIDs) do
			if not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, auraInstanceID, filter) then
				return true
			end
		end
	end
	-- Removed auras no longer exist, so the filter can't be queried; refresh on any removal.
	return (auraData.removedAuraInstanceIDs and #auraData.removedAuraInstanceIDs > 0)
end

local function OnEvent(_, event, unit, auraData)
	if event == "PLAYER_REGEN_DISABLED" then
		if testMode then
			testMode = false
			addon:Refresh()
		end
	elseif event == "PLAYER_ENTERING_WORLD" or event == "ARENA_OPPONENT_UPDATE" then
		addon:Refresh()
	elseif event == "UNIT_AURA" then
		if not testMode and HasRelevantAuraChanges(unit, auraData) then
			for _, entry in pairs(entries) do
				if entry.Unit == unit then
					UpdateContainer(entry.Container, entry.Unit)
				end
			end
		end
	end
end

local function OnAddonLoaded()
	addon.Config:Init()

	db = mini:GetSavedVars()

	eventsFrame = CreateFrame("Frame")
	eventsFrame:SetScript("OnEvent", OnEvent)
	eventsFrame:RegisterEvent("ARENA_OPPONENT_UPDATE")
	eventsFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	eventsFrame:RegisterEvent("PLAYER_REGEN_DISABLED")

	EnsureEntries()
	UpdateUnitAuraRegistration()
end

function addon:Refresh()
	EnsureEntries()
	UpdateUnitAuraRegistration()

	if testMode then
		TestMode()
	else
		RealMode()
	end
end

function addon:ToggleTest()
	testMode = not testMode
	addon:Refresh()

	if InCombatLockdown() then
		mini:NotifyWithPrefix("Can't test during combat, we'll test once combat drops.")
	end
end

mini:WaitForAddonLoad(OnAddonLoaded)

---@class Addon
---@field Framework MiniFramework
---@field WoWEx WoWEx
---@field SpellNameIndex table<string, string>
---@field SpellSearch SpellSearch
---@field Config Config
---@field CustomAnchors table
---@field IconSlotContainer IconSlotContainer
---@field AuraContainerDisplay AuraContainerDisplay
---@field Refresh fun(self: table)
---@field ToggleTest fun(self: table)
