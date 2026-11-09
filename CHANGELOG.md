# Changelog

## Unreleased

- `/hanzi fake banter | yell | lfg` prints three invented Chinese lines into the chat window with hover links, to try the card when nobody is online. They do not count toward known words.
- The selftest and `WhatsAHanziDB.ui.chatRect` record where the chat frame sits (position, size, scale, screen size), so the companion's overlay can dock beside it.
- The hover card no longer turns smeared and overlapping after a while of play (only `/reload` cleared it). The card fades in without the small zoom, and uses three text sizes instead of five, which is the most likely reason the client's glyph cache kept filling up.
- The hovered word is read aloud, one syllable at a time, from a bank of 1,503 syllable recordings in `Sounds/` (Kokoro-82M, voice zf_001). A hover held for a quarter second speaks; sweeping the mouse stays quiet. Setting: "Speak hovered words". `/hanzi speak 你好` plays any text. The addon checks at login that the client plays its sound files; when it does not, the card says "sound plays in the companion". Needs a client restart once (new files). The bank is not in the release zip yet.
- The guild Message of the Day in the chat window now has hover links (it never reached the chat filter: the chat frame prints it itself).
- Glossary terms on the card show an icon for their kind (zone, dungeon, boss, item, spell, slang...).
- Game names and guild slang: `Data/Game.lua` (about 7,000 zones, dungeons, bosses, items, class spells, races, factions and slang terms, from the Forever client's own data). A term at least as long as the dictionary word wins, so 灰谷 shows `Ashenvale · zone` with the dictionary gloss under it. Needs a client restart once (new file).
- `K` and `S` on the hover card are off by default; turn them on in Settings ("K and S keys on the card"). Off, the card takes no keys at all.
- `/hanzi reset` now redraws the Settings panel with the reset values.
- Hovering a repeated word in a line from before the last `/reload` lights that occurrence, not the first one.
- The line cache drops its oldest 50 entries in one pass when full, instead of scanning on every new line.

- The hover card: pinyin as ruby over each character with tone colours, the gloss, the sentence with the hovered word lit, a "known 4 of 6" meter, the word underlined in the chat line itself. Drawn in the chat line's own Chinese font (ARHei); `/hanzi font` still overrides.
- Known and new words: new words in chat take a soft colour, known ones none. `K` while hovering marks a word known, `S` stars it; a word seen 8 times (setting) counts as known.
- Settings panel (`/hanzi options`, or Options > AddOns): channels, tones, card size, known threshold, chat links; a Companion page shows what the companion app last wrote.
- Reads the companion's `Data/Local.lua` (translations, game terms, pattern notes) when present; the placeholder `Data/Inbox.lua` is gone. Chat lines carry a FNV-1a hash in their links so the companion and the addon name the same line.
- README is for players; client limits moved to `docs/limits.md`.

- Hover Chinese words in the normal chat window for pinyin and meaning (`/hanzi chat on|off`). The pane is hidden by default now; `/hanzi` opens it.
- Scaffold: chat capture with secret-value guard, Han detection, dictionary segmentation with per-character pinyin fallback, learning pane with hover glosses, vocabulary log, selftest table, slash commands.
- Release zips leave out the bundled Noto Sans SC font (the client refuses addon fonts); ARKai with tone marks is the default look.
