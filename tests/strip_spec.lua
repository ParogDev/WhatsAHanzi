local mock = require("tests.wow_mock")

-- Made-up lines and speakers only.
describe("pixel strip", function()
	local ns, timers
	before_each(function()
		mock.install()
		timers = {}
		_G.C_Timer.After = function(_, fn)
			timers[#timers + 1] = fn
		end
		_G.GetPhysicalScreenSize = function()
			return 2560, 1440
		end
		ns = mock.loadAddon(".")
		ns.Data.pinyin = { ["你"] = "nǐ", ["好"] = "hǎo" }
		ns.Data.dict = {}
		ns.Data.maxWordLen = 2
		ns.Data.game = {}
		ns.UI.addAnalysed = function() end
		ns.UI.addRaw = function() end
		ns.initDB({})
	end)

	it("computes the standard CRC-32", function()
		local b = {}
		for i = 1, 9 do
			b[i] = ("123456789"):byte(i)
		end
		assert.equal(0xCBF43926, ns.Strip.crc32(b))
	end)

	it("lays a frame out as sync, header, 96 data bytes and the CRC", function()
		local nib = ns.Strip.encode(7, 1, 3, { 0xAB, 0x01 })
		assert.equal(ns.Strip.BLOCKS * 3, #nib)
		assert.same({ 15, 0, 15, 0, 15, 0 }, { unpack(nib, 1, 6) })
		assert.same({ 0, 7, 0, 1, 0, 3, 0, 2, 0 }, { unpack(nib, 7, 15) })
		assert.same({ 10, 11, 0, 1, 0, 0 }, { unpack(nib, 16, 21) })
		local crc = ns.Strip.crc32({ 7, 1, 3, 2, 0xAB, 0x01 })
		local tail = { unpack(nib, #nib - 8, #nib - 1) }
		local got = 0
		for _, n in ipairs(tail) do
			got = got * 16 + n
		end
		assert.equal(crc, got)
		for _, n in ipairs(nib) do
			assert.is_true(n >= 0 and n <= 15)
		end
	end)

	it("shows every level in every channel in the calibration frame", function()
		local nib = ns.Strip.calibration()
		for ch = 1, 3 do
			local seen = {}
			for i = 16 + ch - 1, 15 + ns.Strip.DATA_BYTES * 2, 3 do
				seen[nib[i]] = true
			end
			for v = 0, 15 do
				assert.is_true(seen[v], "channel " .. ch .. " level " .. v)
			end
		end
	end)

	it("splits a long line into chunks of one sequence and holds each", function()
		local long = ("你好"):rep(40) -- 240 bytes of text
		local n = ns.Strip.push("CHAT_MSG_GUILD", long, "Testa-Realm")
		assert.equal(3, n)
		assert.equal(1, ns.Strip.state.sent)
		assert.equal(2, ns.Strip.state.queued, "the first chunk is on screen")
		timers[1]()
		timers[2]()
		assert.equal(0, ns.Strip.state.queued)
		timers[3]()
		assert.equal(5, ns.Strip.state.frames, "calibration, three chunks, calibration again")
	end)

	it("sends the channel family and the sender with the text", function()
		assert.equal("guild\31Testa-Realm\31你好", ns.Strip.message("CHAT_MSG_GUILD", "你好", "Testa-Realm"))
		assert.equal("general\31Testb\31你好", ns.Strip.message("CHAT_MSG_CHANNEL", "你好", "Testb", "General"))
		assert.equal("whisper\31me\31你好", ns.Strip.message("CHAT_MSG_WHISPER_INFORM", "你好", "Testc"))
		assert.is_nil(ns.Strip.message("CHAT_MSG_EMOTE", "你好", "Testd"))
	end)

	it("skips secrets, lines without Han, and everything when off", function()
		mock.secret["你好"] = true
		assert.is_nil(ns.Strip.push("CHAT_MSG_GUILD", "你好", "Testa"))
		assert.equal(1, ns.Strip.state.skippedSecret)
		mock.secret["你好"] = nil
		assert.is_nil(ns.Strip.push("CHAT_MSG_GUILD", "hello", "Testa"))
		ns.db.ui.strip = false
		assert.is_nil(ns.Strip.push("CHAT_MSG_GUILD", "你好", "Testa"))
		assert.equal(0, ns.Strip.state.sent)
	end)

	it("scales so one unit is one physical pixel", function()
		ns.Strip.start()
		assert.same({ physW = 2560, physH = 1440, uiScale = 1, block = 3 }, ns.Strip.state.pixel)
	end)
end)
