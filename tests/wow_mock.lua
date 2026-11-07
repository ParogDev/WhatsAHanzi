-- Minimal WoW client globals so addon files load under busted. Dumb tables and no-ops, not a client.
local M = {}

local function noop() end

local function newFontString()
	local fs = { _font = nil, _size = 14 }
	function fs:SetFont(path, size)
		if path:find("NotoSansCJK") or path:find("ARKai") then
			self._font, self._size = path, size
			return true
		end
		return false
	end
	function fs:GetFont()
		return self._font, self._size
	end
	fs.SetFontObject, fs.SetFontHeight, fs.SetText, fs.SetPoint = noop, noop, noop, noop
	return fs
end

local function newFrame(_, name)
	local f = { _events = {}, _name = name, _shown = true, _messages = {} }
	function f:RegisterEvent(e)
		self._events[e] = true
	end
	function f:UnregisterEvent(e)
		self._events[e] = nil
	end
	function f:SetScript(k, fn)
		self["_" .. k] = fn
	end
	function f:IsShown()
		return self._shown
	end
	function f:Show()
		self._shown = true
	end
	function f:Hide()
		self._shown = false
	end
	function f:CreateFontString()
		return newFontString()
	end
	function f:AddMessage(m)
		self._messages[#self._messages + 1] = m
	end
	function f:GetPoint()
		return "BOTTOMLEFT", nil, "BOTTOMLEFT", 30, 260
	end
	for _, k in ipairs({
		"SetSize",
		"SetPoint",
		"SetMovable",
		"EnableMouse",
		"RegisterForDrag",
		"SetClampedToScreen",
		"SetBackdrop",
		"SetBackdropColor",
		"SetFontObject",
		"SetJustifyH",
		"SetFading",
		"SetMaxLines",
		"SetHyperlinksEnabled",
		"EnableMouseWheel",
		"ClearAllPoints",
		"SetFont",
		"StartMoving",
		"StopMovingOrSizing",
		"ScrollUp",
		"ScrollDown",
	}) do
		f[k] = f[k] or noop
	end
	function f:GetFont()
		return nil, 14
	end
	return f
end

function M.install()
	_G.CreateFrame = newFrame
	_G.UIParent = newFrame(nil, "UIParent")
	_G.GameTooltip = newFrame(nil, "GameTooltip")
	for _, k in ipairs({ "SetOwner", "ClearLines", "AddLine" }) do
		_G.GameTooltip[k] = noop
	end
	_G.UIParent.GetEffectiveScale = function()
		return 1
	end
	_G.GetCursorPosition = function()
		return 100, 200
	end
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
	_G.ChatFontNormal = {}
	_G.DEFAULT_CHAT_FRAME = newFrame(nil, "DEFAULT_CHAT_FRAME")
	_G.SlashCmdList = {}
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
function M.loadAddon(dir, opts)
	opts = opts or {}
	local ns = {}
	for _, f in ipairs({
		"Han.lua",
		"Data/Pinyin.lua",
		"Data/Dict.lua",
		"Data/Inbox.lua",
		"Pinyin.lua",
		"Dict.lua",
		"Font.lua",
		"UI.lua",
		"Chat.lua",
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
