local State, safeCall
local GH, MainEvent, oldShoot, mt, oldNamecall
local isStoredShootArgsValid
local Taps
local SilentAim
local ZeehoodTracer
local hookedShoot, hookedNamecall
local gameStyle

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

local function buildHooks()
    hookedShoot = function(data)
        if State.Unloaded then return oldShoot(data) end
        local shootData = data
        if type(data) == "table" then
            shootData = SilentAim.prepareShootData(data)
        end
        return oldShoot(shootData)
    end

    hookedNamecall = function(self, ...)
        if State.Unloaded then return oldNamecall(self, ...) end
        if getnamecallmethod() ~= "FireServer" or not rawequal(self, MainEvent) then
            return oldNamecall(self, ...)
        end
        local args = {...}

        if gameStyle == "zeehood" then
            -- Zeehood style: the payload is a table at args[2]. Redirect hits
            -- directly here; there is no GH.shoot hook to set FakePart for us.
            if isStoredShootArgsValid(args) then
                local tapCount = 1
                local sendArgs = cloneZeehoodArgs(args)
                local redirectOk = pcall(function()
                    SilentAim.recordShootArgs(args)
                    SilentAim.redirectZeehoodPayload(sendArgs[2])
                    tapCount = Taps.getTapCount(args)
                end)

                -- If the redirect path fails for any reason, immediately fall
                -- back to the original payload so the gun local can finish its
                -- cooldown/reset logic instead of getting stuck after one shot.
                local result
                if redirectOk then
                    local sendOk, sendResult = pcall(oldNamecall, self, table.unpack(sendArgs))
                    if not sendOk then
                        return oldNamecall(self, ...)
                    end
                    result = sendResult
                    if ZeehoodTracer then
                        pcall(ZeehoodTracer.renderPayload, args[2].StartPoint, sendArgs[2])
                    end
                    for _ = 2, tapCount do
                        pcall(oldNamecall, self, table.unpack(sendArgs))
                        if ZeehoodTracer then
                            pcall(ZeehoodTracer.renderPayload, args[2].StartPoint, sendArgs[2])
                        end
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
    if mt.__namecall ~= hookedNamecall then mt.__namecall = hookedNamecall end
    setReadOnlySafe(true)
end

local function uninstall()
    if GH.shoot == hookedShoot then GH.shoot = oldShoot end
    safeCall(function()
        setReadOnlySafe(false)
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
    isStoredShootArgsValid = deps.isStoredShootArgsValid
    Taps                   = deps.Taps
    SilentAim              = deps.SilentAim
    ZeehoodTracer          = deps.ZeehoodTracer
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
