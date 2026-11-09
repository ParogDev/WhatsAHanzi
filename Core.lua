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
	},
	vocab = {},
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
	return { generatedAt = live.generatedAt, model = live.model, lines = n }
end

function selftest.snapshot(phase)
	local version, build, _, interface = GetBuildInfo()
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
		counters = selftest.counters,
		dictWords = ns.Dict.count(),
		-- Data/Game.lua is a new TOC file: a /reload alone does not load it, only a client restart does.
		gameTerms = ns.Dict.gameCount() or "Data/Game.lua not loaded (restart the client)",
		pinyinChars = ns.Pinyin.count(),
		live = selftest.liveSummary(),
		lastLines = selftest.lastLines,
		lastError = selftest.lastError,
		chatHook = selftest.chatHook,
		hoverBounds = selftest.hoverBounds,
		motd = ns.db.motd and ns.db.motd.hash or nil,
		motdLink = selftest.motdLink,
		cardLineMiss = selftest.cardLineMiss,
		cardPool = ns.Card and ns.Card.poolSummary() or nil,
		options = selftest.options,
	}
	ns.db.selftest = s
	return s
end

local function print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff99ccffWhatsAHanzi:|r " .. tostring(msg))
end
ns.print = print

local function onSlash(input)
	local cmd, rest = strsplit(" ", (input or ""):lower(), 2)
	if cmd == "" or cmd == "toggle" then
		ns.UI.toggle()
	elseif cmd == "test" and rest then
		ns.Chat.process("SLASH", rest, "You")
		print(ns.Chat.linkify(rest) or rest)
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
		-- /hanzi speak 你好: the words' readings through the syllable bank, as a hover would.
		local text = rest and (input or ""):match("^%s*%S+%s+(.+)$")
		if not text then
			local r = ns.Sound.result
			print("/hanzi speak <chinese text>; sound probe: " .. tostring(r and r.status or "not run"))
		else
			local parts = {}
			for _, tok in ipairs(ns.Dict.segment(text)) do
				if tok.han then
					parts[#parts + 1] = ns.Card.reading({ chars = ns.Card.charReadings(tok) })
				end
			end
			local names, why = ns.Sound.speak(table.concat(parts, " "))
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
		ns.Chat.rememberMOTD()
		local okMotd, errMotd = pcall(ns.Chat.hookMOTD)
		if not okMotd then
			selftest.motdLink = { why = "hookMOTD: " .. tostring(errMotd) }
			geterrorhandler()(errMotd)
		end
		selftest.snapshot("login")
		SLASH_WHATSAHANZI1 = "/hanzi"
		SLASH_WHATSAHANZI2 = "/wah"
		SlashCmdList.WHATSAHANZI = onSlash
		print(
			"loaded. Hover a Chinese word in chat; /hanzi options (K/S keys on the card are off until you turn them on), /hanzi test 你好."
		)
	elseif event == "PLAYER_LOGOUT" then
		selftest.snapshot("logout")
	elseif event == "GUILD_MOTD" then
		ns.Chat.onMOTDEvent(...)
	elseif event:sub(1, 9) == "CHAT_MSG_" then
		ns.Chat.onEvent(self, event, ...)
	end
end)
