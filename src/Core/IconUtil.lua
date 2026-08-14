---@type string, Addon
local addonName, addon = ...

-- How much of a spell icon Blizzard's baked silver border takes up. Cropping it off is what makes
-- an icon sit flush against a border of ours instead of carrying two, and it lets the cooldown
-- swipe cover exactly the visible square.
local ICON_TRIM = 0.08

-- The swipe ignores masks, so its shape comes from its own art. A flat block is the square case,
-- set explicitly rather than left at whatever the client defaults to.
local SQUARE_SWIPE_TEXTURE = "Interface\\Buttons\\WHITE8X8"

-- The refresh-window halo, the same asset MiniAuras draws. A plain texture rather than
-- LibCustomGlow, which cannot glow a 12.1 aura button at all: it re-parents pooled frames onto
-- its target, and AuraButtons refuse to take them.
local GLOW_TEXTURE = "Interface\\AddOns\\" .. addonName .. "\\Textures\\SlotGlow.tga"

-- How far past the icon's edge the halo reaches, as a share of the icon's size. The art needs the
-- room: squeezed onto the icon it reads as a bright rim rather than a glow.
local GLOW_PADDING = 1 / 5

---@class IconUtil
local M = {}

addon.IconUtil = M

---The crop a spell icon is drawn with, as SetTexCoord's four arguments. Uncropped for anyone who
---would rather keep Blizzard's border.
---@param zoomed boolean? False keeps the stock art; anything else crops.
---@return number left, number right, number top, number bottom
function M:TexCoord(zoomed)
	if zoomed == false then
		return 0, 1, 0, 1
	end

	return ICON_TRIM, 1 - ICON_TRIM, ICON_TRIM, 1 - ICON_TRIM
end

---Squares off a cooldown's swipe, so it lines up with the icon's edge.
---@param cooldown table
function M:SquareSwipe(cooldown)
	cooldown:SetSwipeTexture(SQUARE_SWIPE_TEXTURE)
end

---Builds the refresh-window halo. Created invisible: both display paths gate it by alpha, one
---from the pandemic curve and one from the toggle, and neither ever shows or hides it.
---@param parent table
---@return table texture
function M:CreateGlow(parent)
	local texture = parent:CreateTexture(nil, "OVERLAY")
	texture:SetTexture(GLOW_TEXTURE)
	texture:SetBlendMode("BLEND")
	texture:SetAlpha(0)

	return texture
end

---Anchors a halo around an icon. Sized from the number the caller configured rather than the
---icon's own width, which reads secret on a button carrying a pandemic region.
---@param texture table
---@param anchor table The icon frame the halo surrounds.
---@param iconSize number
function M:AnchorGlow(texture, anchor, iconSize)
	local padding = math.max(1, math.floor(iconSize * GLOW_PADDING + 0.5))

	texture:ClearAllPoints()
	texture:SetPoint("TOPLEFT", anchor, "TOPLEFT", -padding, padding)
	texture:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", padding, -padding)
end
