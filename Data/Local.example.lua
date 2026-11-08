-- Shape of Data/Local.lua, the file the companion app writes (gitignored; listed in the TOC so a /reload
-- picks up a rewrite). The addon works without it: ns.Data.live stays nil and the card says
-- "not translated yet". Hand-edited never. Keys:
--   lines[<hash>]   hash = FNV-1a 32-bit over the UTF-8 bytes of the chat message text, 8 lowercase hex
--                   digits (Hash.lua, tests/fixtures/hash_parity.json); t = translation, ctx = lines of
--                   context the model saw, m = model alias, at = unix time of the translation.
--   terms[<word>]   { english, kind }: game names (zones, factions, classes) shown as a tag on the card.
--   patterns[<key>] a note shown when a token of the hovered line equals the key.
local _, ns = ...
ns.Data = ns.Data or {}
ns.Data.live = {
	generatedAt = "2026-11-07 21:00:00",
	model = "haiku",
	lines = {
		["3043a59c"] = {
			t = "I got blasted by an Alliance hunter in Ashenvale",
			ctx = 3,
			m = "haiku",
			at = 1762567200,
		},
	},
	terms = {
		["灰谷"] = { "Ashenvale", "zone" },
		["联盟"] = { "Alliance", "faction" },
	},
	patterns = {
		["被"] = "passive marker: 被 + doer + verb, often for something that happened to you",
	},
}
