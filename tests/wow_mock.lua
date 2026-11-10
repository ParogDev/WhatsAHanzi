-- Minimal WoW client globals so addon files load under busted. Dumb tables and no-ops, not a client.
-- Frames, FontStrings, textures and animation groups answer any method (a no-op) and keep the few values
-- the code reads back (text, font, shown, points). The real check of frame code is the in-game reload.
local M = {}

local function noop() end
local anyMethod = {
	__index = function()
		return noop
	end,
}

-- A pure-Lua 32-bit bit library for plain Lua 5.1 (the client has LuaBitOp; the test container does not).
local function toBits(n)
	n = n % 4294967296
	local out = {}
	for i = 1, 32 do
		out[i] = n % 2
		n = math.floor(n / 2)
	end
	return out
end
local function fromBits(b)
	local n, p = 0, 1
	for i = 1, 32 do
		n = n + b[i] * p
		p = p * 2
	end
	return n
end
local pureBit = {
	band = function(a, b)
		local x, y, out = toBits(a), toBits(b), {}
		for i = 1, 32 do
			out[i] = (x[i] == 1 and y[i] == 1) and 1 or 0
		end
		return fromBits(out)
	end,
	bxor = function(a, b)
		local x, y, out = toBits(a), toBits(b), {}
		for i = 1, 32 do
			out[i] = x[i] ~= y[i] and 1 or 0
		end
		return fromBits(out)
	end,
}

-- template: the inherited font object's name, which sets the font. Without one, SetText before SetFont or
-- SetFontObject raises the client's "Font not set" error (seen in game, 2026-11-07).
local function newFontString(template)
	local fs = setmetatable({ _font = template, _size = 14, _text = "", _shown = true }, anyMethod)
	function fs:SetFontObject(obj)
		self._font = obj
	end
	function fs:SetFont(path, size)
		if path:find("NotoSansCJK") or path:find("ARKai") or path:find("ARHei") or path:find("^Fonts\\") then
			self._font, self._size = path, size
			return true
		end
		return false
	end
	function fs:GetFont()
		return self._font, self._size
	end
	function fs:SetText(t)
		if rawget(self, "_font") == nil then -- rawget: anyMethod answers every missing key with noop
			error("FontString:SetText(): Font not set", 2)
		end
		self._text = tostring(t or "")
	end
	function fs:GetText()
		return self._text
	end
	function fs:GetStringWidth()
		local plain = self._text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		return #plain * 7
	end
	function fs:GetStringHeight()
		return self._size or 14
	end
	function fs:Show()
		self._shown = true
	end
	function fs:Hide()
		self._shown = false
	end
	function fs:IsShown()
		return self._shown
	end
	function fs:SetPoint(...)
		self._points[#self._points + 1] = { ... }
	end
	function fs:ClearAllPoints()
		self._points = {}
	end
	fs._points = {}
	return fs
end

local function newAnimationGroup(parent)
	local ag = setmetatable({ _parent = parent, _playing = false, _types = {} }, anyMethod)
	function ag:CreateAnimation(kind)
		self._types[#self._types + 1] = kind
		return setmetatable({}, anyMethod)
	end
	function ag:Play()
		self._playing = true
	end
	function ag:Stop()
		self._playing = false
	end
	function ag:IsPlaying()
		return self._playing
	end
	function ag:GetParent()
		return self._parent
	end
	function ag:SetScript(k, fn)
		self["_" .. k] = fn
	end
	return ag
end

local function newFrame(_, name)
	local f = setmetatable({ _events = {}, _name = name, _shown = true, _messages = {}, _points = {} }, anyMethod)
	M.frames[#M.frames + 1] = f
	function f:RegisterEvent(e)
		self._events[e] = true
	end
	function f:UnregisterEvent(e)
		self._events[e] = nil
	end
	function f:SetScript(k, fn)
		self["_" .. k] = fn
	end
	function f:GetScript(k)
		return self["_" .. k]
	end
	function f:IsShown()
		return self._shown
	end
	function f:IsVisible()
		return self._shown
	end
	function f:Show()
		self._shown = true
	end
	function f:Hide()
		self._shown = false
	end
	function f:CreateFontString(_, _, template)
		return newFontString(template)
	end
	function f:CreateTexture()
		return setmetatable({}, anyMethod)
	end
	function f:CreateAnimationGroup()
		return newAnimationGroup(self)
	end
	function f:AddMessage(m)
		self._messages[#self._messages + 1] = m
	end
	function f:GetPoint()
		return "BOTTOMLEFT", nil, "BOTTOMLEFT", 30, 260
	end
	function f:SetPoint(...)
		self._points[#self._points + 1] = { ... }
	end
	function f:ClearAllPoints()
		self._points = {}
	end
	function f:SetSize(w, h)
		self._w, self._h = w, h
	end
	function f:GetWidth()
		return self._w or 0
	end
	function f:GetHeight()
		return self._h or 0
	end
	function f:SetScale(s)
		self._scale = s
	end
	function f:SetPropagateKeyboardInput(p)
		self._propagate = p
	end
	function f:GetObjectType()
		return "Frame"
	end
	function f:GetName()
		return self._name
	end
	function f:GetFont()
		return nil, 14
	end
	function f:GetEffectiveScale()
		return 1
	end
	function f:GetMessageInfo(i)
		return self._messages[#self._messages + 1 - i]
	end
	return f
end

-- Blizzard_Settings, enough for Options.register: settings are recorded, defaults written into the table.
local function newSettings()
	local S = { registered = {}, controls = {}, opened = nil }
	S.VarType = { Boolean = "boolean", Number = "number", String = "string" }
	S.Default = { True = true, False = false }
	local function category(name)
		local c = { name = name, id = name }
		function c:GetID()
			return self.id
		end
		local layout = { initializers = {} }
		function layout:AddInitializer(i)
			self.initializers[#self.initializers + 1] = i
		end
		return c, layout
	end
	function S.RegisterVerticalLayoutCategory(name)
		return category(name)
	end
	function S.RegisterCanvasLayoutSubcategory(_, frame, name)
		local c, l = category(name)
		c.frame = frame
		return c, l
	end
	function S.RegisterAddOnSetting(_, variable, key, tbl, varType, name, default)
		if tbl[key] == nil then
			tbl[key] = default
		end
		local setting = { variable = variable, key = key, tbl = tbl, varType = varType, name = name }
		function setting:GetValue()
			return self.tbl[self.key]
		end
		function setting:SetValue(v)
			self.tbl[self.key] = v
			if self.callback then
				self.callback(self, v)
			end
		end
		function setting:SetValueChangedCallback(fn)
			self.callback = fn
		end
		-- Blizzard: re-reads the table and fires the value-changed callbacks; the mock counts the calls.
		function setting:NotifyUpdate()
			self.notified = (self.notified or 0) + 1
			if self.callback then
				self.callback(self, self.tbl[self.key])
			end
		end
		S.registered[variable] = setting
		return setting
	end
	local function control(kind)
		return function(_, setting)
			S.controls[#S.controls + 1] = { kind = kind, setting = setting }
			return {}
		end
	end
	S.CreateCheckbox = control("checkbox")
	S.CreateDropdown = control("dropdown")
	S.CreateSlider = control("slider")
	function S.CreateSliderOptions(minValue, maxValue, rate)
		return { minValue = minValue, maxValue = maxValue, rate = rate, SetLabelFormatter = noop }
	end
	function S.CreateControlTextContainer()
		local c = { data = {} }
		function c:Add(value, label)
			self.data[#self.data + 1] = { value = value, label = label }
		end
		function c:GetData()
			return self.data
		end
		return c
	end
	function S.RegisterAddOnCategory(c)
		S.addonCategory = c
	end
	function S.OpenToCategory(id)
		S.opened = id
	end
	return S
end

function M.install()
	M.frames = {}
	_G.bit = _G.bit or pureBit
	_G.CreateFrame = newFrame
	_G.UIParent = newFrame(nil, "UIParent")
	_G.GameTooltip = newFrame(nil, "GameTooltip")
	_G.GetCursorPosition = function()
		return 100, 200
	end
	_G.InCombatLockdown = function()
		return M.inCombat == true
	end
	M.motd = nil
	_G.C_GuildInfo = {
		GetMOTD = function()
			return M.motd
		end,
	}
	M.modifier = false
	_G.IsShiftKeyDown = function()
		return M.modifier
	end
	_G.IsControlKeyDown = _G.IsShiftKeyDown
	_G.IsAltKeyDown = _G.IsShiftKeyDown
	M.inCombat = false
	M.chatFilters = {}
	_G.ChatFrameUtil = {
		AddMessageEventFilter = function(event, fn)
			M.chatFilters[event] = fn
		end,
	}
	M.callbacks = {}
	_G.EventRegistry = {
		RegisterCallback = function(_, event, fn, owner)
			M.callbacks[event] = function(...)
				return fn(owner, ...)
			end
		end,
	}
	_G.ChatFontNormal = {
		GetFontObjectForAlphabet = function()
			return {
				GetFont = function()
					return "Fonts\\ARHei.ttf", 14
				end,
			}
		end,
		GetFont = function()
			return "Fonts\\ARIALN.ttf", 14
		end,
	}
	_G.DEFAULT_CHAT_FRAME = newFrame(nil, "DEFAULT_CHAT_FRAME")
	_G.ChatFrame1 = newFrame(nil, "ChatFrame1")
	_G.SlashCmdList = {}
	_G.Settings = newSettings()
	_G.MinimalSliderWithSteppersMixin = { Label = { Left = 1, Right = 2, Top = 3 } }
	_G.CreateSettingsListSectionHeaderInitializer = function(name)
		return { header = name }
	end
	_G.WOW_PROJECT_ID = 18
	_G.WOW_PROJECT_CAMELOT = 18
	_G.GetBuildInfo = function()
		return "1.60.1", "70790", "Nov 4 2026", 16001
	end
	_G.GetLocale = function()
		return "enUS"
	end
	_G.C_AddOns = {
		GetAddOnMetadata = function()
			return "test"
		end,
	}
	_G.C_Timer = {
		After = function(_, fn)
			fn()
		end,
	}
	_G.date = function(fmt)
		return os.date(fmt)
	end
	_G.time = os.time
	_G.strsplit = function(sep, s, n)
		local out = {}
		local pattern = "([^" .. sep .. "]*)"
		for piece in s:gmatch(pattern) do
			if n and #out == n - 1 then
				break
			end
			out[#out + 1] = piece
		end
		if n and #out < n then
			local rest = s:match(("[^" .. sep .. "]*" .. sep):rep(n - 1) .. "(.*)")
			out[#out + 1] = rest or ""
		end
		return unpack(out)
	end
	_G.strlenutf8 = function(s)
		local _, n = s:gsub("[^\128-\191]", "")
		return n
	end
	_G.geterrorhandler = function()
		return function(err)
			M.lastError = err
		end
	end
	M.secret = {} -- values registered as secret for tests
	_G.issecretvalue = function(v)
		return M.secret[v] == true
	end
	return M
end

-- Loads an addon file the way the client does: with (ADDON_NAME, namespace) as varargs.
function M.load(dir, file, ns)
	local chunk, err = loadfile(dir .. "/" .. file)
	assert(chunk, err)
	return chunk("WhatsAHanzi", ns)
end

-- Loads the whole addon in TOC order (minus Core.lua when skipCore) into a fresh namespace.
-- Data/Local.lua and Data/SoundIndex.lua are the companion's files and are not loaded: tests set
-- ns.Data.live and ns.Data.wordSound themselves.
function M.loadAddon(dir, opts)
	opts = opts or {}
	local ns = {}
	for _, f in ipairs({
		"Han.lua",
		"Data/Pinyin.lua",
		"Data/Dict.lua",
		"Data/Game.lua",
		"Data/SoundLengths.lua",
		"Hash.lua",
		"Pinyin.lua",
		"Dict.lua",
		"Font.lua",
		"Sound.lua",
		"Card.lua",
		"UI.lua",
		"Chat.lua",
		"Options.lua",
	}) do
		M.load(dir, f, ns)
	end
	if not opts.skipCore then
		M.load(dir, "Core.lua", ns)
		ns.initDB(nil)
	end
	return ns
end

return M
