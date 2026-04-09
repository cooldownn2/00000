local SilentAim = {}

local State
local cloneArgs
local applyRangePolicy
local getSpreadAimPosition
local isTargetFeatureAllowed
local isStoredShootArgsValid

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

    -- Important: do NOT overwrite GH.shoot AimPosition/Hit here.
    -- That would collapse native spread while a target is locked.
    -- We only stage redirect data for the FireServer hook below.
    applyRangePolicy(data)

    State.FakePart = hitPart
    State.FakePos  = aimPos

    return data
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

    -- Preserve spread by translating the original shot packet vectors together
    -- so their relative offsets remain unchanged.
    local anchor = nil
    if typeof(args[5]) == "Vector3" then
        anchor = args[5]
    elseif typeof(args[3]) == "Vector3" then
        anchor = args[3]
    end

    local delta = nil
    if anchor then
        delta = fakePos - anchor
    end

    if delta then
        if typeof(args[3]) == "Vector3" then args[3] = args[3] + delta end
        if typeof(args[5]) == "Vector3" then args[5] = args[5] + delta end
        if typeof(args[6]) == "Vector3" then args[6] = args[6] + delta end
    else
        -- Fallback safety: if packet shape is unexpected, still redirect.
        if typeof(args[3]) == "Vector3" then args[3] = fakePos end
        if typeof(args[5]) == "Vector3" then args[5] = fakePos end
        if typeof(args[6]) == "Vector3" then args[6] = fakePos end
    end

    args[4] = fakePart

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
