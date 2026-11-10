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

-- The pixel strip: each new Chinese chat line, encoded in near-black blocks along the bottom edge of the screen,
-- for the companion to read with a screen capture of that rectangle (docs/companion-rs.md, "Pixel strip"). The
-- client writes its chat log in 48 KiB blocks, so this is the companion's live path. Nothing is sent anywhere and
-- nothing is read back: textures only. Colours are 0..15 of 255 per channel (a thin dark border), and the
-- textures change only when a chunk changes, never every frame.
--
-- A frame is STRIP_BLOCKS blocks of BLOCK x BLOCK physical pixels, left to right from the bottom-left corner;
-- each block holds three 4-bit nibbles (r, g, b):
--   2 sync blocks (15,0,15) (0,15,0) | 3 header blocks: seq, chunk index, chunk count, length (one byte each,
--   high nibble first) | 64 data blocks: 96 bytes | 3 blocks: CRC-32 of the header's 4 bytes and the `length`
--   payload bytes. Chunk count 0 is the calibration frame (every nibble value in every channel), shown when idle.
-- A message is `channel \31 sender \31 text`, split into 96-byte chunks, each held HOLD seconds.
local Strip = {
	BLOCK = 3,
	DATA_BYTES = 96,
	HOLD = 0.2,
	MAX_QUEUE = 40,
	SYNC = { { 15, 0, 15 }, { 0, 15, 0 } },
}
ns.Strip = Strip
Strip.BLOCKS = 2 + 3 + Strip.DATA_BYTES * 2 / 3 + 3
local stripState = { sent = 0, frames = 0, skippedSecret = 0, dropped = 0, queued = 0, seq = 0 }
Strip.state = stripState

local MOD32 = 4294967296
local crcTable
function Strip.crc32(bytes, n)
	local bxor, band = bit.bxor, bit.band
	if not crcTable then
		crcTable = {}
		for i = 0, 255 do
			local c = i
			for _ = 1, 8 do
				if c % 2 == 1 then
					c = bxor(3988292384, math.floor(c / 2)) % MOD32
				else
					c = math.floor(c / 2)
				end
			end
			crcTable[i] = c
		end
	end
	local crc = MOD32 - 1
	for i = 1, n or #bytes do
		crc = bxor(crcTable[band(bxor(crc, bytes[i]), 255)], math.floor(crc / 256)) % MOD32
	end
	return bxor(crc, MOD32 - 1) % MOD32
end

-- The nibbles (0..15) of one frame, 3 per block, sync blocks included. `payload` is a byte list (at most
-- DATA_BYTES); the header bytes are seq, idx, count, #payload.
function Strip.encode(seq, idx, count, payload)
	local head = { seq, idx, count, #payload }
	local all = {}
	for i = 1, 4 do
		all[i] = head[i]
	end
	for i = 1, #payload do
		all[4 + i] = payload[i]
	end
	local crc = Strip.crc32(all)
	local nib = {}
	local function byte(b)
		nib[#nib + 1] = math.floor(b / 16)
		nib[#nib + 1] = b % 16
	end
	for _, s in ipairs(Strip.SYNC) do
		nib[#nib + 1], nib[#nib + 2], nib[#nib + 3] = s[1], s[2], s[3]
	end
	for i = 1, 4 do
		byte(head[i])
	end
	nib[#nib + 1] = 0 -- the header's ninth nibble
	for i = 1, Strip.DATA_BYTES do
		byte(payload[i] or 0)
	end
	for _ = 1, 4 do -- CRC, most significant byte first
		local b = math.floor(crc / 16777216)
		crc = (crc % 16777216) * 256
		byte(b)
	end
	nib[#nib + 1] = 0
	return nib
end

-- The idle frame: nibbles 0..15 repeated through the data, so every channel shows every level.
function Strip.calibration()
	local p = {}
	for i = 1, Strip.DATA_BYTES do
		local k = ((i - 1) * 2) % 16
		p[i] = k * 16 + k + 1
	end
	return Strip.encode(0, 0, 0, p)
end

local CHANNELS = {
	CHAT_MSG_GUILD = "guild",
	CHAT_MSG_OFFICER = "officer",
	CHAT_MSG_PARTY = "party",
	CHAT_MSG_PARTY_LEADER = "party",
	CHAT_MSG_RAID = "raid",
	CHAT_MSG_RAID_LEADER = "raid",
	CHAT_MSG_RAID_WARNING = "raid",
	CHAT_MSG_INSTANCE_CHAT = "instance",
	CHAT_MSG_INSTANCE_CHAT_LEADER = "instance",
	CHAT_MSG_WHISPER = "whisper",
	CHAT_MSG_WHISPER_INFORM = "whisper",
	CHAT_MSG_SAY = "say",
	CHAT_MSG_YELL = "yell",
}

-- The message bytes of one chat line, or nil and why not.
function Strip.message(event, text, sender, channel)
	local chan = CHANNELS[event]
	if event == "CHAT_MSG_CHANNEL" and type(channel) == "string" and channel ~= "" then
		chan = channel:lower()
	end
	if not chan then
		return nil, "no channel family"
	end
	if event == "CHAT_MSG_WHISPER_INFORM" then
		sender = "me"
	end
	return chan .. "\31" .. (type(sender) == "string" and sender or "?") .. "\31" .. text
end

local queue = {}
local stripFrame, textures, holding

local function stripOn()
	return ns.db and ns.db.ui.strip ~= false
end

-- Size and place the strip so one unit is one physical pixel, at the screen's bottom-left corner.
function Strip.layout()
	if not stripFrame then
		return
	end
	if not GetPhysicalScreenSize then
		stripState.why = "GetPhysicalScreenSize missing: the strip cannot match physical pixels"
		return
	end
	local _, physH = GetPhysicalScreenSize()
	local parentScale = UIParent:GetEffectiveScale()
	if not (physH and physH > 0 and parentScale and parentScale > 0) then
		stripState.why = "no physical screen size or UIParent scale"
		return
	end
	stripFrame:SetScale((768 / physH) / parentScale)
	stripFrame:ClearAllPoints()
	stripFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
	stripFrame:SetSize(Strip.BLOCKS * Strip.BLOCK, Strip.BLOCK)
	local physW = GetPhysicalScreenSize()
	stripState.pixel = { physW = physW, physH = physH, uiScale = parentScale, block = Strip.BLOCK }
end

local function show(nib)
	for i = 1, Strip.BLOCKS do
		local j = (i - 1) * 3
		textures[i]:SetColorTexture(nib[j + 1] / 255, nib[j + 2] / 255, nib[j + 3] / 255, 1)
	end
	stripState.frames = stripState.frames + 1
end

local function create()
	stripFrame = CreateFrame("Frame", nil, UIParent)
	stripFrame:SetFrameStrata("TOOLTIP")
	stripFrame:SetFrameLevel(10000)
	stripFrame:EnableMouse(false)
	textures = {}
	for i = 1, Strip.BLOCKS do
		local t = stripFrame:CreateTexture(nil, "OVERLAY")
		t:SetSize(Strip.BLOCK, Strip.BLOCK)
		t:SetPoint("BOTTOMLEFT", stripFrame, "BOTTOMLEFT", (i - 1) * Strip.BLOCK, 0)
		textures[i] = t
	end
	Strip.layout()
	show(Strip.calibration())
	stripFrame:Show()
end

-- Show the next queued chunk for HOLD seconds, then the next, then the calibration frame.
local function step()
	local nib = table.remove(queue, 1)
	stripState.queued = #queue
	if not nib then
		holding = false
		show(Strip.calibration())
		return
	end
	holding = true
	show(nib)
	C_Timer.After(Strip.HOLD, step)
end

-- Queue one chat line (Chat.process). Returns the number of chunks queued, or nil and why not.
function Strip.push(event, text, sender, channel)
	if not stripOn() then
		return nil, "strip off"
	end
	if issecretvalue and (issecretvalue(text) or issecretvalue(sender) or issecretvalue(channel)) then
		stripState.skippedSecret = stripState.skippedSecret + 1
		return nil, "secret"
	end
	if type(text) ~= "string" or not ns.Han.hasHan(text) then
		return nil, "no Han"
	end
	local msg, why = Strip.message(event, text, sender, channel)
	if not msg then
		return nil, why
	end
	if not stripFrame then
		create()
	end
	stripState.seq = stripState.seq % 255 + 1
	local count = math.ceil(#msg / Strip.DATA_BYTES)
	if count > 255 or #queue + count > Strip.MAX_QUEUE then
		stripState.dropped = stripState.dropped + 1
		return nil, "queue full"
	end
	for idx = 0, count - 1 do
		local p = {}
		for i = 1, math.min(Strip.DATA_BYTES, #msg - idx * Strip.DATA_BYTES) do
			p[i] = msg:byte(idx * Strip.DATA_BYTES + i)
		end
		queue[#queue + 1] = Strip.encode(stripState.seq, idx, count, p)
	end
	stripState.sent = stripState.sent + 1
	stripState.queued = #queue
	if not holding then
		step()
	end
	return count
end

-- PLAYER_LOGIN: show the calibration frame (the companion finds and measures the strip with it); follow scale
-- changes.
function Strip.start()
	stripState.on = stripOn()
	if not stripState.on then
		return
	end
	create()
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("UI_SCALE_CHANGED")
	ev:RegisterEvent("DISPLAY_SIZE_CHANGED")
	ev:SetScript("OnEvent", Strip.layout)
end

-- The setting changed: hide or show.
function Strip.apply()
	stripState.on = stripOn()
	if stripFrame then
		stripFrame:SetShown(stripState.on)
	elseif stripState.on then
		Strip.start()
	end
end

-- A line we could not analyse (secret value inside an instance): shown raw with a tag.
function UI.addRaw(sender, text, tag)
	local f = UI.get()
	f.msg:AddMessage(
		"|cffffd100" .. (sender or "?") .. ":|r " .. text .. (tag and (" |cff888888(" .. tag .. ")|r") or "")
	)
end
