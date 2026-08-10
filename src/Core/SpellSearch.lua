---@type string, Addon
local _, addon = ...

-- Search over the generated SpellNameIndex for the spell filter's picker. Each index entry is a
-- spell NAME mapped to every id that applies an aura under it; the picker offers one row per
-- name and GetVariants expands a picked name to all of its ids, because the id the game applies
-- is often not the one a player can look up.

local MAX_RESULTS = 12
local EMPTY = {}
-- Built on first use: naming ~8,000 spells is pointless if the picker is never opened.
---@type SpellSearchEntry[]?
local entries
-- Index names already split out of their stored string, and the union GetVariants last handed
-- back for an id. Both are pure caches of work that never changes within a session.
---@type table<string, number[]>
local indexVariants = {}
---@type table<number, number[]>
local variantCache = {}
local results = {}

---@class SpellSearch
local M = {}

addon.SpellSearch = M

---The ids the generated index has under a spell's name, or nil when it has none. Keyed on the
---name exactly as the client spells it, so a non-English client simply never matches.
---@param spellId number
---@return number[]?
local function IndexVariants(spellId)
	local index = addon.SpellNameIndex

	if not index then
		return nil
	end

	local name = C_Spell.GetSpellName(spellId)
	local raw = name and index[name]

	if not raw then
		return nil
	end

	local split = indexVariants[name]

	if not split then
		split = {}

		for id in raw:gmatch("%d+") do
			split[#split + 1] = tonumber(id)
		end

		indexVariants[name] = split
	end

	return split
end

local function BuildIndex()
	entries = {}

	-- One row per name; its id is the lowest of the name's variants, so a suggestion picked
	-- twice adds the same one.
	for name, raw in pairs(addon.SpellNameIndex or EMPTY) do
		local first = tonumber(raw:match("%d+"))

		if first then
			entries[#entries + 1] = { Id = first, Name = name, Lower = name:lower() }
		end
	end

	table.sort(entries, function(a, b)
		return a.Lower < b.Lower
	end)
end

local function EnsureIndex()
	if not entries then
		BuildIndex()
	end
end

---The suggestions for a partially typed spell name or id, best match first.
---Returns a shared table that the next call refills; copy anything you need to keep.
---@param query string
---@param limit number?
---@return SpellSearchEntry[]
function M:Search(query, limit)
	wipe(results)

	query = (query or ""):match("^%s*(.-)%s*$")

	if query == "" then
		return results
	end

	EnsureIndex()

	limit = limit or MAX_RESULTS

	local numeric = tonumber(query)

	-- A fully typed id is an answer, not a search, so it leads even if the index lacks it.
	if numeric and numeric == math.floor(numeric) and numeric > 0 then
		local entry = self:GetEntry(numeric)

		if entry then
			results[#results + 1] = entry
		end
	end

	local lower = query:lower()
	local prefixes = {}
	local contains = {}

	for _, entry in ipairs(entries) do
		if entry.Id ~= numeric then
			local at = entry.Lower:find(lower, 1, true)

			if at == 1 then
				prefixes[#prefixes + 1] = entry
			elseif at then
				contains[#contains + 1] = entry
			elseif numeric and tostring(entry.Id):find(query, 1, true) == 1 then
				contains[#contains + 1] = entry
			end
		end
	end

	for _, list in ipairs({ prefixes, contains }) do
		for _, entry in ipairs(list) do
			if #results >= limit then
				return results
			end

			results[#results + 1] = entry
		end
	end

	return results
end

---An entry for a spell id, so a hand-typed id still shows its name and icon. Returns nil for
---ids the client has never heard of.
---@param spellId number
---@return SpellSearchEntry?
function M:GetEntry(spellId)
	local name = C_Spell.GetSpellName(spellId)

	if not name or name == "" then
		return nil
	end

	return { Id = spellId, Name = name, Lower = name:lower() }
end

---Every id sharing a spell's name, including the one passed in. Aura filters match the id the
---game applied, which is often not the spellbook one, so a filtered ability must cover them all.
---@param spellId number
---@return number[]
function M:GetVariants(spellId)
	local cached = variantCache[spellId]

	if cached then
		return cached
	end

	local scanned = IndexVariants(spellId)
	local seen = {}
	local merged = {}

	for _, list in ipairs({ scanned or EMPTY, { spellId } }) do
		for _, id in ipairs(list) do
			if not seen[id] then
				seen[id] = true
				merged[#merged + 1] = id
			end
		end
	end

	table.sort(merged)
	variantCache[spellId] = merged

	return merged
end

---@class SpellSearchEntry
---@field Id number
---@field Name string
---@field Lower string
