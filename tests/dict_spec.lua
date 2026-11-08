local mock = require("tests.wow_mock")

describe("Dict and Pinyin", function()
	local ns
	setup(function()
		mock.install()
		ns = mock.loadAddon(".", { skipCore = true })
		-- Deterministic data for the specs, independent of the generated files.
		ns.Data.pinyin = {
			["中"] = "zhōng",
			["国"] = "guó",
			["人"] = "rén",
			["你"] = "nǐ",
			["好"] = "hǎo",
			["副"] = "fù",
			["本"] = "běn",
		}
		ns.Data.dict = {
			["中国"] = { "zhōng guó", "China" },
			["中国人"] = { "zhōng guó rén", "Chinese person" },
			["你好"] = { "nǐ hǎo", "hello" },
			["副本"] = { "fù běn", "dungeon; instance" },
		}
		ns.Data.maxWordLen = 3
	end)

	it("reads single characters", function()
		assert.equal("zhōng", ns.Pinyin.char("中"))
		assert.is_nil(ns.Pinyin.char("龘"))
		assert.equal("nǐ hǎo ?", ns.Pinyin.string("你好龘"))
	end)

	it("prefers the longest dictionary match", function()
		local t = ns.Dict.segment("中国人")
		assert.equal(1, #t)
		assert.equal("中国人", t[1].word)
		assert.equal("zhōng guó rén", t[1].pinyin)
	end)

	it("falls back to single characters with their reading", function()
		local t = ns.Dict.segment("人中")
		assert.same({ "人", "中" }, { t[1].word, t[2].word })
		assert.is_false(t[1].inDict)
		assert.is_nil(t[1].known) -- renamed: known is the vocabulary's word, not the dictionary's
		assert.equal("rén", t[1].pinyin)
		assert.is_true(ns.Dict.segment("中国")[1].inDict)
	end)

	describe("with the game glossary", function()
		local saved
		before_each(function()
			saved = { ns.Data.game, ns.Data.gameMaxLen, ns.Data.pinyin["灰"], ns.Data.pinyin["谷"] }
			ns.Data.pinyin["灰"], ns.Data.pinyin["谷"] = "huī", "gǔ"
			ns.Data.game = {
				["灰谷"] = { "Ashenvale", "zone" }, -- not in CEDICT here
				["副本"] = { "instance", "slang" }, -- same length as CEDICT's word
				["中国"] = { "China (game)", "zone" },
				["国人"] = { "Guoren", "boss" }, -- would overlap 中国人 from the second character
				["副"] = { "off-spec", "slang" }, -- one character, shorter than CEDICT's 副本
			}
			ns.Data.gameMaxLen = 6
		end)
		after_each(function()
			ns.Data.game, ns.Data.gameMaxLen, ns.Data.pinyin["灰"], ns.Data.pinyin["谷"] =
				saved[1], saved[2], saved[3], saved[4]
		end)

		it("tags a game-only term with its English name and kind, reading per character", function()
			local t = ns.Dict.segment("灰谷")
			assert.equal(1, #t)
			assert.same({ en = "Ashenvale", kind = "zone" }, t[1].game)
			assert.equal("huī gǔ", t[1].pinyin)
			assert.is_false(t[1].inDict)
			assert.is_nil(t[1].gloss)
		end)

		it("wins over CEDICT at equal length and keeps CEDICT's reading and gloss", function()
			local t = ns.Dict.segment("副本")
			assert.equal(1, #t)
			assert.same({ en = "instance", kind = "slang" }, t[1].game)
			assert.equal("fù běn", t[1].pinyin)
			assert.equal("dungeon; instance", t[1].gloss)
			assert.is_true(t[1].inDict)
		end)

		it("loses to a longer CEDICT word", function()
			local t = ns.Dict.segment("中国人")
			assert.equal(1, #t)
			assert.equal("中国人", t[1].word)
			assert.is_nil(t[1].game)
			-- and a one-character term never splits a longer CEDICT word
			local f = ns.Dict.segment("副本")
			assert.equal("副本", f[1].word)
		end)

		it("matches a one-character term where CEDICT has no longer word", function()
			local t = ns.Dict.segment("副中")
			assert.equal("副", t[1].word)
			assert.same({ en = "off-spec", kind = "slang" }, t[1].game)
		end)

		it("ignores terms longer than gameMaxLen allows", function()
			ns.Data.gameMaxLen = 3 -- one character
			assert.equal(2, #ns.Dict.segment("灰谷"))
		end)
	end)

	it("ships Data/Game.lua with Ashenvale, and finds it in a guild line", function()
		local fresh = mock.loadAddon(".", { skipCore = true })
		assert.truthy(fresh.Data.gameMaxLen)
		assert.same({ "Ashenvale", "zone" }, fresh.Data.game["灰谷"])
		local found
		for _, t in ipairs(fresh.Dict.segment("我在灰谷被联盟猎人射爆了")) do
			if t.word == "灰谷" then
				found = t
			end
		end
		assert.truthy(found, "灰谷 not segmented as one word")
		assert.same({ en = "Ashenvale", kind = "zone" }, found.game)
	end)

	it("keeps non-Han runs as tokens and builds the pinyin line", function()
		local t = ns.Dict.segment("gg 你好 lfg 副本！")
		assert.equal("gg nǐ hǎo lfg fù běn ！", ns.Dict.pinyinLine(t))
		assert.is_false(t[1].han)
		assert.is_true(t[2].han)
	end)

	it("marks unknown characters with a question mark", function()
		local t = ns.Dict.segment("龘")
		assert.equal("?", t[1].pinyin)
		assert.is_false(t[1].inDict)
	end)
end)
