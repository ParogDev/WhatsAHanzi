# Whats A Hanzi

A World of Warcraft: Forever addon for learning Chinese from the people you play with. Every Chinese chat line (guild, party, raid, whisper, say) is shown again in a small pane with its pinyin underneath, word by word; hover a word for its meaning. Everything you have seen goes into a vocabulary log you can review later.

Only WoW: Forever (interface 16001) is supported.

## Use

- `/hanzi` toggles the pane. Drag it where you like.
- `/hanzi test 你好` runs a line through the analyser without anyone having to say it.
- `/hanzi size 26` sets the pane's text size (10 to 48; default 22).
- `/hanzi status` prints counters and which CJK font is in use; `/hanzi vocab` the vocabulary size; `/hanzi reset` the pane position.

Inside dungeons, raids and battlegrounds the client hands addons chat text as a *secret value* that cannot be analysed; the pane then shows the line as is with an "instance" tag.

## Fonts

Blizzard's fonts have no glyphs for the pinyin tone letters (ǎ ǐ ǒ ǔ ǚ), and an English client may not even ship a Chinese font. The addon therefore bundles a subset of Noto Sans SC (OFL 1.1, see `LICENSES/OFL-NotoSansSC.txt`), which carries the Han characters and the tone letters in one design, and uses it for the pane and the word popup. `/hanzi status` tells you which font is in use.

## Data

- Character readings: Unihan `kMandarin` (Unicode, Inc.; see `LICENSES/UNICODE.txt`).
- Words and glosses: CC-CEDICT (CC-BY-SA 4.0; see `LICENSES/CC-CEDICT.txt`). The bundled list is trimmed; regenerate with the scaffolding repo's `/regen-dict`.

## Development

Part of the [WowForeverScaffolding](https://github.com/ParogDev/WowForeverScaffolding) workspace. `luacheck .`, `busted`, `stylua --check .` must be green; CI runs them on every push.

MIT licence for the code.
