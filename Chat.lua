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
function Chat.process(event, text, sender, channel)
	local counters = ns.selftest.counters
	counters.lines = counters.lines + 1
	local who = shortName(sender)
	if Chat.recentAdd then
		Chat.recentAdd(event, text, sender, channel)
	end
	if ns.Strip then
		-- a strip failure must not cost the line its analysis
		local ok, err = pcall(ns.Strip.push, event, text, sender, channel)
		if not ok then
			ns.Strip.state.why = "Strip.push: " .. tostring(err)
		end
	end
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

-- The event's 9th payload value is channelBaseName ("General") for CHAT_MSG_CHANNEL.
function Chat.onEvent(_, event, text, sender, ...)
	local channel = event == "CHAT_MSG_CHANNEL" and select(7, ...) or nil
	local ok, err = pcall(Chat.process, event, text, sender, channel)
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
function Chat.chatFilter(frame, _, text, ...)
	if isSecret(text) then
		return false
	end
	Chat.recentNoteFrame(frame, text)
	if ns.db and ns.db.ui.inChat == false then
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

-- The MOTD never passes the message filters: the chat frame prints it itself (ChatFrameUtil.DisplayGMOTD ->
-- chatFrame:AddMessage, on GUILD_MOTD and once per frame at login). So the printed line is rewritten in the
-- frame's history afterwards (TransformMessages, the secure mixin's, safe from addon code). The body is
-- linked on its own, so its hash is ns.db.motd.hash, the key the companion translates it under.
-- Returns how many lines changed, or nil and why not.
function Chat.relinkMOTD(chatFrame, gmotd)
	if not (chatFrame and chatFrame.TransformMessages) then
		return nil, "chat frame has no TransformMessages"
	end
	local why = Chat.motdUnusable(gmotd)
	if why then
		return nil, why
	end
	if ns.db and ns.db.ui.inChat == false then
		return nil, "words in chat turned off"
	end
	local linked = Chat.linkify(gmotd)
	if not linked then
		return nil, "motd has no Han"
	end
	local template = GUILD_MOTD_TEMPLATE or "Guild Message of the Day: %s"
	local printed, replacement = template:format(gmotd), template:format(linked)
	-- A line already linked counts as present (third return), so a retry never prints the MOTD twice.
	local n, present = 0, 0
	chatFrame:TransformMessages(function(message)
		if type(message) ~= "string" or isSecret(message) then
			return false
		end
		if message == replacement then
			present = present + 1
		end
		return message == printed
	end, function(_, ...)
		n = n + 1
		return replacement, ...
	end)
	return n, nil, present + n
end

-- Why a MOTD value cannot be linked, or nil when it can. "Not loaded yet" is the normal state at
-- PLAYER_LOGIN after a /reload (guild data arrives later), not a fault.
function Chat.motdUnusable(gmotd)
	if isSecret(gmotd) then
		return "motd is a secret value"
	end
	if gmotd == nil or gmotd == "" then
		return "motd not loaded yet (empty)"
	end
	if type(gmotd) ~= "string" then
		return "motd is a " .. type(gmotd)
	end
	return nil
end

local motdState -- selftest.motdLink: { hooked, relinked, printed, why, tries }

local function chatFrames()
	local out = {}
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local f = _G["ChatFrame" .. i]
		if f then
			out[#out + 1] = f
		end
	end
	return out
end

-- Relinks the MOTD line in every chat frame. With print = true and no frame showing it (a /reload: the
-- client prints the MOTD at login only), adds one linked MOTD line to the frames that show guild MOTDs,
-- once per MOTD text. Returns the number of lines relinked or printed.
function Chat.relinkAllMOTD(gmotd, print)
	local st = motdState or {}
	if gmotd == nil and C_GuildInfo and C_GuildInfo.GetMOTD then
		gmotd = C_GuildInfo.GetMOTD()
	end
	local why = Chat.motdUnusable(gmotd)
	if why then
		st.why = why
		return 0
	end
	-- One reason for the whole pass: the first frame's refusal, nil when any frame could be searched.
	local n, shownAlready, searched, firstWhy = 0, 0, false, nil
	for _, f in ipairs(chatFrames()) do
		local got, whyNot, present = Chat.relinkMOTD(f, gmotd)
		n = n + (got or 0)
		shownAlready = shownAlready + (present or 0)
		searched = searched or got ~= nil
		firstWhy = firstWhy or whyNot
	end
	st.why = (not searched) and (firstWhy or "no chat frames") or nil
	st.relinked = (st.relinked or 0) + n
	if shownAlready > 0 then
		st.printedFor = gmotd -- a frame shows it linked: never print another copy of this MOTD
	end
	if shownAlready == 0 and print and st.printedFor ~= gmotd and searched then
		local linked = Chat.linkify(gmotd)
		local info = _G.ChatTypeInfo and _G.ChatTypeInfo.GUILD -- FrameXML table, read via _G for luacheck
		local template = GUILD_MOTD_TEMPLATE or "Guild Message of the Day: %s"
		local shown = 0
		for _, f in ipairs(chatFrames()) do
			if f.IsEventRegistered and f:IsEventRegistered("GUILD_MOTD") then
				f:AddMessage(template:format(linked), info and info.r, info and info.g, info and info.b)
				shown = shown + 1
			end
		end
		if shown == 0 and DEFAULT_CHAT_FRAME then
			DEFAULT_CHAT_FRAME:AddMessage(template:format(linked), info and info.r, info and info.g, info and info.b)
			shown = 1
		end
		st.printedFor = gmotd
		st.printed = (st.printed or 0) + shown
		n = n + shown
	end
	return n
end

-- Post-hooks DisplayGMOTD for MOTDs printed from now on, relinks what the frames show already, and retries
-- while the guild MOTD has not loaded (3, 10 and 30 s after login; the last try prints a linked line when no
-- frame shows one). The GUILD_MOTD event handler (Core) calls Chat.onMOTDEvent. Records selftest.motdLink.
function Chat.hookMOTD()
	motdState = { relinked = 0, tries = 0 }
	local st = motdState
	ns.selftest.motdLink = st
	if not (ChatFrameUtil and ChatFrameUtil.DisplayGMOTD and hooksecurefunc) then
		st.why = "ChatFrameUtil.DisplayGMOTD missing: MOTD not linked"
		return st
	end
	hooksecurefunc(ChatFrameUtil, "DisplayGMOTD", function(chatFrame, gmotd)
		local n, why = Chat.relinkMOTD(chatFrame, gmotd)
		st.relinked = st.relinked + (n or 0)
		st.why = why
	end)
	st.hooked = true
	Chat.relinkAllMOTD(nil, false)
	if C_Timer and C_Timer.After then
		for _, delay in ipairs({ 3, 10, 30 }) do
			C_Timer.After(delay, function()
				st.tries = st.tries + 1
				local gmotd = C_GuildInfo and C_GuildInfo.GetMOTD and C_GuildInfo.GetMOTD()
				if not Chat.motdUnusable(gmotd) then
					Chat.rememberMOTD(gmotd)
				end
				Chat.relinkAllMOTD(gmotd, delay == 30)
			end)
		end
	end
	return st
end

-- GUILD_MOTD (a new MOTD, or the login one): the chat frames print it in their own handler, which may run
-- after ours, so the relink waits a frame.
function Chat.onMOTDEvent(gmotd)
	Chat.rememberMOTD(gmotd)
	if motdState and C_Timer and C_Timer.After then
		C_Timer.After(0, function()
			-- The frames printed it in this same event: one frame later it is there to relink. When none
			-- shows it (no frame takes guild lines), print the linked copy once.
			Chat.relinkAllMOTD(gmotd, true)
		end)
	end
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
	-- System lines too: the filter links only lines with Han and leaves every other system message untouched.
	-- The guild Message of the Day is not one of them (Chat.hookMOTD).
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

-- Recent Chinese lines (WhatsAHanziDB.recent), oldest first: { e = event, ch = channel name (CHAT_MSG_CHANNEL),
-- s = sender, t = text, at = time(), f = chat frame id }. Two readers: the companion takes them from
-- SavedVariables (the client writes WoWChatLog.txt late, see docs/companion-rs.md), and PLAYER_LOGIN prints them
-- again after a /reload, which empties the chat window. Secret senders or texts are never stored.
Chat.RECENT_MAX = 200
Chat.RECENT_MAX_AGE = 6 * 3600
local recentState = { buffered = 0, added = 0, restored = 0, skippedSecret = 0 }
Chat.recentState = recentState
local lastRecent -- the entry added last, for the filter to tell which chat frame shows it
local filterSaw -- { t, f }: the filter ran before the event handler for this text

local function recentOn()
	return ns.db and ns.db.ui.recent ~= false
end

-- Drops entries older than RECENT_MAX_AGE (against `now`) and the oldest beyond RECENT_MAX. Returns the list.
function Chat.recentPrune(list, now)
	local keep = {}
	for _, e in ipairs(list) do
		if type(e) == "table" and type(e.at) == "number" and now - e.at <= Chat.RECENT_MAX_AGE then
			keep[#keep + 1] = e
		end
	end
	local drop = #keep - Chat.RECENT_MAX
	if drop > 0 then
		for _ = 1, drop do
			table.remove(keep, 1)
		end
	end
	return keep
end

-- Stores one Chinese chat line. Returns the entry, or nil and why not.
function Chat.recentAdd(event, text, sender, channel)
	if not recentOn() then
		return nil, "recent off"
	end
	if type(event) ~= "string" or event:sub(1, 9) ~= "CHAT_MSG_" then
		return nil, "not a chat event"
	end
	if isSecret(text) or isSecret(sender) or isSecret(channel) then
		recentState.skippedSecret = recentState.skippedSecret + 1
		return nil, "secret"
	end
	if type(text) ~= "string" or not ns.Han.hasHan(text) then
		return nil, "no Han"
	end
	local list = ns.db.recent
	if type(list) ~= "table" then
		list = {}
		ns.db.recent = list
	end
	local e = { e = event, s = sender, t = text, at = time() }
	if event == "CHAT_MSG_CHANNEL" and type(channel) == "string" and channel ~= "" then
		e.ch = channel
	end
	if filterSaw and filterSaw.t == text then
		e.f = filterSaw.f
	end
	filterSaw = nil
	list[#list + 1] = e
	if #list > Chat.RECENT_MAX then
		ns.db.recent = Chat.recentPrune(list, e.at)
	end
	lastRecent = e
	recentState.added = recentState.added + 1
	recentState.buffered = #ns.db.recent
	return e
end

-- The chat filter's half: which chat frame shows the line (the filter runs once per frame; the first one wins).
function Chat.recentNoteFrame(frame, text)
	local id = frame and frame.GetID and frame:GetID()
	if not id then
		return
	end
	if lastRecent and lastRecent.t == text then
		lastRecent.f = lastRecent.f or id
	elseif not (filterSaw and filterSaw.t == text) then
		filterSaw = { t = text, f = id }
	end
end

Chat.RECENT_LABELS = {
	CHAT_MSG_GUILD = "Guild",
	CHAT_MSG_OFFICER = "Officer",
	CHAT_MSG_PARTY = "Party",
	CHAT_MSG_PARTY_LEADER = "Party",
	CHAT_MSG_RAID = "Raid",
	CHAT_MSG_RAID_LEADER = "Raid",
	CHAT_MSG_INSTANCE_CHAT = "Instance",
	CHAT_MSG_INSTANCE_CHAT_LEADER = "Instance",
	CHAT_MSG_WHISPER = "From",
	CHAT_MSG_WHISPER_INFORM = "To",
	CHAT_MSG_EMOTE = "Emote",
	CHAT_MSG_SAY = "Say",
	CHAT_MSG_YELL = "Yell",
}
Chat.RESTORED_COLOR = { 0.6, 0.6, 0.6 }

-- The restored line as printed: dimmed, "restored" and the original time, then the text with its hover links.
function Chat.recentLine(e)
	local label = e.ch or Chat.RECENT_LABELS[e.e] or "Chat"
	local when = date("%H:%M", e.at)
	return ("|cff808080[restored %s] [%s] %s:|r %s"):format(
		when,
		label,
		shortName(e.s) or "?",
		Chat.linkify(e.t) or e.t
	)
end

-- PLAYER_LOGIN: print the lines kept from before this load into the frame each came from, once per load. Only
-- AddMessage: nothing is sent, and linkify does not count words toward "known". Returns the number printed.
function Chat.recentRestore()
	if Chat.recentRestored then
		return 0
	end
	Chat.recentRestored = true
	local list = Chat.recentPrune(type(ns.db.recent) == "table" and ns.db.recent or {}, time())
	ns.db.recent = list
	recentState.buffered = #list
	if not recentOn() then
		return 0
	end
	local c = Chat.RESTORED_COLOR
	for _, e in ipairs(list) do
		local frame = (e.f and _G["ChatFrame" .. e.f]) or _G.ChatFrame1 or DEFAULT_CHAT_FRAME
		if not isSecret(e.t) and type(e.t) == "string" then
			frame:AddMessage(Chat.recentLine(e), c[1], c[2], c[3])
			recentState.restored = recentState.restored + 1
		end
	end
	return recentState.restored
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
