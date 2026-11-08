local mock = require("tests.wow_mock")

describe("Chat window links", function()
	local ns
	local L = "|Haddon:WhatsAHanzi:"
	local NEW = "|cffb9e6ff"
	local function link(text, index, word)
		return L .. ns.Hash.fnv1a32(text) .. ":" .. index .. "|h" .. word .. "|h"
	end
	before_each(function()
		mock.install()
		ns = mock.loadAddon(".")
		ns.Data.pinyin = { ["你"] = "nǐ", ["好"] = "hǎo", ["怒"] = "nù", ["焰"] = "yàn" }
		ns.Data.dict = { ["你好"] = { "nǐ hǎo", "hello" }, ["怒焰"] = { "nù yàn", "Ragefire" } }
		ns.Data.maxWordLen = 2
		ns.Data.game = {}
	end)

	it("links each Chinese word with the line hash and token index, new words in the soft colour", function()
		assert.equal(NEW .. link("你好 gg", 1, "你好") .. "|r gg", ns.Chat.linkify("你好 gg"))
		assert.equal("lf " .. NEW .. link("lf 怒焰", 2, "怒焰") .. "|r", ns.Chat.linkify("lf 怒焰"))
	end)

	it("leaves known words in the line's own colour", function()
		ns.db.vocab["怒焰"] = { n = 2 }
		assert.is_false(ns.Vocab.isKnown("怒焰"))
		assert.equal(NEW .. link("怒焰", 1, "怒焰") .. "|r", ns.Chat.linkify("怒焰"))
		ns.db.vocab["你好"] = { n = 8 }
		ns.db.vocab["怒焰"] = { n = 1, known = true }
		assert.equal(link("你好", 1, "你好"), ns.Chat.linkify("你好"))
		assert.equal(link("怒焰", 1, "怒焰"), ns.Chat.linkify("怒焰"))
		ns.db.ui.knownAfter = 20
		assert.equal(NEW .. link("你好", 1, "你好") .. "|r", ns.Chat.linkify("你好"))
	end)

	it("caches the line's tokens under its hash", function()
		local out, line = ns.Chat.linkify("gg 你好 怒焰")
		assert.truthy(out)
		assert.equal(ns.Hash.fnv1a32("gg 你好 怒焰"), line.hash)
		assert.equal("gg 你好 怒焰", line.body)
		local words = {}
		for k, t in ipairs(line.tokens) do
			words[k] = t.word
		end
		assert.same({ "gg ", "你好", " ", "怒焰" }, words)
		assert.equal(line, ns.Chat.lines.get(line.hash))
		local hash, index = ns.Chat.tokenFromLink("addon:WhatsAHanzi:" .. line.hash .. ":4")
		assert.equal(line.hash, hash)
		assert.equal(4, index)
		assert.is_nil(ns.Chat.tokenFromLink("item:1234"))
		assert.is_nil(ns.Chat.tokenFromLink("addon:WhatsAHanzi:你好"))
	end)

	it("keeps the 200 most recently used lines", function()
		ns.Chat.LINES_MAX = 3
		ns.Chat.LINES_EVICT = 1
		ns.Chat.linkify("你好 1")
		ns.Chat.linkify("你好 2")
		ns.Chat.linkify("你好 3")
		ns.Chat.lines.get(ns.Hash.fnv1a32("你好 1")) -- used again: stays
		ns.Chat.linkify("你好 4")
		assert.is_nil(ns.Chat.lines.get(ns.Hash.fnv1a32("你好 2")))
		assert.truthy(ns.Chat.lines.get(ns.Hash.fnv1a32("你好 1")))
		assert.truthy(ns.Chat.lines.get(ns.Hash.fnv1a32("你好 4")))
		assert.equal(3, ns.Chat.lines.count)
	end)

	it("evicts the least recently used lines in one scan per batch", function()
		ns.Chat.LINES_MAX = 10
		ns.Chat.LINES_EVICT = 4
		for k = 1, 10 do
			ns.Chat.linkify("你好 " .. k)
		end
		ns.Chat.lines.get(ns.Hash.fnv1a32("你好 2")) -- used again: survives the batch
		assert.equal(0, ns.Chat.lines.scans)
		ns.Chat.linkify("你好 11") -- 11 > 10: one scan drops the 4 least recently used (1, 3, 4, 5)
		assert.equal(1, ns.Chat.lines.scans)
		assert.equal(7, ns.Chat.lines.count)
		for _, k in ipairs({ 1, 3, 4, 5 }) do
			assert.is_nil(ns.Chat.lines.map[ns.Hash.fnv1a32("你好 " .. k)], "line " .. k)
		end
		for _, k in ipairs({ 2, 6, 7, 8, 9, 10, 11 }) do
			assert.truthy(ns.Chat.lines.map[ns.Hash.fnv1a32("你好 " .. k)], "line " .. k)
		end
		for k = 12, 14 do -- back up to 10: no scan yet
			ns.Chat.linkify("你好 " .. k)
		end
		assert.equal(1, ns.Chat.lines.scans)
		assert.equal(10, ns.Chat.lines.count)
		ns.Chat.linkify("你好 15")
		assert.equal(2, ns.Chat.lines.scans)
		assert.equal(7, ns.Chat.lines.count)
	end)

	it("never evicts the line just added, even with a batch larger than the cache", function()
		ns.Chat.LINES_MAX = 2
		ns.Chat.LINES_EVICT = 50
		ns.Chat.linkify("你好 1")
		ns.Chat.linkify("你好 2")
		local _, newest = ns.Chat.linkify("你好 3")
		assert.equal(1, ns.Chat.lines.count)
		assert.equal(newest, ns.Chat.lines.get(newest.hash))
	end)

	it("leaves lines without Chinese, secrets and non-strings alone", function()
		assert.is_nil(ns.Chat.linkify("gg wp"))
		assert.is_nil(ns.Chat.linkify(nil))
		local secret = "你好"
		mock.secret[secret] = true
		assert.is_nil(ns.Chat.linkify(secret))
	end)

	it("copies existing links, textures and atlases untouched and keeps them as plain tokens", function()
		local item = "|cff0070dd|Hitem:1234::::::::60|h[你好剑]|h|r"
		local tex = "|TInterface\\Icons\\INV_Misc_Book_09:0|t"
		local text = item .. " 你好 " .. tex
		local out, line = ns.Chat.linkify(text)
		-- tokens: the colour code, the item link (as its text), "|r ", the word, " ", the texture
		assert.equal(item .. " " .. NEW .. link(text, 4, "你好") .. "|r " .. tex, out)
		assert.equal("[你好剑]", line.tokens[2].word)
		assert.is_true(line.tokens[2].escape)
		assert.equal("你好", line.tokens[4].word)
		assert.is_true(line.tokens[6].escape)
	end)

	it("filters chat events with the linked text and passes the other arguments through", function()
		ns.Chat.hookChatFrames()
		local f = mock.chatFilters.CHAT_MSG_GUILD
		assert.is_function(f)
		local discard, text, sender = f(nil, "CHAT_MSG_GUILD", "你好", "Bob-Realm")
		assert.is_false(discard)
		assert.equal(NEW .. link("你好", 1, "你好") .. "|r", text)
		assert.equal("Bob-Realm", sender)
		assert.equal(1, ns.selftest.counters.linked)
		-- the same line in a second chat frame: same result, counted once
		local _, again = f(nil, "CHAT_MSG_GUILD", "你好", "Bob-Realm")
		assert.equal(text, again)
		assert.equal(1, ns.selftest.counters.linked)
	end)

	it("recolours a repeated line after a word is marked known", function()
		ns.Chat.hookChatFrames()
		local f = mock.chatFilters.CHAT_MSG_GUILD
		local _, before = f(nil, "CHAT_MSG_GUILD", "你好", "Bob")
		assert.equal(NEW .. link("你好", 1, "你好") .. "|r", before)
		ns.Vocab.toggle("你好", "known")
		local _, after = f(nil, "CHAT_MSG_GUILD", "你好", "Bob")
		assert.equal(link("你好", 1, "你好"), after)
	end)

	it("returns only false for lines it does not change, secrets, or when turned off", function()
		ns.Chat.hookChatFrames()
		local f = mock.chatFilters.CHAT_MSG_SAY
		assert.same({ false }, { f(nil, "CHAT_MSG_SAY", "gg", "Bob") })
		local secret = "你好"
		mock.secret[secret] = true
		assert.same({ false }, { f(nil, "CHAT_MSG_SAY", secret, "Bob") })
		ns.db.ui.inChat = false
		assert.same({ false }, { f(nil, "CHAT_MSG_SAY", "怒焰", "Bob") })
	end)

	it("links Chinese system lines (the guild MOTD) and leaves other system lines alone", function()
		ns.Chat.hookChatFrames()
		local f = mock.chatFilters.CHAT_MSG_SYSTEM
		assert.is_function(f)
		local _, text = f(nil, "CHAT_MSG_SYSTEM", "Guild Message of the Day: 你好", 1)
		assert.equal(
			"Guild Message of the Day: " .. NEW .. link("Guild Message of the Day: 你好", 2, "你好") .. "|r",
			text
		)
		assert.same({ false }, { f(nil, "CHAT_MSG_SYSTEM", "You have joined the channel.", 1) })
	end)

	it("remembers a Chinese MOTD for the companion", function()
		assert.is_nil(ns.Chat.rememberMOTD("Welcome to the guild"))
		assert.is_nil(ns.db.motd)
		mock.motd = "欢迎 all"
		local rec = ns.Chat.rememberMOTD()
		assert.equal("欢迎 all", rec.text)
		assert.equal(ns.Hash.fnv1a32("欢迎 all"), rec.hash)
		assert.equal(rec, ns.db.motd)
		assert.is_number(rec.seen)
		local secret = "欢迎"
		mock.secret[secret] = true
		assert.is_nil(ns.Chat.rememberMOTD(secret))
		assert.equal(rec, ns.db.motd)
	end)

	it("records the hook in the selftest", function()
		local hook = ns.Chat.hookChatFrames()
		assert.equal(#ns.Chat.EVENTS + 1, hook.filters)
		assert.is_true(hook.hover)
		assert.is_nil(hook.error)
		assert.equal(hook, ns.selftest.chatHook)
		-- a second call registers nothing new
		mock.chatFilters = {}
		assert.equal(hook, ns.Chat.hookChatFrames())
		assert.same({}, mock.chatFilters)
	end)

	it("names the broken link when the chat filter API is missing", function()
		_G.ChatFrameUtil = nil
		local hook = ns.Chat.hookChatFrames()
		assert.equal(0, hook.filters)
		assert.truthy(hook.error:find("AddMessageEventFilter"))
	end)

	it("opens the card on hover of our links only, with the bounds, and closes it on leave", function()
		ns.Chat.hookChatFrames()
		local entered, left
		ns.Card.enter = function(...)
			entered = { ... }
		end
		ns.Card.leave = function()
			left = true
		end
		local region = {}
		-- the mock passes the owner itself; the arguments are Blizzard's (chatFrame, link, text, region, bounds)
		mock.callbacks["ChatFrame.OnHyperlinkEnter"](_G.ChatFrame1, "item:1234", "[x]", region, 1, 2, 3, 4)
		assert.is_nil(entered)
		local _, line = ns.Chat.linkify("怒焰")
		local lnk = "addon:WhatsAHanzi:" .. line.hash .. ":1"
		mock.callbacks["ChatFrame.OnHyperlinkEnter"](_G.ChatFrame1, lnk, "怒焰", region, 10, 20, 30, 40)
		assert.same({ _G.ChatFrame1, lnk, "怒焰", region, 10, 20, 30, 40 }, entered)
		mock.callbacks["ChatFrame.OnHyperlinkLeave"]()
		assert.is_true(left)
	end)

	it("rebuilds an uncached line from the chat frame's messages", function()
		local out, line = ns.Chat.linkify("你好 gg 怒焰")
		local lnk = "addon:WhatsAHanzi:" .. line.hash .. ":3"
		_G.ChatFrame1:AddMessage("[Guild] [Bob]: " .. out)
		_G.ChatFrame1:AddMessage("[Guild] [Ann]: later line")
		ns.Chat.lines.clear()
		local got, index = ns.Chat.lineForLink(_G.ChatFrame1, lnk, "怒焰")
		assert.equal("你好 gg 怒焰", got.body)
		assert.equal(3, index)
		assert.equal("怒焰", got.tokens[index].word)
		assert.is_true(got.rebuilt)
		assert.equal(got, ns.Chat.lines.get(line.hash))
		local none, why = ns.Chat.lineForLink(_G.ChatFrame1, "addon:WhatsAHanzi:00000000:1", "你好")
		assert.is_nil(none)
		assert.truthy(why:find("not in the last 40"))
	end)

	it("finds the hovered occurrence of a repeated word in a rebuilt line", function()
		-- An item link with a Chinese name sits between them: the rebuilt body segments its text as well.
		local out, line = ns.Chat.linkify("你好 |Hitem:1|h[你好]|h 你好 gg 你好")
		local function positions(tokens)
			local at = {}
			for k, t in ipairs(tokens) do
				if t.han and t.word == "你好" then
					at[#at + 1] = k
				end
			end
			return at
		end
		local cached = positions(line.tokens)
		assert.equal(3, #cached)
		local msg = "[Guild] [Bob]: " .. out
		_G.ChatFrame1:AddMessage(msg)
		local function hover(index)
			ns.Chat.lines.clear()
			return ns.Chat.lineForLink(_G.ChatFrame1, "addon:WhatsAHanzi:" .. line.hash .. ":" .. index, "你好")
		end
		-- Rebuilt body "你好 [你好] 你好 gg 你好": four 你好, the second from the item name. Each hovered link
		-- still lands on its own word (rebuilt 1st, 3rd, 4th), never on the first or the item's.
		local got = hover(cached[1])
		assert.equal("你好 [你好] 你好 gg 你好", got.body)
		local rebuilt = positions(got.tokens)
		assert.equal(4, #rebuilt)
		local want = { rebuilt[1], rebuilt[3], rebuilt[4] }
		for n = 1, 3 do
			local _, index = hover(cached[n])
			assert.equal(want[n], index, "occurrence " .. n)
		end
	end)

	it("measures the link's offset in the message body", function()
		local A = L .. "ab:"
		local msg = "[Guild] [Bob]: " .. A .. "1|h好|h |cffb9e6ff" .. A .. "2|h好|h|r"
		assert.equal(0, ns.Chat.bodyOffset(msg, A .. "1|h"))
		assert.equal(#"好 ", ns.Chat.bodyOffset(msg, A .. "2|h"))
		assert.is_nil(ns.Chat.bodyOffset(msg, A .. "9|h")) -- not in the message
		local tokens = { { word = "好", han = true }, { word = " ", han = false }, { word = "好", han = true } }
		assert.equal(3, ns.Chat.tokenAt(tokens, #"好 ", "好"))
		assert.is_nil(ns.Chat.tokenAt(tokens, 1, "好")) -- inside a token
		assert.is_nil(ns.Chat.tokenAt(tokens, #"好 ", "你")) -- another word there
		assert.equal(1, ns.Chat.firstWord(tokens, "好"))
	end)

	it("hides the pane once for players upgrading from version 1", function()
		local db = ns.initDB({ dbVersion = 1, ui = { hidden = false } })
		assert.is_true(db.ui.hidden)
		assert.is_true(db.ui.inChat)
		db.ui.hidden = false
		assert.is_false(ns.initDB(db).ui.hidden)
	end)
end)
