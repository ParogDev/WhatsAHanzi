local mock = require("tests.wow_mock")

-- tests/fixtures/syllable_parity.json: reading -> space-joined bank names, written from the companion's
-- wah.audio.syllables. One flat object of string pairs, so a pattern reads it.
local function parityCases()
	local f = assert(io.open("tests/fixtures/syllable_parity.json", "rb"))
	local json = f:read("*a")
	f:close()
	local cases = {}
	for k, v in json:gmatch('"([^"]*)"%s*:%s*"([^"]*)"') do
		cases[#cases + 1] = { k, v }
	end
	return cases
end

local function fileExists(path)
	local f = io.open(path, "rb")
	if f then
		f:close()
		return true
	end
	return false
end

describe("Sound", function()
	local ns, played, stopped
	before_each(function()
		mock.install()
		_G.GetTime = nil -- a test that sets a clock does not leak it
		played, stopped = {}, {}
		_G.PlaySoundFile = function(path, channel)
			played[#played + 1] = { path = path, channel = channel }
			return true, #played
		end
		_G.StopSound = function(handle)
			stopped[#stopped + 1] = handle
		end
		_G.C_CVar = {
			GetCVarBool = function()
				return true
			end,
		}
		ns = mock.loadAddon(".")
	end)

	describe("names", function()
		it("maps readings to bank names exactly as the companion does", function()
			local cases = parityCases()
			assert.is_true(#cases >= 25)
			for _, c in ipairs(cases) do
				assert.equal(c[2], table.concat(ns.Sound.names(c[1]), " "), c[1])
			end
		end)

		it("writes ü as v and the neutral tone as 5", function()
			assert.same({ "lv4", "nv3", "ma5" }, ns.Sound.names("lǜ nǚ ma"))
		end)

		it("skips Latin words and digits that are not syllables", function()
			assert.same({}, ns.Sound.names("gg wp 666 DPS"))
			assert.same({}, ns.Sound.names(nil))
		end)

		-- Shape only, like the companion's regex: "zhv1" passes both (the bank simply has no such file).
		it("accepts initial plus final and rejects the rest", function()
			for _, s in ipairs({ "zhi1", "shuang3", "e4", "er2", "lve4", "nv3", "a5", "zhv1" }) do
				assert.is_true(ns.Sound.isSyllable(s), s)
			end
			for _, s in ipairs({ "ok5", "gg5", "ni", "ni6", "x1", "Ni3" }) do
				assert.is_false(ns.Sound.isSyllable(s), s)
			end
		end)

		it("has a bank file for every single-character reading in Data/Pinyin.lua", function()
			local missing = {}
			for _, py in pairs(ns.Data.pinyin) do
				for _, name in ipairs(ns.Sound.names(py)) do
					if not fileExists("Sounds/" .. name .. ".ogg") then
						missing[name] = true
					end
				end
			end
			assert.same({}, missing)
			assert.is_true(fileExists("Sounds/probe.ogg"))
		end)
	end)

	describe("probe", function()
		it("records willPlay and the handle, then stops the probe sound", function()
			local r = ns.Sound.probe()
			assert.is_true(r.willPlay)
			assert.equal(1, r.handle)
			assert.equal("ok", r.status)
			assert.equal("Interface\\AddOns\\WhatsAHanzi\\Sounds\\probe.ogg", played[1].path)
			assert.equal("Master", played[1].channel)
			assert.same({ 1 }, stopped)
			assert.equal(r, ns.selftest.soundProbe)
			assert.equal(r, ns.selftest.snapshot("test").soundProbe)
		end)

		it("counts a refusal as broken and the card says where sound plays", function()
			_G.PlaySoundFile = function()
				return false, nil
			end
			local r = ns.Sound.probe()
			assert.is_false(r.willPlay)
			assert.is_nil(r.handle)
			assert.equal("refused", r.status)
			local ok, why = ns.Sound.ready()
			assert.is_false(ok)
			assert.equal("sound plays in the companion", why)
			assert.is_nil(ns.Sound.speak("nǐ hǎo"))
		end)

		it("tells game sound off (not now) from a refusal, and probes again once sound is on", function()
			local refuse, on = true, false
			_G.PlaySoundFile = function()
				if refuse then
					return false, nil
				end
				return true, 7
			end
			_G.C_CVar.GetCVarBool = function()
				return on
			end
			assert.equal("sound off", ns.Sound.probe().status)
			assert.equal("game sound is off", select(2, ns.Sound.ready()))
			refuse, on = false, true
			assert.is_true(ns.Sound.ready())
			assert.equal("ok", ns.Sound.result.status)
		end)

		it("stops every playing syllable of the word on stop", function()
			local queued = {}
			_G.C_Timer.After = function(_, fn)
				queued[#queued + 1] = fn
			end
			ns.Sound.probe()
			stopped = {}
			ns.Sound.speak("nǐ hǎo")
			queued[1]()
			ns.Sound.stop()
			assert.equal(2, #stopped) -- both handles, not only the newest
		end)

		it("records a PlaySoundFile error as error", function()
			_G.PlaySoundFile = function()
				error("bad path")
			end
			local r = ns.Sound.probe()
			assert.equal("error", r.status)
			assert.truthy(r.error:find("bad path"))
		end)
	end)

	describe("speak", function()
		it("chains one file per syllable at each file's length", function()
			local delays = {}
			_G.C_Timer.After = function(d, fn)
				delays[#delays + 1] = d
				fn()
			end
			ns.Data.soundMs = { dui4 = 600, bu5 = 430 } -- qi3 has no length: it is last, so none is needed
			ns.Sound.probe()
			played = {}
			assert.same({ "dui4", "bu5", "qi3" }, ns.Sound.speak("duì bu qǐ"))
			assert.equal(3, #played)
			assert.equal("Interface\\AddOns\\WhatsAHanzi\\Sounds\\dui4.ogg", played[1].path)
			assert.equal("Interface\\AddOns\\WhatsAHanzi\\Sounds\\qi3.ogg", played[3].path)
			assert.equal(2, #delays)
			assert.is_true(math.abs(delays[1] - 0.57) < 1e-9)
			assert.is_true(math.abs(delays[2] - 0.97) < 1e-9)
			assert.equal(ns.Sound.GAP, ns.Sound.length("zzz1"))
		end)

		it("has a length in Data/SoundLengths.lua for every bank file", function()
			local missing = {}
			for _, py in pairs(ns.Data.pinyin) do
				for _, name in ipairs(ns.Sound.names(py)) do
					if not ns.Data.soundMs[name] then
						missing[name] = true
					end
				end
			end
			assert.same({}, missing)
		end)

		it("drops the queued syllables of a word when the next one starts", function()
			local queued = {}
			_G.C_Timer.After = function(_, fn)
				queued[#queued + 1] = fn
			end
			ns.Sound.probe()
			played = {}
			ns.Sound.speak("nǐ hǎo")
			ns.Sound.speak("mā")
			for _, fn in ipairs(queued) do
				fn()
			end
			assert.equal(2, #played) -- ni3, then ma1; hao3 was cancelled
			assert.truthy(played[2].path:find("ma1.ogg", 1, true))
		end)

		it("speaks a held hover only while its card is still open", function()
			local queued = {}
			_G.C_Timer.After = function(_, fn)
				queued[#queued + 1] = fn
			end
			ns.Sound.probe()
			played = {}
			local ctx = {}
			ns.Card.ctx = ctx
			ns.Sound.speakHover(ctx, "nǐ")
			ns.Card.ctx = nil -- the mouse moved on before the delay
			queued[1]()
			assert.equal(0, #played)
			ns.db.ui.speak = false
			ns.Card.ctx = ctx
			ns.Sound.speakHover(ctx, "nǐ")
			assert.equal(1, #queued)
		end)
	end)

	describe("word bank", function()
		local queued
		before_each(function()
			queued = {}
			_G.C_Timer.After = function(_, fn)
				queued[#queued + 1] = fn
			end
			ns.Sound.probe()
			played = {}
		end)

		it("plays one file for a word in the index and counts it as a word sound", function()
			ns.Data.wordSound = { ["你好"] = { "ni2hao3", 820, "ni3hao3" } }
			assert.same({ "words/ni2hao3" }, ns.Sound.speak("nǐ hǎo", "你好"))
			assert.equal(1, #played)
			assert.equal("Interface\\AddOns\\WhatsAHanzi\\Sounds\\words\\ni2hao3.ogg", played[1].path)
			assert.equal("Master", played[1].channel)
			assert.equal(0, #queued) -- no syllable chain behind it
			assert.equal(1, ns.selftest.counters.wordSounds)
			assert.is_nil(ns.selftest.counters.syllables)
			assert.equal(1, ns.selftest.counters.spoken)
		end)

		it("plays the syllables for a word not in the index", function()
			ns.Data.wordSound = { ["你好"] = { "ni2hao3", 820, "ni3hao3" } }
			assert.same({ "dui4", "bu5", "qi3" }, ns.Sound.speak("duì bu qǐ", "对不起"))
			for _, fn in ipairs(queued) do
				fn()
			end
			assert.equal(3, #played)
			assert.equal(3, ns.selftest.counters.syllables)
			assert.is_nil(ns.selftest.counters.wordSounds)
		end)

		it("treats a missing index as empty", function()
			ns.Data.wordSound = nil
			assert.is_nil(ns.Sound.wordEntry("你好", "nǐ hǎo"))
			assert.same({ "ni3", "hao3" }, ns.Sound.speak("nǐ hǎo", "你好"))
			assert.truthy(played[1].path:find("\\Sounds\\ni3.ogg", 1, true))
			assert.same({ loaded = false, entries = 0 }, ns.selftest.snapshot("test").soundIndex)
		end)

		it("says in the selftest whether the index loaded and how many rows it has", function()
			ns.Data.wordSound = { ["你好"] = { "ni2hao3", 820, "ni3hao3" }, ["一起"] = { "yi4qi3", 760 } }
			assert.same({ loaded = true, entries = 2, noReading = 1 }, ns.selftest.snapshot("test").soundIndex)
			ns.Data.wordSound["一起"][3] = "yi1qi3"
			assert.same({ loaded = true, entries = 2 }, ns.Sound.indexSummary())
		end)

		it("ignores secret words, malformed entries and entries without a reading", function()
			ns.Data.wordSound = {
				["你好"] = { "ni2hao3", 820, "ni3hao3" },
				["一起"] = { "../x", 1, "yi1qi3" },
				["好"] = "hao3",
				["朋友"] = { "peng2you5", 700 }, -- an index written before the reading check
			}
			_G.issecretvalue = function(v)
				return v == "你好"
			end
			assert.same({ nil, "secret" }, { ns.Sound.wordEntry("你好", "nǐ hǎo") })
			assert.same({ nil, "malformed entry" }, { ns.Sound.wordEntry("一起", "yì qǐ") })
			assert.same({ nil, "not in the index" }, { ns.Sound.wordEntry("好", "hǎo") })
			assert.same({ nil, "entry has no reading" }, { ns.Sound.wordEntry("朋友", "péng you") })
			assert.is_nil(ns.Sound.wordEntry(nil))
		end)

		-- 行 is háng (a row) or xíng (to walk): the file says one of them, and only that reading plays it.
		it("plays the file only when the card shows the reading it was made for", function()
			ns.Data.wordSound = { ["行"] = { "xing2", 500, "xing2" } }
			assert.same({ "hang2" }, ns.Sound.speak("háng", "行"))
			assert.truthy(played[1].path:find("\\Sounds\\hang2.ogg", 1, true))
			assert.equal(1, ns.selftest.counters.wordReadingDiffers)
			assert.is_nil(ns.selftest.counters.wordSounds)
			assert.same({ "words/xing2" }, ns.Sound.speak("xíng", "行"))
			assert.same({ "xing2", 500 }, { ns.Sound.wordEntry("行", "xing2") })
		end)

		it("falls back to the syllables when the client refuses the word file", function()
			ns.Data.wordSound = { ["你好"] = { "ni2hao3", 820, "ni3hao3" } }
			_G.PlaySoundFile = function(path, channel)
				played[#played + 1] = { path = path, channel = channel }
				return not path:find("words", 1, true), #played
			end
			assert.same({ "ni3", "hao3" }, ns.Sound.speak("nǐ hǎo", "你好"))
			assert.equal("words/ni2hao3", ns.selftest.soundMiss.name)
			assert.equal(1, ns.selftest.counters.syllables)
			assert.equal(1, ns.selftest.counters.wordMiss)
		end)

		it("keeps the word-file miss when a syllable miss follows", function()
			ns.Data.wordSound = { ["你好"] = { "ni2hao3", 820, "ni3hao3" } }
			_G.PlaySoundFile = function()
				return false, nil
			end
			ns.Sound.speak("nǐ hǎo", "你好")
			assert.equal("ni3", ns.selftest.soundMiss.name) -- the syllable fallback missed too
			assert.equal(1, ns.selftest.counters.wordMiss)
			local snap = ns.selftest.snapshot("test")
			assert.equal("words/ni2hao3", snap.wordMiss.name)
			assert.equal(1, snap.counters.wordMiss)
		end)

		it("chains a word file by its ms and drops its handle once it has ended", function()
			local t, delays = 0, {}
			_G.GetTime = function()
				return t
			end
			_G.C_Timer.After = function(d, fn)
				delays[#delays + 1] = d
				queued[#queued + 1] = fn
			end
			ns.Data.wordSound = { ["你好"] = { "ni2hao3", 820, "ni3hao3" } }
			local names, length = ns.Sound.speakParts({
				{ reading = "nǐ hǎo", word = "你好" },
				{ reading = "ma", word = "吗" },
			})
			assert.same({ "words/ni2hao3", "ma5" }, names)
			assert.is_true(math.abs(delays[1] - 0.79) < 1e-9) -- 820 ms less the overlap
			assert.is_true(length > 0.79)
			assert.equal(1, ns.Sound.playing())
			t = 0.9 -- the word file has ended
			assert.equal(0, ns.Sound.playing())
			queued[1]()
			assert.equal(1, ns.Sound.playing())
			stopped = {}
			ns.Sound.stop()
			assert.same({ 2 }, stopped) -- only ma5's handle: the ended word file was dropped
		end)

		it("/hanzi speak segments the text as chat is and speaks each Han word in turn", function()
			local parts = ns.speakParts("你好abc朋友!")
			assert.equal(2, #parts)
			assert.same({ reading = "nǐ hǎo", word = "你好" }, parts[1])
			assert.equal("朋友", parts[2].word)
			local key = table.concat(ns.Sound.names(parts[2].reading))
			ns.Data.wordSound = { ["朋友"] = { "peng2you5", 700, key } }
			assert.same({ "ni3", "hao3", "words/peng2you5" }, ns.Sound.speakParts(parts))
			for _, fn in ipairs(queued) do
				fn()
			end
			assert.equal(3, #played)
			assert.truthy(played[3].path:find("words\\peng2you5.ogg", 1, true))
			assert.same({}, ns.speakParts("gg wp 123"))
			assert.same({ nil, "no syllables in " }, { ns.Sound.speakParts({}) })
		end)

		it("passes the hovered word through a held hover", function()
			ns.Data.wordSound = { ["你好"] = { "ni2hao3", 820, "ni3hao3" } }
			local ctx = {}
			ns.Card.ctx = ctx
			ns.Sound.speakHover(ctx, "nǐ hǎo", "你好")
			queued[1]()
			assert.equal(1, #played)
			assert.truthy(played[1].path:find("words\\ni2hao3.ogg", 1, true))
		end)
	end)

	describe("card", function()
		it("reads the ruby row and puts the kind icon before a glossary term", function()
			assert.equal("nǐ hǎo", ns.Card.reading({ chars = { { py = "nǐ" }, { py = "hǎo" } } }))
			assert.equal("|A:poi-town:14:14|a ", ns.Card.kindIcon("zone"))
			assert.equal("", ns.Card.kindIcon("unknown"))
			assert.equal("", ns.Card.kindIcon(nil))
		end)
	end)
end)
