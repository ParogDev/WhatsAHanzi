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
