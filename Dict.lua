-- Word segmentation and glosses over Data/Dict.lua (CC-CEDICT) and Data/Game.lua (game names, slang): greedy
-- longest match, with a per-character fallback from Data/Pinyin.lua so every Han character gets a reading.
local _, ns = ...
local Dict = {}
ns.Dict = Dict

local Han = ns.Han

-- CEDICT entry for a word, simplified or traditional: Data.trad maps a traditional headword (歡迎) to the
-- simplified key (欢迎) the entry is stored under. Returns the entry and, for a traditional word, its simplified form.
local function entry(word)
	local d = ns.Data and ns.Data.dict
	if not d then
		return nil
	end
	local e = d[word]
	if e then
		return e
	end
	local simp = ns.Data.trad and ns.Data.trad[word]
	if simp and d[simp] then
		return d[simp], simp
	end
	return nil
end
Dict.entry = entry

local function maxWordLen()
	return (ns.Data and ns.Data.maxWordLen) or 1
end

-- Data/Game.lua (game names and guild slang): term -> { english, kind }. gameMaxLen is in UTF-8 bytes; a Han
-- character takes at least three, so a third of it bounds the length in characters.
local function gameEntry(word)
	local g = ns.Data and ns.Data.game
	return g and g[word] or nil
end

local function maxGameLen()
	local bytes = ns.Data and ns.Data.game and ns.Data.gameMaxLen
	return bytes and math.floor(bytes / 3) or 0
end

-- Longest match of lookup() starting at chars[i], at most maxLen characters and at least minLen.
local function longest(chars, i, maxLen, minLen, lookup)
	for len = math.min(maxLen, #chars - i + 1), minLen, -1 do
		local w = table.concat(chars, "", i, i + len - 1)
		local e = lookup(w)
		if e then
			return w, e, len
		end
	end
end

-- Segments one run of Han text into words: { { word=, pinyin=, gloss=, inDict=bool, game=? }, ... }.
-- Characters: chars[] (UTF-8 strings). At each position the longest CEDICT word (two characters or more) and
-- the longest game term compete: the game term wins when it is as long or longer, and its token carries
-- game = { en, kind } plus CEDICT's reading and gloss when CEDICT has the same word. No match: one character.
-- inDict says whether CEDICT has the token's word (false for a per-character fallback or a game-only term).
function Dict.segmentChars(chars)
	local out, i, n = {}, 1, #chars
	local maxLen, gameLen = maxWordLen(), maxGameLen()
	while i <= n do
		local token
		local w, e, len = longest(chars, i, maxLen, 2, entry)
		local gw, g, glen = longest(chars, i, gameLen, 1, gameEntry)
		if gw and glen >= (len or 1) then
			local d = entry(gw)
			token = {
				word = gw,
				pinyin = d and d[1] or ns.Pinyin.string(gw),
				gloss = d and d[2] or nil,
				inDict = d ~= nil,
				game = { en = g[1], kind = g[2] },
			}
			len = glen
		elseif w then
			token = { word = w, pinyin = e[1], gloss = e[2], inDict = true }
		else
			local ch = chars[i]
			e = entry(ch)
			if e then
				token = { word = ch, pinyin = e[1], gloss = e[2], inDict = true }
			else
				token = { word = ch, pinyin = ns.Pinyin.char(ch) or "?", gloss = nil, inDict = false }
			end
			len = 1
		end
		out[#out + 1] = token
		i = i + len
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

-- Number of game terms, or nil when Data/Game.lua did not load.
function Dict.gameCount()
	local g = ns.Data and ns.Data.game
	if not g then
		return nil
	end
	local n = 0
	for _ in pairs(g) do
		n = n + 1
	end
	return n
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
