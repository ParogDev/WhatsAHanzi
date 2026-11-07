local mock = require("tests.wow_mock")

describe("Chat window links", function()
	local ns
	local L = "|Haddon:WhatsAHanzi:"
	before_each(function()
		mock.install()
		ns = mock.loadAddon(".")
		ns.Data.pinyin = { ["你"] = "nǐ", ["好"] = "hǎo", ["怒"] = "nù", ["焰"] = "yàn" }
		ns.Data.dict = { ["你好"] = { "nǐ hǎo", "hello" }, ["怒焰"] = { "nù yàn", "Ragefire" } }
		ns.Data.maxWordLen = 2
	end)

	it("links each Chinese word and keeps the rest of the line", function()
		assert.equal(L .. "你好|h你好|h gg", ns.Chat.linkify("你好 gg"))
		assert.equal("lf " .. L .. "怒焰|h怒焰|h", ns.Chat.linkify("lf 怒焰"))
	end)

	it("leaves lines without Chinese, secrets and non-strings alone", function()
		assert.is_nil(ns.Chat.linkify("gg wp"))
		assert.is_nil(ns.Chat.linkify(nil))
		local secret = "你好"
		mock.secret[secret] = true
		assert.is_nil(ns.Chat.linkify(secret))
	end)

	it("copies existing links, textures and atlases untouched", function()
		local item = "|cff0070dd|Hitem:1234::::::::60|h[你好剑]|h|r"
		local tex = "|TInterface\\Icons\\INV_Misc_Book_09:0|t"
		local out = ns.Chat.linkify(item .. " 你好 " .. tex)
		assert.equal(item .. " " .. L .. "你好|h你好|h " .. tex, out)
	end)

	it("filters chat events with the linked text and passes the other arguments through", function()
		ns.Chat.hookChatFrames()
		local f = mock.chatFilters.CHAT_MSG_GUILD
		assert.is_function(f)
		local discard, text, sender = f(nil, "CHAT_MSG_GUILD", "你好", "Bob-Realm")
		assert.is_false(discard)
		assert.equal(L .. "你好|h你好|h", text)
		assert.equal("Bob-Realm", sender)
		assert.equal(1, ns.selftest.counters.linked)
		-- the same line in a second chat frame: same result, counted once
		local _, again = f(nil, "CHAT_MSG_GUILD", "你好", "Bob-Realm")
		assert.equal(text, again)
		assert.equal(1, ns.selftest.counters.linked)
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

	it("shows the gloss on hover of our links only, and hides it on leave", function()
		ns.Chat.hookChatFrames()
		local shown, hidden
		ns.UI.showGlossAtCursor = function(w)
			shown = w
		end
		ns.UI.hideGloss = function()
			hidden = true
		end
		mock.callbacks["ChatFrame.OnHyperlinkEnter"](nil, "item:1234")
		assert.is_nil(shown)
		mock.callbacks["ChatFrame.OnHyperlinkEnter"](nil, "addon:WhatsAHanzi:怒焰")
		assert.equal("怒焰", shown)
		mock.callbacks["ChatFrame.OnHyperlinkLeave"](nil)
		assert.is_true(hidden)
	end)

	it("hides the pane once for players upgrading from version 1", function()
		local db = ns.initDB({ dbVersion = 1, ui = { hidden = false } })
		assert.is_true(db.ui.hidden)
		assert.is_true(db.ui.inChat)
		db.ui.hidden = false
		assert.is_false(ns.initDB(db).ui.hidden)
	end)
end)
