-- Settings panel (Blizzard_Settings vertical layout): channels, tones, card size, known threshold, chat
-- links; a "Companion" canvas page shows what the companion last wrote to Data/Local.lua.
-- Reference: Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua.
local ADDON, ns = ...
local Options = {}
ns.Options = Options

Options.TITLE = "Whats A Hanzi"
Options.settings = {} -- every registered setting, for Options.refresh

-- Display names for Chat.EVENTS; the channel list is one checkbox per event.
Options.CHANNEL_NAMES = {
	CHAT_MSG_GUILD = "Guild",
	CHAT_MSG_OFFICER = "Officer",
	CHAT_MSG_PARTY = "Party",
	CHAT_MSG_PARTY_LEADER = "Party leader",
	CHAT_MSG_RAID = "Raid",
	CHAT_MSG_RAID_LEADER = "Raid leader",
	CHAT_MSG_INSTANCE_CHAT = "Instance",
	CHAT_MSG_INSTANCE_CHAT_LEADER = "Instance leader",
	CHAT_MSG_WHISPER = "Whisper",
	CHAT_MSG_WHISPER_INFORM = "Whisper sent",
	CHAT_MSG_EMOTE = "Emote",
	CHAT_MSG_SAY = "Say",
	CHAT_MSG_YELL = "Yell",
	CHAT_MSG_CHANNEL = "Numbered channels",
}

local function percent(v)
	return ("%d%%"):format(v * 100 + 0.5)
end

local function whole(v)
	return ("%d"):format(v)
end

-- The companion page: status read from ns.Data.live each time the panel shows it.
local function companionFrame()
	local f = CreateFrame("Frame", ADDON .. "CompanionOptions")
	local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Companion")
	local status = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
	status:SetJustifyH("LEFT")
	status:SetWidth(520)
	status:SetWordWrap(true)
	local note = f:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	note:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -16)
	note:SetJustifyH("LEFT")
	note:SetWidth(520)
	note:SetWordWrap(true)
	note:SetText(
		"Translations and audio come from the companion app on this PC; change those settings there. "
			.. "What it writes reaches the game at your next /reload."
	)
	function f.OnRefresh()
		status:SetText(Options.companionStatus())
	end
	f:SetScript("OnShow", f.OnRefresh)
	return f
end

-- Lines describing the companion's last write (or its absence).
function Options.companionStatus()
	local live = ns.Data and ns.Data.live
	if not live then
		return "No data from the companion yet (Data/Local.lua absent or empty)."
	end
	local n = 0
	for _ in pairs(live.lines or {}) do
		n = n + 1
	end
	return ("Last written %s\nModel %s\n%d translated lines"):format(
		tostring(live.generatedAt or "?"),
		tostring(live.model or "?"),
		n
	)
end

-- Registers the category once; records in selftest.options what took.
function Options.register()
	if Options.category then
		return Options.category
	end
	local st = { settings = 0 }
	ns.selftest.options = st
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then
		st.error = "Settings API missing: no options panel"
		return nil
	end
	local ui, db = ns.db.ui, ns.db
	local category, layout = Settings.RegisterVerticalLayoutCategory(Options.TITLE)
	Options.category = category

	local function addon(key, tbl, kind, name, default)
		st.settings = st.settings + 1
		local varType = Settings.VarType[kind]
		local s = Settings.RegisterAddOnSetting(category, "WAH_" .. key, key, tbl, varType, name, default)
		Options.settings[#Options.settings + 1] = s
		return s
	end

	local inChat = addon("inChat", ui, "Boolean", "Words in chat linked", true)
	Settings.CreateCheckbox(category, inChat, "Chinese words in the chat window become hover links.")

	local tones = addon("tones", ui, "String", "Tones", "marks")
	Settings.CreateDropdown(category, tones, function()
		local c = Settings.CreateControlTextContainer()
		c:Add("marks", "Marks (nǐ hǎo)")
		c:Add("numbers", "Numbers (ni3 hao3)")
		return c:GetData()
	end, "How pinyin tones are written on the card and in the pane.")

	local scale = addon("cardScale", ui, "Number", "Hover card size", 1)
	local scaleOpts = Settings.CreateSliderOptions(0.8, 1.4, 0.05)
	scaleOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, percent)
	Settings.CreateSlider(category, scale, scaleOpts, "Scale of the card that opens over a hovered word.")

	local known = addon("knownAfter", ui, "Number", "Known after", 8)
	known:SetValueChangedCallback(function()
		ns.Vocab.version = ns.Vocab.version + 1
	end)
	local knownOpts = Settings.CreateSliderOptions(3, 30, 1)
	knownOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, whole)
	Settings.CreateSlider(
		category,
		known,
		knownOpts,
		"A word seen this many times counts as known: no link colour in chat."
	)

	local keys = addon("hoverKeys", ui, "Boolean", "K and S keys on the card", false)
	Settings.CreateCheckbox(
		category,
		keys,
		"While a card is open, K marks the word known and S stars it. Off by default: the card then takes no keys, "
			.. "so K and S stay with your own bindings."
	)

	local speak = addon("speak", ui, "Boolean", "Speak hovered words", true)
	Settings.CreateCheckbox(
		category,
		speak,
		"A word held under the mouse for a moment is read aloud, one syllable at a time, on the Master channel."
	)

	local chatLog = addon("chatLog", ui, "Boolean", "Log chat for the companion", true)
	chatLog:SetValueChangedCallback(function()
		-- ticking turns the log on now; unticking leaves this session's log as it is (/chatlog turns it off)
		local ok, err = pcall(ns.ensureChatLogging)
		if not ok then
			ns.selftest.chatLogging = { why = "ensureChatLogging: " .. tostring(err) }
		end
	end)
	Settings.CreateCheckbox(
		category,
		chatLog,
		"Turns the game's chat log (Logs\\WoWChatLog.txt) on at every login, so the companion overlay sees chat. "
			.. "/chatlog by hand lasts one session only. Unticking stops it from the next login; /chatlog turns it off now."
	)

	local strip = addon("strip", ui, "Boolean", "Live lines to the companion", true)
	Settings.CreateCheckbox(
		category,
		strip,
		"Shows each new Chinese line as a thin dark strip of pixels along the bottom edge of the screen, which the "
			.. "companion overlay reads to translate it at once (the game writes its chat log only every few minutes)."
	)
	strip:SetValueChangedCallback(function()
		if ns.Strip then
			ns.Strip.apply()
		end
	end)

	local recent = addon("recent", ui, "Boolean", "Keep recent Chinese lines", true)
	Settings.CreateCheckbox(
		category,
		recent,
		"Keeps the last 200 Chinese chat lines (six hours) for the companion overlay, and prints them again, dimmed, "
			.. "after a /reload empties the chat window. Lines in instances that the game hides from addons are not kept."
	)

	if layout and CreateSettingsListSectionHeaderInitializer then
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Channels"))
	end
	for _, ev in ipairs(ns.Chat.EVENTS) do
		local s = addon(ev, db.channels, "Boolean", Options.CHANNEL_NAMES[ev] or ev, true)
		s:SetValueChangedCallback(function()
			if ns.frame then
				ns.Chat.register(ns.frame)
			end
		end)
		Settings.CreateCheckbox(category, s)
	end

	if Settings.RegisterCanvasLayoutSubcategory then
		Options.companion = companionFrame()
		Settings.RegisterCanvasLayoutSubcategory(category, Options.companion, "Companion")
	end
	Settings.RegisterAddOnCategory(category)
	st.registered = true
	return category
end

-- After the values changed behind the panel's back (/hanzi reset): each setting re-reads its table and the
-- open panel redraws its controls. Returns how many settings were told.
function Options.refresh()
	local n = 0
	for _, s in ipairs(Options.settings) do
		if s.NotifyUpdate then
			s:NotifyUpdate()
			n = n + 1
		end
	end
	return n
end

-- /hanzi options
function Options.open()
	local cat = Options.register()
	if not cat then
		return false, ns.selftest.options and ns.selftest.options.error
	end
	Settings.OpenToCategory(cat:GetID())
	return true
end
