-- Chat capture: registers the chat events the user enabled and turns Chinese lines into analysed entries.
-- Every text path guards issecretvalue: inside instances and encounters chat text is a secret string
-- (docs/forever-api.md) that can be shown but not inspected.
local _, ns = ...
local Chat = {}
ns.Chat = Chat

Chat.EVENTS = {
	"CHAT_MSG_GUILD",
	"CHAT_MSG_OFFICER",
	"CHAT_MSG_PARTY",
	"CHAT_MSG_PARTY_LEADER",
	"CHAT_MSG_RAID",
	"CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_INSTANCE_CHAT",
	"CHAT_MSG_INSTANCE_CHAT_LEADER",
	"CHAT_MSG_WHISPER",
	"CHAT_MSG_WHISPER_INFORM",
	"CHAT_MSG_EMOTE",
	"CHAT_MSG_SAY",
	"CHAT_MSG_YELL",
	"CHAT_MSG_CHANNEL",
}

local function isSecret(v)
	return issecretvalue ~= nil and issecretvalue(v)
end
Chat.isSecret = isSecret

-- Short sender: "Name-Realm" -> "Name". Sender names are not secret, but guard anyway.
local function shortName(name)
	if not name or isSecret(name) then
		return name
	end
	return (name:gsub("%-.*$", ""))
end

-- Analyses one line. Returns a record { sender, text, tokens, pinyin, secret = bool } and feeds the UI,
-- counters and vocabulary. Pure enough to unit test: UI calls go through ns.UI, which the mock stubs.
function Chat.process(event, text, sender)
	local counters = ns.selftest.counters
	counters.lines = counters.lines + 1
	local who = shortName(sender)
	if isSecret(text) then
		counters.secret = counters.secret + 1
		if ns.UI then
			ns.UI.addRaw(who, text, "instance: pinyin unavailable")
		end
		return { sender = who, secret = true }
	end
	if not ns.Han.hasHan(text) then
		return nil
	end
	counters.chinese = counters.chinese + 1
	local tokens = ns.Dict.segment(text)
	local pinyin = ns.Dict.pinyinLine(tokens)
	local rec = { sender = who, text = text, tokens = tokens, pinyin = pinyin, event = event }
	ns.Vocab.record(tokens, who)
	if ns.UI then
		ns.UI.addAnalysed(who, tokens, pinyin)
	end
	ns.selftest.remember(rec)
	return rec
end

function Chat.onEvent(_, event, text, sender)
	local ok, err = pcall(Chat.process, event, text, sender)
	if not ok then
		ns.selftest.lastError = tostring(err)
		geterrorhandler()(err)
	end
end

function Chat.register(frame)
	for _, ev in ipairs(Chat.EVENTS) do
		if ns.db.channels[ev] ~= false then
			frame:RegisterEvent(ev)
		else
			frame:UnregisterEvent(ev)
		end
	end
end

-- Recent lines by hash, so a hovered link knows its whole sentence: Chat.lines[hash] = { hash, body,
-- tokens }. When the cache passes LINES_MAX, one scan drops the least recently used LINES_EVICT entries, so a
-- busy channel pays for a full scan once every LINES_EVICT new lines rather than on every line.
Chat.LINES_MAX = 200
Chat.LINES_EVICT = 50
local lines = { map = {}, count = 0, clock = 0, scans = 0 }
Chat.lines = lines

local function byTick(a, b)
	return a.tick < b.tick
end

function lines.evict()
	local all = {}
	for h, l in pairs(lines.map) do
		all[#all + 1] = { hash = h, tick = l.tick }
	end
	table.sort(all, byTick)
	-- The newest entry (highest tick, sorted last) always stays.
	local drop = math.max(1, math.min(Chat.LINES_EVICT, #all - 1))
	for k = 1, drop do
		lines.map[all[k].hash] = nil
	end
	lines.count = lines.count - drop
	lines.scans = lines.scans + 1
end

function lines.put(hash, line)
	lines.clock = lines.clock + 1
	line.tick = lines.clock
	if not lines.map[hash] then
		lines.count = lines.count + 1
	end
	lines.map[hash] = line
	if lines.count > Chat.LINES_MAX then
		lines.evict()
	end
	return line
end

function lines.get(hash)
	local line = lines.map[hash]
	if line then
		lines.clock = lines.clock + 1
		line.tick = lines.clock
	end
	return line
end

function lines.clear()
	lines.map, lines.count = {}, 0
end

-- In the normal chat window: a message filter wraps each Chinese word in an addon hyperlink
-- (|Haddon:WhatsAHanzi:<lineHash>:<tokenIndex>|h<word>|h) and hovering one shows the card. Words not yet
-- known take a soft link colour; known words keep the line's chat colour. Escapes already in the line
-- (item and player links, textures, atlases, Battle.net names) are copied untouched. Blizzard skips filters
-- for secret text (canaccessvalue in ChatFrameFilters.lua); the guard here is the second line of defence.
Chat.LINK_PREFIX = "addon:WhatsAHanzi:"
Chat.NEW_WORD_COLOR = "|cffb9e6ff"
local ESCAPES = { "|H.-|h.-|h", "|T.-|t", "|A.-|a", "|K.-|k" }

local function linkWord(out, hash, index, word)
	local link = "|H" .. Chat.LINK_PREFIX .. hash .. ":" .. index .. "|h" .. word .. "|h"
	if ns.Vocab.isKnown(word) then
		out[#out + 1] = link
	else
		out[#out + 1] = Chat.NEW_WORD_COLOR .. link .. "|r"
	end
end

-- Segments one plain stretch into the line's token list and writes the linked text to out.
local function linkPlain(out, tokens, hash, s)
	if s == "" then
		return
	end
	if not ns.Han.hasHan(s) then
		out[#out + 1] = s
		tokens[#tokens + 1] = { word = s, han = false }
		return
	end
	for _, t in ipairs(ns.Dict.segment(s)) do
		tokens[#tokens + 1] = t
		if t.han then
			linkWord(out, hash, #tokens, t.word)
		else
			out[#out + 1] = t.word
		end
	end
end

-- Returns the line with every Han word linked and the cached line record, or nil when there is nothing to
-- do (secret, no Han). The hash covers the text as the event delivered it, escapes included.
function Chat.linkify(text)
	if type(text) ~= "string" or isSecret(text) or not ns.Han.hasHan(text) then
		return nil
	end
	local hash = ns.Hash.fnv1a32(text)
	local out, tokens, pos = {}, {}, 1
	while pos <= #text do
		local s, e
		for _, p in ipairs(ESCAPES) do
			local ps, pe = text:find(p, pos)
			if ps and (not s or ps < s) then
				s, e = ps, pe
			end
		end
		if not s then
			break
		end
		linkPlain(out, tokens, hash, text:sub(pos, s - 1))
		local raw = text:sub(s, e)
		out[#out + 1] = raw
		tokens[#tokens + 1] = { word = Chat.plainText(raw) or raw, han = false, escape = true }
		pos = e + 1
	end
	linkPlain(out, tokens, hash, text:sub(pos))
	local line = lines.put(hash, { hash = hash, body = text, tokens = tokens })
	return table.concat(out), line
end

-- The same line reaches the filter once per chat frame that shows it: keep the last result. The known/new
-- colour is baked into it, so the cache also keys on Vocab.version (bumped when a word changes state).
local lastIn, lastOut, lastVersion
function Chat.chatFilter(_, _, text, ...)
	if ns.db and ns.db.ui.inChat == false then
		return false
	end
	if isSecret(text) then
		return false
	end
	if text ~= lastIn or lastVersion ~= ns.Vocab.version then
		lastIn, lastVersion = text, ns.Vocab.version
		lastOut = Chat.linkify(text)
		if lastOut then
			ns.selftest.counters.linked = (ns.selftest.counters.linked or 0) + 1
		end
	end
	if not lastOut then
		return false
	end
	return false, lastOut, ...
end

Chat.SYSTEM_EVENT = "CHAT_MSG_SYSTEM"

-- The guild Message of the Day, for the companion: WhatsAHanziDB.motd = { text, hash, seen } when it has
-- Han (GUILD_MOTD and login). Returns the record, or nil and why not.
function Chat.rememberMOTD(text)
	if text == nil and C_GuildInfo and C_GuildInfo.GetMOTD then
		text = C_GuildInfo.GetMOTD() -- Forever: no GetGuildRosterMOTD global (GlobalAPI.lua)
	end
	if type(text) ~= "string" or isSecret(text) then
		return nil, "motd absent or secret"
	end
	if not ns.Han.hasHan(text) then
		return nil, "motd has no Han"
	end
	local rec = { text = text, hash = ns.Hash.fnv1a32(text), seen = time() }
	ns.db.motd = rec
	return rec
end

-- Hash and token index from one of our links; nil for any other link.
function Chat.tokenFromLink(link)
	if type(link) ~= "string" or isSecret(link) or link:sub(1, #Chat.LINK_PREFIX) ~= Chat.LINK_PREFIX then
		return nil
	end
	local hash, index = link:match("^(%x+):(%d+)$", #Chat.LINK_PREFIX + 1)
	if not hash then
		return nil
	end
	return hash, tonumber(index)
end

-- The plain text of a displayed message: links to their text, colour codes and textures dropped.
function Chat.plainText(msg)
	if type(msg) ~= "string" or isSecret(msg) then
		return nil
	end
	msg = msg:gsub("|H.-|h(.-)|h", "%1")
		:gsub("|c%x%x%x%x%x%x%x%x", "")
		:gsub("|r", "")
		:gsub("|T.-|t", "")
		:gsub("|A.-|a", "")
		:gsub("|K.-|k", "")
	return msg
end

-- The message body after a "[Channel] [Name]: " prefix (or the whole text when there is none).
function Chat.messageBody(plain)
	return plain:match("^%[.-%]%s*%[.-%]:%s*(.*)$") or plain:match("^%[.-%]:%s*(.*)$") or plain
end

-- Where the hovered link starts inside the message body, as a byte offset into Chat.messageBody(plainText(msg))
-- (0 = the body's first byte), or nil. Everything before the link is reduced the same way the body is, so the
-- offset survives escapes and item links with Chinese names before it.
function Chat.bodyOffset(msg, needle)
	local at = msg:find(needle, 1, true)
	if not at then
		return nil
	end
	local plain = Chat.plainText(msg)
	local before = Chat.plainText(msg:sub(1, at - 1))
	local offset = #before - (#plain - #Chat.messageBody(plain))
	return offset >= 0 and offset or nil
end

-- Index of the Han token for word that starts at byte offset in the body the tokens were cut from, or nil.
-- A repeated word ("走 走", "好好") then maps to its own position, not the first one.
function Chat.tokenAt(tokens, offset, word)
	local pos = 0
	for k, t in ipairs(tokens) do
		if pos == offset then
			return (t.han and t.word == word) and k or nil
		end
		if pos > offset then
			return nil
		end
		pos = pos + #t.word
	end
	return nil
end

-- Index of the first Han token whose word is word, or nil.
function Chat.firstWord(tokens, word)
	for k, t in ipairs(tokens) do
		if t.han and t.word == word then
			return k
		end
	end
	return nil
end

-- Fallback for a link whose line is not cached (a line from before the last /reload): searches the chat
-- frame's newest messages for the link and re-segments the body. Returns { hash, body, tokens }, index,
-- or nil with the link that broke. The rebuilt body has no escapes, so it is cached under the link's hash
-- only for this session's hovers; nothing is written for the companion.
function Chat.lineForLink(chatFrame, link, word)
	if not (chatFrame and chatFrame.GetMessageInfo) then
		return nil, "chatFrame.GetMessageInfo missing"
	end
	local hash, linkIndex = Chat.tokenFromLink(link)
	if isSecret(word) then
		word = nil
	end
	local needle = "|H" .. link .. "|h"
	for i = 1, 40 do
		local msg = chatFrame:GetMessageInfo(i)
		if msg == nil then
			break
		end
		if not isSecret(msg) and msg:find(needle, 1, true) then
			local body = Chat.messageBody(Chat.plainText(msg))
			local tokens = ns.Dict.segment(body)
			-- The rebuilt body has no escapes, so the link's index may point at another token, or at another
			-- occurrence of a repeated word: the link's byte position in the body decides. Re-segmenting can
			-- cut words differently; then the link's index if it still fits, else the first occurrence.
			local offset = word and Chat.bodyOffset(msg, needle)
			local index = offset and Chat.tokenAt(tokens, offset, word)
			if not index and linkIndex and tokens[linkIndex] and tokens[linkIndex].word == word then
				index = linkIndex
			end
			index = index or Chat.firstWord(tokens, word)
			if not index then
				return nil, "word not among the line's tokens"
			end
			local line = { hash = hash, body = body, tokens = tokens, rebuilt = true }
			if hash and not lines.map[hash] then
				lines.put(hash, line)
			end
			return line, index
		end
	end
	return nil, "link not in the last 40 messages"
end

-- Hooks the chat window: the filter per event and the hover callbacks. Records in selftest.chatHook what
-- took and, when something is missing, which link broke.
function Chat.hookChatFrames()
	if Chat.hooked then
		return ns.selftest.chatHook
	end
	Chat.hooked = true
	local hook = { filters = 0 }
	ns.selftest.chatHook = hook
	if not (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) then
		hook.error = "ChatFrameUtil.AddMessageEventFilter missing: no words linked in chat"
		return hook
	end
	for _, ev in ipairs(Chat.EVENTS) do
		ChatFrameUtil.AddMessageEventFilter(ev, Chat.chatFilter)
		hook.filters = hook.filters + 1
	end
	-- System lines too (the guild Message of the Day arrives this way): the filter links only lines with Han
	-- and leaves every other system message untouched.
	ChatFrameUtil.AddMessageEventFilter(Chat.SYSTEM_EVENT, Chat.chatFilter)
	hook.filters = hook.filters + 1
	if not (EventRegistry and EventRegistry.RegisterCallback) then
		hook.error = "EventRegistry missing: words linked but hover shows nothing"
		return hook
	end
	-- Blizzard passes the hovered link's FontString and the link's bounds inside it, measured from the
	-- string's BOTTOMLEFT (Blizzard_ChatFrameBase/Shared/ChatFrame.lua: OnHyperlinkEnter; verified in game).
	EventRegistry:RegisterCallback(
		"ChatFrame.OnHyperlinkEnter",
		function(_, chatFrame, link, text, region, left, bottom, width, height)
			if not Chat.tokenFromLink(link) or not ns.Card then
				return
			end
			ns.Card.enter(chatFrame, link, text, region, left, bottom, width, height)
		end,
		Chat
	)
	EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkLeave", function()
		if ns.Card then
			ns.Card.leave()
		end
	end, Chat)
	hook.hover = true
	return hook
end

-- Vocabulary log: every known word seen, with counts and who said it (SavedVariable, account-wide).
local Vocab = {}
ns.Vocab = Vocab

Vocab.DEFAULT_KNOWN_AFTER = 8
-- Bumped whenever a word's known state can have changed (a mark, a sighting that crosses the threshold,
-- a new threshold); the chat filter's cache keys on it.
Vocab.version = 0

local function thresholdSetting()
	return (ns.db and ns.db.ui and ns.db.ui.knownAfter) or Vocab.DEFAULT_KNOWN_AFTER
end

function Vocab.record(tokens, who)
	local v = ns.db.vocab
	local now = time()
	local threshold = thresholdSetting()
	for _, t in ipairs(tokens) do
		if t.han then
			local e = v[t.word]
			if not e then
				e = { n = 0, first = now, pinyin = t.pinyin }
				v[t.word] = e
			end
			local was = e.known or e.n >= threshold
			e.n = e.n + 1
			if not was and e.n >= threshold then
				Vocab.version = Vocab.version + 1
			end
			e.last = now
			e.by = who
			ns.selftest.counters.words = ns.selftest.counters.words + 1
		end
	end
end

-- A word is known when the user marked it (K while hovering) or it was seen knownAfter times.
function Vocab.isKnown(word, vocab, knownAfter)
	vocab = vocab or (ns.db and ns.db.vocab)
	local e = vocab and vocab[word]
	if not e then
		return false
	end
	-- An explicit mark wins either way: known = false keeps a frequently seen word "new".
	if e.known ~= nil then
		return e.known == true
	end
	return (e.n or 0) >= (knownAfter or thresholdSetting())
end

-- Toggles a flag ("known" or "star") on a word's vocabulary entry, creating the entry if needed.
function Vocab.toggle(word, flag)
	local v = ns.db.vocab
	local e = v[word]
	if not e then
		e = { n = 0, first = time() }
		v[word] = e
	end
	if flag == "known" then
		e.known = not Vocab.isKnown(word)
		Vocab.version = Vocab.version + 1
	else
		e[flag] = not e[flag] or nil
	end
	return e[flag] == true
end
