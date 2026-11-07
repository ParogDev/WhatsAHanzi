-- Font handling. Never SetFont on a FontFamily: use SetFontObject + SetFontHeight.
--
-- What the Forever client does (measured 2026-11-06, build 1.60.1): SetFont returns false for every font
-- file under Interface\AddOns, whatever the file (a 70 KB plain Noto Sans and Windows' Arial included),
-- while textures from the same folder load and Blizzard's own Fonts\ files load. The text renderer
-- converts fonts to .slug files by file ID and never does so for addon files. So the bundled Noto Sans SC
-- is tried first (should a later client accept it) and the choice in practice is between Blizzard's
-- fonts: ARKai_T has the Han characters and the pinyin tone letters but wide, uneven Latin;
-- ARIALN and FRIZQT__ have tidy Latin, Han through the client's fallback, but no caron letters
-- (ǎ ǐ ǒ ǔ ǚ), which is what /hanzi tones numbers is for.
local ADDON, ns = ...
local Font = {}
ns.Font = Font

local BUNDLED = "Interface\\AddOns\\" .. ADDON .. "\\Fonts\\NotoSansSC-Regular.ttf"

-- Named fonts the user can pick with /hanzi font <name>.
Font.NAMED = {
	noto = BUNDLED,
	kai = "Fonts\\ARKai_T.ttf",
	hei = "Fonts\\ARHei.ttf",
	arial = "Fonts\\ARIALN.ttf",
	friz = "Fonts\\FRIZQT__.ttf",
}
-- Preference order when nothing is chosen (or the chosen one is refused): full glyph coverage first.
local ORDER = { "noto", "kai", "hei", "arial", "friz" }
Font.DEFAULT = "kai"

Font.probe = nil -- filled by Font.detect(): { path, tried = { path = ok }, detail = { path = {...} } }

-- Finds which font assets the client accepts. Uses a throwaway FontString; SetFont returns false on a
-- refused asset and errors on a missing one, both recorded as "not ok" with the stage that failed.
function Font.detect()
	local result = { tried = {}, detail = {}, byName = {} }
	local fs = Font._probeString
		or (UIParent and UIParent.CreateFontString and UIParent:CreateFontString(nil, "ARTWORK"))
	Font._probeString = fs
	for _, name in ipairs(ORDER) do
		local path = Font.NAMED[name]
		local ok = false
		if fs then
			local okCall, ret = pcall(fs.SetFont, fs, path, 14, "")
			ok = okCall and ret ~= false
			local got = fs:GetFont()
			if ok then
				ok = got ~= nil and got:lower() == path:lower()
			end
			result.detail[path] = { call = okCall, ret = tostring(ret), got = tostring(got) }
		end
		result.tried[path] = ok
		result.byName[name] = ok
		if ok and not result.path then
			result.path = path
			result.name = name
		end
	end
	Font.probe = result
	return result
end

-- The font in use: the user's choice when the client accepts it, else the first accepted one.
function Font.current()
	local p = Font.probe
	if not p then
		return nil, nil
	end
	local want = ns.db and ns.db.ui and ns.db.ui.font
	if want and p.byName[want] then
		return Font.NAMED[want], want
	end
	return p.path, p.name
end

-- /hanzi font <name>: persists when the name is known and the client accepted that font.
function Font.set(name)
	name = name and name:lower()
	if not (name and Font.NAMED[name]) then
		return false, "unknown font"
	end
	if not (Font.probe and Font.probe.byName[name]) then
		return false, "the client refused " .. Font.NAMED[name]
	end
	ns.db.ui.font = name
	return true
end

-- Applies the current font to a FontString of ours, keeping its size.
function Font.apply(fontString, height)
	local path = Font.current()
	if not path then
		return false
	end
	local _, size = fontString:GetFont()
	fontString:SetFont(path, height or size or 14, "")
	return true
end
