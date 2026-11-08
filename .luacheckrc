-- luacheck for a WoW: Forever addon. Run from this folder (tools\lua.ps1 does): the generated globals list
-- lives in the scaffolding root; standalone (CI in this repo) falls back to a short list.
std = "lua51"
max_line_length = 140
codes = true
ignore = {
	"212/self", -- unused self
	"212/_.*", -- unused args named _x
	"631", -- line too long (max_line_length still applies to real code via 631? keep stylua in charge)
}

local ok, wow = pcall(dofile, "../../tools/luacheck-wow-globals.lua")
if ok and type(wow) == "table" then
	read_globals = wow.read_globals
else
	read_globals = {
		"CreateFrame", "UIParent", "GameTooltip", "ChatFontNormal", "DEFAULT_CHAT_FRAME",
		"GetBuildInfo", "GetLocale", "WOW_PROJECT_ID", "C_AddOns", "C_Timer", "issecretvalue", "strsplit",
		"strlenutf8", "date", "time", "geterrorhandler", "bit", "ChatFrameUtil", "GetCursorPosition",
		-- CI in this repo runs standalone: every global the addon touches must be here as well.
		"Settings", "InCombatLockdown", "C_GuildInfo", "IsShiftKeyDown", "IsControlKeyDown", "IsAltKeyDown",
		"CreateSettingsListSectionHeaderInitializer", "WOW_PROJECT_CAMELOT", "SlashCmdList",
			"PlaySoundFile", "StopSound", "C_CVar",
	}
end
-- FrameXML globals the generated list doesn't carry (it is built from the C API lists).
read_globals[#read_globals + 1] = "EventRegistry"
read_globals[#read_globals + 1] = "MinimalSliderWithSteppersMixin"

-- SlashCmdList is a client table addons write their handler into; listing it here makes its fields writable.
globals = { "WhatsAHanzi", "WhatsAHanziDB", "SLASH_WHATSAHANZI1", "SLASH_WHATSAHANZI2", "SlashCmdList" }

files["Data/"] = { max_line_length = false }
files["tests/"] = { std = "+busted", globals = { "WhatsAHanzi", "WhatsAHanziDB", "_G" } }
exclude_files = { "Libs/", ".luacheckrc" }
