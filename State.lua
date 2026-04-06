local State = {
    FakePart             = nil,
    FakePos              = nil,
    CurrentPart          = nil,
    LockedTarget         = nil,
    Enabled              = false,

    LastShootArgs        = nil,
    LastShootData        = nil,
    SkipNextFireServer   = false,
    LastRetarget         = 0,
    SpeedCharacter       = nil,
    DefaultWalkSpeed     = nil,
    SpeedStatesPatched   = false,
    ESPEnabled           = false,
    SpeedActive          = false,
    Connections          = {},
    Unloaded             = false,
    Diagnostics          = {
        FireServerFails = 0,
        CleanupFails    = 0,
    },
    TriggerbotToggleActive = false,
    TriggerbotHoldActive   = false,
    CamlockToggleActive    = false,
    CamlockHoldActive      = false,
    LastTriggerShot        = 0,
    NextTriggerShot        = 0,
    CardCapabilityBlocked  = false,
    ForceHitActive         = false,
    ForceHitLoopId         = 0,
}

local function isUnloaded()
    return State.Unloaded
end

local function safeCall(fn, bucket)
    local ok = pcall(fn)
    if not ok and bucket and State.Diagnostics[bucket] ~= nil then
        State.Diagnostics[bucket] = State.Diagnostics[bucket] + 1
    end
    return ok
end

local function connect(signal, fn)
    local cn = signal:Connect(fn)
    table.insert(State.Connections, cn)
    return cn
end

local function disconnectAllTracked()
    for _, cn in ipairs(State.Connections) do
        if cn then
            pcall(function() cn:Disconnect() end)
        end
    end
end

return {
    State                = State,
    isUnloaded           = isUnloaded,
    safeCall             = safeCall,
    connect              = connect,
    disconnectAllTracked = disconnectAllTracked,
}
