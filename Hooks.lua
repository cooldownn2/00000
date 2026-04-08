local State, Settings, safeCall
local GH, MainEvent, oldShoot, mt, oldNamecall
local cloneArgs, applyRangePolicy, getSpreadAimPosition
local isTargetFeatureAllowed, isStoredShootArgsValid
local hookedShoot, hookedNamecall

local function setReadOnlySafe(value)
    if setreadonly then setreadonly(mt, value) end
end

local function buildShootHook()
    hookedShoot = function(data)
        if State.Unloaded then return oldShoot(data) end
        local shootData = data
        if type(data) == "table" then
            State.LastShootData = {}
            for k, v in pairs(data) do State.LastShootData[k] = v end
            if isTargetFeatureAllowed() then
                local aimPos, hitPart
                if State.FakePart then
                    hitPart = State.FakePart
                    aimPos = State.FakePos or hitPart.Position
                elseif State.Enabled and State.CurrentPart then
                    local computedPos, aimPart = getSpreadAimPosition(State.CurrentPart)
                    hitPart = aimPart or State.CurrentPart
                    aimPos = computedPos
                end
                if hitPart and aimPos then
                    shootData = {}
                    for k, v in pairs(data) do shootData[k] = v end
                    shootData.AimPosition = aimPos
                    shootData.Hit         = hitPart
                    applyRangePolicy(shootData)
                    State.FakePart = hitPart
                    State.FakePos  = aimPos
                end
            end
        end
        return oldShoot(shootData)
    end
end

local function getTapCount(args)
    local taps = Settings.Taps
    if type(taps) ~= "table" then return 1 end
    local handle = args[2]
    if not handle or not handle.Parent then return 1 end
    local toolName = handle.Parent.Name
    local entry = taps[toolName]
    if type(entry) ~= "table" then return 1 end
    if not entry["Enabled"] then return 1 end
    local value = tonumber(entry["Value"])
    if not value or value < 2 then return 1 end
    return math.floor(value)
end

local function buildNamecallHook()
    hookedNamecall = function(self, ...)
        if State.Unloaded then return oldNamecall(self, ...) end
        if getnamecallmethod() == "FireServer" and rawequal(self, MainEvent) then
            if State.SkipNextFireServer then
                State.SkipNextFireServer = false
                return oldNamecall(self, ...)
            end
            local args = {...}
            if isStoredShootArgsValid(args) then
                State.LastShootArgs = cloneArgs(args)
            end
            if State.FakePart and isStoredShootArgsValid(args) and isTargetFeatureAllowed() then
                local headPos = State.FakePos or State.FakePart.Position
                args[3] = headPos
                args[4] = State.FakePart; args[6] = headPos
                State.FakePart, State.FakePos = nil, nil
                local result = oldNamecall(self, table.unpack(args))
                local extra = getTapCount(args) - 1
                for _ = 1, extra do
                    State.SkipNextFireServer = true
                    oldNamecall(self, table.unpack(args))
                end
                return result
            end
            if isStoredShootArgsValid(args) then
                local result = oldNamecall(self, ...)
                local extra = getTapCount(args) - 1
                for _ = 1, extra do
                    State.SkipNextFireServer = true
                    oldNamecall(self, table.unpack(args))
                end
                return result
            end
        end
        return oldNamecall(self, ...)
    end
end

local function install()
    buildShootHook()
    buildNamecallHook()
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
end

return {
    init      = init,
    install   = install,
    uninstall = uninstall,
    getHookedShoot    = function() return hookedShoot end,
    getHookedNamecall = function() return hookedNamecall end,
}
