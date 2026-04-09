local SilentAim = {}

local State
local Settings
local cloneArgs
local applyRangePolicy
local getSpreadAimPosition
local isTargetFeatureAllowed
local isStoredShootArgsValid
local gameStyle

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
    cloneArgs              = deps.cloneArgs
    applyRangePolicy       = deps.applyRangePolicy
    getSpreadAimPosition   = deps.getSpreadAimPosition
    isTargetFeatureAllowed = deps.isTargetFeatureAllowed
    isStoredShootArgsValid = deps.isStoredShootArgsValid
    gameStyle              = deps.gameStyle
end

-- Redirect a zeehood-style FireServer payload table in-place to aim at the
-- current locked target.  Called directly from the namecall hook because
-- Zeehood has no GH.shoot to serve as a redirect trigger.
local function redirectZeehoodPayload(payload)
    if not isTargetFeatureAllowed() then return end
    if not payload or type(payload) ~= "table" then return end

    local hitPart, aimPos

    if State.FakePart then
        hitPart = State.FakePart
        aimPos  = State.FakePos or hitPart.Position
    elseif State.Enabled and State.CurrentPart then
        local computedPos, aimPart = getSpreadAimPosition(State.CurrentPart)
        hitPart = aimPart or State.CurrentPart
        aimPos  = computedPos
    end

    if not hitPart or not aimPos then return end

    -- Zeehood payloads do not have a Range field. To support Infinite Range,
    -- spoof the server-visible StartPoint to the aimed position the same way
    -- ForceHit does for this profile.
    if Settings and Settings.InfiniteRange and payload.StartPoint then
        payload.StartPoint = aimPos
    end

    if type(payload.Pellets) == "table" then
        for _, p in ipairs(payload.Pellets) do
            p.HitPosition = aimPos
            p.HitInstance = hitPart
        end
    else
        payload.HitPosition = aimPos
        payload.HitInstance = hitPart
    end
end

SilentAim.init                   = init
SilentAim.redirectZeehoodPayload = redirectZeehoodPayload
SilentAim.prepareShootData = prepareShootData
SilentAim.recordShootArgs = recordShootArgs
SilentAim.shouldRedirectFireServer = shouldRedirectFireServer
SilentAim.applyFireServerRedirect = applyFireServerRedirect

return SilentAim
