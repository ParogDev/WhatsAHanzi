-- Speaks a hovered word: its own file from the word bank in Sounds/words/ when Data/SoundIndex.lua lists it,
-- else one syllable at a time from the syllable bank in Sounds/ (<syl><tone>.ogg, ü written
-- as v, neutral tone 5; rendered by the companion's gen_audio.py with Kokoro). Sound.names is pure and keeps
-- parity with the companion's wah.audio.syllables; Sound.probe checks at login that the client plays addon
-- .ogg files at all (the same client refuses addon fonts, Font.lua).
local ADDON, ns = ...
local Sound = {}
ns.Sound = Sound

Sound.DIR = "Interface\\AddOns\\" .. ADDON .. "\\Sounds\\"
Sound.CHANNEL = "Master"
Sound.GAP = 0.55 -- seconds between syllables when Data/SoundLengths.lua has no length for the file
Sound.DELAY = 0.25 -- a hover held this long speaks, so sweeping the mouse across a line stays quiet

-- The companion's syllable grammar (wah/audio.py _SYLLABLE): an optional initial, then one of these finals.
local FINALS = {}
for f in
	(
		"a ai an ang ao e ei en eng er o ong ou i ia ian iang iao ie in ing iong iu u ua uai uan uang ue ui un uo "
		.. "v ve van vn"
	):gmatch("%S+")
do
	FINALS[f] = true
end
local INITIALS = { "zh", "ch", "sh" }
for c in ("bpmfdtnlgkhjqxrzcsyw"):gmatch(".") do
	INITIALS[#INITIALS + 1] = c
end

-- "ni3", "lv4", "ma5" are bank names; "ok5", "gg5", "ni" are not.
function Sound.isSyllable(name)
	local base = name:match("^(%l+)[1-5]$")
	if not base then
		return false
	end
	if FINALS[base] then
		return true
	end
	for _, ini in ipairs(INITIALS) do
		if base:sub(1, #ini) == ini and FINALS[base:sub(#ini + 1)] then
			return true
		end
	end
	return false
end

-- Bank names for the syllables of a reading: "lǜ nǚ ma" -> { "lv4", "nv3", "ma5" }. Lowercase, ü as v,
-- neutral tone 5; tokens that are not Mandarin syllables ("gg", "r", "123") are skipped. Same answers as
-- wah.audio.syllables: a run of letters, then an optional tone digit 1-5.
function Sound.names(reading)
	local out = {}
	if type(reading) ~= "string" or reading == "" then
		return out
	end
	local s = ns.Pinyin.numbered(reading):gsub("\195\188", "v"):gsub("\195\156", "V")
	for letters, digit in s:gmatch("(%a+)([1-5]?)") do
		local name = letters:lower() .. (digit ~= "" and digit or "5")
		if Sound.isSyllable(name) then
			out[#out + 1] = name
		end
	end
	return out
end

local function soundOn()
	local get = C_CVar and C_CVar.GetCVarBool
	if not get then
		return nil
	end
	local ok, on = pcall(get, "Sound_EnableAllSound")
	if ok then
		return on
	end
	return nil
end

Sound.result = nil -- Sound.probe(): { willPlay, handle, status, path, soundOn, error }

-- Plays probe.ogg and stops it at once. status: "ok"; "refused" (the client would not play the file: broken,
-- the bank cannot work); "error" (PlaySoundFile raised); "sound off" (game sound disabled: not now, the
-- next probe may pass). Stored in selftest.soundProbe.
function Sound.probe()
	local path = Sound.DIR .. "probe.ogg"
	local r = { path = path, soundOn = soundOn() }
	if type(PlaySoundFile) ~= "function" then
		r.status, r.error = "error", "PlaySoundFile missing"
	else
		local okCall, willPlay, handle = pcall(PlaySoundFile, path, Sound.CHANNEL)
		if not okCall then
			r.status, r.error = "error", tostring(willPlay)
		else
			r.willPlay, r.handle = willPlay == true, handle
			if r.willPlay then
				r.status = "ok"
				if handle and StopSound then
					StopSound(handle)
				end
			elseif r.soundOn == false then
				r.status = "sound off"
			else
				r.status = "refused"
			end
		end
	end
	Sound.result = r
	if ns.selftest then
		ns.selftest.soundProbe = r
	end
	return r
end

-- Whether the bank can play now; false with the reason the card shows otherwise.
function Sound.ready()
	local r = Sound.result
	-- Sound was off at the last probe and is on now: probe again, so turning sound on needs no /reload.
	if r and r.status == "sound off" and soundOn() == true then
		r = Sound.probe()
	end
	if not r then
		return false, "sound not probed yet"
	end
	if r.status == "ok" then
		return true
	end
	if r.status == "sound off" then
		return false, "game sound is off"
	end
	return false, "sound plays in the companion"
end

-- Hover setting (ui.speak, default on).
function Sound.enabled()
	return not (ns.db and ns.db.ui and ns.db.ui.speak == false)
end

-- Handles of the files playing now, each with the time it ends ({ handle, ends }): Sound.stop must reach every one
-- (syllables overlap by Sound.OVERLAP), and a file that has ended is dropped when the next one starts.
local generation, handles = 0, {}

local function now()
	return GetTime and GetTime() or 0
end

local function track(handle, seconds)
	local t = now()
	local live = {}
	for _, h in ipairs(handles) do
		if h.ends > t then
			live[#live + 1] = h
		end
	end
	live[#live + 1] = { handle = handle, ends = t + seconds }
	handles = live
end

-- Files of the word being spoken that have not ended yet.
function Sound.playing()
	local t, n = now(), 0
	for _, h in ipairs(handles) do
		if h.ends > t then
			n = n + 1
		end
	end
	return n
end

-- Stops the word being spoken and cancels its queued syllables.
function Sound.stop()
	generation = generation + 1
	if StopSound then
		for _, h in ipairs(handles) do
			StopSound(h.handle)
		end
	end
	handles = {}
end

-- A file's full length in seconds from its ms (Sound.GAP when unknown).
local function seconds(ms)
	return type(ms) == "number" and ms > 0 and ms / 1000 or Sound.GAP
end

local function playOne(name, gen)
	if gen ~= generation or type(PlaySoundFile) ~= "function" then
		return
	end
	local st = ns.selftest
	local okCall, willPlay, handle = pcall(PlaySoundFile, Sound.DIR .. name .. ".ogg", Sound.CHANNEL)
	if okCall and willPlay then
		track(handle, seconds(ns.Data and ns.Data.soundMs and ns.Data.soundMs[name]))
		if st then
			st.counters.syllables = (st.counters.syllables or 0) + 1
		end
	elseif st then
		-- The probe passed, so a refusal here is a syllable the bank lacks (or a broken file).
		st.soundMiss = { name = name, error = not okCall and tostring(willPlay) or nil }
	end
end

Sound.OVERLAP = 0.03 -- each file has 15 ms of padding at both ends: the next syllable starts inside it

-- Seconds until the syllable after `name` starts: the file's length (Data/SoundLengths.lua) less the overlap,
-- or Sound.GAP when the table has no entry.
function Sound.length(name)
	local ms = ns.Data and ns.Data.soundMs and ns.Data.soundMs[name]
	if type(ms) ~= "number" then
		return Sound.GAP
	end
	return math.max(ms / 1000 - Sound.OVERLAP, 0.1)
end

-- The word bank (Phase 5d): Sounds/words/<stem>.ogg, one file per spoken (post-sandhi) reading, listed in
-- Data/SoundIndex.lua as ns.Data.wordSound[word] = { stem, ms, reading }. `reading` is the addon's own reading the
-- file was made for ("ni3hao3": Sound.names of what the card shows, run together); the file plays only when the
-- card shows that reading, so a polyphone (行 háng/xíng) or a game term read another way plays its syllables. The
-- companion writes the index and lists only files older than the client's start (a newer file would not play
-- until a restart). No index: syllables only.
Sound.WORDS = Sound.DIR .. "words\\"

local function count(key)
	local st = ns.selftest
	if st then
		st.counters[key] = (st.counters[key] or 0) + 1
	end
end

-- The bank file for a word shown with `reading`: stem and ms, or nil and why (not in the index, no index, a secret
-- value, a malformed entry, an entry without a reading, or the card shows another reading than the file says).
function Sound.wordEntry(word, reading)
	if type(word) ~= "string" or word == "" then
		return nil, "no word"
	end
	if issecretvalue and issecretvalue(word) then
		return nil, "secret"
	end
	local index = ns.Data and ns.Data.wordSound
	local entry = type(index) == "table" and index[word]
	if type(entry) ~= "table" then
		return nil, "not in the index"
	end
	local stem, ms, want = entry[1], entry[2], entry[3]
	if type(stem) ~= "string" or not stem:match("^[%w_]+$") then
		return nil, "malformed entry"
	end
	if type(want) ~= "string" or want == "" then
		return nil, "entry has no reading"
	end
	if table.concat(Sound.names(reading)) ~= want then
		count("wordReadingDiffers")
		return nil, "card reads " .. tostring(reading) .. ", the file says " .. want
	end
	return stem, type(ms) == "number" and ms or nil
end

-- Plays the word's file once. False when the client refused it (counted in selftest.counters.wordMiss, recorded in
-- selftest.wordMiss and selftest.soundMiss; the counter survives a later syllable miss).
local function playWord(stem, ms)
	local st = ns.selftest
	local okCall, willPlay, handle = false, "PlaySoundFile missing", nil
	if type(PlaySoundFile) == "function" then
		okCall, willPlay, handle = pcall(PlaySoundFile, Sound.WORDS .. stem .. ".ogg", Sound.CHANNEL)
	end
	if okCall and willPlay then
		track(handle, seconds(ms))
		count("wordSounds")
		return true
	end
	if st then
		count("wordMiss")
		st.wordMiss = { name = "words/" .. stem, error = not okCall and tostring(willPlay) or nil }
		st.soundMiss = st.wordMiss
	end
	return false
end

-- Seconds until the item after `item` starts: a word file's ms less the overlap, or a syllable's Sound.length.
local function itemLength(item)
	if item.stem then
		return type(item.ms) == "number" and math.max(item.ms / 1000 - Sound.OVERLAP, 0.1) or Sound.GAP
	end
	return Sound.length(item.name)
end

local function syllableItems(reading)
	local out = {}
	for _, name in ipairs(Sound.names(reading)) do
		out[#out + 1] = { name = name }
	end
	return out
end

-- Plays `items` from now, each after the one before it has played its length.
local function chain(items, gen, playFirst)
	if playFirst then
		playOne(items[1].name, gen)
	end
	local at = 0
	for i = 2, #items do
		local item = items[i]
		at = at + itemLength(items[i - 1])
		C_Timer.After(at, function()
			if gen ~= generation then
				return
			end
			if item.stem then
				if not playWord(item.stem, item.ms) then
					-- refused (a broken file): its syllables from here
					local syl = syllableItems(item.reading)
					if #syl > 0 then
						chain(syl, gen, true)
					end
				end
			else
				playOne(item.name, gen)
			end
		end)
	end
	return at + itemLength(items[#items])
end

-- Speaks words in a row: `parts` is a list of { reading = "nǐ hǎo", word = "你好" }. A word in the bank plays its
-- one file (when the card's reading matches the file's), every other word its syllables, each starting when the
-- one before ends (the word file's ms, the syllables' Sound.length). Returns the names queued ({ "words/ni2hao3",
-- "ma5" }) and the seconds until the last one ends, or nil and why nothing plays.
function Sound.speakParts(parts)
	local ok, why = Sound.ready()
	if not ok then
		return nil, why
	end
	local items, readings = {}, {}
	for _, p in ipairs(parts) do
		readings[#readings + 1] = tostring(p.reading)
		local stem, ms = Sound.wordEntry(p.word, p.reading)
		if stem then
			items[#items + 1] = { stem = stem, ms = ms, reading = p.reading }
		else
			for _, item in ipairs(syllableItems(p.reading)) do
				items[#items + 1] = item
			end
		end
	end
	Sound.stop()
	local gen = generation
	-- The first word file plays now; refused (a broken file), its syllables take its place.
	while items[1] and items[1].stem and not playWord(items[1].stem, items[1].ms) do
		local first = table.remove(items, 1)
		local syl = syllableItems(first.reading)
		for i = #syl, 1, -1 do
			table.insert(items, 1, syl[i])
		end
	end
	if #items == 0 then
		return nil, "no syllables in " .. table.concat(readings, " ")
	end
	local length = chain(items, gen, not items[1].stem)
	local names = {}
	for i, item in ipairs(items) do
		names[i] = item.stem and ("words/" .. item.stem) or item.name
	end
	count("spoken")
	return names, length
end

-- Speaks a reading ("nǐ hǎo"): the word's bank file when `word` is in the bank with that reading, else the
-- syllables. Returns the bank names queued ({ "words/ni2hao3" } for a bank word), or nil and why nothing plays.
function Sound.speak(reading, word)
	return Sound.speakParts({ { reading = reading, word = word } })
end

-- Whether Data/SoundIndex.lua loaded (selftest.soundIndex): it is the companion's file, gitignored, and listed in
-- the TOC, so a PC without a bank build has none. noReading counts rows from an index older than the reading check
-- (they play syllables until `wah bank build` rewrites it).
function Sound.indexSummary()
	local index = ns.Data and ns.Data.wordSound
	if type(index) ~= "table" then
		return { loaded = false, entries = 0 }
	end
	local n, noReading = 0, 0
	for _, e in pairs(index) do
		n = n + 1
		if type(e) ~= "table" or type(e[3]) ~= "string" then
			noReading = noReading + 1
		end
	end
	return { loaded = true, entries = n, noReading = noReading > 0 and noReading or nil }
end

-- After a held hover: speaks the word (bank file or reading) if ctx is still the open card (Card.ctx)
-- after Sound.DELAY.
function Sound.speakHover(ctx, reading, word)
	if not Sound.enabled() or not Sound.ready() or not (C_Timer and C_Timer.After) then
		return
	end
	C_Timer.After(Sound.DELAY, function()
		if ns.Card.ctx == ctx then
			Sound.speak(reading, word)
		end
	end)
end
