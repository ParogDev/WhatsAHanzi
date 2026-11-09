local mock = require("tests.wow_mock")

describe("Core and Chat", function()
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
	end)

	it("fills defaults into an empty SavedVariable and keeps existing values", function()
		local db = ns.initDB({ ui = { hidden = true } })
		assert.is_true(db.ui.hidden)
		assert.same({}, db.vocab)
		assert.equal(3, db.dbVersion)
		assert.equal(8, db.ui.knownAfter)
		assert.equal(1, db.ui.cardScale)
	end)

	it("migrates a version 2 database to the card settings", function()
		local db = ns.initDB({ dbVersion = 2, ui = { hidden = true, tones = "numbers" } })
		assert.equal(3, db.dbVersion)
		assert.equal("numbers", db.ui.tones)
		assert.equal(8, db.ui.knownAfter)
		assert.equal(1, db.ui.cardScale)
	end)

	it("summarises the companion's file in the selftest", function()
		assert.is_nil(ns.selftest.liveSummary())
		ns.Data.live = { generatedAt = "2026-11-07 21:00:00", model = "haiku", lines = { a = {}, b = {}, c = {} } }
		assert.same({ generatedAt = "2026-11-07 21:00:00", model = "haiku", lines = 3 }, ns.selftest.liveSummary())
	end)

	it("ignores lines without Chinese", function()
		assert.is_nil(ns.Chat.process("CHAT_MSG_GUILD", "gg wp", "Bob-Realm"))
		assert.equal(1, ns.selftest.counters.lines)
		assert.equal(0, ns.selftest.counters.chinese)
	end)

	it("analyses a Chinese line, logs vocabulary and remembers it for the selftest", function()
		local rec = ns.Chat.process("CHAT_MSG_GUILD", "你好 gg", "Bob-Realm")
		assert.equal("Bob", rec.sender)
		assert.equal("nǐ hǎo gg", rec.pinyin)
		assert.equal(1, ns.db.vocab["你好"].n)
		assert.equal("Bob", ns.db.vocab["你好"].by)
		assert.equal("你好 gg", ns.selftest.lastLines[1].text)
	end)

	it("shows a secret line raw and never inspects it", function()
		local secret = "你好"
		mock.secret[secret] = true
		local rec = ns.Chat.process("CHAT_MSG_GUILD", secret, "Bob")
		assert.is_true(rec.secret)
		assert.equal(1, ns.selftest.counters.secret)
		assert.equal(0, ns.selftest.counters.chinese)
		assert.same({}, ns.selftest.lastLines)
	end)

	it("routes a handler error to the error handler and records it", function()
		ns.Dict.segment = function()
			error("boom")
		end
		ns.Chat.onEvent(nil, "CHAT_MSG_GUILD", "你好", "Bob")
		assert.truthy(ns.selftest.lastError:find("boom"))
		assert.truthy(mock.lastError)
	end)

	it("persists a valid font size and rejects an invalid one", function()
		assert.is_true(ns.UI.setFontSize("30"))
		assert.equal(30, ns.db.ui.fontSize)
		assert.is_false(ns.UI.setFontSize("4"))
		assert.is_false(ns.UI.setFontSize("big"))
		assert.equal(30, ns.db.ui.fontSize)
	end)

	it("writes a selftest snapshot with version and counters", function()
		ns.Font.detect()
		local s = ns.selftest.snapshot("login")
		assert.equal("test", s.version)
		assert.equal(16001, s.interface)
		assert.equal(18, s.project)
		assert.equal(1, s.dictWords)
		assert.is_table(s.fontProbe.tried)
		assert.equal(0, s.counters.cards)
		assert.is_nil(s.live)
		assert.equal(s, ns.db.selftest)
		-- the mock's ChatFrame1 has no GetRect: the snapshot names the broken link and stores no rect
		assert.truthy(s.ui.chatRect.why)
		assert.is_nil(ns.db.ui.chatRect)
	end)

	it("puts ChatFrame1's rect in the snapshot and in SavedVariables", function()
		local chat = _G.ChatFrame1 -- a fresh mock frame per test (mock.install)
		chat.GetRect = function()
			return 20, 40, 430, 120
		end
		_G.GetPhysicalScreenSize = function()
			return 1920, 1080
		end
		local s = ns.selftest.snapshot("logout")
		local want = { left = 20, bottom = 40, width = 430, height = 120, scale = 1, screenW = 1920, screenH = 1080 }
		assert.same(want, s.ui.chatRect)
		assert.same(want, ns.db.ui.chatRect)
		chat.GetRect = nil
		_G.GetPhysicalScreenSize = nil
	end)

	it("/hanzi fake prints invented lines with links and leaves vocabulary alone", function()
		ns.frame._OnEvent(ns.frame, "PLAYER_LOGIN") -- registers the slash command
		local chat = _G.ChatFrame1
		local before = #chat._messages
		local chinese = ns.selftest.counters.chinese
		_G.SlashCmdList.WHATSAHANZI("fake yell")
		assert.equal(before + 3, #chat._messages)
		assert.equal(3, ns.selftest.counters.fake)
		assert.equal(chinese, ns.selftest.counters.chinese)
		_G.SlashCmdList.WHATSAHANZI("fake nope")
		local said = _G.DEFAULT_CHAT_FRAME._messages
		assert.truthy(said[#said]:find("banter | lfg | yell", 1, true))
	end)
end)
