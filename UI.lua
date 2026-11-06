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
		GameTooltip:Hide()
	end)
	f.msg = msg
	ns.Font.apply(msg, 14)
	return f
end

function UI.showGloss(anchor, word)
	local e = ns.Data and ns.Data.dict and ns.Data.dict[word]
	GameTooltip:SetOwner(anchor, "ANCHOR_CURSOR")
	GameTooltip:ClearLines()
	GameTooltip:AddLine(word, 1, 1, 1)
	if e then
		GameTooltip:AddLine(e[1], 0.6, 0.9, 1)
		GameTooltip:AddLine(e[2], 0.9, 0.9, 0.9, true)
	else
		GameTooltip:AddLine(ns.Pinyin.string(word), 0.6, 0.9, 1)
		GameTooltip:AddLine("(no dictionary entry)", 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
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
	f.msg:AddMessage("    |cff99ccff" .. pinyinLine .. "|r")
end

-- A line we could not analyse (secret value inside an instance): shown raw with a tag.
function UI.addRaw(sender, text, tag)
	local f = UI.get()
	f.msg:AddMessage(
		"|cffffd100" .. (sender or "?") .. ":|r " .. text .. (tag and (" |cff888888(" .. tag .. ")|r") or "")
	)
end
