local State, safeCall
local GH, MainEvent, oldShoot, mt, oldNamecall, oldIndex
local isStoredShootArgsValid
local Taps
local SilentAim
local LP, UIS, Mouse
local hookedShoot, hookedNamecall, hookedIndex
local gameStyle
local random = math.random

local MOUSE1 = Enum.UserInputType.MouseButton1

local function setReadOnlySafe(value)
    if setreadonly then setreadonly(mt, value) end
end

local function cloneZeehoodArgs(args)
    local out = table.clone and table.clone(args) or { unpack(args) }
    local payload = args[2]
    if type(payload) ~= "table" then return out end

    local payloadCopy = table.clone and table.clone(payload) or {}
    if not table.clone then
        for k, v in pairs(payload) do
            payloadCopy[k] = v
        end
    end

    local pellets = payload.Pellets
    if type(pellets) == "table" then
        local pelletsCopy = table.create and table.create(#pellets) or {}
        for i, pellet in ipairs(pellets) do
            if type(pellet) == "table" then
                local pelletCopy = table.clone and table.clone(pellet) or {}
                if not table.clone then
                    for k, v in pairs(pellet) do
                        pelletCopy[k] = v
                    end
                end
                pelletsCopy[i] = pelletCopy
            else
                pelletsCopy[i] = pellet
            end
        end
        payloadCopy.Pellets = pelletsCopy
    end

    out[2] = payloadCopy
    return out
end

local function setFreshZeehoodTimestamp(payload, burstIndex)
    if type(payload) ~= "table" then return end

    local ok, serverNow = pcall(workspace.GetServerTimeNow, workspace)
    if ok and type(serverNow) == "number" then
        local idx = tonumber(burstIndex) or 0
        payload.Timestamp = serverNow + (idx * (1 / 120)) + ((random() - 0.5) * 0.0005)
        return
    end

    payload.Timestamp = os.clock()
end

local function sendZeehoodAssistShot(self, baseArgs, burstIndex)
    local sendArgs = cloneZeehoodArgs(baseArgs)
    setFreshZeehoodTimestamp(sendArgs[2], burstIndex)
    local redirected = false

    local ok = pcall(function()
        redirected = SilentAim.redirectZeehoodPayload(sendArgs[2]) == true
    end)

    if not ok or not redirected then
        return false
    end

    pcall(oldNamecall, self, table.unpack(sendArgs))
    return true
end

local function buildHooks()
    hookedShoot = function(data)
        if State.Unloaded then return oldShoot(data) end
        local shootData = data
        if type(data) == "table" then
            shootData = SilentAim.prepareShootData(data)
        end
        return oldShoot(shootData)
    end

    hookedIndex = function(self, key)
        if State.Unloaded then return oldIndex(self, key) end

        if gameStyle == "zeehood" and Mouse and rawequal(self, Mouse) and key == "Hit" then
            local firing = UIS and UIS:IsMouseButtonPressed(MOUSE1)
            if firing then
                local ok, aimPos = pcall(function()
                    if SilentAim.getCurrentMouseHitPosition then
                        return SilentAim.getCurrentMouseHitPosition()
                    end
                    if SilentAim.getCurrentAimPosition then
                        return SilentAim.getCurrentAimPosition()
                    end
                    return nil
                end)
                if ok and typeof(aimPos) == "Vector3" then
                    local cOk, aimedCf = pcall(CFrame.new, aimPos)
                    if cOk and aimedCf then
                        return aimedCf
                    end
                end
            end
        end

        return oldIndex(self, key)
    end

    hookedNamecall = function(self, ...)
        if State.Unloaded then return oldNamecall(self, ...) end
        if getnamecallmethod() ~= "FireServer" or not rawequal(self, MainEvent) then
            return oldNamecall(self, ...)
        end
        local args = {...}

        if gameStyle == "zeehood" then
            -- Zeehood style: keep the original shot path untouched for weapon
            -- state stability, then send a redirected assist shot when a valid
            -- lock exists (forcehit-style behavior).
            if isStoredShootArgsValid(args) then
                local tapCount = 1
                local prepOk = pcall(function()
                    SilentAim.recordShootArgs(args)
                    tapCount = Taps.getTapCount(args)
                end)

                if prepOk then
                    local result = oldNamecall(self, ...)
                    sendZeehoodAssistShot(self, args, 1)
                    for _ = 2, tapCount do
                        pcall(oldNamecall, self, ...)
                        sendZeehoodAssistShot(self, args, _)
                    end
                    return result
                end

                return oldNamecall(self, ...)
            end
            return oldNamecall(self, ...)
        end

        -- Dashood / positional-args style.
        SilentAim.recordShootArgs(args)
        if SilentAim.shouldRedirectFireServer(args) then
            SilentAim.applyFireServerRedirect(args)
            local result = oldNamecall(self, table.unpack(args))
            -- Tap extra shots: call oldNamecall directly (bypasses hook) so
            -- SkipNextFireServer is never needed and can't be left dirty.
            local extra = Taps.getTapCount(args) - 1
            for _ = 1, extra do
                oldNamecall(self, table.unpack(args))
            end
            return result
        end
        if isStoredShootArgsValid(args) then
            local result = oldNamecall(self, ...)
            local extra = Taps.getTapCount(args) - 1
            for _ = 1, extra do
                oldNamecall(self, table.unpack(args))
            end
            return result
        end
        return oldNamecall(self, ...)
    end
end

local function install()
    -- Hooks are built once in init; install just wires them in.
    if GH.shoot ~= hookedShoot then GH.shoot = hookedShoot end
    setReadOnlySafe(false)
    if mt.__index ~= hookedIndex then mt.__index = hookedIndex end
    if mt.__namecall ~= hookedNamecall then mt.__namecall = hookedNamecall end
    setReadOnlySafe(true)
end

local function uninstall()
    if GH.shoot == hookedShoot then GH.shoot = oldShoot end
    safeCall(function()
        setReadOnlySafe(false)
        if mt.__index == hookedIndex then mt.__index = oldIndex end
        if mt.__namecall == hookedNamecall then mt.__namecall = oldNamecall end
        setReadOnlySafe(true)
    end, "CleanupFails")
end

local function init(deps)
    State                  = deps.State
    safeCall               = deps.safeCall
    GH                     = deps.GH
    MainEvent              = deps.MainEvent
    oldShoot               = deps.oldShoot
    mt                     = deps.mt
    oldNamecall            = deps.oldNamecall
    oldIndex               = deps.oldIndex
    isStoredShootArgsValid = deps.isStoredShootArgsValid
    Taps                   = deps.Taps
    SilentAim              = deps.SilentAim
    LP                     = deps.LP
    UIS                    = deps.UIS
    Mouse                  = LP and LP:GetMouse() or nil
    gameStyle              = deps.gameStyle
    SilentAim.init(deps)
    -- Build closures once here so install() just wires them in without re-allocating.
    buildHooks()
end

return {
    init      = init,
    install   = install,
    uninstall = uninstall,
}
