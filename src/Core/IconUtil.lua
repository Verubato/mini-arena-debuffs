---@type string, Addon
local _, addon = ...

-- How much of a spell icon Blizzard's baked silver border takes up. Cropping it off is what makes
-- an icon sit flush against a border of ours instead of carrying two, and it lets the cooldown
-- swipe cover exactly the visible square.
local ICON_TRIM = 0.08

-- The swipe ignores masks, so its shape comes from its own art. A flat block is the square case,
-- set explicitly rather than left at whatever the client defaults to.
local SQUARE_SWIPE_TEXTURE = "Interface\\Buttons\\WHITE8X8"

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
