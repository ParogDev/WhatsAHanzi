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

	it("records the hook in the selftest", function()
		local hook = ns.Chat.hookChatFrames()
		assert.equal(#ns.Chat.EVENTS, hook.filters)
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
		mock.callbacks["ChatFrame.OnHyperlinkEnter"](nil, _G.ChatFrame1, "item:1234", "[x]", region, 1, 2, 3, 4)
		assert.is_nil(entered)
		local _, line = ns.Chat.linkify("怒焰")
		local lnk = "addon:WhatsAHanzi:" .. line.hash .. ":1"
		mock.callbacks["ChatFrame.OnHyperlinkEnter"](nil, _G.ChatFrame1, lnk, "怒焰", region, 10, 20, 30, 40)
		assert.same({ _G.ChatFrame1, lnk, "怒焰", region, 10, 20, 30, 40 }, entered)
		mock.callbacks["ChatFrame.OnHyperlinkLeave"](nil)
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

	it("hides the pane once for players upgrading from version 1", function()
		local db = ns.initDB({ dbVersion = 1, ui = { hidden = false } })
		assert.is_true(db.ui.hidden)
		assert.is_true(db.ui.inChat)
		db.ui.hidden = false
		assert.is_false(ns.initDB(db).ui.hidden)
	end)
end)
