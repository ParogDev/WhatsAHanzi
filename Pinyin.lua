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

-- Tone-marked vowel -> { base letter, tone }. Byte patterns, since there is no utf8 library.
local MARKED = {
	["ā"] = { "a", 1 },
	["á"] = { "a", 2 },
	["ǎ"] = { "a", 3 },
	["à"] = { "a", 4 },
	["ē"] = { "e", 1 },
	["é"] = { "e", 2 },
	["ě"] = { "e", 3 },
	["è"] = { "e", 4 },
	["ī"] = { "i", 1 },
	["í"] = { "i", 2 },
	["ǐ"] = { "i", 3 },
	["ì"] = { "i", 4 },
	["ō"] = { "o", 1 },
	["ó"] = { "o", 2 },
	["ǒ"] = { "o", 3 },
	["ò"] = { "o", 4 },
	["ū"] = { "u", 1 },
	["ú"] = { "u", 2 },
	["ǔ"] = { "u", 3 },
	["ù"] = { "u", 4 },
	["ǖ"] = { "ü", 1 },
	["ǘ"] = { "ü", 2 },
	["ǚ"] = { "ü", 3 },
	["ǜ"] = { "ü", 4 },
}

-- "nǐ hǎo" -> "ni3 hao3": the tone number goes at the end of the syllable the marked vowel belongs to.
-- Syllables are runs of letters (ASCII or ü); anything else passes through. Neutral tone gets no number.
-- For fonts without the caron letters (every Blizzard font): /hanzi tones numbers.
function Pinyin.numbered(s)
	local out = {}
	local syl, tone = {}, nil
	local function flush()
		if #syl > 0 then
			out[#out + 1] = table.concat(syl) .. (tone or "")
			syl, tone = {}, nil
		end
	end
	local i, n = 1, #s
	while i <= n do
		local c = s:byte(i)
		local len = c < 0x80 and 1 or c < 0xE0 and 2 or c < 0xF0 and 3 or 4
		local ch = s:sub(i, i + len - 1)
		local m = MARKED[ch]
		if m then
			syl[#syl + 1] = m[1]
			tone = m[2]
		elseif ch:match("^%a$") or ch == "ü" or ch == "Ü" then
			syl[#syl + 1] = ch
		else
			flush()
			out[#out + 1] = ch
		end
		i = i + len
	end
	flush()
	return table.concat(out)
end

-- The reading as the user wants it shown (ns.db.ui.tones: "marks" or "numbers").
function Pinyin.display(s)
	if ns.db and ns.db.ui and ns.db.ui.tones == "numbers" then
		return Pinyin.numbered(s)
	end
	return s
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
