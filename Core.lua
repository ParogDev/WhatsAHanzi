-- Addon entry: SavedVariables defaults and migration, the selftest contract (docs/verify-loop.md), slash
-- commands, event wiring. Loads last (see the TOC).
local ADDON, ns = ...
WhatsAHanzi = ns -- the one global besides WhatsAHanziDB, for /dump and other addons

local DB_VERSION = 3

local defaults = {
	dbVersion = DB_VERSION,
	channels = {}, -- event -> false to disable; absent = on
	-- inChat: link Chinese words in the normal chat window for hover cards (false turns it off).
	-- knownAfter: a word seen this many times counts as known; cardScale: the hover card's scale.
	ui = {
		hidden = true,
		inChat = true,
		point = nil,
		fontSize = 22,
		font = nil,
		tones = "marks",
		knownAfter = 8,
		cardScale = 1,
		hoverKeys = false, -- K/S on an open card; opt-in so the card never takes keys the user bound
		speak = true, -- a held hover speaks the word from the syllable bank (Sound.lua)
		-- chatLog: turn the client's chat log (Logs\WoWChatLog.txt) on at login; the companion reads it.
		-- /chatlog lasts one client session only, so without this the companion goes blind after a restart.
		chatLog = true,
		-- recent: keep the last Chinese chat lines (WhatsAHanziDB.recent) for the companion and print them again
		-- after a /reload (Chat.recentRestore).
		recent = true,
	},
	vocab = {},
	recent = {},
	selftest = {},
}

local function copyDefaults(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then
				dst[k] = {}
			end
			copyDefaults(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

-- Migrations run in order from the stored dbVersion up to DB_VERSION.
local migrations = {
	-- 2: words are glossed in the chat window now, so the pane starts hidden (/hanzi opens it).
	[2] = function(db)
		if type(db.ui) == "table" then
			db.ui.hidden = true
		end
	end,
	-- 3: the hover card and known-word colouring arrive with their two settings.
	[3] = function(db)
		if type(db.ui) ~= "table" then
			db.ui = {}
		end
		db.ui.knownAfter = db.ui.knownAfter or 8
		db.ui.cardScale = db.ui.cardScale or 1
	end,
}

function ns.initDB(saved)
	saved = saved or {}
	local from = saved.dbVersion or DB_VERSION
	for v = from + 1, DB_VERSION do
		if migrations[v] then
			migrations[v](saved)
		end
		saved.dbVersion = v
	end
	-- the pixel strip was removed (0.1.1): its setting and selftest section go with it
	if type(saved.ui) == "table" then
		saved.ui.strip = nil
	end
	if type(saved.selftest) == "table" then
		saved.selftest.strip = nil
	end
	copyDefaults(saved, defaults)
	ns.db = saved
	return saved
end

-- The TOC version; "dev" while the packager's @project-version@ placeholder is unreplaced (a linked checkout).
function ns.version()
	local v = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")
	if not v or v:sub(1, 1) == "@" then
		return "dev"
	end
	return v
end

-- Selftest: what the verify loop reads back after a /reload. Never contains secret values.
local selftest = {
	counters = { lines = 0, secret = 0, chinese = 0, words = 0, linked = 0, cards = 0, marks = 0 },
	lastLines = {},
}
ns.selftest = selftest

-- Whether the client logs chat now: C_ChatInfo.IsLoggingChat, else LoggingChat() with no argument (both in Forever).
local function isLoggingChat()
	if C_ChatInfo and C_ChatInfo.IsLoggingChat then
		return C_ChatInfo.IsLoggingChat()
	end
	if LoggingChat then
		return LoggingChat()
	end
	return nil
end

-- Turn the chat log on at login when the chatLog setting allows (the companion follows Logs\WoWChatLog.txt).
-- Returns selftest.chatLogging: { setting, before, on, turnedOn, why }. `why` names the broken link.
function ns.ensureChatLogging()
	local st = { setting = ns.db.ui.chatLog ~= false }
	selftest.chatLogging = st
	if not LoggingChat then
		st.why = "LoggingChat missing: the companion gets no chat (type /chatlog)"
		return st
	end
	local okBefore, before = pcall(isLoggingChat)
	if okBefore then
		st.before = before
	end
	if not st.setting then
		st.on = st.before
		if not st.before then
			st.why = "chatLog setting off: the companion gets no chat"
		end
		return st
	end
	if st.before then
		st.on = true
		return st
	end
	local ok, err = pcall(LoggingChat, true)
	if not ok then
		st.why = "LoggingChat(true): " .. tostring(err)
		return st
	end
	local okAfter, after = pcall(isLoggingChat)
	st.on = okAfter and after or false
	st.turnedOn = st.on
	if not st.on then
		st.why = "LoggingChat(true) left the chat log off"
	end
	return st
end

function selftest.remember(rec)
	local l = selftest.lastLines
	l[#l + 1] = { sender = rec.sender, text = rec.text, pinyin = rec.pinyin }
	while #l > 20 do
		table.remove(l, 1)
	end
end

-- What the companion last wrote (Data/Local.lua), or nil when the file is absent or empty.
function selftest.liveSummary()
	local live = ns.Data and ns.Data.live
	if not live then
		return nil
	end
	local n = 0
	for _ in pairs(live.lines or {}) do
		n = n + 1
	end
	return { generatedAt = live.generatedAt, model = live.model, lines = n, heartbeat = live.heartbeat }
end

-- "45 s", "12 min", "3 h", "2 d".
function ns.ageText(s)
	s = math.max(0, math.floor(s))
	if s < 120 then
		return s .. " s"
	elseif s < 7200 then
		return math.floor(s / 60) .. " min"
	elseif s < 172800 then
		return math.floor(s / 3600) .. " h"
	end
	return math.floor(s / 86400) .. " d"
end

-- Whether the companion was running when this /reload read Data/Local.lua. The companion rewrites the file at least
-- every `heartbeatEvery` seconds and stamps `heartbeat` (epoch seconds), so a stamp older than three beats means it
-- stopped: a quiet chat no longer looks the same as a dead companion. The stamp says the companion process is up,
-- not that translating works (a refused API key still beats). The addon cannot hear from the companion between
-- reloads (nothing reaches a running client but the files it reads at load), so this is checked at load.
-- { state = "absent" | "unknown" | "running" | "stopped", age, limit, why }; `why` names the link.
ns.COMPANION_MISSED_BEATS = 3
function ns.companionState(live, now)
	if type(live) ~= "table" then
		return { state = "absent", why = "Data/Local.lua absent or empty: no companion on this PC, or it never wrote" }
	end
	local beat = tonumber(live.heartbeat)
	if not beat then
		return { state = "unknown", why = "Data/Local.lua has no heartbeat (written by a companion before wah 0.9.0)" }
	end
	local every = tonumber(live.heartbeatEvery)
	if not every or every ~= every or every < 30 or every > 600 then
		every = 60 -- absent, NaN or out of range: a huge beat would never trip the limit
	end
	local limit = math.max(every * ns.COMPANION_MISSED_BEATS, 180)
	local age = now - beat
	if age < -60 then
		return {
			state = "unknown",
			age = age,
			why = ("heartbeat is %s in the future: the PC clock was set back"):format(ns.ageText(-age)),
		}
	end
	if age > limit then
		return {
			state = "stopped",
			age = age,
			limit = limit,
			why = ("Data/Local.lua last written %s ago (the companion rewrites it every %d s): not running"):format(
				ns.ageText(age),
				every
			),
		}
	end
	return { state = "running", age = age, limit = limit }
end

-- The chat notice for a stopped companion, or nil when there is nothing to say.
function ns.companionNotice(st)
	if st.state ~= "stopped" then
		return nil
	end
	return ("|cffff6060Companion not running:|r wah last checked in %s ago, so new Chinese lines get no translation. Start it again (wah watch), then /reload to check."):format(
		ns.ageText(st.age)
	)
end

-- Where ChatFrame1 sits, for the companion's overlay to dock against: UI units (origin bottom-left), the frame's
-- effective scale, and the client size in pixels. A failure names the link that broke instead of a bare nil.
function selftest.chatRect()
	local f = _G.ChatFrame1
	if not f or not f.GetRect then
		return { why = "ChatFrame1 missing" }
	end
	local ok, left, bottom, width, height = pcall(f.GetRect, f)
	if not ok then
		return { why = "ChatFrame1:GetRect: " .. tostring(left) }
	end
	if not left then
		return { why = "ChatFrame1:GetRect returned nil (frame not laid out yet)" }
	end
	local screenW, screenH
	if GetPhysicalScreenSize then
		screenW, screenH = GetPhysicalScreenSize()
	end
	return {
		left = left,
		bottom = bottom,
		width = width,
		height = height,
		scale = f:GetEffectiveScale(),
		screenW = screenW,
		screenH = screenH,
	}
end

function selftest.snapshot(phase)
	local version, build, _, interface = GetBuildInfo()
	local rect = selftest.chatRect()
	if not rect.why then
		ns.db.ui.chatRect = rect -- the companion reads it from SavedVariables (plan §1 Docking)
	end
	local s = {
		version = ns.version(),
		clientVersion = version,
		build = build,
		interface = interface,
		project = WOW_PROJECT_ID,
		locale = GetLocale(),
		phase = phase,
		savedAt = date("%Y-%m-%d %H:%M:%S"),
		loadedAt = selftest.loadedAt,
		fontProbe = ns.Font and ns.Font.probe or nil,
		-- Sound.lua is a new TOC file and Sounds/ new files: a /reload alone loads neither, a restart does.
		soundProbe = (ns.Sound and ns.Sound.result) or "Sound.lua not loaded (restart the client)",
		soundMiss = selftest.soundMiss,
		wordMiss = selftest.wordMiss,
		-- Data/SoundIndex.lua is the companion's gitignored file: { loaded, entries } says whether this reload had it.
		soundIndex = ns.Sound and ns.Sound.indexSummary() or nil,
		counters = selftest.counters,
		dictWords = ns.Dict.count(),
		-- Data/Game.lua is a new TOC file: a /reload alone does not load it, only a client restart does.
		gameTerms = ns.Dict.gameCount() or "Data/Game.lua not loaded (restart the client)",
		pinyinChars = ns.Pinyin.count(),
		live = selftest.liveSummary(),
		companion = selftest.companion,
		lastLines = selftest.lastLines,
		lastError = selftest.lastError,
		chatHook = selftest.chatHook,
		hoverBounds = selftest.hoverBounds,
		motd = ns.db.motd and ns.db.motd.hash or nil,
		motdLink = selftest.motdLink,
		cardLineMiss = selftest.cardLineMiss,
		cardPool = ns.Card and ns.Card.poolSummary() or nil,
		options = selftest.options,
		chatLogging = selftest.chatLogging,
		recent = ns.Chat and ns.Chat.recentState or nil,
		ui = { chatRect = rect },
	}
	ns.db.selftest = s
	return s
end

local function print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff99ccffWhatsAHanzi:|r " .. tostring(msg))
end
ns.print = print

-- `/hanzi fake <scene>`: three invented lines each (invented speakers), printed into ChatFrame1 with hover links
-- like `/hanzi test`, so the card can be tried with nobody online. { channel kind, speaker, text }.
ns.fakeScenes = {
	banter = {
		{ "GUILD", "Baiyun", "大家晚上好，今天谁去副本" },
		{ "GUILD", "Tiedan", "我刚在灰谷被联盟猎人射爆了" },
		{ "GUILD", "Huahua", "哈哈哈太惨了，要不要帮忙" },
	},
	yell = {
		{ "YELL", "Dazhuang", "谁抢了我的怪！" },
		{ "SAY", "Feifei", "我先打的，你看清楚" },
		{ "YELL", "Dazhuang", "好吧，组一下一起打" },
	},
	lfg = {
		{ "CHANNEL", "Yeying", "死亡矿井缺T缺奶，来的密" },
		{ "CHANNEL", "Shitou", "出恐惧之刃 50G 不议价" },
		{ "GUILD", "Jinqian", "这刀太贵了吧" },
	},
}

-- `/hanzi speak <text>`'s words: the text segmented as chat is (Dict.segment), one { reading, word } per Han token
-- with the reading its card shows; Latin, digits and punctuation are left out.
function ns.speakParts(text)
	local parts = {}
	for _, tok in ipairs(ns.Dict.segment(text)) do
		if tok.han then
			parts[#parts + 1] = { reading = ns.Card.reading({ chars = ns.Card.charReadings(tok) }), word = tok.word }
		end
	end
	return parts
end

local function onSlash(input)
	local cmd, rest = strsplit(" ", (input or ""):lower(), 2)
	if cmd == "" or cmd == "toggle" then
		ns.UI.toggle()
	elseif cmd == "test" and rest then
		ns.Chat.process("SLASH", rest, "You")
		print(ns.Chat.linkify(rest) or rest)
	elseif cmd == "fake" then
		local scene = ns.fakeScenes[rest or "banter"]
		if not scene then
			local names = {}
			for name in pairs(ns.fakeScenes) do
				names[#names + 1] = name
			end
			table.sort(names)
			print("/hanzi fake " .. table.concat(names, " | ") .. " (invented lines, not sent to anyone)")
		else
			-- Linked like chat, but not through Chat.process: replays must not count toward "known" words.
			for _, line in ipairs(scene) do
				selftest.counters.fake = (selftest.counters.fake or 0) + 1
				local frame = _G.ChatFrame1 or DEFAULT_CHAT_FRAME
				frame:AddMessage(
					"[fake " .. line[1]:lower() .. "] " .. line[2] .. ": " .. (ns.Chat.linkify(line[3]) or line[3])
				)
			end
		end
	elseif cmd == "chat" then
		if rest == "on" or rest == "off" then
			ns.db.ui.inChat = rest == "on"
			print(
				"words in the chat window "
					.. (ns.db.ui.inChat and "linked for hover" or "left alone; /hanzi opens the pane")
					.. " (new lines)"
			)
		else
			print("/hanzi chat on | off (now " .. (ns.db.ui.inChat == false and "off" or "on") .. ")")
		end
	elseif cmd == "status" then
		local comp = selftest.companion
		if comp then
			print(
				"companion at the last /reload: "
					.. comp.state
					.. (comp.why and (": " .. comp.why) or "")
					.. (comp.state == "stopped" and "; start it again (wah watch), then /reload" or "")
			)
		end
		local c = selftest.counters
		local path, name = ns.Font.current()
		local accepted = {}
		for _, n in ipairs({ "noto", "kai", "hei", "arial", "friz" }) do
			if ns.Font.probe and ns.Font.probe.byName[n] then
				accepted[#accepted + 1] = n
			end
		end
		print(
			("v%s: %d lines, %d chinese, %d secret, %d words; dict %d, pinyin %d; tones %s; font %s (%s); accepted: %s"):format(
				ns.version(),
				c.lines,
				c.chinese,
				c.secret,
				c.words,
				ns.Dict.count(),
				ns.Pinyin.count(),
				ns.db.ui.tones or "marks",
				tostring(name),
				tostring(path),
				table.concat(accepted, " ")
			)
		)
	elseif cmd == "font" then
		local ok, why = ns.Font.set(rest)
		if ok then
			ns.UI.applyFontSize()
			print("font " .. rest .. " (" .. ns.Font.NAMED[rest] .. ")")
		else
			print(
				"/hanzi font kai | arial | friz | hei | noto (default: the chat line's own CJK font)"
					.. (why and rest and (": " .. why) or "")
			)
		end
	elseif cmd == "options" then
		local ok, why = ns.Options.open()
		if not ok then
			print("|cffff6060" .. tostring(why) .. "|r")
		end
	elseif cmd == "tones" then
		if rest == "marks" or rest == "numbers" then
			ns.db.ui.tones = rest
			print("tones shown as " .. rest .. " (new lines; " .. ns.Pinyin.display("nǐ hǎo") .. ")")
		else
			print("/hanzi tones marks | numbers (now " .. (ns.db.ui.tones or "marks") .. ")")
		end
	elseif cmd == "size" then
		if ns.UI.setFontSize(rest) then
			print("font size " .. ns.db.ui.fontSize)
		else
			print("/hanzi size <10-48> (now " .. tostring(ns.db.ui.fontSize or ns.UI.DEFAULT_FONT_SIZE) .. ")")
		end
	elseif cmd == "speak" then
		-- /hanzi speak 你好朋友: the text segmented as chat is; each word as a hover would speak it (its word-bank
		-- file when the index has it with the card's reading, else its syllables), one after the other.
		local text = rest and (input or ""):match("^%s*%S+%s+(.+)$")
		if not text then
			local r = ns.Sound.result
			print("/hanzi speak <chinese text>; sound probe: " .. tostring(r and r.status or "not run"))
		else
			local names, why = ns.Sound.speakParts(ns.speakParts(text))
			print(names and table.concat(names, " ") or ("|cffff6060" .. tostring(why) .. "|r"))
		end
	elseif cmd == "vocab" then
		local n = 0
		for _ in pairs(ns.db.vocab) do
			n = n + 1
		end
		print(n .. " words in the vocabulary log (WhatsAHanziDB.vocab).")
	elseif cmd == "reset" then
		-- In place: the Settings panel holds a reference to ns.db.ui.
		for k in pairs(ns.db.ui) do
			ns.db.ui[k] = nil
		end
		copyDefaults(ns.db.ui, defaults.ui)
		ns.db.ui.hidden = false
		ns.Vocab.version = ns.Vocab.version + 1
		local f = ns.UI.get()
		f:ClearAllPoints()
		f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 30, 260)
		f:Show()
		-- The Settings panel caches what it drew: tell each setting its value changed.
		ns.Options.refresh()
	else
		print(
			"/hanzi  toggle | options | test <chinese text> | speak <chinese text> | chat on|off | size <10-48> | font <name> | tones marks|numbers | status | vocab | reset"
		)
	end
end

local frame = CreateFrame("Frame")
ns.frame = frame
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("GUILD_MOTD")
frame:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		if ... ~= ADDON then
			return
		end
		WhatsAHanziDB = ns.initDB(WhatsAHanziDB)
		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_LOGIN" then
		selftest.loadedAt = date("%Y-%m-%d %H:%M:%S")
		local okLog, errLog = pcall(ns.ensureChatLogging)
		if not okLog then
			selftest.chatLogging = { why = "ensureChatLogging: " .. tostring(errLog) }
			geterrorhandler()(errLog)
		end
		ns.Font.detect()
		ns.Font.chatCJK()
		if ns.Sound then
			local okSnd, errSnd = pcall(ns.Sound.probe)
			if not okSnd then
				selftest.soundProbe = { status = "error", error = "Sound.probe: " .. tostring(errSnd) }
				ns.Sound.result = selftest.soundProbe
				geterrorhandler()(errSnd)
			end
		end
		ns.UI.get()
		ns.Chat.register(self)
		local okOpt, errOpt = pcall(ns.Options.register)
		if not okOpt then
			selftest.options = { error = "Options.register: " .. tostring(errOpt) }
			geterrorhandler()(errOpt)
		end
		local ok, err = pcall(ns.Chat.hookChatFrames)
		if not ok then
			selftest.chatHook = { error = "hookChatFrames: " .. tostring(err) }
			geterrorhandler()(err)
		end
		-- No hover in chat (hook broken, or turned off): the pane is the only view, so show it for this session.
		local hookErr = selftest.chatHook and selftest.chatHook.error
		if hookErr or ns.db.ui.inChat == false then
			ns.UI.get():Show()
			if hookErr then
				print("|cffff6060" .. hookErr .. "|r; showing the pane instead.")
			end
		end
		local okMotd, errMotd = pcall(ns.Chat.hookMOTD)
		if not okMotd then
			selftest.motdLink = { why = "hookMOTD: " .. tostring(errMotd) }
			geterrorhandler()(errMotd)
		end
		local okRec, errRec = pcall(ns.Chat.recentRestore)
		if not okRec then
			ns.Chat.recentState.why = "recentRestore: " .. tostring(errRec)
			geterrorhandler()(errRec)
		end
		local okComp, comp = pcall(ns.companionState, ns.Data and ns.Data.live, time())
		selftest.companion = okComp and comp or { state = "error", why = "companionState: " .. tostring(comp) }
		selftest.snapshot("login")
		SLASH_WHATSAHANZI1 = "/hanzi"
		SLASH_WHATSAHANZI2 = "/wah"
		SlashCmdList.WHATSAHANZI = onSlash
		print(
			"loaded. Hover a Chinese word in chat; /hanzi options (K/S keys on the card are off until you turn them on), /hanzi test 你好."
		)
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- The notice only on a /reload: at a cold start Local.lua still holds the last session's stamp until the
		-- watcher's first write (about 5 s after Wow.exe), so a login would cry wolf almost every time.
		local _, isReloadingUi = ...
		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
		local comp = selftest.companion
		if comp then
			comp.noticeSkipped = not isReloadingUi
					and comp.state == "stopped"
					and "cold login: wah may not have written yet"
				or nil
		end
		local notice = comp and isReloadingUi and ns.companionNotice(comp)
		if notice then
			print(notice)
		end
	elseif event == "PLAYER_LOGOUT" then
		selftest.snapshot("logout")
	elseif event == "GUILD_MOTD" then
		ns.Chat.onMOTDEvent(...)
	elseif event:sub(1, 9) == "CHAT_MSG_" then
		ns.Chat.onEvent(self, event, ...)
	end
end)
