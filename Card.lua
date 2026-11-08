-- The hover card ("Ruby card"): above the hovered word, in the chat line's own CJK typeface. Pinyin as ruby
-- over each character, the gloss, the companion's translation when it has one, the sentence with the word
-- lit, a known-words meter and pattern notes. The word itself is underlined inside the chat frame.
-- Card.build is pure data (unit-tested); everything below it is frames, pools and AnimationGroups.
local ADDON, ns = ...
local Card = {}
ns.Card = Card

local ACCENT = { 0.36, 0.80, 0.95 }
local ACCENT_HEX = "5ccbf2"
-- Pinyin tone colours (Pleco's convention, lightened for a dark card): 1 red, 2 orange, 3 blue, 4 violet, 5 grey.
Card.TONE_HEX = { "ff7b7b", "ffc46b", "7fb4ff", "cf95ff", "9c9c9c" }
local PAD = 10
local TEXT_WIDTH = 340
local ENTRANCE, EXIT = 0.12, 0.08

-- Data ------------------------------------------------------------------------------------------------------

-- Tone number of one marked syllable ("nǐ" -> 3; no mark -> 5).
function Card.toneOf(syl)
	local n = ns.Pinyin.numbered(syl):match("(%d)%s*$")
	return tonumber(n) or 5
end

-- One entry per character of a Han token: { ch, py, tone }. The dictionary reading is used when it has one
-- syllable per character, else the per-character reading.
function Card.charReadings(t)
	local chars, out = {}, {}
	for ch in ns.Han.chars(t.word) do
		chars[#chars + 1] = ch
	end
	local syls = {}
	for syl in (t.pinyin or ""):gmatch("%S+") do
		syls[#syls + 1] = syl
	end
	for i, ch in ipairs(chars) do
		local py = (#syls == #chars and syls[i]) or ns.Pinyin.char(ch) or "?"
		out[i] = { ch = ch, py = py, tone = Card.toneOf(py) }
	end
	return out
end

-- First two senses of a CEDICT gloss: "to be able/can/possible/..." -> "to be able / can".
function Card.shortGloss(meaning)
	if not meaning or meaning == "" then
		return nil
	end
	local a, b = meaning:match("^([^/]*)/?([^/]*)")
	return b ~= "" and (a .. " / " .. b) or a
end

-- Everything the card shows, as a table: line = { hash, body, tokens }, index = the hovered token,
-- live = ns.Data.live (or nil), vocab = the vocabulary log. No frames.
function Card.build(line, index, live, vocab)
	local tokens = line.tokens
	local t = tokens[index]
	if not t then
		return nil, "token " .. tostring(index) .. " not in the line"
	end
	local entry = vocab and vocab[t.word]
	local data = {
		word = t.word,
		pinyin = t.pinyin,
		chars = Card.charReadings(t),
		gloss = Card.shortGloss(t.gloss),
		known = ns.Vocab.isKnown(t.word, vocab),
		starred = entry and entry.star == true or false,
		seen = entry and entry.n or 0,
		sentence = {},
		meter = { known = 0, total = 0 },
		patterns = {},
	}
	for k, tok in ipairs(tokens) do
		local known = tok.han and ns.Vocab.isKnown(tok.word, vocab) or false
		data.sentence[k] = { word = tok.word, han = tok.han == true, lit = k == index, known = known }
		if tok.han then
			data.meter.total = data.meter.total + 1
			if known then
				data.meter.known = data.meter.known + 1
			end
		end
	end
	if live then
		local tr = live.lines and line.hash and live.lines[line.hash]
		if tr and tr.t then
			data.translation = { text = tr.t, model = tr.m or live.model, ctx = tr.ctx or 0 }
		end
		local term = live.terms and live.terms[t.word]
		if term then
			data.term = { en = term[1], kind = term[2] }
		end
		local patterns = live.patterns
		if patterns then
			if patterns[t.word] then
				data.patterns[1] = { key = t.word, note = patterns[t.word] }
			end
			for _, tok in ipairs(tokens) do
				if tok.han and tok.word ~= t.word and patterns[tok.word] and #data.patterns < 3 then
					data.patterns[#data.patterns + 1] = { key = tok.word, note = patterns[tok.word] }
				end
			end
		end
	end
	return data
end

-- Pinyin with each syllable coloured by tone, in the user's tone display (marks or numbers).
function Card.coloredPinyin(py)
	local out = {}
	for syl in (py or ""):gmatch("%S+") do
		out[#out + 1] = "|cff" .. Card.TONE_HEX[Card.toneOf(syl)] .. ns.Pinyin.display(syl) .. "|r"
	end
	return table.concat(out, " ")
end

-- The sentence with the hovered token lit, known words light, new words in the soft link colour, the rest dim.
function Card.sentenceMarkup(sentence)
	local parts = {}
	for _, s in ipairs(sentence) do
		-- Non-Han stretches may carry the line's own colour codes: drop them, escape any other bar.
		local word = s.word
		if not s.han then
			word = (word:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", "||"))
		end
		if s.lit then
			parts[#parts + 1] = "|cff" .. ACCENT_HEX .. word .. "|r"
		elseif not s.han then
			parts[#parts + 1] = "|cff8a8a8a" .. word .. "|r"
		elseif s.known then
			parts[#parts + 1] = "|cffd0d0d0" .. word .. "|r"
		else
			parts[#parts + 1] = "|cff8fb8cc" .. word .. "|r"
		end
	end
	return table.concat(parts)
end

-- Pools --------------------------------------------------------------------------------------------------

local function acquireFS(card)
	local p = card.pool
	p.nfs = p.nfs + 1
	local fs = p.fs[p.nfs]
	if not fs then
		fs = card:CreateFontString(nil, "OVERLAY")
		p.fs[p.nfs] = fs
	end
	fs:ClearAllPoints()
	fs:SetWidth(0)
	fs:SetWordWrap(false)
	fs:SetJustifyH("LEFT")
	fs:SetTextColor(1, 1, 1)
	fs:SetAlpha(1)
	fs:Show()
	return fs
end

local function resetPools(card)
	local p = card.pool
	for i = 1, p.nfs do
		p.fs[i]:Hide()
	end
	p.nfs = 0
end

-- Animations -----------------------------------------------------------------------------------------------

-- Entrance: fade in and, for the card, a scale-up from 0.92 anchored at the bottom-left.
local function entranceGroup(target, scale, duration)
	local ag = target:CreateAnimationGroup()
	local a = ag:CreateAnimation("Alpha")
	a:SetFromAlpha(0)
	a:SetToAlpha(1)
	a:SetDuration(duration)
	a:SetSmoothing("OUT")
	if scale then
		local s = ag:CreateAnimation("Scale")
		s:SetScaleFrom(0.92, 0.92)
		s:SetScaleTo(1, 1)
		s:SetDuration(duration)
		s:SetSmoothing("OUT")
		s:SetOrigin("BOTTOMLEFT", 0, 0)
	end
	return ag
end

local function exitGroup(target)
	local ag = target:CreateAnimationGroup()
	local a = ag:CreateAnimation("Alpha")
	a:SetFromAlpha(1)
	a:SetToAlpha(0)
	a:SetDuration(EXIT)
	a:SetSmoothing("IN")
	ag:SetToFinalAlpha(true)
	ag:SetScript("OnFinished", function(self)
		local f = self:GetParent()
		f:Hide()
		f:SetAlpha(1)
	end)
	return ag
end

local function showAnimated(f)
	f.out:Stop()
	f.anim:Stop()
	f:SetAlpha(1)
	f:Show()
	f.anim:Play()
end

local function hideAnimated(f)
	if f and f:IsShown() then
		f.anim:Stop()
		f.out:Play()
	end
end

-- Frames -----------------------------------------------------------------------------------------------------

local card, highlight, keys

local function setFont(fs, size)
	fs:SetFont(ns.Font.card(), size, "")
end

-- Offsets from OnHyperlinkEnter are in the chat FontString's scale; SetPoint and SetSize take the
-- positioned frame's own scale (the card is scaled by cardScale, the highlight sits under UIParent).
local function scaleRatio(region, frame)
	local from = region and region.GetEffectiveScale and region:GetEffectiveScale() or 1
	local to = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
	if not (from and to) or to == 0 then
		return 1
	end
	return from / to
end

-- Text from outside (companion data, dictionary glosses) must not open or close escape sequences.
local function safe(s)
	return (tostring(s or ""):gsub("|", "||"))
end

local function cardFrame()
	if card then
		return card
	end
	local f = CreateFrame("Frame", ADDON .. "Card", UIParent, "BackdropTemplate")
	f:SetFrameStrata("TOOLTIP")
	f:SetClampedToScreen(true)
	if f.SetBackdrop then
		f:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Buttons\\WHITE8x8",
			edgeSize = 1,
		})
		f:SetBackdropColor(0.055, 0.065, 0.085, 0.96)
		f:SetBackdropBorderColor(1, 1, 1, 0.10)
	end
	f.accent = f:CreateTexture(nil, "ARTWORK")
	f.accent:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)
	f.accent:SetPoint("TOPLEFT", 1, -1)
	f.accent:SetPoint("TOPRIGHT", -1, -1)
	f.accent:SetHeight(2)
	f.pool = { fs = {}, nfs = 0 }
	f.anim = entranceGroup(f, true, ENTRANCE)
	f.out = exitGroup(f)
	f:Hide()
	card = f
	return f
end

-- The underline under the hovered word, inside the chat frame, at the bounds OnHyperlinkEnter gave.
local function showHighlight(ctx)
	if not highlight then
		highlight = CreateFrame("Frame", ADDON .. "CardHighlight", UIParent)
		highlight:SetFrameStrata("TOOLTIP")
		highlight.glow = highlight:CreateTexture(nil, "BACKGROUND")
		highlight.glow:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.14)
		highlight.glow:SetAllPoints()
		highlight.bar = highlight:CreateTexture(nil, "ARTWORK")
		highlight.bar:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)
		highlight.bar:SetPoint("BOTTOMLEFT")
		highlight.bar:SetPoint("BOTTOMRIGHT")
		highlight.bar:SetHeight(2)
		highlight.anim = entranceGroup(highlight, false, 0.1)
		highlight.out = exitGroup(highlight)
	end
	if not (ctx.region and type(ctx.left) == "number") then
		highlight:Hide()
		return
	end
	local r = scaleRatio(ctx.region, highlight)
	highlight:ClearAllPoints()
	highlight:SetPoint("BOTTOMLEFT", ctx.region, "BOTTOMLEFT", ctx.left * r, ctx.bottom * r)
	highlight:SetSize(math.max(ctx.width * r, 1), math.max(ctx.height * r, 1))
	showAnimated(highlight)
end

-- Keyboard while hovering: K marks the word known, S stars it. A frame with keyboard input shown only
-- during the hover; every other key passes through. Never in combat (SetPropagateKeyboardInput is
-- protected there), so the frame simply stays hidden then.
local function modifierDown()
	return (IsShiftKeyDown and IsShiftKeyDown())
		or (IsControlKeyDown and IsControlKeyDown())
		or (IsAltKeyDown and IsAltKeyDown())
end

local function onKeyDown(self, key)
	if InCombatLockdown and InCombatLockdown() then
		return -- SetPropagateKeyboardInput is protected now; the frame hides on PLAYER_REGEN_DISABLED
	end
	local ctx = Card.ctx
	-- The hovered line scrolled or its tab closed without a leave event: give the keyboard back.
	if ctx and ctx.region and ctx.region.IsVisible and not ctx.region:IsVisible() then
		self:SetPropagateKeyboardInput(true)
		Card.leave()
		return
	end
	local mine = (key == "K" or key == "S") and not modifierDown()
	self:SetPropagateKeyboardInput(not mine)
	if not (mine and ctx) then
		return
	end
	local tok = ctx.line.tokens[ctx.index]
	if not tok then
		return
	end
	ns.Vocab.toggle(tok.word, key == "K" and "known" or "star")
	ns.selftest.counters.marks = (ns.selftest.counters.marks or 0) + 1
	local ok, err = pcall(Card.show, ctx)
	if not ok then
		ns.selftest.lastError = "card: " .. tostring(err)
		geterrorhandler()(err)
	end
end

-- Key releases pass through the same way, so a key held across a hover is not left stuck.
local function onKeyUp(self, key)
	if InCombatLockdown and InCombatLockdown() then
		return
	end
	self:SetPropagateKeyboardInput(key ~= "K" and key ~= "S" or modifierDown())
end

local function showKeys(on)
	if on and InCombatLockdown and InCombatLockdown() then
		on = false
	end
	if not keys then
		if not on then
			return
		end
		keys = CreateFrame("Frame", ADDON .. "CardKeys", UIParent)
		keys:SetFrameStrata("TOOLTIP")
		keys:SetSize(1, 1)
		keys:SetPoint("CENTER")
		keys:EnableKeyboard(true)
		keys:SetScript("OnKeyDown", onKeyDown)
		keys:SetScript("OnKeyUp", onKeyUp)
		-- Combat starting mid-hover: give the keyboard back before SetPropagateKeyboardInput is protected.
		keys:RegisterEvent("PLAYER_REGEN_DISABLED")
		keys:SetScript("OnEvent", function(self)
			self:Hide()
		end)
		keys:Hide()
	end
	if on then
		keys:Show()
	else
		keys:Hide()
	end
end

-- Layout ------------------------------------------------------------------------------------------------

-- Fills and sizes the card for ctx = { line, index, region, left, bottom, width, height, anchor }.
function Card.show(ctx)
	local data, why = Card.build(ctx.line, ctx.index, ns.Data and ns.Data.live, ns.db.vocab)
	if not data then
		return nil, why
	end
	local c = cardFrame()
	resetPools(c)
	c:SetScale((ns.db.ui and ns.db.ui.cardScale) or 1)
	local rows = {} -- FontStrings stacked under the ruby row, with the gap above each

	-- Ruby row: pinyin over each character.
	local x, colH = PAD, 0
	for _, col in ipairs(data.chars) do
		local p = acquireFS(c)
		setFont(p, 12)
		p:SetText(Card.coloredPinyin(col.py))
		local h = acquireFS(c)
		setFont(h, 28)
		h:SetText(col.ch)
		local w = math.max(h:GetStringWidth(), p:GetStringWidth()) + 8
		p:SetPoint("TOP", c, "TOPLEFT", x + w / 2, -PAD - 2)
		h:SetPoint("TOP", c, "TOPLEFT", x + w / 2, -PAD - 2 - p:GetStringHeight() - 1)
		colH = math.max(colH, p:GetStringHeight() + 1 + h:GetStringHeight())
		x = x + w
	end
	-- Marks beside the word: a star, and "known" when marked or seen often enough.
	local marks = {}
	if data.starred then
		marks[#marks + 1] = "|cffffd27f★|r"
	end
	if data.known then
		marks[#marks + 1] = "|cff9fe0a0known|r"
	end
	if #marks > 0 then
		local m = acquireFS(c)
		setFont(m, 11)
		m:SetText(table.concat(marks, "  "))
		m:SetPoint("BOTTOMLEFT", c, "TOPLEFT", x + 2, -PAD - 2 - colH + 4)
		x = x + m:GetStringWidth() + 6
	end

	local function row(size, text, gap, color)
		local fs = acquireFS(c)
		setFont(fs, size)
		fs:SetWidth(TEXT_WIDTH)
		fs:SetWordWrap(true)
		if color then
			fs:SetTextColor(color[1], color[2], color[3])
		end
		fs:SetText(text)
		rows[#rows + 1] = { fs = fs, gap = gap }
		return fs
	end

	-- Gloss, or the game term.
	if data.term then
		row(
			13,
			"|cffffe08a" .. safe(data.term.en) .. "|r  |cff8a8a8a·|r  |cffb0b0b0" .. safe(data.term.kind) .. "|r",
			6
		)
		if data.gloss then
			row(12, safe(data.gloss), 2, { 0.75, 0.75, 0.75 })
		end
	else
		row(13, data.gloss and safe(data.gloss) or "|cff888888(no dictionary entry)|r", 6, { 0.92, 0.92, 0.92 })
	end

	-- Translation from the companion, or the quiet state.
	if data.translation then
		local tr = data.translation
		local chip = safe(tr.model or "companion")
		if type(tr.ctx) == "number" and tr.ctx > 0 then
			chip = chip .. " · " .. tr.ctx .. " lines of context"
		end
		row(13, "|cffe6e6e6" .. safe(tr.text) .. "|r  |cff6f8ea0" .. chip .. "|r", 8)
	else
		row(12, "|cff6f8ea0not translated yet|r", 8)
	end

	-- The sentence with the word lit.
	row(14, Card.sentenceMarkup(data.sentence), 8)

	-- Meter and key hints.
	local meter = ("|cffb0b0b0known %d of %d|r"):format(data.meter.known, data.meter.total)
	local hint = (InCombatLockdown and InCombatLockdown()) and "" or "   |cff5c6670K known · S star|r"
	row(11, meter .. hint, 6)

	-- Pattern notes.
	for _, p in ipairs(data.patterns) do
		row(11, "|cffcf95ff" .. safe(p.key) .. "|r  |cffb0b0b0" .. safe(p.note) .. "|r", 3)
	end

	-- Stack the rows and size the card.
	local w, y = x, PAD + 2 + colH
	local prev
	for _, r in ipairs(rows) do
		if prev then
			r.fs:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -r.gap)
		else
			r.fs:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -(y + r.gap))
		end
		y = y + r.gap + r.fs:GetStringHeight()
		w = math.max(w, math.min(TEXT_WIDTH, r.fs:GetStringWidth()) + PAD)
		prev = r.fs
	end
	c:SetSize(w + PAD, y + PAD)

	-- Anchor: bottom-left just above the hovered word; else above the given frame; else the cursor.
	c:ClearAllPoints()
	if ctx.region and type(ctx.left) == "number" then
		local r = scaleRatio(ctx.region, c)
		c:SetPoint("BOTTOMLEFT", ctx.region, "BOTTOMLEFT", ctx.left * r - PAD, (ctx.bottom + ctx.height) * r + 6)
	elseif ctx.anchor then
		c:SetPoint("BOTTOMLEFT", ctx.anchor, "TOPLEFT", 0, 4)
	else
		local cx, cy = GetCursorPosition()
		local s = c:GetEffectiveScale() -- cursor pixels into the card's own (scaled) units
		c:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx / s - 10, cy / s + 14)
	end
	-- A card still fading out (the last word was left a moment ago) is brought back, not re-hidden.
	if not c:IsShown() or c.out:IsPlaying() then
		showAnimated(c)
	end
	return data
end

-- Entry from the chat frame hover (Chat.hookChatFrames). Resolves the line from the cache, else from the
-- chat frame's recent messages; records the first hover's bounds in the selftest.
function Card.enter(chatFrame, link, text, region, left, bottom, width, height)
	local st = ns.selftest
	if not st.hoverBounds and type(left) == "number" then
		st.hoverBounds = {
			left = left,
			bottom = bottom,
			width = width,
			height = height,
			regionType = region and region.GetObjectType and region:GetObjectType() or nil,
		}
	end
	local hash, index = ns.Chat.tokenFromLink(link)
	if not hash then
		return
	end
	-- The hover's text is the whole escape sequence (|H...|h上下|h, as for OnHyperlinkClick), not the bare
	-- word; plainText reduces it, and returns nil for a secret, which is never compared or segmented.
	text = ns.Chat.plainText(text)
	if text == "" then
		text = nil
	end
	local line = ns.Chat.lines.get(hash)
	-- A line rebuilt from the chat frame is numbered differently: trust the cache only when the token is
	-- the hovered word.
	-- the hovered word. Secret text (instances, forced restrictions) cannot be compared: the hash and index
	-- alone decide, and nothing of it is read.
	if not (line and line.tokens[index] and (text == nil or line.tokens[index].word == text)) then
		local why
		line, index = ns.Chat.lineForLink(chatFrame, link, text)
		why = index
		if not line then
			st.cardLineMiss = why or "line not cached"
			if type(text) ~= "string" or not ns.Han.hasHan(text) then
				return
			end
			-- The hovered text alone, without its hash: its translation would belong to the whole line.
			line = { body = text, tokens = ns.Dict.segment(text) }
			index = 1
			for k, tok in ipairs(line.tokens) do
				if tok.han then
					index = k
					break
				end
			end
		end
	end
	local ctx = {
		chatFrame = chatFrame,
		line = line,
		index = index,
		region = region,
		left = left,
		bottom = bottom,
		width = width,
		height = height,
	}
	Card.ctx = ctx
	st.counters.cards = (st.counters.cards or 0) + 1
	local ok, data = pcall(Card.show, ctx)
	if not ok then
		st.lastError = "card: " .. tostring(data)
		geterrorhandler()(data)
		return
	end
	-- The companion wrote lines but not this one: a hash mismatch shows up here, not as silence.
	local live = ns.Data and ns.Data.live
	if data and live and live.lines and next(live.lines) and not data.translation then
		st.counters.liveMiss = (st.counters.liveMiss or 0) + 1
	end
	showHighlight(ctx)
	showKeys(true)
end

-- A single word hovered in the pane (no sentence): the card above the given frame.
function Card.enterWord(anchor, word)
	if type(word) ~= "string" or ns.Chat.isSecret(word) or word == "" then
		return
	end
	local ctx = { line = { body = word, tokens = ns.Dict.segment(word) }, index = 1, anchor = anchor }
	Card.ctx = ctx
	ns.selftest.counters.cards = (ns.selftest.counters.cards or 0) + 1
	local ok, err = pcall(Card.show, ctx)
	if not ok then
		ns.selftest.lastError = "card: " .. tostring(err)
		geterrorhandler()(err)
		return
	end
	showKeys(true)
end

function Card.leave()
	Card.ctx = nil
	showKeys(false)
	hideAnimated(highlight)
	hideAnimated(card)
end
