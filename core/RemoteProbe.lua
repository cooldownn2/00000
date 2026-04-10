local Probe = {}

local Settings, State, MainEvent, gameStyle

local stats = {
    startClock  = os.clock(),
    totalCalls  = 0,
    byCommand   = {},
    byRemote    = {},
    candidates  = {},
    candidateSet = {},
}

local lastSummaryAt = 0

local KEYWORDS = {
    "ammo", "reload", "clip", "mag", "magazine", "reserve", "bullet", "shell", "cartridge",
}

local function lower(s)
    return string.lower(tostring(s or ""))
end

local function hasKeyword(s)
    local text = lower(s)
    if text == "" then return false end
    for i = 1, #KEYWORDS do
        if string.find(text, KEYWORDS[i], 1, true) then
            return true
        end
    end
    return false
end

local function getRemoteName(remote)
    local ok, name = pcall(function() return remote.Name end)
    if ok and name then return tostring(name) end
    return "<unknown-remote>"
end

local function getRemotePath(remote)
    local ok, path = pcall(function() return remote:GetFullName() end)
    if ok and path then return path end
    return getRemoteName(remote)
end

local function getCallerScriptName()
    local gcs = rawget(_G, "getcallingscript")
    if type(gcs) == "function" then
        local ok, scr = pcall(gcs)
        if ok and scr then
            local okName, nm = pcall(function() return scr:GetFullName() end)
            if okName and nm then return nm end
            local okName2, nm2 = pcall(function() return scr.Name end)
            if okName2 and nm2 then return tostring(nm2) end
        end
    end
    return "<unknown-script>"
end

local function tableKeysSummary(t)
    if type(t) ~= "table" then return "" end
    local keys = {}
    for k, _ in pairs(t) do
        keys[#keys + 1] = tostring(k)
        if #keys >= 16 then break end
    end
    table.sort(keys)
    return table.concat(keys, ",")
end

local function hasKeywordInPayload(payload)
    if type(payload) ~= "table" then return false end
    for k, v in pairs(payload) do
        if hasKeyword(k) then return true end
        if type(v) == "string" and hasKeyword(v) then return true end
        if type(v) == "table" then
            for k2, v2 in pairs(v) do
                if hasKeyword(k2) then return true end
                if type(v2) == "string" and hasKeyword(v2) then return true end
            end
        end
    end
    return false
end

local function addCandidate(remotePath, command, payload, caller)
    local payloadKeys = tableKeysSummary(payload)
    local key = table.concat({remotePath, tostring(command), payloadKeys, caller}, "|")
    if stats.candidateSet[key] then return end
    stats.candidateSet[key] = true

    stats.candidates[#stats.candidates + 1] = {
        command = tostring(command),
        remote  = remotePath,
        caller  = caller,
        keys    = payloadKeys,
        t       = os.clock(),
    }
end

local function recordCommand(remotePath, remoteName, command, payload)
    local cmd = tostring(command)
    local bucket = stats.byCommand[cmd]
    if not bucket then
        bucket = {
            count = 0,
            first = os.clock(),
            remote = remoteName,
            payloadKeys = "",
        }
        stats.byCommand[cmd] = bucket
    end
    bucket.count = bucket.count + 1
    if bucket.payloadKeys == "" and type(payload) == "table" then
        bucket.payloadKeys = tableKeysSummary(payload)
    end

    local rBucket = stats.byRemote[remotePath]
    if not rBucket then
        rBucket = { count = 0 }
        stats.byRemote[remotePath] = rBucket
    end
    rBucket.count = rBucket.count + 1
end

local function sortedCommandEntries()
    local out = {}
    for cmd, data in pairs(stats.byCommand) do
        out[#out + 1] = { cmd = cmd, count = data.count, keys = data.payloadKeys }
    end
    table.sort(out, function(a, b) return a.count > b.count end)
    return out
end

local function printSummary(reason)
    warn("[RemoteProbe] === Summary " .. tostring(reason or "") .. " ===")
    warn("[RemoteProbe] Total FireServer calls captured: " .. tostring(stats.totalCalls))

    local top = sortedCommandEntries()
    local topN = math.min(8, #top)
    for i = 1, topN do
        local e = top[i]
        warn("[RemoteProbe] cmd=" .. e.cmd .. " count=" .. tostring(e.count) .. " keys=" .. tostring(e.keys))
    end

    local candCount = #stats.candidates
    warn("[RemoteProbe] candidate ammo/reload commands: " .. tostring(candCount))
    local startIdx = math.max(1, candCount - 10 + 1)
    for i = startIdx, candCount do
        local c = stats.candidates[i]
        warn("[RemoteProbe] candidate cmd=" .. c.command .. " remote=" .. c.remote .. " caller=" .. c.caller .. " keys=" .. c.keys)
    end
end

local function shouldCapture(remote)
    if not Settings or Settings.RemoteProbeEnabled ~= true then return false end
    if State and State.Unloaded then return false end

    if Settings.RemoteProbeCaptureAll == true then
        return true
    end

    if MainEvent and rawequal(remote, MainEvent) then
        return true
    end

    if gameStyle == "zeehood" then
        local name = getRemoteName(remote)
        if name == "MainRemoteEvent" then
            return true
        end
    end

    return false
end

local function observeNamecall(remote, method, args)
    if method ~= "FireServer" then return end
    if not shouldCapture(remote) then return end

    stats.totalCalls = stats.totalCalls + 1

    local command = args and args[1]
    local payload = args and args[2]

    local remoteName = getRemoteName(remote)
    local remotePath = getRemotePath(remote)
    local caller = getCallerScriptName()

    recordCommand(remotePath, remoteName, command, payload)

    if hasKeyword(command) or hasKeywordInPayload(payload) then
        addCandidate(remotePath, command, payload, caller)
        if Settings.RemoteProbeVerbose == true then
            warn("[RemoteProbe] keyword-hit cmd=" .. tostring(command) .. " remote=" .. remotePath .. " caller=" .. caller)
        end
    end

    local interval = tonumber(Settings.RemoteProbeAutoDumpSeconds) or 0
    if interval > 0 then
        local now = os.clock()
        if now - lastSummaryAt >= interval then
            lastSummaryAt = now
            printSummary("auto")
        end
    end
end

local function getSnapshot()
    return {
        startClock = stats.startClock,
        totalCalls = stats.totalCalls,
        byCommand  = stats.byCommand,
        byRemote   = stats.byRemote,
        candidates = stats.candidates,
    }
end

local function cleanup()
    printSummary("cleanup")
end

local function init(deps)
    Settings  = deps.Settings
    State     = deps.State
    MainEvent = deps.MainEvent
    gameStyle = deps.gameStyle

    if type(shared) == "table" then
        shared.RemoteProbe = {
            dumpSummary = printSummary,
            getSnapshot = getSnapshot,
        }
    end
end

Probe.init = init
Probe.cleanup = cleanup
Probe.observeNamecall = observeNamecall
Probe.dumpSummary = printSummary
Probe.getSnapshot = getSnapshot

return Probe