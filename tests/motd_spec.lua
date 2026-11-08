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
		assert.same({ nil, "motd absent or secret" }, { ns.Chat.relinkMOTD(f, nil) })
		assert.same({ nil, "chat frame has no TransformMessages" }, { ns.Chat.relinkMOTD({}, "今晚") })
	end)

	it("hooks DisplayGMOTD and relinks the line each frame already shows", function()
		local hooked
		_G.hooksecurefunc = function(tbl, name, fn)
			hooked = { tbl = tbl, name = name, fn = fn }
		end
		_G.ChatFrameUtil.DisplayGMOTD = function() end
		_G.C_GuildInfo = {
			GetMOTD = function()
				return "今晚开组"
			end,
		}
		_G.ChatFrame1 = chatFrame({ { "Guild Message of the Day: 今晚开组", 1 } })
		local st = ns.Chat.hookMOTD()
		assert.is_true(st.hooked)
		assert.equal(1, st.relinked)
		assert.equal("DisplayGMOTD", hooked.name)
		local f2 = chatFrame({ { "Guild Message of the Day: 明天休息", 1 } })
		hooked.fn(f2, "明天休息")
		assert.equal(2, st.relinked)
		assert.truthy(f2.lines[1][1]:find("|H", 1, true))
		_G.ChatFrame1 = nil
	end)
end)
