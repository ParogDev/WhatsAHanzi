# Changelog

## Unreleased

- The hover card: pinyin as ruby over each character with tone colours, the gloss, the sentence with the hovered word lit, a "known 4 of 6" meter, the word underlined in the chat line itself. Drawn in the chat line's own Chinese font (ARHei); `/hanzi font` still overrides.
- Known and new words: new words in chat take a soft colour, known ones none. `K` while hovering marks a word known, `S` stars it; a word seen 8 times (setting) counts as known.
- Settings panel (`/hanzi options`, or Options > AddOns): channels, tones, card size, known threshold, chat links; a Companion page shows what the companion app last wrote.
- Reads the companion's `Data/Local.lua` (translations, game terms, pattern notes) when present; the placeholder `Data/Inbox.lua` is gone. Chat lines carry a FNV-1a hash in their links so the companion and the addon name the same line.
- README is for players; client limits moved to `docs/limits.md`.

- Hover Chinese words in the normal chat window for pinyin and meaning (`/hanzi chat on|off`). The pane is hidden by default now; `/hanzi` opens it.
- Scaffold: chat capture with secret-value guard, Han detection, dictionary segmentation with per-character pinyin fallback, learning pane with hover glosses, vocabulary log, selftest table, slash commands.
- Release zips leave out the bundled Noto Sans SC font (the client refuses addon fonts); ARKai with tone marks is the default look.
