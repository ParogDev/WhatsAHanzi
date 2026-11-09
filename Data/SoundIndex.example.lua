-- Shape of Data/SoundIndex.lua, the word bank index the companion app writes (`wah bank build`; gitignored;
-- listed in the TOC so a /reload picks up a rewrite). The addon works without it: ns.Data.wordSound stays nil
-- and every word plays syllable by syllable. Hand-edited never. Keys:
--   wordSound[<word>] = { stem, ms }
--     stem  file name under Sounds/words/ without ".ogg", the word's spoken (post-sandhi) pinyin with tone
--           digits, ü as v, neutral tone 5: "ni2hao3". Homophones share one file. Letters, digits and "_" only.
--     ms    the file's length in milliseconds.
-- The companion lists only files older than the running client's start: the client plays only the files it
-- saw at startup, so a newer file waits for the next client restart and its word keeps playing syllables.
local _, ns = ...
ns.Data = ns.Data or {}
ns.Data.wordSound = {
	["你好"] = { "ni2hao3", 820 },
	["一起"] = { "yi4qi3", 760 },
}
