# LibTTS-1.0

WoW 3.3.5 has no text-to-speech. LibTTS is the interface between addons that speak (consumers) and addons that supply voices (providers). Neither side needs to know the other.

```
Consumers (TTS, ...)  ->  LibTTS-1.0  ->  Providers (TTS_Arctic, TTS_Kal, ...)
```

The library handles the provider list, loading, feature negotiation, the queue and playback. A provider only turns text into clips.

## Embedding

Copy `LibTTS-1.0.lua`, `LibTTS-1.0.xml` and LibStub into your addon and list them in the TOC:

```
Libs\LibStub\LibStub.lua
Libs\LibTTS-1.0\LibTTS-1.0.xml
```

The newest copy wins. Queue, providers and existing consumers survive the upgrade.

## Consumers

```lua
local TTS = LibStub("LibTTS-1.0")
local tts = TTS:NewConsumer("MyAddon")

tts:SetProvider("arctic")                 -- optional; without it the default voice, see "Which voice speaks"
tts:SetDefaults({ speed = 1.2 })          -- optional; applied to every request
tts:Preload()                             -- optional; load the voice at login, not on the first sentence

local handle, reason = tts:Speak("Pull in five", {
    speed = 1.2, require = { "speed" },
    priority = "alert", interrupt = true, ttl = 3, key = "pull",
})
```

### Which voice speaks

1. The `provider` option of the request. There is no fallback.
2. The consumer's `SetProvider` choice.
3. The default voice, set with `TTS:SetDefaultProvider(id)`.
4. The first available provider by id.

A choice from step 2 or 3 that cannot be loaded is skipped. The default is also skipped when it lacks a required feature.

`SetDefaultProvider` is only for an addon that lets the player pick a voice, so that other addons follow that choice. It is shared by all consumers, the last call wins, and `nil` clears it. It is not saved by the library: call it again each session. It shares the voice only, not speed or other settings. Added in minor version 2.

### Request options

Library options work with every provider:

| Option | Meaning |
|---|---|
| `provider` | Use this provider for this request only. There is no fallback if it is unavailable |
| `require` | List of features that must exist, otherwise the request fails |
| `priority` | `"low"`, `"normal"` (default) or `"alert"`. Higher plays first. Equal priorities play in order |
| `interrupt` | Drop what is playing now |
| `channel` | Your label for a group of requests, for `StopChannel` |
| `ttl` | Seconds it may wait in the queue. If it has not started by then, it is dropped |
| `key` | Replaces your older request with the same key, so repeats do not stack |
| `maxLength` | Cut the text to this many characters |
| `onEvent` | `function(event, handle, info)` for this request |

Anything else is a provider feature, such as `speed`.

### Provider features

Providers advertise what they support. Most are optional and no feature is mandatory.

| Feature | Value | Notes |
|---|---|---|
| `speed` | number, 1 = normal | `{ pausesOnly = true }` means only the pauses change, not the words |
| `pause` | number, 1 = normal | Scales pauses between words and sentences |
| `volume` | number | The client has no per-sound volume, so a provider needs louder and quieter clip sets |
| `pitch` | number | Needs pitch-shifted clip sets |
| `voice` | id from `voices` | Several voices in one provider |
| `language` | string | |
| `spell` | boolean | Read letter by letter |
| `lexicon` | table word -> pronunciation | Overrides, e.g. boss names |
| `phonemes` | string | Direct phoneme input |
| `marks` | boolean | Word progress through the `mark` event |
| `fallback` | diphone voice id | Whole-word voices only: which voice speaks the words they lack |

The library has no fixed list, so a provider can add a feature without a library release.

If a provider lacks an option, the request still plays and the option name is listed in `handle.info.ignored`. Put it in `require` to fail instead. Numbers outside the range are limited to it and listed in `handle.info.clamped`.

### Events

Set with `onEvent`, or `tts:SetCallback(fn)` for all your requests.

| Event | When |
|---|---|
| `started` | The first clip is about to play. `info` is the same as `handle.info` |
| `mark` | A clip with a mark started. `info.mark` |
| `finished` | The last clip's time has passed |
| `interrupted` | Stopped while playing. `info.reason` |
| `dropped` | Removed before playing. `info.reason`: `stopped`, `expired`, `replaced` or `queue_full` |
| `failed` | Could not be spoken. `info.reason`. `handle` is nil if `Speak` itself failed |

### Failure reasons

`Speak` returns nil and one of: `no_provider`, `unavailable:<id>`, `unsupported:<feature>`, `provider_error`, `queue_full`, or `empty` (nothing to say; no event is sent).

### Other calls

```lua
tts:Stop()                     -- everything from this consumer
tts:Stop(handle)               -- one request
tts:StopChannel("chat")
tts:Pause()  tts:Resume()      -- holds at the next clip; other consumers keep playing
tts:IsBusy()
tts:GetActiveProvider()        -- id Speak would use now, without loading anything

TTS:ListProviders({ language = "en", gender = "female", require = { "speed" } })
TTS:GetProviderInfo(id)        -- id, name, addon, extension, language, gender, quality, voices, features,
                               -- loaded, available, reason, extensionLoaded
TTS:GetFeatures(id)            -- for building sliders from min and max
TTS:IsAvailable(id)            -- true, or false and "missing" / "disabled" / "unknown"
TTS:Preload(id)
TTS:SetDefaultProvider(id)   TTS:GetDefaultProvider()
TTS:RegisterCallback(fn)       -- fn("provider_registered" or "provider_updated", id)
TTS:DeclareProvider(id, info)  -- name a voice you recommend, so you can tell the user it is not installed
```

## Providers

```lua
local TTS = LibStub("LibTTS-1.0")
TTS:RegisterProvider("myvoice", {
    name = "My voice",
    Synthesize = function(self, text, options)
        -- options holds only the features you advertised, already limited to their range
        return { { path = "Interface\\AddOns\\MyVoice\\hello.ogg", wait = 0.4 } }
    end,
})
```

`name` and `Synthesize` are required. Everything else is optional:

| Field | Meaning |
|---|---|
| `features` | `{ speed = { min = 0.6, max = 1.6, default = 1 }, spell = true }` |
| `language`, `gender`, `quality` | Used by `ListProviders` filters and shown to users |
| `voices` | `{ { id =, name =, gender = }, ... }` |
| `OnStop` | `function(self, handle)`, called when speech is stopped while playing |

`Synthesize` returns a list of items, or nil and a reason. An item is `{ path, wait, mark }`: the file, the seconds until the next clip, and an optional `mark` value. The client cannot report when a sound ends, so `wait` must be accurate. Return fresh tables, because the library changes `wait` to add pauses.

Long text arrives in pieces of up to `CHUNK_SIZE` characters, so one call never stalls the game for long.

`TTS:UpdateProvider(id, patch)` changes a registered provider. Features are merged by name. Extension addons use this.

### Load on demand

Voices can be large, so they should be load-on-demand. Add these TOC fields so the library can list the voice before it loads:

```
## LoadOnDemand: 1
## X-LibTTS-Provider: myvoice
## X-LibTTS-Name: My voice (female)
## X-LibTTS-Extension: MyVoice_HQ
## X-LibTTS-Language: en
## X-LibTTS-Gender: female
## X-LibTTS-Features: speed, pause
```

Only `X-LibTTS-Provider` is needed. The library loads the addon on first use, then the extension if there is one.

## Client limits

These come from the 3.3.5 client and cannot be worked around in Lua:

- **No completion callback.** `PlaySoundFile` returns nothing useful, so timing relies on known durations.
- **No stop.** A clip that started always finishes. Stopping drops the clips after it. This is about 0.1 s for diphones, but a provider with long clips cannot be cut off.
- **No per-sound volume.** Every script sound plays at full volume in the sound channel, so `volume` needs separate clip sets.
- **No position.** Sounds are 2D.
- Nothing is heard during movies or with sound disabled, but the queue still advances.
