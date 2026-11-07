-- The learning pane: a movable, scrollable frame that shows each Chinese line, its pinyin, and a gloss on hover.
local ADDON, ns = ...
local UI = {}
ns.UI = UI

local frame

local function createFrame()
	local f = CreateFrame("Frame", ADDON .. "Frame", UIParent, "BackdropTemplate")
	f:SetSize(420, 220)
	f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 30, 260)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		ns.db.ui.point = { point, relPoint, x, y }
	end)
	f:SetClampedToScreen(true)
	if f.SetBackdrop then
		f:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		f:SetBackdropColor(0, 0, 0, 0.75)
	end

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("TOPLEFT", 8, -6)
	title:SetText("Whats A Hanzi")
	f.title = title

	local msg = CreateFrame("ScrollingMessageFrame", nil, f)
	msg:SetPoint("TOPLEFT", 8, -22)
	msg:SetPoint("BOTTOMRIGHT", -8, 8)
	msg:SetFontObject(ChatFontNormal)
	msg:SetJustifyH("LEFT")
	msg:SetFading(false)
	msg:SetMaxLines(300)
	msg:SetHyperlinksEnabled(true)
	msg:EnableMouseWheel(true)
	msg:SetScript("OnMouseWheel", function(self, delta)
		if delta > 0 then
			self:ScrollUp()
		else
			self:ScrollDown()
		end
	end)
	msg:SetScript("OnHyperlinkEnter", function(self, link)
		local kind, word = strsplit(":", link, 2)
		if kind == "wahword" then
			UI.showGloss(self, word)
		end
	end)
	msg:SetScript("OnHyperlinkLeave", function()
		UI.hideGloss()
	end)
	f.msg = msg
	UI.applyFontSize(msg)
	return f
end

UI.DEFAULT_FONT_SIZE = 22

-- Sets the pane's font at the configured size: the chosen font when the client accepts one, else the chat
-- font's file. Both are plain SetFont calls on the message frame (a FontInstance), never on a font object.
function UI.applyFontSize(msg)
	msg = msg or UI.get().msg
	local size = (ns.db and ns.db.ui and ns.db.ui.fontSize) or UI.DEFAULT_FONT_SIZE
	if not ns.Font.apply(msg, size) then
		local path = ChatFontNormal and ChatFontNormal.GetFont and ChatFontNormal:GetFont()
		if path then
			msg:SetFont(path, size, "")
		end
	end
end

-- /hanzi size N (10..48). Persists and applies at once.
function UI.setFontSize(n)
	n = tonumber(n)
	if not n or n < 10 or n > 48 then
		return false
	end
	ns.db.ui.fontSize = n
	local f = UI.get()
	UI.applyFontSize(f.msg)
	return true
end

-- Our own gloss popup instead of GameTooltip: the tooltip's font has no pinyin tone letters, and setting
-- fonts on GameTooltip's shared lines would leak into every other tooltip.
local gloss
local function glossFrame()
	if gloss then
		return gloss
	end
	gloss = CreateFrame("Frame", ADDON .. "Gloss", UIParent, "BackdropTemplate")
	gloss:SetFrameStrata("TOOLTIP")
	gloss:SetClampedToScreen(true)
	if gloss.SetBackdrop then
		gloss:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		gloss:SetBackdropColor(0.05, 0.05, 0.1, 0.95)
	end
	gloss.word = gloss:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	gloss.word:SetPoint("TOPLEFT", 10, -8)
	gloss.pinyin = gloss:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	gloss.pinyin:SetPoint("TOPLEFT", gloss.word, "BOTTOMLEFT", 0, -4)
	gloss.meaning = gloss:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	gloss.meaning:SetPoint("TOPLEFT", gloss.pinyin, "BOTTOMLEFT", 0, -4)
	gloss.meaning:SetWidth(300)
	gloss.meaning:SetJustifyH("LEFT")
	gloss.meaning:SetWordWrap(true)
	gloss:Hide()
	return gloss
end

function UI.showGloss(anchor, word)
	local e = ns.Data and ns.Data.dict and ns.Data.dict[word]
	local g = glossFrame()
	local size = (ns.db.ui.fontSize or UI.DEFAULT_FONT_SIZE)
	ns.Font.apply(g.word, size + 6)
	ns.Font.apply(g.pinyin, size)
	ns.Font.apply(g.meaning, math.max(12, size - 4))
	g.word:SetText(word)
	if e then
		g.pinyin:SetText("|cff99ccff" .. ns.Pinyin.display(e[1]) .. "|r")
		g.meaning:SetText(e[2])
	else
		g.pinyin:SetText("|cff99ccff" .. ns.Pinyin.display(ns.Pinyin.string(word)) .. "|r")
		g.meaning:SetText("|cff888888(no dictionary entry)|r")
	end
	local w = math.max(g.word:GetStringWidth(), g.pinyin:GetStringWidth(), math.min(300, g.meaning:GetStringWidth()))
	g:SetSize(w + 20, g.word:GetStringHeight() + g.pinyin:GetStringHeight() + g.meaning:GetStringHeight() + 24)
	g:ClearAllPoints()
	if anchor then
		g:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 4)
	else
		-- A word in the chat window: the popup sits just above the cursor.
		local x, y = GetCursorPosition()
		local scale = UIParent:GetEffectiveScale()
		g:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale - 10, y / scale + 14)
	end
	g:Show()
end

function UI.showGlossAtCursor(word)
	UI.showGloss(nil, word)
end

function UI.hideGloss()
	if gloss then
		gloss:Hide()
	end
end

function UI.get()
	if not frame then
		frame = createFrame()
		local p = ns.db.ui.point
		if p then
			frame:ClearAllPoints()
			frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
		end
		if ns.db.ui.hidden then
			frame:Hide()
		end
	end
	return frame
end

function UI.toggle()
	local f = UI.get()
	if f:IsShown() then
		f:Hide()
		ns.db.ui.hidden = true
	else
		f:Show()
		ns.db.ui.hidden = false
	end
end

-- Adds one analysed line: the original (words as hover links), then the pinyin line in a softer colour.
function UI.addAnalysed(sender, tokens, pinyinLine)
	local f = UI.get()
	local parts = {}
	for _, t in ipairs(tokens) do
		if t.han then
			local color = t.known and "|cffffffff" or "|cffffaa66"
			parts[#parts + 1] = color .. "|Hwahword:" .. t.word .. "|h" .. t.word .. "|h|r"
		else
			parts[#parts + 1] = t.word
		end
	end
	f.msg:AddMessage("|cffffd100" .. (sender or "?") .. ":|r " .. table.concat(parts))
	f.msg:AddMessage("    |cff99ccff" .. ns.Pinyin.display(pinyinLine) .. "|r")
end

-- A line we could not analyse (secret value inside an instance): shown raw with a tag.
function UI.addRaw(sender, text, tag)
	local f = UI.get()
	f.msg:AddMessage(
		"|cffffd100" .. (sender or "?") .. ":|r " .. text .. (tag and (" |cff888888(" .. tag .. ")|r") or "")
	)
end
