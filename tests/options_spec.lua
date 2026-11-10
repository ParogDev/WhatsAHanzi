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
		assert.equal(8 + #ns.Chat.EVENTS, ns.selftest.options.settings)
		assert.is_true(ns.db.ui.chatLog) -- the chat log is turned on at login unless the user says no
		assert.is_false(ns.db.ui.hoverKeys) -- K/S on the card is opt-in
		assert.is_true(ns.db.ui.speak) -- a held hover speaks the word
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

	it("refreshes every setting after /hanzi reset", function()
		ns.Options.register()
		ns.db.ui.cardScale = 1.3
		ns.db.ui.hoverKeys = true
		local version = ns.Vocab.version
		ns.frame._OnEvent(ns.frame, "PLAYER_LOGIN") -- registers the slash command
		_G.SlashCmdList.WHATSAHANZI("reset")
		assert.equal(1, ns.db.ui.cardScale)
		assert.is_false(ns.db.ui.hoverKeys)
		for _, s in ipairs(ns.Options.settings) do
			assert.equal(1, s.notified, s.variable)
		end
		assert.is_true(ns.Vocab.version > version)
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
