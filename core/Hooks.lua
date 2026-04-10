local State, safeCall
local GH, MainEvent, oldShoot, mt, oldNamecall, oldIndex
local isStoredShootArgsValid
local Taps
local SilentAim
local ForceHit
local RemoteProbe
local Settings
local LP, UIS, Mouse
local hookedShoot, hookedNamecall, hookedIndex
local gameStyle

local MOUSE1 = Enum.UserInputType.MouseButton1
local ASSIST_MIN_INTERVAL = 0.05
local _lastAssistSendAt = 0
local INF_AMMO_RELOAD_INTERVAL = 0.2
local _lastInfAmmoReloadAt = 0
local _infAmmoShotsByTool = {}

local INF_AMMO_CLIPS = {
    ["[Revolver]"] = 6,
    ["[Double-Barrel SG]"] = 2,
    ["[TacticalShotgun]"] = 5,
    ["[Shotgun]"] = 5,
    ["[Drum-Shotgun]"] = 8,
    ["[SMG]"] = 25,
    ["[AR]"] = 30,
}

local function getInfAmmoClip(toolName)
    return INF_AMMO_CLIPS[toolName] or 12
end

local function setReadOnlySafe(value)
    if setreadonly then setreadonly(mt, value) end
end

local function trySendZeehoodWallbangAssist()
    if gameStyle ~= "zeehood" then return end
    if not Settings or Settings.VisCheck == true then return end
    if not ForceHit or not ForceHit.sendAssistShot then return end

    local blocked = false
    pcall(function()
        if SilentAim.shouldUseZeehoodAssistShot then
            blocked = (SilentAim.shouldUseZeehoodAssistShot() == true)
        end
    end)
    if not blocked then return end

    local now = os.clock()
    if now - _lastAssistSendAt < ASSIST_MIN_INTERVAL then return end
    _lastAssistSendAt = now

    -- Defer so native gun local flow finishes first.
    task.defer(function()
        pcall(ForceHit.sendAssistShot)
    end)
end

local function trySendZeehoodInfAmmoReload(toolName, shotCount)
    if gameStyle ~= "zeehood" then return end
    if not Settings or Settings.InfiniteAmmo ~= true then return end
    if type(toolName) ~= "string" then return end

    local count = tonumber(shotCount) or 1
    if count < 1 then count = 1 end

    local nextCount = (_infAmmoShotsByTool[toolName] or 0) + count
    _infAmmoShotsByTool[toolName] = nextCount

    local clip = getInfAmmoClip(toolName)
    if nextCount <= clip then return end

    local char = LP and LP.Character
    local be = char and char:FindFirstChild("BodyEffects")
    local reloadFlag = be and (be:FindFirstChild("Reload") or be:FindFirstChild("Reloading"))
    if reloadFlag and reloadFlag.Value == true then return end

    local now = os.clock()
    if now - _lastInfAmmoReloadAt < INF_AMMO_RELOAD_INTERVAL then return end
    _lastInfAmmoReloadAt = now
    _infAmmoShotsByTool[toolName] = 0

    task.defer(function()
        pcall(oldNamecall, MainEvent, "Reload")
    end)
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

        local method = getnamecallmethod()
        if method == "FireServer" and RemoteProbe and RemoteProbe.observeNamecall then
            local probeArgs = {...}
            pcall(RemoteProbe.observeNamecall, self, method, probeArgs)
        end

        if method ~= "FireServer" or not rawequal(self, MainEvent) then
            return oldNamecall(self, ...)
        end

        local args = {...}

        if gameStyle == "zeehood" then
            -- Zeehood stability: strict native passthrough for manual shooting.
            if isStoredShootArgsValid(args) then
                local tapCount = 1
                local toolName
                pcall(function()
                    SilentAim.recordShootArgs(args)
                    tapCount = Taps.getTapCount(args)
                    local payload = args[2]
                    if type(payload) == "table" then
                        toolName = payload.ToolName
                    end
                end)

                local result = oldNamecall(self, ...)
                for _ = 2, tapCount do
                    oldNamecall(self, ...)
                end

                trySendZeehoodInfAmmoReload(toolName, tapCount)
                trySendZeehoodWallbangAssist()
                return result
            end
            return oldNamecall(self, ...)
        end

        -- Dashood / positional-args style.
        SilentAim.recordShootArgs(args)
        if SilentAim.shouldRedirectFireServer(args) then
            SilentAim.applyFireServerRedirect(args)
            local result = oldNamecall(self, table.unpack(args))
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
    ForceHit               = deps.ForceHit
    RemoteProbe            = deps.RemoteProbe
    Settings               = deps.Settings
    LP                     = deps.LP
    UIS                    = deps.UIS
    Mouse                  = LP and LP:GetMouse() or nil
    gameStyle              = deps.gameStyle
    SilentAim.init(deps)
    buildHooks()
end

return {
    init      = init,
    install   = install,
    uninstall = uninstall,
}
