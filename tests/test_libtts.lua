-- Offline tests of LibTTS-1.0 with stubbed WoW API, a fake provider and a fake clock. Usage: lua test_libtts.lua
local function eq(a, b, m) if a ~= b then error((m or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end end

strmatch = string.match
local frameShown
function CreateFrame()
    return { SetScript = function() end, Show = function() frameShown = true end, Hide = function() frameShown = false end }
end
local errors = {}
function geterrorhandler() return function(e) errors[#errors + 1] = tostring(e) end end
local played = {}
function PlaySoundFile(path) played[#played + 1] = path end

-- addons the client "has": name -> { meta = TOC fields, enabled, register = function run by LoadAddOn }
local addons, order, loaded, loadCalls = {}, {}, {}, {}
local function addAddon(name, def)
    addons[name] = def; order[#order + 1] = name
    if def.enabled == nil then def.enabled = true end
end
function GetNumAddOns() return #order end
function GetAddOnMetadata(i, key) local a = addons[order[i]]; return a and a.meta and a.meta[key] end
function GetAddOnInfo(n)
    local name = type(n) == "number" and order[n] or n
    local a = addons[name]
    if not a then return nil end
    return name, name, "", a.enabled, true, (not a.enabled) and "DISABLED" or nil
end
function IsAddOnLoaded(n) return loaded[n] end
function LoadAddOn(n)
    loadCalls[#loadCalls + 1] = n
    local a = addons[n]
    if not a or not a.enabled then return nil, "DISABLED" end
    loaded[n] = true
    if a.register then a.register() end
    return 1
end

dofile("../LibStub/LibStub.lua")
dofile("../LibTTS-1.0.lua")
local TTS = LibStub("LibTTS-1.0")

-- A provider that makes one clip per word, 0.1 s each, named after the word. Remembers what it was asked.
local asked = {}
local function fake(id, features)
    return {
        name = id, language = "en", features = features,
        Synthesize = function(_, text, options)
            asked[#asked + 1] = { text = text, options = options }
            local items = {}
            for word in text:gmatch("%S+") do items[#items + 1] = { path = word, wait = 0.1 } end
            return items
        end,
    }
end
local function run(seconds)
    for _ = 1, math.floor(seconds / 0.05 + 0.5) do TTS:Tick(0.05) end
end
local function reset() played = {}; asked = {}; errors = {} end
local function joined() return table.concat(played, " ") end

addAddon("Voice_Gamma", { meta = { ["X-LibTTS-Provider"] = "gamma", ["X-LibTTS-Name"] = "Gamma voice",
    ["X-LibTTS-Extension"] = "Voice_GammaHQ", ["X-LibTTS-Language"] = "de", ["X-LibTTS-Gender"] = "female",
    ["X-LibTTS-Features"] = "speed, pitch" },
    register = function() TTS:RegisterProvider("gamma", fake("gamma", { speed = { min = 0.8, max = 1.2 } })) end })
addAddon("Voice_GammaHQ", {})
addAddon("Voice_Off", { enabled = false, meta = { ["X-LibTTS-Provider"] = "off" } })
addAddon("Other", {})

-- registration validates its input and tells listeners
assert(not pcall(function() TTS:RegisterProvider("x", { name = "x" }) end), "Synthesize is required")
assert(not pcall(function() TTS:RegisterProvider("x", { Synthesize = function() end }) end), "name is required")
local changes = {}
TTS:RegisterCallback(function(event, id) changes[#changes + 1] = event .. ":" .. id end)
TTS:RegisterProvider("alpha", fake("alpha", { speed = { min = 0.5, max = 2 }, pause = true }))
TTS:RegisterProvider("beta", fake("beta"))
eq(changes[1], "provider_registered:alpha")
TTS:UpdateProvider("beta", { features = { speed = { min = 1, max = 1.5 } }, gender = "male" })
eq(changes[3], "provider_updated:beta")
eq(TTS:GetFeatures("beta").speed.max, 1.5, "update merges features")
eq(TTS:GetProviderInfo("beta").gender, "male")
assert(not pcall(function() TTS:UpdateProvider("nope", {}) end), "update needs a registered provider")

-- discovery of unloaded addons through TOC fields (the client's addon list never changes, so the library scans it once)
local list = TTS:ListProviders()
eq(#list, 4, "registered and unloaded providers"); eq(list[1].id, "alpha"); eq(list[3].id, "gamma")
eq(list[3].name, "Gamma voice"); eq(list[3].loaded, false); eq(list[3].available, true)
eq(list[4].available, false); eq(list[4].reason, "disabled")
eq(#TTS:ListProviders({ language = "de" }), 2, "gamma, and off: providers that do not state a language stay in the list")
eq(TTS:ListProviders({ language = "de" })[1].id, "gamma")
local pitch = TTS:ListProviders({ require = { "pitch" } })
eq(#pitch, 2, "TOC features filter; off states none so it stays"); eq(pitch[1].id, "gamma")
eq(TTS:GetFeatures("gamma").pitch, true, "features from the TOC before loading")
eq(TTS:IsAvailable("nothing"), false)
assert(TTS:GetProviderInfo("nothing") == nil)

-- a consumer can name a voice that is not installed; TOC data wins over a declaration
TTS:DeclareProvider("missing", { addon = "Voice_Missing", name = "Missing voice" })
TTS:DeclareProvider("gamma", { addon = "Wrong" })
eq(TTS:GetProviderInfo("gamma").addon, "Voice_Gamma")
local av, why = TTS:IsAvailable("missing")
eq(av, false); eq(why, "missing")

-- Preload loads the addon and its extension once
assert(TTS:Preload("gamma"))
eq(table.concat(loadCalls, ","), "Voice_Gamma,Voice_GammaHQ")
TTS:Preload("gamma")
eq(#loadCalls, 2, "second preload does nothing")
eq(TTS:GetProviderInfo("gamma").features.speed.max, 1.2, "registered features replace the TOC list")
eq(TTS:GetProviderInfo("gamma").extensionLoaded, true)
local ok, reason = TTS:Preload("off")
eq(ok, false); eq(reason, "disabled")

-- Speak: order, timing, events, feature negotiation
local tts = TTS:NewConsumer("A")
tts:SetProvider("alpha")
local events = {}
local function log(event, _, info) events[#events + 1] = event .. (info and info.reason and (":" .. info.reason) or "") end
local h, err = tts:Speak("one two", { speed = 3, pause = 2, pitch = 1, onEvent = log })
assert(h, err)
eq(frameShown, true, "clock runs while busy")
eq(asked[1].options.speed, 2, "clamped to the range"); eq(asked[1].options.pause, 2)
eq(asked[1].options.pitch, nil, "not supported, so not passed on"); eq(asked[1].options.onEvent, nil)
eq(h.info.clamped[1], "speed"); eq(h.info.ignored[1], "pitch")
TTS:Tick(0.01); eq(joined(), "one", "first clip at once")
eq(events[1], "started")
TTS:Tick(0.05); eq(joined(), "one", "waits for the clip's duration")
TTS:Tick(0.05); eq(joined(), "one two")
eq(tts:IsBusy(), true, "busy until the last clip's time has passed")
TTS:Tick(0.11)
eq(events[2], "finished"); eq(tts:IsBusy(), false); eq(frameShown, false, "clock stops when idle")

-- required features
reset()
local nothing, r = tts:Speak("x", { require = { "voice" } })
eq(nothing, nil); eq(r, "unsupported:voice")
events = {}
tts:Speak("x", { require = { "voice" }, onEvent = log })
eq(events[1], nil and "" or "failed:unsupported:voice")
local n2, r2 = tts:Speak("!!!  ", { provider = "nope" })
eq(n2, nil); eq(r2, "unavailable:nope", "an explicit provider has no fallback")
eq(select(2, tts:Speak("")), "empty")

-- defaults, per-request override
tts:SetDefaults({ pause = 1.5, speed = 1.2 })
tts:Speak("a", { speed = 0.9 })
eq(asked[#asked].options.pause, 1.5); eq(asked[#asked].options.speed, 0.9)
tts:SetDefaults({}); tts:Stop(); run(0.2)

-- fallback: unset or unavailable provider picks the first that works
reset()
local any = TTS:NewConsumer("Any")
any:Speak("x"); eq(asked[1] ~= nil, true); run(0.2)
any:SetProvider("off")
eq(any:GetActiveProvider(), "alpha", "chosen one not loaded: first loaded one")
eq(any:Preload(), "alpha")
any:SetProvider(nil)

-- priorities: alert goes first, then normal in order, then low; nothing overlaps across consumers
reset()
local b = TTS:NewConsumer("B")
tts:Speak("n1"); b:Speak("low", { priority = "low" }); tts:Speak("n2"); b:Speak("alert", { priority = "alert" })
run(1)
eq(joined(), "alert n1 n2 low", "priority order")
for i = 1, 2 do eq(TTS.queue[i], nil, "queue empty") end

-- one clip at a time across two consumers
reset()
tts:Speak("a b"); b:Speak("c d")
TTS:Tick(0.01); eq(joined(), "a")
run(0.5); eq(joined(), "a b c d")

-- interrupt drops what is playing, the queue stays
reset(); events = {}
tts:Speak("p1 p2 p3", { onEvent = log })
tts:Speak("q1")
TTS:Tick(0.01)
b:Speak("now", { interrupt = true, priority = "alert" })
run(0.5)
eq(events[2], "interrupted:interrupted"); eq(joined(), "p1 now q1", "cut after the current clip")

-- Stop: own speech only, per handle or all
reset(); events = {}
local h1 = tts:Speak("x1", { onEvent = log })
local h2 = tts:Speak("x2", { onEvent = log })
b:Speak("y1")
tts:Stop(h2)
eq(events[1], "dropped:stopped")
tts:Stop()
eq(events[2], "dropped:stopped"); assert(h1)
run(0.5); eq(joined(), "y1", "other consumer untouched")

-- Stop while playing resets the clock, and the provider hears it
reset()
local stopped = 0
TTS:UpdateProvider("alpha", { OnStop = function() stopped = stopped + 1 end })
tts:Speak("long1 long2"); TTS:Tick(0.01); tts:Stop(); eq(stopped, 1); eq(TTS:IsBusy(), false); eq(TTS.timer, 0)
TTS:UpdateProvider("alpha", { OnStop = false })

-- channel
reset()
tts:Speak("c1", { channel = "chat" }); tts:Speak("c2", { channel = "quest" }); tts:StopChannel("chat")
run(0.3); eq(joined(), "c2")

-- ttl: stale requests are dropped before they start, started ones finish
reset(); events = {}
tts:Speak("w1 w2 w3 w4")
tts:Speak("late", { ttl = 0.2, onEvent = log })
tts:Speak("keep", { ttl = 5 })
run(1)
eq(joined(), "w1 w2 w3 w4 keep"); eq(events[1], "dropped:expired")

-- key: a repeat replaces the older request of the same consumer
reset(); events = {}
tts:Speak("hold")
tts:Speak("v1", { key = "boss", onEvent = log })
tts:Speak("v2", { key = "boss", onEvent = log })
b:Speak("v3", { key = "boss" })
run(0.5)
eq(events[1], "dropped:replaced"); eq(joined(), "hold v2 v3")

-- pause and resume at a clip boundary; other consumers keep speaking
reset()
tts:Speak("s1 s2 s3")
TTS:Tick(0.01); tts:Pause()
b:Speak("other")
run(0.5); eq(joined(), "s1 other"); eq(frameShown, false, "only paused speech left: clock stops")
tts:Resume(); eq(frameShown, true)
run(0.5); eq(joined(), "s1 other s2 s3", "resumes where it stopped")

-- maxLength and the clip limit
reset()
tts:Speak("one two three", { maxLength = 3 }); run(0.3); eq(joined(), "one")
reset()
TTS.MAX_CLIPS = 3
tts:Speak("a b"); h, err = tts:Speak("c d e")
assert(h); eq(#h.items, 1, "cut to the room left")
eq(select(2, tts:Speak("f")), "queue_full")
TTS.MAX_CLIPS = 600
tts:Stop()

-- long text: synthesized piece by piece, split at sentences, with a pause between pieces
reset()
TTS.CHUNK_SIZE, TTS.REFILL_CLIPS = 20, 1
h = tts:Speak("aaaa bbbb cccc. dddd eeee ffff. ggggg", { pause = 2 })
eq(#asked, 1, "only the first piece at once"); eq(asked[1].text, "aaaa bbbb cccc. ")
run(0.05); eq(#asked, 1, "next piece waits until clips run low")
run(0.1); eq(#asked, 2); eq(asked[2].text, "dddd eeee ffff. ")
assert(math.abs(h.items[3].wait - (0.1 + TTS.CHUNK_PAUSE * 2)) < 1e-9, "pause between pieces scales with the option")
run(3); eq(#asked, 3); eq(asked[3].text, "ggggg"); eq(#played, 7)
-- a long word with no break is cut at the size
reset()
tts:Speak(string.rep("x", 50)); eq(asked[1].text, string.rep("x", 20)); tts:Stop()
TTS.CHUNK_SIZE, TTS.REFILL_CLIPS = 300, 8

-- a failing later piece still plays what exists, then reports one failure and no finish
local calls = 0
TTS:RegisterProvider("flaky", { name = "flaky", Synthesize = function()
    calls = calls + 1
    if calls == 2 then return nil, "no clips" end
    return { { path = "clip", wait = 0.1 } }
end })
TTS.CHUNK_SIZE = 5
reset(); events = {}
tts:Speak("hello there friend", { provider = "flaky", onEvent = log })
run(1)
TTS.CHUNK_SIZE = 300
eq(events[1], "started"); eq(events[2], "failed:no clips"); eq(events[3], nil); eq(joined(), "clip")

-- a provider that errors: reported, nothing stalls
TTS:RegisterProvider("broken", { name = "broken", Synthesize = function() error("boom") end })
reset()
eq(select(2, tts:Speak("x", { provider = "broken" })), "provider_error"); assert(errors[1]:find("boom"))
tts:Speak("fine"); run(0.2); eq(joined(), "fine")

-- a consumer callback that errors does not break the queue, and may start speech itself
reset()
tts:SetCallback(function(event) if event == "finished" and #played == 1 then tts:Speak("next") end; error("cb") end)
tts:Speak("first"); run(0.5)
tts:SetCallback(nil)
eq(joined(), "first next"); assert(#errors > 0)

-- marks
TTS:RegisterProvider("marked", { name = "marked", Synthesize = function() return { { path = "m", wait = 0.1, mark = "word1" } } end })
reset(); local mark
tts:Speak("x", { provider = "marked", onEvent = function(e, _, info) if e == "mark" then mark = info.mark end end })
run(0.2); eq(mark, "word1")

-- LibStub upgrade: a newer copy keeps providers, known addons, consumers and speech in progress
reset()
tts:Speak("before upgrade")
TTS:Tick(0.01)
TTS:SetDefaultProvider("alpha")
local minor = select(2, LibStub:GetLibrary("LibTTS-1.0"))
local source = io.open("../LibTTS-1.0.lua"):read("*a")
local newer, changed = source:gsub('local MAJOR, MINOR = "LibTTS%-1%.0", %d+', 'local MAJOR, MINOR = "LibTTS-1.0", ' .. (minor + 1))
eq(changed, 1)
assert(loadstring(newer))()
eq(LibStub("LibTTS-1.0"), TTS, "same table after upgrade")
eq(select(2, LibStub:GetLibrary("LibTTS-1.0")), minor + 1)
eq(TTS:GetDefaultProvider(), "alpha", "default voice kept")
assert(TTS.providers.alpha and TTS.known.gamma, "state kept")
run(0.5); eq(joined(), "before upgrade", "speech goes on")
tts:Speak("after"); run(0.2); eq(joined(), "before upgrade after", "old consumer works")
dofile("../LibTTS-1.0.lua")   -- an older copy loaded later changes nothing
eq(select(2, LibStub:GetLibrary("LibTTS-1.0")), minor + 1)

-- default voice: for consumers without their own choice
TTS.providers, TTS.known, TTS.scanned = {}, {}, true
TTS:RegisterProvider("a1", fake("a1"))
TTS:RegisterProvider("b2", fake("b2", { speed = true }))
local plain = TTS:NewConsumer("plain")
local function used(consumer, options) local h = assert(consumer:Speak("w", options)); consumer:Stop(); return h.provider end
TTS:SetDefaultProvider(nil)
eq(used(plain), "a1", "no default: first by id")
TTS:SetDefaultProvider("b2")
eq(used(plain), "b2"); eq(plain:GetActiveProvider(), "b2"); eq(plain:Preload(), "b2")
eq(used(plain, { provider = "a1" }), "a1", "request option wins")
plain:SetProvider("a1")
eq(used(plain), "a1", "own choice wins"); eq(plain:GetActiveProvider(), "a1")
plain:SetProvider(nil)
TTS:SetDefaultProvider("gone")
eq(used(plain), "a1", "unknown default is skipped"); eq(plain:GetActiveProvider(), "a1")
TTS:SetDefaultProvider("a1")
eq(used(plain, { require = { "speed" } }), "b2", "default without a required feature is skipped")

print("LibTTS tests passed")
