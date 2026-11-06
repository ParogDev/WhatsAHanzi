-- CJK font handling. The enUS client may lack Fonts\ARKai_T.ttf (then Han renders as boxes); a bundled OFL
-- font under Fonts\ is used when present. Never SetFont on a FontFamily: use SetFontObject + SetFontHeight.
local ADDON, ns = ...
local Font = {}
ns.Font = Font

-- The bundled font first: it is the only one with both the Han characters and the pinyin tone letters
-- (ǎ ǐ ǒ ǔ ǚ); Blizzard's ARKai_T has the Han but not the tone letters.
local CANDIDATES = {
	"Interface\\AddOns\\" .. ADDON .. "\\Fonts\\NotoSansSC-Regular.ttf",
	"Fonts\\ARKai_T.ttf",
	"Fonts\\ARHei.ttf",
}

Font.probe = nil -- filled by Font.detect(): { path = string|nil, tried = { path = ok } }

-- Finds the first font asset the client accepts. Uses a throwaway FontString; SetFont on a missing asset
-- returns false (or errors on older clients), both treated as "missing".
function Font.detect()
	local result = { tried = {} }
	local fs = Font._probeString or (UIParent and UIParent:CreateFontString(nil, "ARTWORK"))
	Font._probeString = fs
	for _, path in ipairs(CANDIDATES) do
		local ok = false
		if fs then
			local okCall, ret = pcall(fs.SetFont, fs, path, 14, "")
			ok = okCall and ret ~= false
			if ok then
				-- A font that "sets" but has no glyphs still reports the path we asked for; nothing more to check here.
				local got = fs:GetFont()
				ok = got ~= nil and got:lower() == path:lower()
			end
		end
		result.tried[path] = ok
		if ok and not result.path then
			result.path = path
		end
	end
	Font.probe = result
	return result
end

-- Applies the CJK-capable font to a FontString of ours, keeping its size.
function Font.apply(fontString, height)
	local path = Font.probe and Font.probe.path
	if not path then
		return false
	end
	local _, size = fontString:GetFont()
	fontString:SetFont(path, height or size or 14, "")
	return true
end
