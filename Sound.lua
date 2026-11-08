-- Speaks a hovered word one syllable at a time from the syllable bank in Sounds/ (<syl><tone>.ogg, ü written
-- as v, neutral tone 5; rendered by the companion's gen_audio.py with Kokoro). Sound.names is pure and keeps
-- parity with the companion's wah.audio.syllables; Sound.probe checks at login that the client plays addon
-- .ogg files at all (the same client refuses addon fonts, Font.lua).
local ADDON, ns = ...
local Sound = {}
ns.Sound = Sound

Sound.DIR = "Interface\\AddOns\\" .. ADDON .. "\\Sounds\\"
Sound.CHANNEL = "Master"
Sound.GAP = 0.42 -- seconds between syllables; the files are 409 to 463 ms
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

local generation, lastHandle = 0, nil

-- Stops the word being spoken and cancels its queued syllables.
function Sound.stop()
	generation = generation + 1
	if lastHandle and StopSound then
		StopSound(lastHandle)
	end
	lastHandle = nil
end

local function playOne(name, gen)
	if gen ~= generation then
		return
	end
	local st = ns.selftest
	local okCall, willPlay, handle = pcall(PlaySoundFile, Sound.DIR .. name .. ".ogg", Sound.CHANNEL)
	if okCall and willPlay then
		lastHandle = handle
		if st then
			st.counters.syllables = (st.counters.syllables or 0) + 1
		end
	elseif st then
		-- The probe passed, so a refusal here is a syllable the bank lacks (or a broken file).
		st.soundMiss = { name = name, error = not okCall and tostring(willPlay) or nil }
	end
end

-- Speaks a reading ("nǐ hǎo"). Returns the bank names queued, or nil and why nothing plays.
function Sound.speak(reading)
	local ok, why = Sound.ready()
	if not ok then
		return nil, why
	end
	local names = Sound.names(reading)
	if #names == 0 then
		return nil, "no syllables in " .. tostring(reading)
	end
	Sound.stop()
	local gen = generation
	playOne(names[1], gen)
	for i = 2, #names do
		local name = names[i]
		C_Timer.After((i - 1) * Sound.GAP, function()
			playOne(name, gen)
		end)
	end
	if ns.selftest then
		ns.selftest.counters.spoken = (ns.selftest.counters.spoken or 0) + 1
	end
	return names
end

-- After a held hover: speaks the reading if ctx is still the open card (Card.ctx) after Sound.DELAY.
function Sound.speakHover(ctx, reading)
	if not Sound.enabled() or not Sound.ready() then
		return
	end
	C_Timer.After(Sound.DELAY, function()
		if ns.Card.ctx == ctx then
			Sound.speak(reading)
		end
	end)
end
