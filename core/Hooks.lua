local State, Settings, safeCall
local GH, MainEvent, oldShoot, mt, oldNamecall
local cloneArgs, applyRangePolicy, getSpreadAimPosition
local isTargetFeatureAllowed, isStoredShootArgsValid
local Taps
local hookedShoot, hookedNamecall

-- Reusable shootData table — avoids a fresh allocation per shot when silent aim
-- redirects the aim position. Fields are overwritten before every use.
local _shootData = {}

local function setReadOnlySafe(value)
    if setreadonly then setreadonly(mt, value) end
end

local function buildHooks()
    hookedShoot = function(data)
        if State.Unloaded then return oldShoot(data) end
        local shootData = data
        if type(data) == "table" then
            if isTargetFeatureAllowed() then
                local aimPos, hitPart
                if State.FakePart then
                    -- FakePart already set by an earlier code path; use it directly.
                    -- Do NOT write FakePos back — it's already set or legitimately nil.
                    hitPart = State.FakePart
                    aimPos  = State.FakePos or hitPart.Position
                elseif State.Enabled and State.CurrentPart then
                    local computedPos, aimPart = getSpreadAimPosition(State.CurrentPart)
                    hitPart = aimPart or State.CurrentPart
                    aimPos  = computedPos
                end
                if hitPart and aimPos then
                    -- Wipe _shootData first so no stale keys from a previous shot bleed in,
                    -- then copy current data and override only the aim fields.
                    for k in pairs(_shootData) do _shootData[k] = nil end
                    for k, v in pairs(data) do _shootData[k] = v end
                    _shootData.AimPosition = aimPos
                    _shootData.Hit         = hitPart
                    applyRangePolicy(_shootData)
                    shootData = _shootData
                    -- Stage for the namecall hook; computed position is already stored.
                    State.FakePart = hitPart
                    State.FakePos  = aimPos
                else
                    -- Feature allowed but no valid aim target — clear any stale FakePart
                    -- so the namecall hook doesn't fire a redirect on the next shot.
                    State.FakePart = nil
                    State.FakePos  = nil
                end
            else
                -- Feature disabled mid-shot — clear stale state so nothing leaks.
                State.FakePart = nil
                State.FakePos  = nil
            end
        end
        return oldShoot(shootData)
    end

    hookedNamecall = function(self, ...)
        if State.Unloaded then return oldNamecall(self, ...) end
        -- Gate on method name and target BEFORE unpacking varargs into a table.
        -- __namecall fires for every : call game-wide; early exit avoids an
        -- allocation on the vast majority of calls that aren't FireServer on MainEvent.
        if getnamecallmethod() ~= "FireServer" or not rawequal(self, MainEvent) then
            return oldNamecall(self, ...)
        end
        local args = {...}
        if isStoredShootArgsValid(args) then
            State.LastShootArgs = cloneArgs(args)
        end
        if State.FakePart and isStoredShootArgsValid(args) and isTargetFeatureAllowed() then
            local headPos = State.FakePos or State.FakePart.Position
            args[3] = headPos
            args[4] = State.FakePart
            args[6] = headPos
            -- Clear before firing — prevents stale state if the tap loop errors
            State.FakePart = nil
            State.FakePos  = nil
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
    Settings               = deps.Settings
    safeCall               = deps.safeCall
    GH                     = deps.GH
    MainEvent              = deps.MainEvent
    oldShoot               = deps.oldShoot
    mt                     = deps.mt
    oldNamecall            = deps.oldNamecall
    cloneArgs              = deps.cloneArgs
    applyRangePolicy       = deps.applyRangePolicy
    getSpreadAimPosition   = deps.getSpreadAimPosition
    isTargetFeatureAllowed = deps.isTargetFeatureAllowed
    isStoredShootArgsValid = deps.isStoredShootArgsValid
    Taps                   = deps.Taps
    -- Build closures once here so install() just wires them in without re-allocating.
    buildHooks()
end

return {
    init      = init,
    install   = install,
    uninstall = uninstall,
    getHookedShoot    = function() return hookedShoot end,
    getHookedNamecall = function() return hookedNamecall end,
}
