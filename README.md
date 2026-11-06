# Whats A Hanzi

A World of Warcraft: Forever addon for learning Chinese from the people you play with. Every Chinese chat line (guild, party, raid, whisper, say) is shown again in a small pane with its pinyin underneath, word by word; hover a word for its meaning. Everything you have seen goes into a vocabulary log you can review later.

Only WoW: Forever (interface 16001) is supported.

## Use

- `/hanzi` toggles the pane. Drag it where you like.
- `/hanzi test 你好` runs a line through the analyser without anyone having to say it.
- `/hanzi status` prints counters and which CJK font is in use; `/hanzi vocab` the vocabulary size; `/hanzi reset` the pane position.

Inside dungeons, raids and battlegrounds the client hands addons chat text as a *secret value* that cannot be analysed; the pane then shows the line as is with an "instance" tag.

## Fonts

An English client may not ship a Chinese font, and Chinese then renders as boxes. The addon looks for a bundled font under `Fonts\` first, then the client's `ARKai_T.ttf`. `/hanzi status` tells you which one it found.

## Data

- Character readings: Unihan `kMandarin` (Unicode, Inc.; see `LICENSES/UNICODE.txt`).
- Words and glosses: CC-CEDICT (CC-BY-SA 4.0; see `LICENSES/CC-CEDICT.txt`). The bundled list is trimmed; regenerate with the scaffolding repo's `/regen-dict`.

## Development

Part of the [WowForeverScaffolding](https://github.com/ParogDev/WowForeverScaffolding) workspace. `luacheck .`, `busted`, `stylua --check .` must be green; CI runs them on every push.

MIT licence for the code.
