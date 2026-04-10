local State, safeCall
local GH, MainEvent, oldShoot, mt, oldNamecall, oldIndex
local isStoredShootArgsValid
local Taps
local SilentAim
local ForceHit
local Settings
local LP, UIS, Mouse
local hookedShoot, hookedNamecall, hookedIndex
local gameStyle
local random = math.random
local HUGE = math.huge

local MOUSE1 = Enum.UserInputType.MouseButton1
local ASSIST_MIN_INTERVAL = 0.05
local TAP_TIME_STEP = 1 / 120
local TAP_TIME_JITTER = 0.0005
local _lastAssistSendAt = 0

local function isFiniteNumber(value)
    return type(value) == "number" and value == value and value > -HUGE and value < HUGE
end

local function isVector3(value)
    return typeof(value) == "Vector3"
end

local function isValidHitInstance(value)
    return typeof(value) == "Instance" and value.Parent ~= nil
end

local function cloneArray(arr)
    if table.clone then return table.clone(arr) end
    local out = {}
    for i = 1, #arr do
        out[i] = arr[i]
    end
    return out
end

local function clonePayload(payload)
    local copy = {}
    for k, v in pairs(payload) do
        if k == "Pellets" and type(v) == "table" then
            local pellets = table.create and table.create(#v) or {}
            for i = 1, #v do
                local p = v[i]
                if type(p) == "table" then
                    pellets[i] = {
                        HitPosition = p.HitPosition,
                        HitInstance = p.HitInstance,
                    }
                else
                    pellets[i] = p
                end
            end
            copy[k] = pellets
        else
            copy[k] = v
        end
    end
    return copy
end

local function getFreshTimestamp(burstIndex)
    local ok, serverNow = pcall(workspace.GetServerTimeNow, workspace)
    local base = (ok and type(serverNow) == "number") and serverNow or os.clock()
    local idx = tonumber(burstIndex) or 0
    return base + (idx * TAP_TIME_STEP) + ((random() - 0.5) * TAP_TIME_JITTER)
end

local function normalizeZeehoodPayload(payload, burstIndex, forceFreshTimestamp)
    if type(payload) ~= "table" then return nil end
    if type(payload.ToolName) ~= "string" or payload.ToolName == "" then return nil end

    local out = clonePayload(payload)
    local fallbackPos = isVector3(out.HitPosition) and out.HitPosition or nil
    local fallbackHit = isValidHitInstance(out.HitInstance) and out.HitInstance or nil

    if type(out.Pellets) == "table" then
        local foundPelletPos = nil
        local foundPelletHit = nil
        for i, pellet in ipairs(out.Pellets) do
            if type(pellet) == "table" then
                local hitPos = isVector3(pellet.HitPosition) and pellet.HitPosition or fallbackPos
                local hitInst = isValidHitInstance(pellet.HitInstance) and pellet.HitInstance or fallbackHit
                if hitPos then
                    pellet.HitPosition = hitPos
                    pellet.HitInstance = hitInst
                    if not foundPelletPos then foundPelletPos = hitPos end
                    if not foundPelletHit and hitInst then foundPelletHit = hitInst end
                elseif foundPelletPos then
                    pellet.HitPosition = foundPelletPos
                    pellet.HitInstance = foundPelletHit
                else
                    return nil
                end
            end
        end
        if not fallbackPos then fallbackPos = foundPelletPos end
        if not fallbackHit then fallbackHit = foundPelletHit end
        if not isVector3(out.HitPosition) then out.HitPosition = fallbackPos end
        if out.HitInstance ~= nil and not isValidHitInstance(out.HitInstance) then
            out.HitInstance = fallbackHit
        elseif out.HitInstance == nil then
            out.HitInstance = fallbackHit
        end
    else
        if not fallbackPos then return nil end
        out.HitPosition = fallbackPos
        if out.HitInstance ~= nil and not isValidHitInstance(out.HitInstance) then
            out.HitInstance = fallbackHit
        end
    end

    if not isVector3(out.StartPoint) then
        out.StartPoint = out.HitPosition
    end
    if not isVector3(out.StartPoint) then
        return nil
    end

    if forceFreshTimestamp or not isFiniteNumber(out.Timestamp) then
        out.Timestamp = getFreshTimestamp(burstIndex)
    end

    return out
end

local function buildZeehoodSendArgs(args, burstIndex, forceFreshTimestamp)
    if type(args) ~= "table" then return nil end
    local payload = args[2]
    local normalized = normalizeZeehoodPayload(payload, burstIndex, forceFreshTimestamp)
    if not normalized then return nil end

    local out = cloneArray(args)
    out[2] = normalized
    return out
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

        if method ~= "FireServer" or not rawequal(self, MainEvent) then
            return oldNamecall(self, ...)
        end

        local args = {...}

        if gameStyle == "zeehood" then
            -- Zeehood stability: strict native passthrough for manual shooting.
            if isStoredShootArgsValid(args) then
                local tapCount = 1
                pcall(function()
                    SilentAim.recordShootArgs(args)
                    tapCount = Taps.getTapCount(args)
                end)

                local baseArgs = buildZeehoodSendArgs(args, 0, false) or args
                local result = oldNamecall(self, table.unpack(baseArgs))
                for burstIndex = 1, tapCount - 1 do
                    local tapArgs = buildZeehoodSendArgs(args, burstIndex, true) or baseArgs
                    oldNamecall(self, table.unpack(tapArgs))
                end

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
