-- The learning pane: a movable, scrollable frame that shows each Chinese line with its pinyin. Hovering a
-- word there shows the same card as in the chat window (Card.lua).
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
		if kind == "wahword" and ns.Card then
			ns.Card.enterWord(self, word)
		end
	end)
	msg:SetScript("OnHyperlinkLeave", function()
		if ns.Card then
			ns.Card.leave()
		end
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
			local color = ns.Vocab.isKnown(t.word) and "|cffffffff" or ns.Chat.NEW_WORD_COLOR
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
