local SilentAim = {}

local State
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

local function prepareShootData(data)
    if type(data) ~= "table" then
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
    local redirectedAim = fakePos

    -- Preserve the original shot spread by keeping the same ray delta between
    -- the engine-provided hit point (arg[3]) and aim endpoint (arg[6]).
    -- This keeps silent aim active while honoring configured spread values.
    local originalHit = args[3]
    local originalAim = args[6]
    if typeof(originalHit) == "Vector3" and typeof(originalAim) == "Vector3" then
        redirectedAim = fakePos + (originalAim - originalHit)
    end

    args[3] = fakePos
    args[4] = fakePart
    if typeof(args[5]) == "Vector3" then
        args[5] = fakePos
    end
    args[6] = redirectedAim

    -- Clear immediately to prevent stale replay if follow-up calls fail.
    clearFakeState()

    return args
end

local function init(deps)
    State                  = deps.State
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
