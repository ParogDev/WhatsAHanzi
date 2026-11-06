-- UTF-8 and Han (CJK ideograph) helpers. Pure Lua 5.1 string ops: the client has no utf8 library.
local _, ns = ...
local Han = {}
ns.Han = Han

local byte, sub = string.byte, string.sub

-- Byte length of the UTF-8 character starting at i (1 for ASCII and for invalid lead bytes).
function Han.charLen(s, i)
	local b = byte(s, i)
	if not b then
		return 0
	elseif b < 0x80 then
		return 1
	elseif b >= 0xF0 then
		return 4
	elseif b >= 0xE0 then
		return 3
	elseif b >= 0xC0 then
		return 2
	end
	return 1
end

-- Iterator over UTF-8 characters: for ch, pos in Han.chars(s) do ... end
function Han.chars(s)
	local i = 1
	return function()
		if i > #s then
			return nil
		end
		local n = Han.charLen(s, i)
		local ch = sub(s, i, i + n - 1)
		local pos = i
		i = i + n
		return ch, pos
	end
end

-- Code point of a single UTF-8 character (nil for an empty or malformed one).
function Han.codepoint(ch)
	local b1, b2, b3, b4 = byte(ch, 1, 4)
	if not b1 then
		return nil
	elseif b1 < 0x80 then
		return b1
	elseif b1 >= 0xF0 and b4 then
		return (b1 - 0xF0) * 0x40000 + (b2 - 0x80) * 0x1000 + (b3 - 0x80) * 0x40 + (b4 - 0x80)
	elseif b1 >= 0xE0 and b3 then
		return (b1 - 0xE0) * 0x1000 + (b2 - 0x80) * 0x40 + (b3 - 0x80)
	elseif b1 >= 0xC0 and b2 then
		return (b1 - 0xC0) * 0x40 + (b2 - 0x80)
	end
	return nil
end

-- CJK Unified Ideographs (U+4E00..U+9FFF), Extension A (U+3400..U+4DBF), Compatibility (U+F900..U+FAFF).
function Han.isHan(ch)
	local cp = Han.codepoint(ch)
	if not cp then
		return false
	end
	return (cp >= 0x4E00 and cp <= 0x9FFF) or (cp >= 0x3400 and cp <= 0x4DBF) or (cp >= 0xF900 and cp <= 0xFAFF)
end

-- Does the string contain at least one Han character?
function Han.hasHan(s)
	for ch in Han.chars(s) do
		if Han.isHan(ch) then
			return true
		end
	end
	return false
end

-- Number of Han characters in s.
function Han.countHan(s)
	local n = 0
	for ch in Han.chars(s) do
		if Han.isHan(ch) then
			n = n + 1
		end
	end
	return n
end

-- Splits s into runs: { { text = "...", han = true|false }, ... } so Han runs can be segmented and the rest kept.
function Han.runs(s)
	local out, cur, curHan = {}, {}, nil
	for ch in Han.chars(s) do
		local h = Han.isHan(ch)
		if curHan ~= nil and h ~= curHan then
			out[#out + 1] = { text = table.concat(cur), han = curHan }
			cur = {}
		end
		cur[#cur + 1] = ch
		curHan = h
	end
	if #cur > 0 then
		out[#out + 1] = { text = table.concat(cur), han = curHan }
	end
	return out
end
