# Whats A Hanzi

Your guild speaks Chinese and you want to keep up. Whats A Hanzi turns every Chinese word in your chat window into something you can hover: a card opens above the word, in the same typeface as the line, with the pinyin written over each character, the meaning, and the whole sentence with your word lit. Words you have seen often enough stop being coloured, so the chat itself shows you what you have learned. Press `K` on a word you know, `S` on one you want to keep.

Only WoW: Forever (interface 16001) is supported.

## What it does

- **Hover any Chinese word** in guild, party, raid, whisper, say or channel chat for pinyin per character, tone colours and a short gloss, with the word underlined in the line itself.
- **Watch your vocabulary grow**: new words take a soft colour, known ones take the chat's own colour, and the card counts how many words of the sentence you already know.
- **Translations and game terms** appear on the card when the companion app runs on your PC: the sentence in English, a tag like "Ashenvale · zone", and notes on patterns such as the 被 passive.

## Install

Download the latest zip from [GitHub Releases](https://github.com/ParogDev/WhatsAHanzi/releases) and unpack it into `World of Warcraft\_forever_\Interface\AddOns\`. Open the game, and hover a Chinese word.

## Commands

- `/hanzi options` opens the settings: channels, tone marks or numbers, card size, how many sightings make a word known.
- `/hanzi test 你好` runs a line through the addon without anyone having to say it.
- `/hanzi` opens the pane that lists every Chinese line with its pinyin; `/hanzi size 26` sets its text size.
- `/hanzi font kai|hei|arial|friz` and `/hanzi tones numbers` change the look; `/hanzi status` shows what is in use.

What the client cannot do (instance chat, bundled fonts) is in `docs/limits.md`.

## Licences

Code MIT. Readings from Unihan `kMandarin` (Unicode licence), glosses from CC-CEDICT (CC-BY-SA 4.0), Noto Sans SC under the OFL 1.1; the texts are in `LICENSES/`.
