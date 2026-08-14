---@type string, Addon
local addonName, addon = ...
local wowEx = addon.WoWEx
local auraMasque = addon.AuraMasque
local iconUtil = addon.IconUtil
local frameIdCounter = 0
local groupKey = "debuffs"
local filter = "HARMFUL|PLAYER"
local liveDisplays = {}
local editModePreviewActive = false
local displayEventsFrame = nil
local pendingRestyleCount = 0
local restyleTicker = nil
local pendingBounceCount = 0
local bounceFlushScheduled = false

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
-- Desaturating on pandemic has no 12.1 equivalent (it needs the per-aura remaining duration).
-- The glow does: clients with pandemic regions (12.1.5+) get an engine-driven refresh-window
-- halo, registered per button via AddPandemicRegion.

---@class AuraContainerDisplay
local M = {}
M.__index = M

addon.AuraContainerDisplay = M

-- The style fields StoreStyle copies verbatim from a caller's table. Drives both the compare
-- and the copy, so a new field lands in both at once.
local STYLE_FIELDS = {
	"ReverseCooldown",
	"HideSwipe",
	"HideNumbers",
	"FontScale",
	"ShowStacks",
	"ShowMilliseconds",
	"ColorCountdown",
	"PandemicGlow",
	"Zoom",
}

-- Halo tint for the pandemic (refresh-window) reveal, fixed so the cue reads the same at any
-- size. IconSlotContainer's test-mode halo must match.
local PANDEMIC_COLOR = { 1, 0.6, 0.1 }

-- Seconds below which the countdown shows tenths ("4.3") when ShowMilliseconds is on.
local MILLISECONDS_THRESHOLD = 5

-- How often the deferred restyle retry runs while any display is stale (see RestyleButtons).
local RESTYLE_RETRY_INTERVAL = 1

local EMPTY_STYLE = {}

-- Colour-by-time stops for the countdown text: {seconds remaining, r, g, b}. The engine
-- evaluates the curve against the secret remaining time and writes the fontstring's colour
-- itself; nothing here reads the clock. OmniCC's classic bands (red under 5s, yellow to the
-- minute, white above) rather than a gradient: each near-coincident stop pair fakes a hard
-- edge on the linear curve, so the 0.05s blend windows are never visible.
local COUNTDOWN_COLOR_STOPS = {
	{ 0, 1, 0, 0 },
	{ 5, 1, 0, 0 },
	{ 5.05, 1, 0.8, 0 },
	{ 60, 1, 0.8, 0 },
	{ 60.05, 1, 1, 1 },
}
---@type table?
local countdownCurve
-- The flat curve a countdown binds while the colouring is off. See BindDurationText for why the
-- off state is a curve of its own rather than no colour at all. White matches the
-- NumberFontNormal the fontstring is created with, so it looks like the native numbers it stands
-- in for.
---@type table?
local plainCountdownCurve
-- Countdown formatters keyed by milliseconds threshold (0 = whole seconds only). The engine
-- keeps each reference, so variants are built once and shared across every bound fontstring.
---@type table<number, table>
local countdownFormatters = {}

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

-- Button styling is impossible while auras are secret, which covers combat but also whole
-- arenas / encounters / M+ runs out of combat. RestyleButtons therefore records that the
-- buttons are stale and returns. Something has to come back for that later: without it an icon
-- size change made mid-match would leave the buttons at their old size for the rest of the
-- session. PLAYER_REGEN_ENABLED covers the common case immediately; the ticker covers the rest
-- (C_Secrets.ShouldAurasBeSecret has no event) and only runs while something is actually
-- pending, so an idle UI pays nothing.

local function StopRestyleTicker()
	if restyleTicker then
		restyleTicker:Cancel()
		restyleTicker = nil
	end
end

local function FlushPendingRestyles()
	if pendingRestyleCount == 0 or wowEx:IsAuraStylingRestricted() then
		return
	end

	for _, instance in ipairs(liveDisplays) do
		-- Hidden displays are left stale: nothing they show is on screen, and SetShown retries
		-- the restyle on the way back in.
		if instance.RestylePending and instance.DesiredShown then
			instance:RestyleButtons()
		end
	end
end

local function OnRestyleTick()
	FlushPendingRestyles()

	if pendingRestyleCount == 0 then
		StopRestyleTicker()
	end
end

---Flags/clears a display's stale-style state, keeping the global pending count (and therefore
---the retry ticker's lifetime) in sync. Always go through this rather than assigning the field.
---@param instance AuraContainerDisplay
---@param pending boolean
local function SetRestylePending(instance, pending)
	if instance.RestylePending == pending then
		return
	end

	instance.RestylePending = pending
	pendingRestyleCount = pendingRestyleCount + (pending and 1 or -1)

	if pending then
		if not restyleTicker then
			restyleTicker = C_Timer.NewTicker(RESTYLE_RETRY_INTERVAL, OnRestyleTick)
		end
	elseif pendingRestyleCount == 0 then
		StopRestyleTicker()
	end
end

-- Changes pushed from addon context (SetUnit, budgets, filters, sort) set the container's dirty
-- flags but cannot arm the secure-side processor that consumes them, so they sit parked until the
-- unit's next aura event - a retargeted container keeps showing the old unit's auras, a budget
-- flip lands late, and UpdateAllAuras is just another mark. Hiding and showing the container is
-- the one addon-side action that re-arms it: the intrinsic OnShow runs in secure context and
-- issues a full refresh. The bounce is invisible (no render between the two calls) and coalesced
-- to one per display per frame, because a configure pass calls several setters in a row. In
-- combat the flags are left parked instead: aura events are frequent enough there to settle
-- them, and the pending bounce is flushed on the regen event either way.

local function FlushPendingBounces()
	bounceFlushScheduled = false

	if pendingBounceCount == 0 or InCombatLockdown() then
		return
	end

	pendingBounceCount = 0

	for _, instance in ipairs(liveDisplays) do
		if instance.BouncePending then
			instance.BouncePending = false
			local frame = instance.Frame

			-- A hidden frame needs no bounce: the OnShow on its way back arms the processor.
			if frame:IsShown() then
				frame:Hide()
				frame:Show()
			end
		end
	end
end

---@param instance AuraContainerDisplay
local function MarkBouncePending(instance)
	if not instance.BouncePending then
		instance.BouncePending = true
		pendingBounceCount = pendingBounceCount + 1
	end

	if not bounceFlushScheduled then
		bounceFlushScheduled = true
		C_Timer.After(0, FlushPendingBounces)
	end
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

---Starts listening for the Edit Mode data provider switch and for combat ending (the most
---common moment the button restriction lifts). Called from New rather than at load, because
---AURA_DATA_PROVIDER_SWITCH only exists on clients that have the AuraContainer system.
local function EnsureDisplayEvents()
	if displayEventsFrame then
		return
	end

	displayEventsFrame = CreateFrame("Frame")
	displayEventsFrame:RegisterEvent("AURA_DATA_PROVIDER_SWITCH")
	displayEventsFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
	displayEventsFrame:SetScript("OnEvent", function(_, event, useRealDataProvider)
		if event == "AURA_DATA_PROVIDER_SWITCH" then
			OnAuraDataProviderSwitch(useRealDataProvider)
		else
			FlushPendingRestyles()
			FlushPendingBounces()
		end
	end)
end

---True when the client supports colour curves and formatters on duration-text bindings. Probes
---the options processor rather than the curve API alone: builds that predate it accept the
---options table and silently drop the colour, which would leave the swap-in fontstring plain
---white.
---@return boolean
local function HasCountdownText()
	return C_AuraContainerUtil ~= nil
		and C_AuraContainerUtil.ProcessCustomAuraButtonDurationTextOptions ~= nil
		and C_CurveUtil ~= nil
		and C_CurveUtil.CreateColorCurve ~= nil
		and C_StringUtil ~= nil
		and C_StringUtil.CreateNumericRuleFormatter ~= nil
		and Enum.DurationTextBindingProperty ~= nil
		and Enum.NumericRuleFormatRounding ~= nil
end

---Bare-number remaining time ("45" -> "2m" -> "1h"), matching the cooldown countdown the bound
---text replaces. A rule formatter because the engine's default renders a unit suffix ("45s")
---and SecondsFormatter cannot drop it. The promotion thresholds are the game's own (1 + 1.5x
---the unit), and the quotients round up to match Blizzard's frames (2m32s reads "3m"). A
---non-zero msThreshold adds a tenths band below it ("4.3"); that breakpoint deliberately
---carries no min/rounding fields - with them present the engine rendered no fractions at all.
---@param msThreshold number Seconds below which tenths show; 0 for whole seconds only.
---@return table
local function GetCountdownFormatter(msThreshold)
	local fmt = countdownFormatters[msThreshold]
	if not fmt then
		local down = Enum.NumericRuleFormatRounding.Down
		local up = Enum.NumericRuleFormatRounding.Up
		fmt = C_StringUtil.CreateNumericRuleFormatter()
		if msThreshold > 0 then
			fmt:AddBreakpoint({ threshold = 0, step = 0.1, format = "%.1f" })
			fmt:AddBreakpoint({ threshold = msThreshold, step = 1, rounding = down, min = 1, format = "%d" })
		else
			fmt:AddBreakpoint({ threshold = 0, step = 1, rounding = down, min = 1, format = "%d" })
		end
		fmt:AddBreakpoint({ threshold = 91, step = 1, rounding = down, min = 1, format = "%dm",
			components = { { div = 60, rounding = up } } })
		fmt:AddBreakpoint({ threshold = 5401, step = 1, rounding = down, min = 1, format = "%dh",
			components = { { div = 3600, rounding = up } } })
		countdownFormatters[msThreshold] = fmt
	end

	return fmt
end

---The shared colour curve every countdown fontstring binds. Built once; the engine keeps the
---reference and curves are never mutated after creation.
---@return table
local function GetCountdownCurve()
	if not countdownCurve then
		local curve = C_CurveUtil.CreateColorCurve()
		curve:SetType(Enum.LuaCurveType.Linear)
		-- Highest threshold first: the curve API expects points added in descending x order.
		for i = #COUNTDOWN_COLOR_STOPS, 1, -1 do
			local stop = COUNTDOWN_COLOR_STOPS[i]
			curve:AddPoint(stop[1], CreateColor(stop[2], stop[3], stop[4]))
		end
		countdownCurve = curve
	end

	return countdownCurve
end

---The curve bound when colour-by-time is off: white the whole way down.
---@return table
local function GetPlainCountdownCurve()
	if not plainCountdownCurve then
		local curve = C_CurveUtil.CreateColorCurve()
		curve:SetType(Enum.LuaCurveType.Linear)
		-- Descending, like the ramp above; two points so the value is flat rather than clamped
		-- off the end of a single one.
		curve:AddPoint(COUNTDOWN_COLOR_STOPS[#COUNTDOWN_COLOR_STOPS][1], CreateColor(1, 1, 1))
		curve:AddPoint(0, CreateColor(1, 1, 1))
		plainCountdownCurve = curve
	end

	return plainCountdownCurve
end

---Binds (or re-binds) the countdown fontstring. The engine retains the button's duration-text
---binding across calls, so this is how the formatter and colour curve are swapped at restyle
---time. Named fields, not positional: the options validator walks [textColor][curve] and
---[textColor][property], and a positional pair errors per button at AddAuraGroup time.
---
---While the fontstring is the countdown, a colour is bound either way round, the off state being
---a flat white curve: leaving textColor out asks the engine to forget the binding it is holding,
---which it does not do, so the ramp would stay on after the setting went off.
---
---While it is NOT the countdown, no colour is bound at all. Binding one there has the engine draw
---the fontstring regardless of the alpha we set, which puts numbers back on an icon that asked
---for none. The stale curve it keeps costs nothing: nothing is looking at it, and the next bind
---that does use it replaces it.
---@param button table
---@param durationText table
---@param msThreshold number Seconds below which tenths show; 0 for whole seconds only.
---@param curve table? The colour curve to bind, or nil while the fontstring is not in use.
local function BindDurationText(button, durationText, msThreshold, curve)
	button:SetDurationText(durationText, {
		textFormatter = GetCountdownFormatter(msThreshold),
		textColor = curve and {
			curve = curve,
			property = Enum.DurationTextBindingProperty.RemainingDuration,
		} or nil,
	})
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

local function UpdateFontSize(region, iconSize, coefficient, fontScale)
	local font, _, flags = region:GetFont()
	if not font then
		return
	end
	local fontSize = math.max(1, math.floor(iconSize * coefficient * (fontScale or 1.0)))
	region:SetFont(font, fontSize, flags)
end

local function UpdateCooldownFontSize(cd, iconSize, fontScale)
	local region = GetCooldownFontString(cd)
	if region then
		UpdateFontSize(region, iconSize, 0.4, fontScale)
	end
end

---Copies a style into the instance's own persistent style table and reports whether any of it
---actually changed. Callers may hand in a reused table - nothing here retains the argument.
---PandemicColor is copied component-wise for the same reason: a caller building a fresh colour
---table per refresh must not read as a change when the components match.
---@param instance AuraContainerDisplay
---@param style AuraDisplayStyle
---@return boolean changed
local function StoreStyle(instance, style)
	local stored = instance.Style
	local color = style.PandemicColor
	local colorR = color and color[1]
	local colorG = color and color[2]
	local colorB = color and color[3]
	local changed = not stored.Populated
		or stored.PandemicColorR ~= colorR
		or stored.PandemicColorG ~= colorG
		or stored.PandemicColorB ~= colorB

	if not changed then
		for _, field in ipairs(STYLE_FIELDS) do
			if stored[field] ~= style[field] then
				changed = true
				break
			end
		end
	end

	if not changed then
		return false
	end

	for _, field in ipairs(STYLE_FIELDS) do
		stored[field] = style[field]
	end
	stored.PandemicColorR = colorR
	stored.PandemicColorG = colorG
	stored.PandemicColorB = colorB
	stored.Populated = true

	return true
end

-- Applies the stored style (size, cooldown settings, stacks, countdown text) to one button.
-- Safe only while buttons are not forbidden (initializeFrame or out of combat).
---@param instance AuraContainerDisplay
---@param button table
local function StyleButton(instance, button)
	local style = instance.Style
	local widgets = instance.ButtonWidgets[button]

	if not widgets then
		return
	end

	button:SetSize(instance.Size, instance.Size)

	-- A skinned button wears the skin's crop instead: ours would fight it, and one carrying a
	-- pandemic region can never be re-skinned back (its size reads secret), so ours would stick.
	if not widgets.Masqued then
		widgets.Icon:SetTexCoord(iconUtil:TexCoord(style.Zoom))
	end

	local cd = widgets.Cooldown
	cd:SetReverse(style.ReverseCooldown or false)
	cd:SetDrawSwipe(not style.HideSwipe)
	UpdateCooldownFontSize(cd, instance.Size, style.FontScale)

	-- The bound fontstring stands in for the cooldown's own countdown whenever it can do
	-- something the native text cannot: the colour-by-time curve, sub-second tenths, or both.
	-- (The cooldown's SetCountdownMillisecondsThreshold and SetCountdownFormatter both no-op for
	-- 12.1 duration objects; the binding is the only route to fractions.)
	local msThreshold = (style.ShowMilliseconds and MILLISECONDS_THRESHOLD) or 0
	local durationText = widgets.DurationText
	-- Numbers off means neither the cooldown's own text nor the bound fontstring, so the colour
	-- has nothing to colour.
	local colorCountdown = not style.HideNumbers and style.ColorCountdown == true and durationText ~= nil
	local useDurationText = not style.HideNumbers
		and durationText ~= nil
		and (colorCountdown or msThreshold > 0)
	cd:SetHideCountdownNumbers((style.HideNumbers or useDurationText) and true or false)
	if durationText then
		-- The ramp while colouring by time, a flat curve while the fontstring is the countdown
		-- without it, and nothing at all while it is not the countdown (see BindDurationText).
		local curve = (colorCountdown and GetCountdownCurve())
			or (useDurationText and GetPlainCountdownCurve())
			or nil

		-- The formatter and colour curve live inside the binding, so a change re-binds. Only on
		-- change: each SetDurationText runs the engine's options processing per button. The curves
		-- are cached singletons, so comparing the reference is comparing which curve is bound.
		if widgets.DurationTextThreshold ~= msThreshold or widgets.DurationTextCurve ~= curve then
			widgets.DurationTextThreshold = msThreshold
			widgets.DurationTextCurve = curve
			BindDurationText(button, durationText, msThreshold, curve)
		end
		durationText:SetAlpha(useDurationText and 1 or 0)
		-- Stand-in for the cooldown's own countdown, so it borrows that fontstring's face and
		-- size wholesale (UpdateCooldownFontSize above just sized it).
		local cdText = GetCooldownFontString(cd)
		local font, fontSize, fontFlags
		if cdText then
			font, fontSize, fontFlags = cdText:GetFont()
		end
		if font then
			durationText:SetFont(font, fontSize, fontFlags)
		else
			UpdateFontSize(durationText, instance.Size, 0.4, style.FontScale)
		end
	end

	-- Alpha rather than Show/Hide, and never unregistered: the engine owns this font string's
	-- text and shown state, so the only part of it left to us is how visible it is.
	local stacks = widgets.Stacks
	if stacks then
		stacks:SetAlpha(style.ShowStacks and 1 or 0)
		UpdateFontSize(stacks, instance.Size, 0.35, style.FontScale)
	end

	-- The engine owns the pandemic holder's visibility (shown only inside the refresh window);
	-- the toggle is ours and rides the halo's alpha instead.
	local pandemic = widgets.Pandemic
	if pandemic then
		local colorR = style.PandemicColorR or PANDEMIC_COLOR[1]
		local colorG = style.PandemicColorG or PANDEMIC_COLOR[2]
		local colorB = style.PandemicColorB or PANDEMIC_COLOR[3]

		pandemic.Glow:SetAlpha(style.PandemicGlow and 1 or 0)
		pandemic.Glow:SetVertexColor(colorR, colorG, colorB, 1)
		-- The halo's padding is a share of the icon, so a size change re-anchors it.
		iconUtil:AnchorGlow(pandemic.Glow, button, instance.Size)
	end

	-- No tooltips or click-to-cancel: the icons sit over arena frames and must not eat clicks.
	button:EnableMouse(false)
end

---@param instance AuraContainerDisplay
---@param button table
local function InitializeButton(instance, button)
	-- Composite each button's icon/cooldown/text in a single render pass. Must happen here:
	-- initializeFrame is the only place AuraButtons are guaranteed not forbidden.
	button:SetFlattensRenderLayers(true)

	-- Icon on the lowest layer with the swipe above, matching IconSlotContainer's slots.
	local icon = button:CreateTexture(nil, "BACKGROUND", nil, 1)
	icon:SetAllPoints(button)
	button:SetIcon(icon)

	local cd = CreateFrame("Cooldown", NextFrameName("Cooldown"), button, "CooldownFrameTemplate")
	cd:SetAllPoints(button)
	cd:SetDrawEdge(false)
	cd:SetDrawBling(false)
	cd:SetSwipeColor(0, 0, 0, 0.8)
	iconUtil:SquareSwipe(cd)
	button:SetDurationCooldown(cd)

	-- Text sits on its own child frame levelled above the cooldown: fontstrings created on the
	-- button itself are parent regions, which child frames like the swipe always cover. Still a
	-- descendant of the button, so duration/stack registration stays valid.
	local textOverlay = CreateFrame("Frame", nil, button)
	textOverlay:SetAllPoints(button)
	textOverlay:SetFrameLevel(button:GetFrameLevel() + 5)

	-- Countdown stand-in: a fontstring bound as native duration text, carrying the tenths
	-- formatter and/or colour curve. Registered here because regions can only be attached in
	-- initializeFrame; StyleButton decides straight afterwards whether it carries a colour, and
	-- swaps between this and the cooldown's own countdown via alpha.
	local durationText
	if HasCountdownText() then
		durationText = textOverlay:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		durationText:SetPoint("CENTER", button, "CENTER", 0, 0)
		BindDurationText(button, durationText, 0, nil)
	end

	-- The engine writes the count and decides when it is on screen, both of which are secret. We
	-- only get to place it and say how big it is, so it is registered once and never taken back.
	-- Never pass an options table with a formatter here: the engine calls FormatNumber(count) in
	-- Lua with the secret count, and the throw lands inside the container's dirty-flag
	-- processing, which stops re-arming and leaves the container frozen for the session.
	local stacks = textOverlay:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	stacks:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
	stacks:SetJustifyH("RIGHT")
	button:SetApplicationCount(stacks)

	-- Pandemic reveal: the engine computes each aura's refresh window (the tail where re-casting
	-- carries the remainder over) and drives the registered region's visibility itself - the
	-- window's bounds are secret, so nothing here may read them. A holder frame is registered
	-- rather than the halo texture, because registration hands the object's shown state to the
	-- engine and it must be something this addon never shows or hides; the halo inside stays
	-- ours, and the toggle rides its alpha (StyleButton). No animation on purpose: a looping
	-- animation costs CPU every frame across every pre-created button. The holder is built here
	-- but handed over at the end, after Masque has had the button.
	local pandemic
	if instance.PandemicRegions and button.AddPandemicRegion then
		pandemic = CreateFrame("Frame", NextFrameName("Pandemic"), button)
		pandemic:SetFrameLevel(button:GetFrameLevel() + 6)
		pandemic:SetAllPoints(button)

		-- The halo reaches well past the holder, which nothing clips, so it needs no frame of its
		-- own; StyleButton anchors it to the button at the padding the art wants.
		local glow = iconUtil:CreateGlow(pandemic)
		glow:SetVertexColor(PANDEMIC_COLOR[1], PANDEMIC_COLOR[2], PANDEMIC_COLOR[3], 1)
		pandemic.Glow = glow
	end

	local widgets = {
		Icon = icon,
		Cooldown = cd,
		Stacks = stacks,
		Pandemic = pandemic,
		DurationText = durationText,
		-- What the bind above stands for: no fractions and no colour.
		DurationTextThreshold = durationText and 0 or nil,
		DurationTextCurve = nil,
	}
	instance.ButtonWidgets[button] = widgets
	instance.Buttons[#instance.Buttons + 1] = button

	StyleButton(instance, button)
	-- After StyleButton, which is what gives the button the size Masque fits the skin to.
	auraMasque:RegisterButton(instance, button, widgets)

	-- Handed over only now: the refresh window is secret, and registering a region driven by it
	-- takes the button's own size with it, which is the one number Masque has to be able to read.
	-- Building the holder above is free; it is this call that closes the door.
	if pandemic then
		button:AddPandemicRegion(pandemic)
	end
end

---@param instance AuraContainerDisplay
local function ApplyFlowLayout(instance)
	local layout = growLayouts[instance.Grow] or growLayouts.RIGHT
	local frame = instance.Frame
	frame:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
	frame:SetFlowLayoutAnchorPoint(layout.anchorPoint)
	frame:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection[layout.h], AnchorUtil.FlowDirection.Down)
end

---Fills the instance's own layout table. Spacing keys are passed under BOTH the older and newer
---PTR spellings (elementSpacing/lineSpacing was renamed to elementSpacingX/elementSpacingY in a
---later 12.1 build); validators ignore unknown keys, so this works on either build. The table is
---per-instance and reused rather than rebuilt per call, so the engine may retain the reference.
---@param instance AuraContainerDisplay
---@return table
local function BuildGroupLayout(instance)
	local layout = instance.Layout
	layout.elementSpacing = instance.Spacing
	layout.lineSpacing = instance.Spacing
	layout.elementSpacingX = instance.Spacing
	layout.elementSpacingY = instance.Spacing
	layout.elementWidth = instance.Size
	layout.elementHeight = instance.Size

	return layout
end

---Creates a new AuraContainer-backed display tracking the player's debuffs on a unit.
---@param parent table Frame to parent the container to.
---@param unit string? Unit token to track.
---@param maxIcons number Icon budget.
---@param size number Icon size in pixels.
---@param spacing number Spacing between icons.
---@param style AuraDisplayStyle? Style to build the buttons with. Pass it whenever the display
---may be created while auras are secret (an arena) - a later SetStyle cannot reach the buttons
---there, so buttons must be born with the real style.
---@param masqueGroup string? Masque sub-group name; omit to skip Masque.
---@return AuraContainerDisplay
function M:New(parent, unit, maxIcons, size, spacing, style, masqueGroup)
	local instance = setmetatable({}, M)

	instance.Size = size or 36
	instance.Spacing = spacing or 2
	instance.MaxIcons = maxIcons or 6
	instance.Grow = "RIGHT"
	-- Owned by the instance and mutated in place by StoreStyle; callers never hand us a table
	-- we keep.
	instance.Style = {}
	instance.Layout = {}
	instance.Buttons = {}
	-- button -> { Icon, Cooldown, Stacks, Pandemic, DurationText } for restyling and skinning.
	instance.ButtonWidgets = {}
	instance.HideUnimportant = false
	-- Visibility the addon last asked for; frames are created shown.
	instance.DesiredShown = true
	instance.RestylePending = false
	-- Resolved at creation: regions can only be added to a button in initializeFrame, so a
	-- display built on a client without them can never grow them later.
	instance.PandemicRegions = wowEx:HasPandemicRegions()
	-- Kept past the group itself, which AuraMasque clears when skinning is abandoned.
	instance.MasqueGroupName = masqueGroup
	instance.MasqueGroup = auraMasque:ResolveGroup(masqueGroup)

	-- Seed the style BEFORE any button exists, so initializeFrame styles them correctly first
	-- time (AddAuraGroup pre-creates buttons, and a restyle is blocked while auras are secret).
	StoreStyle(instance, style or EMPTY_STYLE)

	local frame = CreateFrame("AuraContainer", NextFrameName("Container"), parent, "CustomAuraContainerTemplate")
	frame:SetIgnoreParentScale(true)
	frame:SetIgnoreParentAlpha(true)
	instance.Frame = frame

	EnsureDisplayEvents()
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

	-- The frame was shown before its group existed, so the arming OnShow has already fired;
	-- bounce once so the initial parse doesn't wait for the unit's first aura event.
	MarkBouncePending(instance)

	return instance
end

---@param unit string?
function M:SetUnit(unit)
	unit = unit or "none"
	if self.Frame:GetUnit() == unit then
		return
	end

	self.Frame:SetUnit(unit)
	MarkBouncePending(self)
end

---Shows or hides the display. Always use this instead of touching Frame:SetShown directly, so
---the Edit Mode placeholder auras stay suppressed (see EnsureDisplayEvents).
---@param shown boolean
function M:SetShown(shown)
	self.DesiredShown = shown == true
	ApplyShownState(self)

	-- Coming back into view is a chance to settle a restyle that was skipped while restricted.
	if self.DesiredShown and self.RestylePending then
		self:RestyleButtons()
	end
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
	MarkBouncePending(self)
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
	MarkBouncePending(self)
end

---Replaces the group's candidate filters. The spell-id maps only apply to harmful auras on
---units the player cannot assist (the engine silently skips them otherwise) - which is exactly
---this display's case, the player's debuffs on arena enemies. Swapping filters at runtime is
---supported by the engine, so a change re-filters in place. Maps are compared by reference:
---the caller caches them and only hands over new tables when the configured list changes.
---@param hideUnimportant boolean Show only debuffs Blizzard flags nameplateShowPersonal (the
---12.1 replacement for the legacy per-aura alpha trick; not identity-gated).
---@param includeSpellIDs table? Map keyed by spell id; only listed spells show.
---@param excludeSpellIDs table? Map keyed by spell id; listed spells are hidden.
function M:SetAuraFilters(hideUnimportant, includeSpellIDs, excludeSpellIDs)
	hideUnimportant = hideUnimportant and true or false
	if self.HideUnimportant == hideUnimportant
		and self.IncludeSpellIDs == includeSpellIDs
		and self.ExcludeSpellIDs == excludeSpellIDs then
		return
	end

	self.HideUnimportant = hideUnimportant
	self.IncludeSpellIDs = includeSpellIDs
	self.ExcludeSpellIDs = excludeSpellIDs

	-- A fresh table per change, in case the engine retains the reference.
	local filters = {
		includeSpellIDs = includeSpellIDs,
		excludeSpellIDs = excludeSpellIDs,
	}
	if hideUnimportant then
		filters.nameplateShowPersonal = true
	end
	self.Frame:SetAuraGroupCandidateFilters(groupKey, filters)
	MarkBouncePending(self)
end

---Applies size, spacing and style together, restyling the buttons once. Callers changing more
---than one of them must use this rather than separate setters - several passes over every
---button per config change is what makes dragging a size slider stutter. Nothing is applied to
---the buttons while aura styling is restricted; the values are stored and the pending-restyle
---retry settles them when it lifts.
---@param size number
---@param spacing number
---@param style AuraDisplayStyle
function M:ApplyConfig(size, spacing, style)
	size = tonumber(size)
	spacing = tonumber(spacing)

	local changed = false

	if size and size > 0 and self.Size ~= size then
		self.Size = size
		changed = true
	end

	if spacing and spacing >= 0 and self.Spacing ~= spacing then
		self.Spacing = spacing
		changed = true
	end

	if StoreStyle(self, style or EMPTY_STYLE) then
		changed = true
	end

	if not changed and not self.RestylePending then
		return
	end

	self:RestyleButtons()
end

---Re-applies the stored style to all created buttons. Buttons are forbidden while auras are
---secret (in combat, but also out-of-combat inside M+/encounters/PvP matches), so this is
---deferred then: the pending flag makes the next call retry even when the style itself is
---unchanged, and the retry ticker comes back for displays that would otherwise never be
---touched again.
function M:RestyleButtons()
	if wowEx:IsAuraStylingRestricted() then
		SetRestylePending(self, true)
		return
	end

	SetRestylePending(self, false)

	-- The group layout spaces icons by elementWidth, but the engine only ever positions a
	-- button - the button's real size comes from StyleButton below. Both therefore have to be
	-- applied together: pushing the layout through while the restyle is deferred spaces the row
	-- for the new size with buttons still at the old one.
	self.Frame:SetAuraGroupLayout(groupKey, BuildGroupLayout(self))

	for _, button in ipairs(self.Buttons) do
		StyleButton(self, button)
	end

	auraMasque:ReSkinButtons(self)
end

---@class AuraDisplayStyle
---@field ReverseCooldown boolean?
---@field HideSwipe boolean?
---@field HideNumbers boolean?
---@field FontScale number?
---@field ShowStacks boolean? Show the engine-written application count in the icon's corner.
---@field ShowMilliseconds boolean? Show tenths of a second on countdowns under 5 seconds.
---@field ColorCountdown boolean? Colour the countdown text by time remaining.
---@field PandemicGlow boolean? Reveal the engine-driven refresh-window halo. Inert on clients
---without pandemic regions.
---@field PandemicColor number[]? {r, g, b} tint for the ring; unset keeps the built-in amber.
---Copied component-wise, so callers may pass a fresh table per call.
---@field Zoom boolean? Crop Blizzard's baked border off the icon art. False keeps it.
---@field Populated boolean?

---@class AuraContainerDisplay
---@field Frame table The AuraContainer frame (anchor/show/hide through this).
---@field Size number
---@field Spacing number
---@field MaxIcons number
---@field Grow string
---@field Style AuraDisplayStyle
---@field Layout table
---@field Buttons table[]
---@field ButtonWidgets table<table, table>
---@field HideUnimportant boolean
---@field IncludeSpellIDs table?
---@field ExcludeSpellIDs table?
---@field DesiredShown boolean
---@field RestylePending boolean
---@field BouncePending boolean?
---@field PandemicRegions boolean
---@field MasqueGroup table?
---@field MasqueGroupName string?
