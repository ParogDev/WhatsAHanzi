# What the client does not allow

Facts about WoW: Forever 1.60.1 that shape this addon, for other authors as much as for users.

## Chat text inside instances is secret

In dungeons, raids and battlegrounds the client hands addons chat text as a *secret value*: it can be shown but not read. Words there are not linked and the pane shows the line as is with an "instance" tag. `/console addonChatRestrictionsForced 1` reproduces this in town for testing.

## Addon font files are refused

`FontString:SetFont(path)` returns `false` for every font file under `Interface\AddOns\`, whatever the file (measured 2026-11-06 with a 10 MB Noto Sans SC subset, a 71 KB Noto Sans, Windows' Arial, different path spellings), while textures from the same folder load and Blizzard's own `Fonts\` files load. The renderer converts fonts to `.slug` files by file ID and never does so for addon files. A Noto Sans SC subset stays in this repository, is tried first, and is left out of release zips until a client build accepts it.

So the card uses the chat line's own Chinese font instead: `ChatFontNormal:GetFontObjectForAlphabet("simplifiedchinese")` resolves to `Fonts\ARHei.ttf`, which has every Han character and the third-tone letters (ǎ ǐ ǒ ǔ ǚ). `/hanzi font` can pick another Blizzard font; `/hanzi tones numbers` writes `ni3 hao3` for fonts without the caron letters.

## Nothing reaches the game while it runs

Lua files load at `/reload`; SavedVariables are written at `/reload`, logout and exit. The companion app therefore writes `Data/Local.lua` and its translations appear on the card after your next `/reload`. Live translation happens in the companion's own window, never inside the game.
