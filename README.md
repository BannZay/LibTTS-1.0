# LibTTS-1.0

The interface between WoW 3.3.5a addons that speak and addons that supply voices. See [docs/LibTTS.md](docs/LibTTS.md).

Used by [TTS](https://github.com/BannZay/TTS).

## Usage example

A `/testTTS <phrase>` command that speaks the phrase.

Copy `LibTTS-1.0.lua`, `LibTTS-1.0.xml` and `LibStub/LibStub.lua` into your addon's `Libs` folder and list them in the TOC before your own files:

```
Libs\LibStub\LibStub.lua
Libs\LibTTS-1.0\LibTTS-1.0.xml
testTTS.lua
```

`testTTS.lua`:

```lua
local tts = LibStub("LibTTS-1.0"):NewConsumer("MyAddon")

local function report(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99testTTS|r: " .. message)
end

tts:SetCallback(function(event, _, info)
    if event == "failed" then report("failed: " .. tostring(info.reason)) end
end)

SLASH_TESTTTS1 = "/testTTS"
SlashCmdList["TESTTTS"] = function(text)
    text = strtrim(text or "")
    if text == "" then
        report("usage: /testTTS <phrase>")
        return
    end
    tts:Speak(text)   -- failures are reported by the callback
end
```

The library has no voice of its own: install a voice addon, such as one from [TTS](https://github.com/BannZay/TTS/releases). Without one, the command reports `failed: no_provider`. The first phrase loads the voice, which can stall the game for a moment.

## Tests

Lua 5.1, no game needed. Run from `tests/`:

```powershell
lua test_libtts.lua
```

## Licence

[MIT](LICENSE). `LibStub/LibStub.lua` is in the public domain.
