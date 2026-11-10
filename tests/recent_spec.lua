local mock = require("tests.wow_mock")

-- Made-up lines and speakers only.
describe("recent lines", function()
	local ns
	before_each(function()
		mock.install()
		ns = mock.loadAddon(".")
		ns.Data.pinyin = { ["你"] = "nǐ", ["好"] = "hǎo" }
		ns.Data.dict = { ["你好"] = { "nǐ hǎo", "hello" } }
		ns.Data.maxWordLen = 2
		ns.Data.game = {}
		ns.UI.addAnalysed = function() end
		ns.UI.addRaw = function() end
		ns.initDB({})
		_G.ChatFrame1.GetID = function()
			return 1
		end
	end)

	it("keeps Chinese chat lines with the frame the filter saw, and nothing else", function()
		ns.Chat.onEvent(nil, "CHAT_MSG_GUILD", "你好", "Testa-Realm")
		ns.Chat.chatFilter(_G.ChatFrame1, "CHAT_MSG_GUILD", "你好", "Testa-Realm")
		ns.Chat.onEvent(nil, "CHAT_MSG_GUILD", "hello", "Testa-Realm")
		ns.Chat.process("SLASH", "你好", "You")
		local r = ns.db.recent
		assert.equal(1, #r)
		assert.same("CHAT_MSG_GUILD", r[1].e)
		assert.equal("Testa-Realm", r[1].s)
		assert.equal("你好", r[1].t)
		assert.equal(1, r[1].f)
		assert.is_number(r[1].at)
	end)

	it("takes the frame when the filter runs before the event handler", function()
		ns.Chat.chatFilter(_G.ChatFrame1, "CHAT_MSG_SAY", "你好你好", "Testb")
		ns.Chat.onEvent(nil, "CHAT_MSG_SAY", "你好你好", "Testb")
		assert.equal(1, ns.db.recent[1].f)
	end)

	it("keeps the channel's base name", function()
		ns.Chat.onEvent(nil, "CHAT_MSG_CHANNEL", "你好", "Testc", "", "1. General", "", "", 1, 1, "General")
		assert.equal("General", ns.db.recent[1].ch)
	end)

	it("skips secret text and senders and counts them", function()
		local secret = "你好秘密"
		mock.secret[secret] = true
		ns.Chat.onEvent(nil, "CHAT_MSG_PARTY", secret, "Testd")
		mock.secret["Teste"] = true
		ns.Chat.onEvent(nil, "CHAT_MSG_PARTY", "你好", "Teste")
		assert.equal(0, #ns.db.recent)
		assert.equal(2, ns.Chat.recentState.skippedSecret)
	end)

	it("keeps at most RECENT_MAX lines and drops old ones", function()
		ns.Chat.RECENT_MAX = 3
		for i = 1, 5 do
			ns.Chat.onEvent(nil, "CHAT_MSG_GUILD", "你好" .. i, "Testf")
		end
		assert.equal(3, #ns.db.recent)
		assert.equal("你好5", ns.db.recent[3].t)
		local now = 10000000
		local kept = ns.Chat.recentPrune({ { at = now - 7 * 3600, t = "a" }, { at = now - 60, t = "b" }, "junk" }, now)
		assert.equal(1, #kept)
		assert.equal("b", kept[1].t)
	end)

	it("prints kept lines once per load, dimmed and linked, without counting words", function()
		ns.db.recent = {
			{ e = "CHAT_MSG_GUILD", s = "Testg-Realm", t = "你好", at = time() - 60, f = 1 },
			{ e = "CHAT_MSG_GUILD", s = "Testh", t = "你好", at = time() - 9 * 3600 },
		}
		assert.equal(1, ns.Chat.recentRestore())
		assert.equal(0, ns.Chat.recentRestore())
		local msgs = _G.ChatFrame1._messages
		assert.equal(1, #msgs)
		assert.truthy(msgs[1]:find("[restored ", 1, true))
		assert.truthy(msgs[1]:find("[Guild] Testg:", 1, true))
		assert.truthy(msgs[1]:find("|Haddon:WhatsAHanzi:", 1, true))
		assert.equal(1, #ns.db.recent, "the nine-hour-old line is dropped")
		assert.is_nil(ns.db.vocab["你好"])
		assert.equal(1, ns.Chat.recentState.restored)
	end)

	it("stores and restores nothing when the setting is off", function()
		ns.db.ui.recent = false
		ns.Chat.onEvent(nil, "CHAT_MSG_GUILD", "你好", "Testi")
		assert.equal(0, #ns.db.recent)
		ns.db.recent = { { e = "CHAT_MSG_GUILD", s = "Testj", t = "你好", at = time() } }
		assert.equal(0, ns.Chat.recentRestore())
	end)

	describe("flushing the chat log", function()
		local logging, toggles
		before_each(function()
			logging, toggles = true, {}
			_G.LoggingChat = function(on)
				if on ~= nil then
					toggles[#toggles + 1] = on
					logging = on
				end
				return logging
			end
		end)
		after_each(function()
			_G.LoggingChat = nil
		end)

		it("turns logging off and on again and records the try", function()
			assert.is_true(ns.flushChatLog("test"))
			assert.same({ false, true }, toggles)
			assert.equal(1, ns.selftest.chatLogging.flush.tries)
			assert.is_nil(ns.selftest.chatLogging.flush.why)
		end)

		it("leaves a chat log that is off alone and says why", function()
			logging = false
			assert.is_false(ns.flushChatLog("test"))
			assert.same({}, toggles)
			assert.equal("chat log off: nothing to flush", ns.selftest.chatLogging.flush.why)
		end)
	end)
end)
