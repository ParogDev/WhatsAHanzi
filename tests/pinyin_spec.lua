local mock = require("tests.wow_mock")

describe("Pinyin", function()
	local ns
	before_each(function()
		mock.install()
		ns = mock.loadAddon(".")
		ns.initDB({})
	end)

	it("converts tone marks to numbers per syllable", function()
		assert.equal("ni3 hao3", ns.Pinyin.numbered("nǐ hǎo"))
		assert.equal("ma1 ma2 ma3 ma4 ma", ns.Pinyin.numbered("mā má mǎ mà ma"))
		assert.equal("lü4 nü3", ns.Pinyin.numbered("lǜ nǚ"))
		assert.equal("zhong1 guo2", ns.Pinyin.numbered("zhōng guó"))
	end)

	it("leaves non-pinyin text alone", function()
		assert.equal("gg wp 123, ok?", ns.Pinyin.numbered("gg wp 123, ok?"))
		assert.equal("", ns.Pinyin.numbered(""))
	end)

	it("follows the tones setting", function()
		assert.equal("nǐ hǎo", ns.Pinyin.display("nǐ hǎo"))
		ns.db.ui.tones = "numbers"
		assert.equal("ni3 hao3", ns.Pinyin.display("nǐ hǎo"))
	end)
end)
