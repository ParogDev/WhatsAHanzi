local mock = require("tests.wow_mock")

describe("Card", function()
	local ns, line, live
	before_each(function()
		mock.install()
		ns = mock.loadAddon(".")
		ns.Data.pinyin = {
			["我"] = "wǒ",
			["在"] = "zài",
			["灰"] = "huī",
			["谷"] = "gǔ",
			["被"] = "bèi",
			["联"] = "lián",
			["盟"] = "méng",
			["猎"] = "liè",
			["人"] = "rén",
			["射"] = "shè",
			["爆"] = "bào",
			["了"] = "le",
		}
		ns.Data.dict = {
			["灰谷"] = { "huī gǔ", "ash valley/Ashenvale (zone)/grey vale" },
			["联盟"] = { "lián méng", "alliance/union" },
			["猎人"] = { "liè rén", "hunter" },
			["我"] = { "wǒ", "I/me" },
		}
		ns.Data.maxWordLen = 2
		local _, cached = ns.Chat.linkify("我在灰谷被联盟猎人射爆了")
		line = cached
		live = {
			generatedAt = "2026-11-07 21:00:00",
			model = "haiku",
			lines = { [line.hash] = { t = "I got blasted by an Alliance hunter in Ashenvale", ctx = 3, m = "haiku" } },
			terms = { ["灰谷"] = { "Ashenvale", "zone" } },
			patterns = { ["被"] = "passive marker", ["了"] = "completed action" },
		}
	end)

	it("splits the word into characters with a reading and tone each", function()
		local d = ns.Card.build(line, 3, nil, {})
		assert.equal("灰谷", d.word)
		assert.same({ { ch = "灰", py = "huī", tone = 1 }, { ch = "谷", py = "gǔ", tone = 3 } }, d.chars)
		assert.equal(5, ns.Card.toneOf("le"))
	end)

	it("keeps the first two senses of the gloss", function()
		assert.equal("ash valley / Ashenvale (zone)", ns.Card.build(line, 3, nil, {}).gloss)
		assert.equal("hunter", ns.Card.build(line, 7, nil, {}).gloss)
		assert.is_nil(ns.Card.build(line, 2, nil, {}).gloss) -- 在: no entry
		assert.is_nil(ns.Card.shortGloss(nil))
	end)

	it("lights the hovered word in the sentence and counts known words", function()
		local vocab = { ["我"] = { n = 9 }, ["猎人"] = { n = 2, known = true } }
		local d = ns.Card.build(line, 3, live, vocab)
		assert.equal(8, #d.sentence)
		assert.is_true(d.sentence[3].lit)
		assert.is_false(d.sentence[1].lit)
		assert.is_true(d.sentence[1].known)
		assert.is_true(d.sentence[7].known)
		assert.is_false(d.sentence[3].known)
		assert.same({ known = 2, total = 8 }, d.meter)
		assert.is_false(d.known)
		assert.is_true(ns.Card.build(line, 7, live, vocab).known)
		local markup = ns.Card.sentenceMarkup(d.sentence)
		assert.truthy(markup:find("|cff5ccbf2灰谷|r", 1, true))
		assert.truthy(markup:find("|cffd0d0d0我|r", 1, true))
	end)

	it("adds the companion's translation, term tag and pattern notes when present", function()
		local d = ns.Card.build(line, 3, live, {})
		assert.same({ text = "I got blasted by an Alliance hunter in Ashenvale", model = "haiku", ctx = 3 }, d.translation)
		assert.same({ en = "Ashenvale", kind = "zone" }, d.term)
		assert.same({ { key = "被", note = "passive marker" }, { key = "了", note = "completed action" } }, d.patterns)
		-- hovering the pattern word itself lists it first
		assert.equal("了", ns.Card.build(line, 8, live, {}).patterns[1].key)
	end)

	it("works without the companion's file", function()
		local d = ns.Card.build(line, 3, nil, {})
		assert.is_nil(d.translation)
		assert.is_nil(d.term)
		assert.same({}, d.patterns)
		local e = ns.Card.build(line, 3, {}, {})
		assert.is_nil(e.translation)
		assert.is_nil(ns.Card.build(line, 99, nil, {}))
	end)

	it("colours pinyin by tone and follows the tones setting", function()
		assert.equal("|cff7fb4ffnǐ|r |cff7fb4ffhǎo|r", ns.Card.coloredPinyin("nǐ hǎo"))
		ns.db.ui.tones = "numbers"
		assert.equal("|cffff7b7bhui1|r |cff7fb4ffgu3|r", ns.Card.coloredPinyin("huī gǔ"))
	end)

	it("lays the card out over the hovered word and marks words from the keyboard", function()
		ns.Data.live = live
		local region = CreateFrame("Frame")
		ns.Card.enter(_G.ChatFrame1, "addon:WhatsAHanzi:" .. line.hash .. ":3", "灰谷", region, 10, 2, 30, 14)
		assert.is_nil(mock.lastError)
		assert.equal(1, ns.selftest.counters.cards)
		assert.same({ left = 10, bottom = 2, width = 30, height = 14, regionType = "Frame" }, ns.selftest.hoverBounds)
		local keys = _G["WhatsAHanziCardKeys"]
		for _, f in ipairs(mock.frames) do
			if f._name == "WhatsAHanziCardKeys" then
				keys = f
			end
		end
		assert.truthy(keys)
		assert.is_true(keys:IsShown())
		keys._OnKeyDown(keys, "K")
		assert.is_false(keys._propagate)
		assert.is_true(ns.db.vocab["灰谷"].known)
		keys._OnKeyDown(keys, "S")
		assert.is_true(ns.db.vocab["灰谷"].star)
		keys._OnKeyDown(keys, "ESCAPE")
		assert.is_true(keys._propagate)
		assert.equal(2, ns.selftest.counters.marks)
		ns.Card.leave()
		assert.is_false(keys:IsShown())
		assert.is_nil(ns.Card.ctx)
	end)

	it("falls back to the word alone when the line is not cached and not in the chat frame", function()
		ns.Chat.lines.clear()
		ns.Card.enter(_G.ChatFrame1, "addon:WhatsAHanzi:" .. line.hash .. ":3", "灰谷", nil)
		assert.is_nil(mock.lastError)
		assert.truthy(ns.selftest.cardLineMiss)
		assert.equal("灰谷", ns.Card.ctx.line.tokens[1].word)
	end)

	it("keeps the keyboard frame hidden in combat", function()
		mock.inCombat = true
		ns.Card.enterWord(_G.UIParent, "灰谷")
		assert.is_nil(mock.lastError)
		for _, f in ipairs(mock.frames) do
			if f._name == "WhatsAHanziCardKeys" then
				assert.is_false(f:IsShown())
			end
		end
	end)
end)
