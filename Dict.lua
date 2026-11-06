-- Word segmentation and glosses over Data/Dict.lua (CC-CEDICT): greedy longest match, with a
-- per-character fallback from Data/Pinyin.lua so every Han character gets a reading.
local _, ns = ...
local Dict = {}
ns.Dict = Dict

local Han = ns.Han

local function entry(word)
	local d = ns.Data and ns.Data.dict
	return d and d[word] or nil
end

local function maxWordLen()
	return (ns.Data and ns.Data.maxWordLen) or 1
end

-- Segments one run of Han text into words: { { word=, pinyin=, gloss=, known=bool }, ... }.
-- Characters: chars[] (UTF-8 strings). Longest dictionary match first; else a single character.
function Dict.segmentChars(chars)
	local out, i, n = {}, 1, #chars
	local maxLen = maxWordLen()
	while i <= n do
		local matched
		for len = math.min(maxLen, n - i + 1), 2, -1 do
			local w = table.concat(chars, "", i, i + len - 1)
			local e = entry(w)
			if e then
				matched = { word = w, pinyin = e[1], gloss = e[2], known = true }
				i = i + len
				break
			end
		end
		if not matched then
			local ch = chars[i]
			local e = entry(ch)
			if e then
				matched = { word = ch, pinyin = e[1], gloss = e[2], known = true }
			else
				matched = { word = ch, pinyin = ns.Pinyin.char(ch) or "?", gloss = nil, known = false }
			end
			i = i + 1
		end
		out[#out + 1] = matched
	end
	return out
end

-- Segments a whole chat line. Returns a list of tokens; non-Han runs are one token each with han=false.
function Dict.segment(line)
	local tokens = {}
	for _, run in ipairs(Han.runs(line)) do
		if run.han then
			local chars = {}
			for ch in Han.chars(run.text) do
				chars[#chars + 1] = ch
			end
			for _, t in ipairs(Dict.segmentChars(chars)) do
				t.han = true
				tokens[#tokens + 1] = t
			end
		else
			tokens[#tokens + 1] = { word = run.text, han = false }
		end
	end
	return tokens
end

-- The pinyin line for a token list: Han words get their reading, other runs are kept as-is.
function Dict.pinyinLine(tokens)
	local parts = {}
	for _, t in ipairs(tokens) do
		if t.han then
			parts[#parts + 1] = t.pinyin
		else
			local s = t.word:gsub("^%s+", ""):gsub("%s+$", "")
			if s ~= "" then
				parts[#parts + 1] = s
			end
		end
	end
	return table.concat(parts, " ")
end

function Dict.count()
	local d = ns.Data and ns.Data.dict
	if not d then
		return 0
	end
	local n = 0
	for _ in pairs(d) do
		n = n + 1
	end
	return n
end
