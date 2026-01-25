---@type string, Addon
local addonName, addon = ...
local mini = addon.Framework
local auras = addon.Auras
local scheduler = addon.Scheduler
local config = addon.Config
local eventsFrame
---@type { table: table }
local headers = {}
---@type { table: table }
local testHeaders = {}
local testArenaFrames = {}
local testMode = false
local maxTestFrames = 3
---@type Db
local db
---@type Db
local dbDefaults = config.DbDefaults
local testSpells = {
	33786, -- Cyclone
	118, -- Polymorph
	3355, -- Freezing Trap
	853, -- Hammer of Justice
	408, -- Kidney Shot
}

local function GetDefaultAnchor(i)
	local sarena = _G["sArenaEnemyFrame" .. i]

	if sarena then
		return sarena
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

local function AnchorHeader(header, anchor)
	header:ClearAllPoints()

	if db.SimpleMode.Enabled then
		header:SetPoint("CENTER", anchor, "CENTER", db.SimpleMode.Offset.X, db.SimpleMode.Offset.Y)
	else
		header:SetPoint(
			db.AdvancedMode.Point,
			anchor,
			db.AdvancedMode.RelativePoint,
			db.AdvancedMode.Offset.X,
			db.AdvancedMode.Offset.Y
		)
	end

	header:SetFrameLevel(anchor:GetFrameLevel() + 1)
end

local function EnsureHeader(anchor, unit)
	unit = unit or anchor.unit or anchor:GetAttribute("unit")

	if not unit then
		return nil
	end

	local header = headers[anchor]

	if not header then
		header = auras:CreateHeader(unit)
		headers[anchor] = header
	else
		auras:UpdateHeader(header, unit)
	end

	AnchorHeader(header, anchor)
	header:Show()

	return header
end

local function EnsureHeaders()
	local index = 1
	local anchor = GetAnchor(index)

	while anchor do
		EnsureHeader(anchor)
		index = index + 1
		anchor = GetAnchor(index)
	end
end

local function CreateTestFrame(i)
	local frame = CreateFrame("Frame", addonName .. "TestFrame" .. i, UIParent, "BackdropTemplate")

	-- same as the max blizzard arena frames size
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
			-- sit directly on top of Blizzard frames
			frame:SetAllPoints(anchor)

			-- try to keep it above the real frame
			frame:SetFrameStrata(anchor:GetFrameStrata() or "DIALOG")
			frame:SetFrameLevel((anchor:GetFrameLevel() or 0) + 10)
		else
			frame:SetSize(144, 72)
			frame:SetPoint("CENTER", UIParent, "CENTER", 300, -i * frame:GetHeight())
		end
	end
end

local function UpdateTestHeader(frame)
	local cols = #testSpells
	local rows = 1
	local size = tonumber(db.Icons.Size) or dbDefaults.Icons.Size
	local padX = 0
	local padY = 0
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

			frame.icons[i] = btn
		end

		btn:SetSize(size, size)
		local texture = C_Spell.GetSpellTexture(testSpells[i])
		btn.icon:SetTexture(texture)

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
end

local function EnsureTestHeader(anchor)
	local header = testHeaders[anchor]

	if not header then
		header = CreateFrame("Frame", nil, UIParent)
		testHeaders[anchor] = header
	end

	UpdateTestHeader(header)

	return header
end

local function RealMode()
	for anchor, header in pairs(headers) do
		local unit = header:GetAttribute("unit") or anchor.unit or anchor:GetAttribute("unit")

		if unit then
			-- refresh options
			auras:UpdateHeader(header, unit)
		end

		-- refresh anchor
		AnchorHeader(header, anchor)

		-- refresh visibility
		header:Show()
	end

	for _, testHeader in pairs(testHeaders) do
		testHeader:Hide()
	end

	for _, testArenaFrame in ipairs(testArenaFrames) do
		testArenaFrame:Hide()
	end
end

local function TestMode()
	-- hide the real headers
	for _, header in pairs(headers) do
		header:Hide()
	end

	-- try to show on real frames first
	local anyRealShown = false
	for anchor, _ in pairs(headers) do
		local testHeader = EnsureTestHeader(anchor)

		if anchor and anchor:IsVisible() then
			anyRealShown = true

			AnchorHeader(testHeader, anchor)

			testHeader:Show()
		end
	end

	if anyRealShown then
		-- hide our test frames if any real exist
		for i = 1, #testArenaFrames do
			local testArenaFrame = testArenaFrames[i]
			testArenaFrame:Hide()
		end

		return
	end

	-- no real frames, show our test frames
	EnsureTestArenaFrames()

	local anchor, testHeader = next(testHeaders)
	for i = 1, #testArenaFrames do
		if testHeader then
			local testArenaFrame = testArenaFrames[i]

			AnchorHeader(testHeader, testArenaFrame)

			testHeader:Show()
			testArenaFrame:Show()
			anchor, testHeader = next(testHeaders, anchor)
		end
	end
end

local function OnEvent(_, event)
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

	if event == "GROUP_ROSTER_UPDATE" then
		addon:Refresh()
	end
end

local function OnAddonLoaded()
	addon.Config:Init()
	addon.Scheduler:Init()
	addon.Auras:Init()

	db = mini:GetSavedVars()

	EnsureHeaders()

	eventsFrame = CreateFrame("Frame")
	eventsFrame:SetScript("OnEvent", OnEvent)
	eventsFrame:RegisterEvent("ARENA_OPPONENT_UPDATE")
	eventsFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	eventsFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
end

function addon:Refresh()
	if InCombatLockdown() then
		scheduler:RunWhenCombatEnds(function()
			addon:Refresh()
		end, "Refresh")
		return
	end

	EnsureHeaders()

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
---@field Auras AurasModule
---@field Framework MiniFramework
---@field Scheduler Scheduler
---@field Config Config
---@field Refresh fun(self: table)
---@field ToggleTest fun(self: table)
