local _, addon = ...
---@type MiniFramework
local mini = addon.Framework
local eventsFrame
local headers = {}
local testHeaders = {}
local testArenaFrames = {}
local testMode = false
local maxHeaders = 3
local maxAuras = 40
local questionMarkIcon = 134400
local pendingRefresh = false

---@type Db
local dbDefaults = addon.Config.DbDefaults

---@type Db
local db

local testSpells = {
	33786, -- Cyclone
	118, -- Polymorph
	51514, -- Hex
	3355, -- Freezing Trap
	853, -- Hammer of Justice
	408, -- Kidney Shot
}

-- blizzard hardcoded values
local debuffBorderTextureCoords = {
	left = 0.296875,
	right = 0.5703125,
	top = 0,
	bottom = 0.515625,
}

local function GetSpellIcon(spellID)
	if C_Spell and C_Spell.GetSpellTexture then
		return C_Spell.GetSpellTexture(spellID)
	end

	if not GetSpellInfo then
		return nil
	end

	local _, _, icon = GetSpellInfo(spellID)
	return icon
end

local function GetRealArenaFrame(i)
	local anchor = db["ArenaFrame" .. i .. "Anchor"]
	local default = _G["CompactArenaFrameMember" .. i]

	if not anchor then
		return default
	end

	local frame = _G[anchor]

	if not frame then
		mini:Notify("Bad anchor '%s' for arena frame %d.", anchor, i)
		return default
	end

	return frame
end

local function GetArenaAnchorFrame(i)
	-- In normal mode: anchor to the real Blizzard frames.
	-- In test mode: anchor to our fake frames, positioned over the real ones if available.
	if not testMode then
		return GetRealArenaFrame(i)
	end

	if not testArenaFrames[i] then
		testArenaFrames[i] = CreateTestArenaFrame(i)
	end

	return testArenaFrames[i]
end

local function OnHeaderEvent(header, event, arg1)
	local unit = header:GetAttribute("unit")
	local filter = header:GetAttribute("filter")

	if not unit then
		return
	end

	if event ~= "UNIT_AURA" then
		return
	end

	if arg1 ~= unit then
		return
	end

	for i = 1, maxAuras do
		local child = header:GetAttribute("child" .. i)

		if not child or not child:IsShown() then
			break
		end

		local icon = child.Icon
		local cooldown = child.Cooldown

		if not icon or not cooldown then
			-- invalid xml
			break
		end

		icon:SetAllPoints(child)

		local data = C_UnitAuras.GetAuraDataByIndex(unit, child:GetID(), filter)

		if data then
			-- this will be a secret value in midnight, but it's still usable as a parameter
			icon:SetTexture(data.icon)
			icon:Show()

			local start
			local duration
			local durationInfo = C_UnitAuras.GetAuraDuration(unit, data.auraInstanceID)

			if durationInfo then
				duration = durationInfo:GetTotalDuration()
				start = durationInfo:GetStartTime()
			end

			if start and duration then
				child.Cooldown:SetCooldown(start, duration)
				child.Cooldown:Show()
			else
				child.Cooldown:Hide()
				child.Cooldown:SetCooldown(0, 0)
			end
		else
			icon:Hide()
		end
	end
end

local function RefreshHeaderChildSizes(header)
	local iconSize = tonumber(db.IconSize) or dbDefaults.IconSize

	for i = 1, maxAuras do
		local child = header:GetAttribute("child" .. i)

		if not child then
			-- children are created sequentially; if this one doesn't exist, later ones won't either
			break
		end

		child:SetSize(iconSize, iconSize)

		-- make sure the icon size stays correct
		if child.Icon then
			child.Icon:SetAllPoints(child)
		end

		-- keep cooldown filling the button
		if child.Cooldown then
			child.Cooldown:ClearAllPoints()
			child.Cooldown:SetAllPoints(child)
		end
	end
end

local function UpdateHeader(header, anchorFrame, unit)
	header:ClearAllPoints()
	header:SetPoint(
		db.ContainerAnchorPoint,
		anchorFrame,
		db.ContainerRelativePoint,
		db.ContainerOffsetX,
		db.ContainerOffsetY
	)

	local iconSize = tonumber(db.IconSize) or dbDefaults.IconSize

	header:SetAttribute("unit", unit)

	header:SetAttribute("filter", db.Filter or dbDefaults.Filter)

	-- xoffset of each icon within the container is the width of the icon itself plus some padding
	header:SetAttribute("xOffset", iconSize + (tonumber(db.IconPaddingX) or dbDefaults.IconPaddingX))

	-- no yoffset padding until we wrap
	header:SetAttribute("yOffset", 0)

	header:SetAttribute("wrapAfter", tonumber(db.IconsPerRow) or dbDefaults.IconsPerRow)
	header:SetAttribute("maxWraps", tonumber(db.Rows) or dbDefaults.Rows)

	-- maintain the same x offset
	header:SetAttribute("wrapXOffset", 0)

	-- wrap the next icons upwards
	header:SetAttribute("wrapYOffset", -iconSize - (tonumber(db.IconPaddingY) or dbDefaults.IconPaddingY))

	header:SetAttribute("sortMethod", tostring(db.SortMethod or dbDefaults.SortMethod))

	header:SetAttribute("x-iconSize", iconSize)

	-- refresh any icon sizes that may have changed
	RefreshHeaderChildSizes(header)

	header:SetShown(not testMode)
end

local function CreateSecureHeader(arenaFrame, unit, index)
	local header = CreateFrame("Frame", "MiniArenaDebuffsSecureHeader" .. index, UIParent, "SecureAuraHeaderTemplate")

	-- use our template
	header:SetAttribute("template", "MiniArenaDebuffsAuraButtonTemplate")
	header:SetAttribute("point", "TOPLEFT")
	header:SetAttribute("unit", unit)
	header:SetAttribute("sortDirection", "+")
	header:SetAttribute("minWidth", 1)
	header:SetAttribute("minHeight", 1)

	header:SetAttribute(
		"initialConfigFunction",
		[[
			local header = self:GetParent()
			local iconSize = header:GetAttribute("x-iconSize")

			self:SetWidth(iconSize)
			self:SetHeight(iconSize)
			-- disable mouse so you can still mouseover cast
			self:EnableMouse(false)
		]]
	)

	header:HookScript("OnEvent", OnHeaderEvent)

	UpdateHeader(header, arenaFrame, unit)

	return header
end

local function EnsureHeaders()
	for i = 1, maxHeaders do
		local arenaFrame = GetRealArenaFrame(i)
		local header = headers[i]

		if not arenaFrame then
			if header then
				header:Hide()
			end
		else
			local unit = arenaFrame.unit or ("arena" .. i)

			if not header then
				headers[i] = CreateSecureHeader(arenaFrame, unit, i)
			else
				UpdateHeader(header, arenaFrame, unit)
			end
		end
	end
end

local function CreateTestArenaFrame(i)
	local frame = CreateFrame("Frame", "MiniArenaDebuffsTestArenaFrame" .. i, UIParent, "BackdropTemplate")

	-- same as the max blizzard arena frames size
	frame:SetSize(144, 72)

	local _, class = UnitClass("player")
	local c = RAID_CLASS_COLORS[class] or NORMAL_FONT_COLOR

	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})

	frame:SetBackdropColor(c.r, c.g, c.b, 0.9)
	frame:SetBackdropBorderColor(0, 0, 0, 1)

	frame.Text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.Text:SetPoint("CENTER")
	frame.Text:SetText(("arena%d"):format(i))
	frame.Text:SetTextColor(1, 1, 1)

	return frame
end

local function EnsureTestArenaFrames()
	for i = 1, maxHeaders do
		local frame = testArenaFrames[i]
		if not frame then
			testArenaFrames[i] = CreateTestArenaFrame(i)
			frame = testArenaFrames[i]
		end

		local real = GetRealArenaFrame(i)

		frame:ClearAllPoints()

		if real and real:GetWidth() > 0 and real:GetHeight() > 0 then
			-- sit directly on top of Blizzard arena frame
			frame:SetAllPoints(real)

			-- try to keep it above the real frame
			frame:SetFrameStrata(real:GetFrameStrata() or "DIALOG")
			frame:SetFrameLevel((real:GetFrameLevel() or 0) + 10)
		else
			frame:SetSize(144, 72)
			frame:SetPoint("CENTER", UIParent, "CENTER", 300, -i * frame:GetHeight())
		end

		frame:SetShown(testMode)
	end
end

local function UpdateTestHeader(frame, arenaFrame)
	local cols = math.max(1, tonumber(db.IconsPerRow) or 1)
	local rows = math.max(1, tonumber(db.Rows) or 1)
	local size = math.max(1, tonumber(db.IconSize) or 20)
	local padX = tonumber(db.IconPaddingX) or 0
	local padY = tonumber(db.IconPaddingY) or 0
	local stepX = size + padX
	local stepY = -(size + padY)
	local maxIcons = math.min(#testSpells, cols * rows)

	frame.icons = frame.icons or {}

	for i = 1, maxIcons do
		local btn = frame.icons[i]

		if not btn then
			btn = CreateFrame("Frame", nil, frame)
			btn.icon = btn:CreateTexture(nil, "ARTWORK")
			btn.icon:SetAllPoints()

			btn.border = btn:CreateTexture(nil, "OVERLAY")
			btn.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
			btn.border:SetAllPoints()
			btn.border:SetTexCoord(
				debuffBorderTextureCoords.left,
				debuffBorderTextureCoords.right,
				debuffBorderTextureCoords.top,
				debuffBorderTextureCoords.bottom
			)

			frame.icons[i] = btn
		end

		btn:SetSize(size, size)
		btn.icon:SetTexture(GetSpellIcon(testSpells[i]) or questionMarkIcon)

		local col = (i - 1) % cols
		local row = math.floor((i - 1) / cols)

		btn:ClearAllPoints()
		btn:SetPoint("TOPLEFT", frame, "TOPLEFT", col * stepX, row * stepY)
		btn:Show()
	end

	-- Hide any extra buttons we previously created but no longer need
	for i = maxIcons + 1, #frame.icons do
		frame.icons[i]:Hide()
	end

	local width = (cols * size) + ((cols - 1) * padX)
	local height = (rows * size) + ((rows - 1) * padY)
	frame:SetSize(width, height)

	frame:ClearAllPoints()
	frame:SetPoint(
		db.ContainerAnchorPoint,
		arenaFrame,
		db.ContainerRelativePoint,
		db.ContainerOffsetX,
		db.ContainerOffsetY
	)
end

local function EnsureTestHeaders()
	EnsureTestArenaFrames()

	for i = 1, maxHeaders do
		local arenaFrame = GetArenaAnchorFrame(i)

		if arenaFrame then
			local frame = testHeaders[i]

			if not frame then
				frame = CreateFrame("Frame", nil, UIParent)
				UpdateTestHeader(frame, arenaFrame)
				testHeaders[i] = frame
			else
				UpdateTestHeader(frame, arenaFrame)
			end
		end
	end
end

local function QueueRefresh()
	pendingRefresh = true
end

local function OnEvent(_, event)
	if event == "PLAYER_REGEN_ENABLED" then
		if not pendingRefresh then
			return
		end

		pendingRefresh = false
		addon:Refresh()
		return
	end

	if event == "PLAYER_REGEN_DISABLED" then
		if testMode then
			-- disable test mode as we enter combat
			testMode = false
			addon:Refresh()
		end
	end

	if event == "PLAYER_ENTERING_WORLD" then
		addon:Refresh()
	end
end

local function OnAddonLoaded()
	addon.Config:Init()

	db = mini:GetSavedVars()

	EnsureHeaders()

	eventsFrame = CreateFrame("Frame")
	eventsFrame:SetScript("OnEvent", OnEvent)
	eventsFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	eventsFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
	eventsFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
end

function addon:Refresh()
	if InCombatLockdown() then
		QueueRefresh()
		return
	end

	EnsureHeaders()

	if testMode then
		EnsureTestHeaders()
	end

	for i = 1, maxHeaders do
		if headers[i] then
			headers[i]:SetShown(not testMode)
		end

		if testHeaders[i] then
			testHeaders[i]:SetShown(testMode)
		end

		if testArenaFrames[i] then
			testArenaFrames[i]:SetShown(testMode)
		end
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
