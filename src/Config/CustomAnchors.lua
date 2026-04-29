---@type string, Addon
local addonName, addon = ...
local mini = addon.Framework
local verticalSpacing = mini.VerticalSpacing
local horizontalSpacing = mini.HorizontalSpacing
---@type Db
local db

local M = {}
addon.CustomAnchors = M

local function ApplySettings()
	if InCombatLockdown() then
		mini:Notify("Can't apply settings during combat.")
		return
	end

	addon:Refresh()
end

function M:Init(category)
	db = mini:GetSavedVars()

	local panel = CreateFrame("Frame")
	panel.name = "Custom Anchors"

	if not category then
		return
	end

	mini:AddSubCategory(category, panel)

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 0, -verticalSpacing)
	title:SetText("Custom Anchors")

	local desc = mini:TextBlock({
		Parent = panel,
		Lines = {
			"Override which frame each arena slot anchors to.",
			"Useful for frame addons such as ElvUI or GladiusEx.",
			"Leave blank to use the default arena frames.",
		},
	})
	desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)

	local anchorWidth = 300

	local arena1 = mini:EditBox({
		Parent = panel,
		LabelText = "Arena 1 Frame",
		Width = anchorWidth,
		GetValue = function()
			return tostring(db.Anchor1)
		end,
		SetValue = function(v)
			db.Anchor1 = tostring(v)
			ApplySettings()
		end,
	})
	arena1.Label:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -verticalSpacing)
	arena1.EditBox:SetPoint("TOPLEFT", arena1.Label, "BOTTOMLEFT", 4, -8)

	local arena2 = mini:EditBox({
		Parent = panel,
		LabelText = "Arena 2 Frame",
		Width = anchorWidth,
		GetValue = function()
			return tostring(db.Anchor2)
		end,
		SetValue = function(v)
			db.Anchor2 = tostring(v)
			ApplySettings()
		end,
	})
	arena2.Label:SetPoint("TOPLEFT", arena1.EditBox, "BOTTOMLEFT", -4, -verticalSpacing)
	arena2.EditBox:SetPoint("TOPLEFT", arena2.Label, "BOTTOMLEFT", 4, -8)

	local arena3 = mini:EditBox({
		Parent = panel,
		LabelText = "Arena 3 Frame",
		Width = anchorWidth,
		GetValue = function()
			return tostring(db.Anchor3)
		end,
		SetValue = function(v)
			db.Anchor3 = tostring(v)
			ApplySettings()
		end,
	})
	arena3.Label:SetPoint("TOPLEFT", arena2.EditBox, "BOTTOMLEFT", -4, -verticalSpacing)
	arena3.EditBox:SetPoint("TOPLEFT", arena3.Label, "BOTTOMLEFT", 4, -8)

	mini:WireTabNavigation({ arena1.EditBox, arena2.EditBox, arena3.EditBox })

	panel:SetScript("OnShow", function()
		panel:MiniRefresh()
	end)
end
