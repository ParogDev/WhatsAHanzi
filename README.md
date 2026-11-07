# Whats A Hanzi

A World of Warcraft: Forever addon for learning Chinese from the people you play with. Every Chinese chat line (guild, party, raid, whisper, say) is shown again in a small pane with its pinyin underneath, word by word; hover a word for its meaning. Everything you have seen goes into a vocabulary log you can review later.

Only WoW: Forever (interface 16001) is supported.

## Use

- `/hanzi` toggles the pane. Drag it where you like.
- `/hanzi test 你好` runs a line through the analyser without anyone having to say it.
- `/hanzi size 26` sets the pane's text size (10 to 48; default 22).
- `/hanzi font kai|arial|friz|hei` picks the font: `kai` (default) has every Chinese character and every tone letter but wide Latin; `arial` and `friz` are the usual UI fonts, tidy but without the third-tone letters (ǎ ǐ ǒ ǔ ǚ).
- `/hanzi tones numbers` writes tones as numbers (`ni3 hao3`) so any font can show them; `/hanzi tones marks` goes back.
- `/hanzi status` prints counters, the font in use and which fonts the client accepted; `/hanzi vocab` the vocabulary size; `/hanzi reset` the pane position.

Inside dungeons, raids and battlegrounds the client hands addons chat text as a *secret value* that cannot be analysed; the pane then shows the line as is with an "instance" tag.

## Fonts

The Forever client (1.60.1) refuses every font file shipped by an addon: `SetFont` returns false for any file under `Interface\AddOns`, whatever the font, while Blizzard's own fonts load. A subset of Noto Sans SC (OFL 1.1, see `LICENSES/OFL-NotoSansSC.txt`) stays in this repository and is tried first, for the day a client build accepts it; release zips leave it out (10 MB that would do nothing). Until then the pane uses Blizzard's ARKai (Han plus every tone letter, wide Latin) by default; `/hanzi font` and `/hanzi tones` are the way around its looks. `/hanzi status` tells you which font is in use and which the client accepted.

## Data

- Character readings: Unihan `kMandarin` (Unicode, Inc.; see `LICENSES/UNICODE.txt`).
- Words and glosses: CC-CEDICT (CC-BY-SA 4.0; see `LICENSES/CC-CEDICT.txt`). The bundled list is trimmed; regenerate with the scaffolding repo's `/regen-dict`.

## Development

Part of the [WowForeverScaffolding](https://github.com/ParogDev/WowForeverScaffolding) workspace. `luacheck .`, `busted`, `stylua --check .` must be green; CI runs them on every push.

MIT licence for the code.
