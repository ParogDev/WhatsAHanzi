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
	"CHAT_MSG_WHISPER",
	"CHAT_MSG_SAY",
	"CHAT_MSG_YELL",
	"CHAT_MSG_CHANNEL",
}

local function isSecret(v)
	return issecretvalue ~= nil and issecretvalue(v)
end

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

-- In the normal chat window: a message filter wraps each Chinese word in an addon hyperlink
-- (|Haddon:WhatsAHanzi:<word>|h<word>|h, no colour code, so the line keeps its chat colour), and hovering
-- one shows the gloss popup at the cursor. Escapes already in the line (item and player links, textures,
-- atlases, Battle.net names) are copied untouched. Blizzard skips filters for secret text (canaccessvalue
-- in ChatFrameFilters.lua); the guard here is the second line of defence.
Chat.LINK_PREFIX = "addon:WhatsAHanzi:"
local ESCAPES = { "|H.-|h.-|h", "|T.-|t", "|A.-|a", "|K.-|k" }

local function linkPlain(out, s)
	if s == "" then
		return
	end
	if not ns.Han.hasHan(s) then
		out[#out + 1] = s
		return
	end
	for _, t in ipairs(ns.Dict.segment(s)) do
		if t.han then
			out[#out + 1] = "|H" .. Chat.LINK_PREFIX .. t.word .. "|h" .. t.word .. "|h"
		else
			out[#out + 1] = t.word
		end
	end
end

-- Returns the line with every Han word linked, or nil when there is nothing to do (secret, no Han).
function Chat.linkify(text)
	if type(text) ~= "string" or isSecret(text) or not ns.Han.hasHan(text) then
		return nil
	end
	local out, pos = {}, 1
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
		linkPlain(out, text:sub(pos, s - 1))
		out[#out + 1] = text:sub(s, e)
		pos = e + 1
	end
	linkPlain(out, text:sub(pos))
	return table.concat(out)
end

-- The same line reaches the filter once per chat frame that shows it: keep the last result.
local lastIn, lastOut
function Chat.chatFilter(_, _, text, ...)
	if ns.db and ns.db.ui.inChat == false then
		return false
	end
	if isSecret(text) then
		return false
	end
	if text ~= lastIn then
		lastIn, lastOut = text, Chat.linkify(text)
		if lastOut then
			ns.selftest.counters.linked = (ns.selftest.counters.linked or 0) + 1
		end
	end
	if not lastOut then
		return false
	end
	return false, lastOut, ...
end

-- Word from one of our links, or nil for any other link.
function Chat.wordFromLink(link)
	if type(link) ~= "string" or link:sub(1, #Chat.LINK_PREFIX) ~= Chat.LINK_PREFIX then
		return nil
	end
	local word = link:sub(#Chat.LINK_PREFIX + 1)
	return word ~= "" and word or nil
end

-- Hooks the chat window: the filter per event and the hover callbacks. Records in selftest.chatHook what
-- took and, when something is missing, which link broke.
function Chat.hookChatFrames()
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
	if not (EventRegistry and EventRegistry.RegisterCallback) then
		hook.error = "EventRegistry missing: words linked but hover shows nothing"
		return hook
	end
	EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkEnter", function(_, _, link)
		local word = Chat.wordFromLink(link)
		if word and ns.UI then
			ns.UI.showGlossAtCursor(word)
		end
	end, Chat)
	EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkLeave", function()
		if ns.UI then
			ns.UI.hideGloss()
		end
	end, Chat)
	hook.hover = true
	return hook
end

-- Vocabulary log: every known word seen, with counts and who said it (SavedVariable, account-wide).
local Vocab = {}
ns.Vocab = Vocab

function Vocab.record(tokens, who)
	local v = ns.db.vocab
	local now = time()
	for _, t in ipairs(tokens) do
		if t.han then
			local e = v[t.word]
			if not e then
				e = { n = 0, first = now, pinyin = t.pinyin }
				v[t.word] = e
			end
			e.n = e.n + 1
			e.last = now
			e.by = who
			ns.selftest.counters.words = ns.selftest.counters.words + 1
		end
	end
end
