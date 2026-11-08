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
		ns.Data.game = {} -- the shipped glossary would tag 联盟, 猎人...; the game-term spec sets its own
		local _, cached = ns.Chat.linkify("我在灰谷被联盟猎人射爆了")
		line = cached
		live = {
			generatedAt = "2026-11-07 21:00:00",
			model = "haiku",
			lines = {
				[line.hash] = { t = "I got blasted by an Alliance hunter in Ashenvale", ctx = 3, m = "haiku" },
			},
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
		assert.equal("hunter", ns.Card.build(line, 6, nil, {}).gloss)
		assert.is_nil(ns.Card.build(line, 2, nil, {}).gloss) -- 在: no entry
		assert.is_nil(ns.Card.shortGloss(nil))
	end)

	it("lights the hovered word in the sentence and counts known words", function()
		local vocab = { ["我"] = { n = 9 }, ["猎人"] = { n = 2, known = true } }
		-- 我 | 在 | 灰谷 | 被 | 联盟 | 猎人 | 射 | 爆 | 了
		local d = ns.Card.build(line, 3, live, vocab)
		assert.equal(9, #d.sentence)
		assert.is_true(d.sentence[3].lit)
		assert.is_false(d.sentence[1].lit)
		assert.is_true(d.sentence[1].known)
		assert.is_true(d.sentence[6].known)
		assert.is_false(d.sentence[3].known)
		assert.same({ known = 2, total = 9 }, d.meter)
		assert.is_false(d.known)
		assert.is_true(ns.Card.build(line, 6, live, vocab).known)
		local markup = ns.Card.sentenceMarkup(d.sentence)
		assert.truthy(markup:find("|cff5ccbf2灰谷|r", 1, true))
		assert.truthy(markup:find("|cffd0d0d0我|r", 1, true))
	end)

	it("adds the companion's translation, term tag and pattern notes when present", function()
		local d = ns.Card.build(line, 3, live, {})
		assert.same(
			{ text = "I got blasted by an Alliance hunter in Ashenvale", model = "haiku", ctx = 3 },
			d.translation
		)
		assert.same({ en = "Ashenvale", kind = "zone" }, d.term)
		assert.same({
			{ key = "被", note = "passive marker" },
			{ key = "了", note = "completed action" },
		}, d.patterns)
		-- hovering the pattern word itself lists it first
		assert.equal("了", ns.Card.build(line, 9, live, {}).patterns[1].key)
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

	local function keysFrame()
		for _, f in ipairs(mock.frames) do
			if f._name == "WhatsAHanziCardKeys" then
				return f
			end
		end
	end

	it("never writes text into a FontString without a font (the client raises 'Font not set')", function()
		assert.has_error(function()
			CreateFrame("Frame"):CreateFontString(nil, "OVERLAY"):SetText("x")
		end)
		ns.Card.enter(_G.ChatFrame1, "addon:WhatsAHanzi:" .. line.hash .. ":3", "灰谷", nil, 10, 2, 30, 14)
		assert.is_nil(ns.selftest.lastError)
		assert.is_nil(mock.lastError)
	end)

	it("takes no keys while the K/S option is off (the default)", function()
		assert.is_false(ns.db.ui.hoverKeys)
		assert.is_false(ns.Card.keysEnabled())
		local link = "addon:WhatsAHanzi:" .. line.hash .. ":3"
		ns.Card.enter(_G.ChatFrame1, link, "灰谷", CreateFrame("Frame"), 10, 2, 30, 14)
		assert.is_nil(mock.lastError)
		assert.equal(1, ns.selftest.counters.cards)
		local keys = keysFrame()
		assert.is_true(keys == nil or not keys:IsShown())
	end)

	it("shows the game term from Data/Game.lua without the companion", function()
		ns.Data.game = { ["灰谷"] = { "Ashenvale", "zone" } }
		ns.Data.gameMaxLen = 6
		local _, l = ns.Chat.linkify("我在灰谷被联盟猎人射爆了")
		local d = ns.Card.build(l, 3, nil, {})
		assert.same({ en = "Ashenvale", kind = "zone" }, d.term)
		assert.equal("ash valley / Ashenvale (zone)", d.gloss) -- CEDICT's gloss stays as the second row
		live.terms["灰谷"] = { "Ashenvale Forest", "zone" }
		assert.equal("Ashenvale Forest", ns.Card.build(l, 3, live, {}).term.en) -- the companion's term wins
	end)

	it("lays the card out over the hovered word and marks words from the keyboard", function()
		ns.Data.live = live
		ns.db.ui.hoverKeys = true
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
		mock.modifier = true
		keys._OnKeyDown(keys, "S") -- Shift+S is movement, not ours
		assert.is_true(keys._propagate)
		mock.modifier = false
		assert.equal(2, ns.selftest.counters.marks)
		-- K on a word known only by count marks it new again
		ns.db.vocab["灰谷"] = { n = 20 }
		assert.is_true(ns.Vocab.isKnown("灰谷"))
		keys._OnKeyDown(keys, "K")
		assert.is_false(ns.Vocab.isKnown("灰谷"))
		assert.is_false(ns.db.vocab["灰谷"].known)
		ns.Card.leave()
		assert.is_false(keys:IsShown())
		assert.is_nil(ns.Card.ctx)
	end)

	it("escapes bars in companion text and strips colour codes from the sentence", function()
		live.lines[line.hash].t = "a |cffff0000red|r bar | here"
		local d = ns.Card.build(line, 3, live, {})
		assert.equal("a |cffff0000red|r bar | here", d.translation.text)
		local markup = ns.Card.sentenceMarkup({
			{ word = "|cff00ff00gg|r ", han = false },
			{ word = "你", han = true, lit = true },
		})
		assert.equal("|cff8a8a8agg |r|cff5ccbf2你|r", markup)
	end)

	it("ignores a cached line whose token is not the hovered word", function()
		ns.Chat.lines.put(line.hash, { hash = line.hash, body = "x", tokens = { { word = "猎人", han = true } } })
		ns.Card.enter(_G.ChatFrame1, "addon:WhatsAHanzi:" .. line.hash .. ":1", "灰谷", nil)
		assert.is_nil(mock.lastError)
		assert.equal("灰谷", ns.Card.ctx.line.tokens[ns.Card.ctx.index].word)
	end)

	it("takes the hover text as Blizzard gives it: the whole escape sequence", function()
		local lnk = "addon:WhatsAHanzi:" .. line.hash .. ":3"
		ns.Card.enter(_G.ChatFrame1, lnk, "|cffb9e6ff|H" .. lnk .. "|h灰谷|h|r", nil)
		assert.is_nil(mock.lastError)
		assert.is_nil(ns.selftest.cardLineMiss)
		assert.equal(line, ns.Card.ctx.line)
		assert.equal(3, ns.Card.ctx.index)
	end)

	it("keeps the original body and segmentation under the hash, not the linked text", function()
		local original = "我重上下游戏"
		local out, cached = ns.Chat.linkify(original)
		assert.truthy(out:find("|H", 1, true))
		assert.equal(original, cached.body)
		assert.equal(#ns.Dict.segment(original), #cached.tokens)
		local d = ns.Card.build(cached, 2, nil, {})
		assert.equal(#cached.tokens, #d.sentence)
		assert.is_nil(ns.Card.sentenceMarkup(d.sentence):find("|H", 1, true))
	end)

	it("opens from the cache alone when the hovered text is secret", function()
		local secret = "灰谷"
		mock.secret[secret] = true
		ns.Card.enter(_G.ChatFrame1, "addon:WhatsAHanzi:" .. line.hash .. ":3", secret, nil)
		assert.is_nil(mock.lastError)
		assert.is_nil(ns.selftest.cardLineMiss)
		assert.equal(line, ns.Card.ctx.line)
		assert.equal(3, ns.Card.ctx.index)
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
		assert.equal(1, ns.selftest.counters.cards)
		for _, f in ipairs(mock.frames) do
			if f._name == "WhatsAHanziCardKeys" then
				assert.is_false(f:IsShown())
			end
		end
	end)
end)

describe("Card.linkRects (a hovered word that wraps over chat rows)", function()
	local ns, mock2
	before_each(function()
		mock2 = require("tests.wow_mock")
		mock2.install()
		ns = mock2.loadAddon(".")
	end)

	local LINK = "addon:WhatsAHanzi:ab12:3"
	local TEXT = "[Guild] Ann: |cffaaaaaa|H" .. LINK .. "|h欢迎|h|r all"

	-- A chat line FontString that reports the given areas for any span, recording the span it was asked.
	local function region(text, areas)
		local r = { asked = nil }
		function r:GetText()
			return text
		end
		function r:CalculateScreenAreaFromCharacterSpan(a, b)
			self.asked = { a, b }
			return areas
		end
		return r
	end

	it("returns one rect per row, top row first, for the link's byte span", function()
		local r = region(TEXT, {
			{ left = 0, bottom = 0, width = 14, height = 14 }, -- second row
			{ left = 300, bottom = 14, width = 14, height = 14 }, -- first row
		})
		local rects, why = ns.Card.linkRects(r, LINK, 0, 0, 14, 14)
		assert.is_nil(why)
		assert.equal(2, #rects)
		assert.equal(300, rects[1].left)
		assert.equal(14, rects[1].bottom)
		assert.equal(0, rects[2].left)
		local s = TEXT:find("|H", 1, true)
		assert.equal(s, r.asked[1])
		assert.equal("|h", TEXT:sub(r.asked[2] - 1, r.asked[2]))
		assert.same({ left = 0, bottom = 0, width = 314, height = 28 }, ns.Card.boundsOf(rects))
	end)

	it("returns the single row for a one-row link in a wrapped line", function()
		local r = region(TEXT, { { left = 40, bottom = 0, width = 28, height = 14 } })
		local rects = ns.Card.linkRects(r, LINK, 40, 0, 28, 14)
		assert.same({ { left = 40, bottom = 0, width = 28, height = 14 } }, rects)
	end)

	it("falls back to OnHyperlinkEnter's bounds and names the broken link", function()
		local fallback = { { left = 5, bottom = 6, width = 7, height = 8 } }
		local rects, why = ns.Card.linkRects({}, LINK, 5, 6, 7, 8)
		assert.same(fallback, rects)
		assert.equal("no CalculateScreenAreaFromCharacterSpan", why)

		rects, why = ns.Card.linkRects(region("no link here", {}), LINK, 5, 6, 7, 8)
		assert.same(fallback, rects)
		assert.equal("link not in line text", why)

		mock2.secret[TEXT] = true
		rects, why = ns.Card.linkRects(region(TEXT, {}), LINK, 5, 6, 7, 8)
		assert.same(fallback, rects)
		assert.equal("line text secret", why)
		mock2.secret[TEXT] = nil

		rects, why = ns.Card.linkRects(region(TEXT, {}), LINK, 5, 6, 7, 8)
		assert.same(fallback, rects)
		assert.equal("no screen area for the span", why)
	end)

	it("gives race and faction their own icons, the badge at its aspect ratio", function()
		assert.are_not.equal(ns.Card.KIND_ATLAS.race, ns.Card.KIND_ATLAS.faction)
		assert.equal("|A:UI-HUD-UnitFrame-Player-PVP-FFAIcon:14:9|a ", ns.Card.kindIcon("faction"))
		assert.equal("|A:AlliedRace-UnlockingFrame-Male:14:14|a ", ns.Card.kindIcon("race"))
	end)
end)
