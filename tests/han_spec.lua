local mock = require("tests.wow_mock")

describe("Han", function()
	local ns
	setup(function()
		mock.install()
		ns = {}
		mock.load(".", "Han.lua", ns)
	end)

	it("iterates UTF-8 characters of mixed text", function()
		local out = {}
		for ch in ns.Han.chars("a你b好") do
			out[#out + 1] = ch
		end
		assert.same({ "a", "你", "b", "好" }, out)
	end)

	it("knows the code point of a three-byte character", function()
		assert.equal(0x4F60, ns.Han.codepoint("你"))
		assert.equal(0x41, ns.Han.codepoint("A"))
	end)

	it("classifies CJK ideographs and nothing else as Han", function()
		assert.is_true(ns.Han.isHan("你"))
		assert.is_true(ns.Han.isHan("㐀")) -- Extension A
		assert.is_false(ns.Han.isHan("a"))
		assert.is_false(ns.Han.isHan("，")) -- fullwidth comma is punctuation, not Han
		assert.is_false(ns.Han.isHan("あ")) -- hiragana
	end)

	it("detects and counts Han in a line", function()
		assert.is_true(ns.Han.hasHan("gg 你好"))
		assert.is_false(ns.Han.hasHan("gg wp"))
		assert.equal(2, ns.Han.countHan("gg 你好!"))
	end)

	it("splits a line into Han and non-Han runs", function()
		local runs = ns.Han.runs("快来 lfg 副本！")
		assert.same({
			{ text = "快来", han = true },
			{ text = " lfg ", han = false },
			{ text = "副本", han = true },
			{ text = "！", han = false },
		}, runs)
	end)
end)
