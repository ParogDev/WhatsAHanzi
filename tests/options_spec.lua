local mock = require("tests.wow_mock")

describe("Options", function()
	local ns
	before_each(function()
		mock.install()
		ns = mock.loadAddon(".")
	end)

	it("registers one setting per option and per channel, writing defaults into the SavedVariable", function()
		local cat = ns.Options.register()
		assert.truthy(cat)
		assert.equal(cat, _G.Settings.addonCategory)
		assert.equal(4 + #ns.Chat.EVENTS, ns.selftest.options.settings)
		assert.equal(1, ns.db.ui.cardScale)
		assert.equal(8, ns.db.ui.knownAfter)
		assert.is_true(ns.db.channels.CHAT_MSG_GUILD)
		assert.equal(cat, ns.Options.register()) -- once
	end)

	it("re-registers chat events when a channel is toggled", function()
		ns.frame = CreateFrame("Frame")
		ns.Options.register()
		_G.Settings.registered.WAH_CHAT_MSG_SAY:SetValue(false)
		assert.is_false(ns.db.channels.CHAT_MSG_SAY)
		assert.is_nil(ns.frame._events.CHAT_MSG_SAY)
		assert.is_true(ns.frame._events.CHAT_MSG_GUILD)
	end)

	it("opens the panel from /hanzi options", function()
		assert.is_true(ns.Options.open())
		assert.equal(ns.Options.category:GetID(), _G.Settings.opened)
	end)

	it("describes the companion's data, or its absence", function()
		assert.truthy(ns.Options.companionStatus():find("absent"))
		ns.Data.live = { generatedAt = "2026-11-07 21:00:00", model = "haiku", lines = { a = {}, b = {} } }
		local s = ns.Options.companionStatus()
		assert.truthy(s:find("2026-11-07 21:00:00", 1, true))
		assert.truthy(s:find("haiku"))
		assert.truthy(s:find("2 translated"))
	end)

	it("names the broken link when the Settings API is missing", function()
		_G.Settings = nil
		assert.is_nil(ns.Options.register())
		assert.truthy(ns.selftest.options.error:find("Settings API"))
		local ok, why = ns.Options.open()
		assert.is_false(ok)
		assert.truthy(why:find("Settings API"))
	end)
end)
