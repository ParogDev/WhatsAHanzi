local mock = require("tests.wow_mock")

describe("Core and Chat", function()
	local ns
	before_each(function()
		mock.install()
		ns = mock.loadAddon(".")
		ns.Data.pinyin = { ["你"] = "nǐ", ["好"] = "hǎo" }
		ns.Data.dict = { ["你好"] = { "nǐ hǎo", "hello" } }
		ns.Data.maxWordLen = 2
		ns.UI.addAnalysed = function() end
		ns.UI.addRaw = function() end
	end)

	it("fills defaults into an empty SavedVariable and keeps existing values", function()
		local db = ns.initDB({ ui = { hidden = true } })
		assert.is_true(db.ui.hidden)
		assert.same({}, db.vocab)
		assert.equal(2, db.dbVersion)
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
		assert.equal(s, ns.db.selftest)
	end)
end)
