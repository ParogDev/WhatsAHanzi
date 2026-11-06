-- Per-character readings from Data/Pinyin.lua (Unihan kMandarin, already tone-marked).
local _, ns = ...
local Pinyin = {}
ns.Pinyin = Pinyin

-- Reading of one Han character, or nil when the data has none.
function Pinyin.char(ch)
	local data = ns.Data and ns.Data.pinyin
	return data and data[ch] or nil
end

-- Readings of every character of a Han string, space-joined; unknown characters show as "?".
function Pinyin.string(s)
	local parts = {}
	for ch in ns.Han.chars(s) do
		parts[#parts + 1] = Pinyin.char(ch) or "?"
	end
	return table.concat(parts, " ")
end

-- Count of entries, for the selftest.
function Pinyin.count()
	local data = ns.Data and ns.Data.pinyin
	if not data then
		return 0
	end
	local n = 0
	for _ in pairs(data) do
		n = n + 1
	end
	return n
end
