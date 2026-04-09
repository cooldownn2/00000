local SilentAim = {}

local State
local LP
local cloneArgs
local applyRangePolicy
local getSpreadAimPosition
local isTargetFeatureAllowed
local isStoredShootArgsValid

local HUGE = math.huge

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

    local vecIndices = table.create(3)
    local vecCount = 0
    if typeof(args[3]) == "Vector3" then vecCount = vecCount + 1; vecIndices[vecCount] = 3 end
    if typeof(args[5]) == "Vector3" then vecCount = vecCount + 1; vecIndices[vecCount] = 5 end
    if typeof(args[6]) == "Vector3" then vecCount = vecCount + 1; vecIndices[vecCount] = 6 end

    -- Determine shooter position to detect origin/muzzle-like vectors.
    local shooterPos = nil
    local char = LP and LP.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if root then
        shooterPos = root.Position
    else
        local cam = workspace.CurrentCamera
        shooterPos = cam and cam.CFrame.Position or nil
    end

    if vecCount > 0 and shooterPos then
        local distSqByIdx = {}
        local minDistSq = HUGE
        local anchorIndex = nil
        local anchorDistSq = -1

        for i = 1, vecCount do
            local idx = vecIndices[i]
            local v = args[idx]
            local d = v - shooterPos
            local d2 = d.X * d.X + d.Y * d.Y + d.Z * d.Z
            distSqByIdx[idx] = d2
            if d2 < minDistSq then
                minDistSq = d2
            end
        end

        -- Any vector close to the nearest shooter vector is treated as origin-like.
        local ORIGIN_BAND_SQ = 6 * 6
        local originBandMax = minDistSq + ORIGIN_BAND_SQ

        for i = 1, vecCount do
            local idx = vecIndices[i]
            local d2 = distSqByIdx[idx]
            if d2 > originBandMax and d2 > anchorDistSq then
                anchorDistSq = d2
                anchorIndex = idx
            end
        end

        if anchorIndex then
            local delta = fakePos - args[anchorIndex]
            for i = 1, vecCount do
                local idx = vecIndices[i]
                if distSqByIdx[idx] > originBandMax then
                    args[idx] = args[idx] + delta
                end
            end
        else
            -- All vectors looked origin-like; fallback to direct redirect.
            for i = 1, vecCount do
                local idx = vecIndices[i]
                args[idx] = fakePos
            end
        end
    elseif vecCount > 0 then
        -- No shooter reference available; fallback to direct redirect.
        for i = 1, vecCount do
            local idx = vecIndices[i]
            args[idx] = fakePos
        end
    end

    args[4] = fakePart

    -- Clear immediately to prevent stale replay if follow-up calls fail.
    clearFakeState()

    return args
end

local function init(deps)
    State                  = deps.State
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
