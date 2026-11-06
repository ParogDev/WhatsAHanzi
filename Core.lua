-- Addon entry: SavedVariables defaults and migration, the selftest contract (docs/verify-loop.md), slash
-- commands, event wiring. Loads last (see the TOC).
local ADDON, ns = ...
WhatsAHanzi = ns -- the one global besides WhatsAHanziDB, for /dump and other addons

local DB_VERSION = 1

local defaults = {
	dbVersion = DB_VERSION,
	channels = {}, -- event -> false to disable; absent = on
	ui = { hidden = false, point = nil, fontSize = 22 },
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
	-- [2] = function(db) ... end,
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
local selftest = { counters = { lines = 0, secret = 0, chinese = 0, words = 0 }, lastLines = {} }
ns.selftest = selftest

function selftest.remember(rec)
	local l = selftest.lastLines
	l[#l + 1] = { sender = rec.sender, text = rec.text, pinyin = rec.pinyin }
	while #l > 20 do
		table.remove(l, 1)
	end
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
		counters = selftest.counters,
		dictWords = ns.Dict.count(),
		pinyinChars = ns.Pinyin.count(),
		inbox = ns.Data and ns.Data.inbox and ns.Data.inbox.generatedAt or nil,
		lastLines = selftest.lastLines,
		lastError = selftest.lastError,
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
	elseif cmd == "status" then
		local c = selftest.counters
		print(
			("v%s: %d lines, %d chinese, %d secret, %d words; dict %d, pinyin %d, font %s"):format(
				ns.version(),
				c.lines,
				c.chinese,
				c.secret,
				c.words,
				ns.Dict.count(),
				ns.Pinyin.count(),
				tostring(ns.Font.probe and ns.Font.probe.path)
			)
		)
	elseif cmd == "size" then
		if ns.UI.setFontSize(rest) then
			print("font size " .. ns.db.ui.fontSize)
		else
			print("/hanzi size <10-48> (now " .. tostring(ns.db.ui.fontSize or ns.UI.DEFAULT_FONT_SIZE) .. ")")
		end
	elseif cmd == "vocab" then
		local n = 0
		for _ in pairs(ns.db.vocab) do
			n = n + 1
		end
		print(n .. " words in the vocabulary log (WhatsAHanziDB.vocab).")
	elseif cmd == "reset" then
		ns.db.ui = { hidden = false }
		local f = ns.UI.get()
		f:ClearAllPoints()
		f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 30, 260)
		f:Show()
	else
		print("/hanzi  toggle | test <chinese text> | size <10-48> | status | vocab | reset")
	end
end

local frame = CreateFrame("Frame")
ns.frame = frame
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
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
		ns.UI.get()
		ns.Chat.register(self)
		selftest.snapshot("login")
		SLASH_WHATSAHANZI1 = "/hanzi"
		SLASH_WHATSAHANZI2 = "/wah"
		SlashCmdList.WHATSAHANZI = onSlash
		print("loaded. /hanzi for the pane, /hanzi test 你好 to try it.")
	elseif event == "PLAYER_LOGOUT" then
		selftest.snapshot("logout")
	elseif event:sub(1, 9) == "CHAT_MSG_" then
		ns.Chat.onEvent(self, event, ...)
	end
end)
