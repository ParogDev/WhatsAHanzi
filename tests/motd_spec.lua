local mock = require("tests.wow_mock")

-- A chat frame with a history buffer and the ScrollingMessageFrame TransformMessages contract.
local function chatFrame(lines)
	local f = { lines = lines }
	function f:TransformMessages(predicate, transform)
		for i, l in ipairs(self.lines) do
			if predicate(l[1], l[2]) then
				self.lines[i] = { transform(l[1], l[2]) }
			end
		end
	end
	return f
end

describe("MOTD links", function()
	local ns
	before_each(function()
		mock.install()
		ns = mock.loadAddon(".")
		_G.GUILD_MOTD_TEMPLATE = "Guild Message of the Day: %s"
	end)

	it("rewrites the printed MOTD line with word links, hashed on the MOTD body", function()
		local f = chatFrame({ { "Guild Message of the Day: 今晚开组", 0.25 }, { "other line", 1 } })
		assert.equal(1, ns.Chat.relinkMOTD(f, "今晚开组"))
		local msg = f.lines[1][1]
		assert.equal("Guild Message of the Day: ", msg:sub(1, 26))
		assert.truthy(msg:find("|H", 1, true))
		assert.equal(0.25, f.lines[1][2]) -- colour and the rest pass through
		assert.equal("other line", f.lines[2][1])
		local hash = ns.Hash.fnv1a32("今晚开组")
		assert.truthy(msg:find(hash, 1, true))
		assert.truthy(ns.Chat.lines.get(hash))
	end)

	it("says why it left the line alone", function()
		local f = chatFrame({ { "Guild Message of the Day: raid at 8", 1 } })
		assert.same({ nil, "motd has no Han" }, { ns.Chat.relinkMOTD(f, "raid at 8") })
		assert.same({ nil, "motd not loaded yet (empty)" }, { ns.Chat.relinkMOTD(f, nil) })
		assert.same({ nil, "motd not loaded yet (empty)" }, { ns.Chat.relinkMOTD(f, "") })
		local secret = "今晚开组"
		mock.secret[secret] = true
		assert.same({ nil, "motd is a secret value" }, { ns.Chat.relinkMOTD(f, secret) })
		mock.secret[secret] = nil
		assert.same({ nil, "chat frame has no TransformMessages" }, { ns.Chat.relinkMOTD({}, "今晚") })
	end)

	-- C_GuildInfo.GetMOTD is HasRestrictions on Forever: an addon call logs ADDON_ACTION_BLOCKED. Every
	-- MOTD test runs with a GetMOTD that fails the test when called.
	local function forbidGetMOTD()
		_G.C_GuildInfo = {
			GetMOTD = function()
				error("C_GuildInfo.GetMOTD called (restricted on Forever)")
			end,
		}
	end

	it("reads the MOTD body back from a printed line", function()
		local tpl = "Guild Message of the Day: %s"
		assert.equal("今晚开组", ns.Chat.motdFromLine("Guild Message of the Day: 今晚开组", tpl))
		assert.is_nil(ns.Chat.motdFromLine("Guild Message of the Day: ", tpl))
		assert.is_nil(ns.Chat.motdFromLine("[Guild] someone: 今晚开组", tpl))
		assert.is_nil(ns.Chat.motdFromLine("Guild Message of the Day: |Hwah:1|h今晚|h", tpl))
		assert.is_nil(ns.Chat.motdFromLine(nil, tpl))
		assert.equal("x 今晚", ns.Chat.motdFromLine("<<x 今晚>>", "<<%s>>"))
		assert.is_nil(ns.Chat.motdFromLine("<<x 今晚", "<<%s>>"))
		local secret = "Guild Message of the Day: 今晚开组"
		mock.secret[secret] = true
		assert.is_nil(ns.Chat.motdFromLine(secret, tpl))
		mock.secret[secret] = nil
	end)

	it("hooks DisplayGMOTD and relinks the line each frame already shows, without GetMOTD", function()
		local hooked
		_G.hooksecurefunc = function(tbl, name, fn)
			hooked = { tbl = tbl, name = name, fn = fn }
		end
		_G.ChatFrameUtil.DisplayGMOTD = function() end
		forbidGetMOTD()
		_G.ChatFrame1 = chatFrame({ { "Guild Message of the Day: 今晚开组", 1 } })
		local st = ns.Chat.hookMOTD()
		assert.is_true(st.hooked)
		assert.equal(1, st.relinked)
		assert.equal("chat line", st.source)
		assert.equal("DisplayGMOTD", hooked.name)
		local f2 = chatFrame({ { "Guild Message of the Day: 明天休息", 1 } })
		hooked.fn(f2, "明天休息")
		assert.equal(2, st.relinked)
		assert.equal("DisplayGMOTD", st.source)
		assert.truthy(f2.lines[1][1]:find("|H", 1, true))
		assert.equal(ns.Hash.fnv1a32("明天休息"), ns.db.motd.hash)
		assert.is_nil(st.printed)
		_G.ChatFrame1 = nil
	end)

	it("after a /reload, the retries never call GetMOTD and print nothing they did not see", function()
		local timers = {}
		_G.C_Timer.After = function(d, fn)
			timers[#timers + 1] = { d = d, fn = fn }
		end
		_G.hooksecurefunc = function() end
		_G.ChatFrameUtil.DisplayGMOTD = function() end
		forbidGetMOTD()
		local f = chatFrame({ { "some other line", 1 } })
		function f:IsEventRegistered(ev)
			return ev == "GUILD_MOTD"
		end
		function f:AddMessage(msg, r)
			self.lines[#self.lines + 1] = { msg, r }
		end
		_G.ChatFrame1 = f
		local st = ns.Chat.hookMOTD()
		assert.truthy(st.why:find("not seen yet", 1, true))
		for _, t in ipairs(timers) do
			t.fn()
		end
		assert.equal(3, st.tries)
		assert.is_nil(st.printed)
		assert.equal(1, #f.lines)
		assert.truthy(st.why:find("GetMOTD is restricted", 1, true))
		_G.ChatFrame1 = nil
	end)

	it("a late retry relinks the line the client printed after login", function()
		local timers = {}
		_G.C_Timer.After = function(d, fn)
			timers[#timers + 1] = { d = d, fn = fn }
		end
		_G.hooksecurefunc = function() end
		_G.ChatFrameUtil.DisplayGMOTD = function() end
		forbidGetMOTD()
		local f = chatFrame({ { "some other line", 1 } })
		_G.ChatFrame1 = f
		local st = ns.Chat.hookMOTD()
		f.lines[2] = { "Guild Message of the Day: 今晚开组", 1 } -- printed by a path we did not hook
		timers[1].fn()
		assert.equal(1, st.relinked)
		assert.truthy(f.lines[2][1]:find("|H", 1, true))
		assert.equal(ns.Hash.fnv1a32("今晚开组"), ns.db.motd.hash)
		assert.is_nil(st.why)
		_G.ChatFrame1 = nil
	end)

	it("GUILD_MOTD prints one linked line when no frame shows it", function()
		local timers = {}
		_G.C_Timer.After = function(d, fn)
			timers[#timers + 1] = { d = d, fn = fn }
		end
		_G.hooksecurefunc = function() end
		_G.ChatFrameUtil.DisplayGMOTD = function() end
		forbidGetMOTD()
		local f = chatFrame({ { "some other line", 1 } })
		function f:IsEventRegistered(ev)
			return ev == "GUILD_MOTD"
		end
		function f:AddMessage(msg, r)
			self.lines[#self.lines + 1] = { msg, r }
		end
		_G.ChatFrame1 = f
		local st = ns.Chat.hookMOTD()
		ns.Chat.onMOTDEvent("今晚开组")
		timers[#timers].fn() -- the one-frame wait of the event
		assert.equal(1, st.printed)
		assert.equal(2, #f.lines)
		assert.truthy(f.lines[2][1]:find("|H", 1, true))
		assert.equal("GUILD_MOTD", st.source)
		for i = 1, 3 do
			timers[i].fn() -- the 3/10/30 s retries: still one copy
		end
		ns.Chat.onMOTDEvent("今晚开组")
		timers[#timers].fn()
		assert.equal(2, #f.lines)
		assert.is_nil(st.why)
		_G.ChatFrame1 = nil
	end)
end)
