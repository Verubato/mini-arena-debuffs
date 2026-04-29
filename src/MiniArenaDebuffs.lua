---@type string, Addon
local addonName, addon = ...
local mini = addon.Framework
local IconSlotContainer = addon.IconSlotContainer
local scheduler = addon.Scheduler
local config = addon.Config
local eventsFrame
---@type { Container: IconSlotContainer, Unit: string }
local entries = {}
---@type IconSlotContainer[]
local testContainers = {}
local testArenaFrames = {}
local testMode = false
local maxTestFrames = 3
---@type Db
local db
---@type Db
local dbDefaults = config.DbDefaults
local testSpells = {
	33786, -- Cyclone
	118,   -- Polymorph
	3355,  -- Freezing Trap
	853,   -- Hammer of Justice
	408,   -- Kidney Shot
}

local filter = "HARMFUL|PLAYER"

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
	ApplyGrowDirection(container)
end

local function CreateContainer()
	local container = IconSlotContainer:New(
		UIParent,
		db.MaxIcons or 6,
		db.Icons.Size or 36,
		db.Icons.Spacing or 2,
		"MiniArenaDebuffs"
	)
	container.Frame:Hide()
	ApplyGrowDirection(container)
	return container
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
		container:SetSlot(idx, {
			Texture = aura.icon,
			DurationObject = durationObj,
			HideSwipe = db.Icons.HideSwipe,
			ReverseCooldown = db.Icons.ReverseCooldown,
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
		mini:Notify("Bad anchor '%s' for arena%d.", anchor, i)
		return nil
	end

	return frame
end

local function GetAnchor(i)
	local anchor = GetOverrideAnchor(i)

	if anchor and anchor:IsVisible() then
		return anchor
	end

	return GetDefaultAnchor(i)
end

local function AnchorContainer(container, anchor)
	local grow = db.Grow or "RIGHT"
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
		local container = CreateContainer()
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
	container:ResetAllSlots()

	local now = GetTime()
	local duration = 16
	for idx, spellId in ipairs(testSpells) do
		if idx > container.Count then
			break
		end

		local texture = C_Spell.GetSpellTexture(spellId)

		if texture then
			container:SetSlot(idx, {
				Texture = texture,
				StartTime = now,
				Duration = duration,
				HideSwipe = db.Icons.HideSwipe,
				ReverseCooldown = db.Icons.ReverseCooldown,
			})
		end
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
		container.Frame:Hide()
	end

	for _, tf in ipairs(testArenaFrames) do
		tf:Hide()
	end

	-- Build set of currently active anchors
	local currentAnchors = {}
	for _, anchor in ipairs(GetCurrentAnchors()) do
		currentAnchors[anchor] = true
	end

	-- Update or hide each entry
	for anchor, entry in pairs(entries) do
		if not currentAnchors[anchor] then
			entry.Container.Frame:Hide()
		else
			local unit = anchor.unit or anchor:GetAttribute("unit")
			entry.Unit = unit

			UpdateContainerOptions(entry.Container)
			AnchorContainer(entry.Container, anchor)
			UpdateContainer(entry.Container, entry.Unit)
			entry.Container.Frame:Show()
		end
	end
end

local function TestMode()
	-- Hide real containers
	for _, entry in pairs(entries) do
		entry.Container.Frame:Hide()
	end

	-- Try to anchor onto real visible frames first
	local anchors = GetCurrentAnchors()
	local anyRealShown = false

	for i, anchor in ipairs(anchors) do
		if anchor:IsVisible() then
			anyRealShown = true
			local container = EnsureTestContainer(i)
			AnchorContainer(container, anchor)
			container.Frame:Show()
		end
	end

	if anyRealShown then
		for _, tf in ipairs(testArenaFrames) do
			tf:Hide()
		end

		-- Hide any extra test containers not used
		for i = #anchors + 1, maxTestFrames do
			if testContainers[i] then
				testContainers[i].Frame:Hide()
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
		container.Frame:Show()
		testFrame:Show()
	end
end

local function UpdateUnitAuraRegistration()
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

local function HasRelevantAuraChanges(auraData)
	if auraData.isFullUpdate then
		return true
	end
	if auraData.addedAuras then
		for _, aura in ipairs(auraData.addedAuras) do
			if aura.isHarmful and aura.isFromPlayerOrPlayerPet then
				return true
			end
		end
	end
	return (auraData.updatedAuraInstanceIDs and #auraData.updatedAuraInstanceIDs > 0)
		or (auraData.removedAuraInstanceIDs and #auraData.removedAuraInstanceIDs > 0)
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
		if not testMode and HasRelevantAuraChanges(auraData) then
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
	addon.Scheduler:Init()

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
	if InCombatLockdown() then
		scheduler:RunWhenCombatEnds(function()
			addon:Refresh()
		end, "Refresh")
		return
	end

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
		mini:Notify("Can't test during combat, we'll test once combat drops.")
	end
end

mini:WaitForAddonLoad(OnAddonLoaded)

---@class Addon
---@field Framework MiniFramework
---@field Scheduler Scheduler
---@field Config Config
---@field CustomAnchors table
---@field IconSlotContainer IconSlotContainer
---@field Refresh fun(self: table)
---@field ToggleTest fun(self: table)
