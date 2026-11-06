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
		assert.is_false(t[1].known)
		assert.equal("rén", t[1].pinyin)
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
		assert.is_false(t[1].known)
	end)
end)
