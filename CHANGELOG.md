# Changelog

## Unreleased

- Hover Chinese words in the normal chat window for pinyin and meaning (`/hanzi chat on|off`). The pane is hidden by default now; `/hanzi` opens it.
- Scaffold: chat capture with secret-value guard, Han detection, dictionary segmentation with per-character pinyin fallback, learning pane with hover glosses, vocabulary log, selftest table, slash commands.
- Release zips leave out the bundled Noto Sans SC font (the client refuses addon fonts); ARKai with tone marks is the default look.
