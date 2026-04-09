local SilentAim = {}

local State
local Settings
local LP
local cloneArgs
local applyRangePolicy
local getSpreadAimPosition
local isTargetFeatureAllowed
local isStoredShootArgsValid

-- Reused table for redirected GH.shoot payload.
local _shootData = {}

local function clearFakeState()
    State.FakePart = nil
    State.FakePos  = nil
end

-- When spread modifier is explicitly set to full/default spread (1.0) for the
-- equipped tool, skip silent redirect so shot behavior matches native spread.
local function shouldPreserveNativeSpread()
    local sm = Settings and Settings.SpreadMod
    if type(sm) ~= "table" then return false end
    if sm["Enabled"] == false then return false end

    local char = LP and LP.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    if not tool then return false end

    local v = sm[tool.Name]
    if type(v) ~= "number" then return false end
    return math.clamp(v, 0, 1) >= 0.999
end

local function prepareShootData(data)
    if type(data) ~= "table" then
        return data
    end

    if shouldPreserveNativeSpread() then
        clearFakeState()
        return data
    end

    if not isTargetFeatureAllowed() then
        clearFakeState()
        return data
    end

    local hitPart, aimPos

    if State.FakePart then
        hitPart = State.FakePart
        aimPos  = State.FakePos or hitPart.Position
    elseif State.Enabled and State.CurrentPart then
        local computedPos, aimPart = getSpreadAimPosition(State.CurrentPart)
        hitPart = aimPart or State.CurrentPart
        aimPos  = computedPos
    end

    if not hitPart or not aimPos then
        clearFakeState()
        return data
    end

    for k in pairs(_shootData) do _shootData[k] = nil end
    for k, v in pairs(data) do _shootData[k] = v end

    _shootData.AimPosition = aimPos
    _shootData.Hit         = hitPart

    applyRangePolicy(_shootData)

    State.FakePart = hitPart
    State.FakePos  = aimPos

    return _shootData
end

local function recordShootArgs(args)
    if isStoredShootArgsValid(args) then
        State.LastShootArgs = cloneArgs(args)
    end
end

local function shouldRedirectFireServer(args)
    return State.FakePart and isStoredShootArgsValid(args) and isTargetFeatureAllowed()
end

local function applyFireServerRedirect(args)
    local fakePart = State.FakePart
    if not fakePart then return args end

    local fakePos = State.FakePos or fakePart.Position
    args[3] = fakePos
    args[4] = fakePart
    args[6] = fakePos

    -- Clear immediately to prevent stale replay if follow-up calls fail.
    clearFakeState()

    return args
end

local function init(deps)
    State                  = deps.State
    Settings               = deps.Settings
    LP                     = deps.LP
    cloneArgs              = deps.cloneArgs
    applyRangePolicy       = deps.applyRangePolicy
    getSpreadAimPosition   = deps.getSpreadAimPosition
    isTargetFeatureAllowed = deps.isTargetFeatureAllowed
    isStoredShootArgsValid = deps.isStoredShootArgsValid
end

SilentAim.init = init
SilentAim.prepareShootData = prepareShootData
SilentAim.recordShootArgs = recordShootArgs
SilentAim.shouldRedirectFireServer = shouldRedirectFireServer
SilentAim.applyFireServerRedirect = applyFireServerRedirect

return SilentAim
