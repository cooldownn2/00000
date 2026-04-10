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

local function isClosestPointMode()
    local mode = string.lower(tostring(Settings.TargetPart or ""))
    return mode == "closest point" or mode == "closestpoint"
end

local function resolveZeehoodSafePart(part)
    if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
        return nil
    end

    local char = part.Parent
    if typeof(char) ~= "Instance" then
        return part
    end

    return char:FindFirstChild("Head")
        or char:FindFirstChild("UpperTorso")
        or char:FindFirstChild("Torso")
        or char:FindFirstChild("LowerTorso")
        or char:FindFirstChild("HumanoidRootPart")
        or part
end

local function isZeehoodAssistEnabled()
    return gameStyle == "zeehood" and (Settings.InfiniteRange or Settings.Wallbang)
end

local function applyZeehoodRangeAndOrigin(payload, aimPos)
    if Settings.InfiniteRange then
        payload.Range = 1e9
    end

    if Settings.Wallbang then
        -- ForceHit-style wallbang: spawn the redirected assist shot at the
        -- target so world geometry between shooter and target is bypassed.
        payload.StartPoint = aimPos
    end
end

local function resolveAimTarget()
    if not isTargetFeatureAllowed() then
        return nil, nil
    end

    local hitPart, aimPos

    local function isValidPart(part)
        return typeof(part) == "Instance" and part:IsA("BasePart") and part.Parent ~= nil
    end

    local function isValidVec3(v)
        return typeof(v) == "Vector3"
    end

    if gameStyle == "zeehood" and State.FakePart then
        if isValidPart(State.FakePart) then
            hitPart = State.FakePart
            aimPos  = isValidVec3(State.FakePos) and State.FakePos or hitPart.Position
        end
    elseif State.Enabled and State.CurrentPart then
        local ok, computedPos, aimPart = pcall(getSpreadAimPosition, State.CurrentPart)
        if ok then
            local candidatePart = aimPart or State.CurrentPart
            if isValidPart(candidatePart) and isValidVec3(computedPos) then
                hitPart = candidatePart
                aimPos  = computedPos
            end
        end
    end

    if gameStyle == "zeehood" and isValidPart(hitPart) then
        -- Preserve true Closest Point behavior in Zeehood. Only coerce to a
        -- safe fallback part when not using Closest Point mode.
        if isClosestPointMode() then
            if not isValidVec3(aimPos) then
                aimPos = hitPart.Position
            end
        else
            local safePart = resolveZeehoodSafePart(hitPart)
            if not isValidPart(safePart) then
                return nil, nil
            end
            hitPart = safePart
            if not isValidVec3(aimPos) then
                aimPos = safePart.Position
            end
        end
    end

    if not isValidPart(hitPart) or not isValidVec3(aimPos) then
        return nil, nil
    end

    return hitPart, aimPos
end

local function prepareShootData(data)
    if type(data) ~= "table" then
        return data
    end

    if not isTargetFeatureAllowed() then
        clearFakeState()
        return data
    end

    local hitPart, aimPos = resolveAimTarget()

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
    if not (State.FakePart and isStoredShootArgsValid(args) and isTargetFeatureAllowed()) then
        return false
    end

    -- Dashood: when wallbang is disabled, never allow stale fake state to
    -- redirect through walls. CurrentPart is only set when visibility passes.
    if gameStyle ~= "zeehood" and Settings.Wallbang ~= true and not State.CurrentPart then
        clearFakeState()
        return false
    end

    return true
end

local function applyFireServerRedirect(args)
    local fakePart = State.FakePart
    if not fakePart then return args end

    local fakePos = State.FakePos or fakePart.Position
    if Settings.InfiniteRange or Settings.Wallbang then
        args[3] = fakePos
    end
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
    if not isTargetFeatureAllowed() then return false end
    if not payload or type(payload) ~= "table" then return false end
    if not isZeehoodAssistEnabled() then return false end

    local hitPart, aimPos = resolveAimTarget()

    if not hitPart or not aimPos then return false end

    applyZeehoodRangeAndOrigin(payload, aimPos)

    if type(payload.Pellets) == "table" then
        if Settings.Wallbang then
            for _, p in ipairs(payload.Pellets) do
                if type(p) == "table" then
                    p.HitPosition = aimPos
                    p.HitInstance = hitPart
                end
            end
        else
            -- Preserve the original pellet spread shape by translating the
            -- existing pellet pattern so its center lands on the locked aim point.
            local center = Vector3.new(0, 0, 0)
            local count = 0

            for _, p in ipairs(payload.Pellets) do
                if type(p) == "table" and typeof(p.HitPosition) == "Vector3" then
                    center = center + p.HitPosition
                    count = count + 1
                end
            end

            if count > 0 then
                center = center / count
                for _, p in ipairs(payload.Pellets) do
                    if type(p) == "table" then
                        local origPos = typeof(p.HitPosition) == "Vector3" and p.HitPosition or center
                        local spreadOffset = origPos - center
                        p.HitPosition = aimPos + spreadOffset
                        p.HitInstance = hitPart
                    end
                end
            else
                for _, p in ipairs(payload.Pellets) do
                    if type(p) == "table" then
                        p.HitPosition = aimPos
                        p.HitInstance = hitPart
                    end
                end
            end
        end
        -- Some Zeehood handlers use top-level fields for visuals even when
        -- pellet data exists; mirror them here for tracer compatibility.
        payload.HitPosition = aimPos
        payload.HitInstance = hitPart
    else
        payload.HitPosition = aimPos
        payload.HitInstance = hitPart
    end

    return true
end

local function getCurrentAimPosition()
    local ok, _, aimPos = pcall(resolveAimTarget)
    if not ok then
        return nil
    end
    return typeof(aimPos) == "Vector3" and aimPos or nil
end

local function getCurrentMouseHitPosition()
    local function isValidPart(part)
        return typeof(part) == "Instance" and part:IsA("BasePart") and part.Parent ~= nil
    end

    if not isTargetFeatureAllowed() then
        return nil
    end

    if isValidPart(State.FakePart) then
        if typeof(State.FakePos) == "Vector3" then
            return State.FakePos
        end
        return State.FakePart.Position
    end

    local current = State.CurrentPart
    if not isValidPart(current) then
        return nil
    end

    if gameStyle == "zeehood" then
        if isClosestPointMode() then
            local ok, closestPos = pcall(getSpreadAimPosition, current)
            if ok and typeof(closestPos) == "Vector3" then
                return closestPos
            end
        end

        local safePart = resolveZeehoodSafePart(current)
        if isValidPart(safePart) then
            return safePart.Position
        end
    end

    return current.Position
end

local function shouldSendZeehoodAssistShot()
    return isTargetFeatureAllowed() and isZeehoodAssistEnabled()
end

SilentAim.init                   = init
SilentAim.redirectZeehoodPayload = redirectZeehoodPayload
SilentAim.getCurrentAimPosition  = getCurrentAimPosition
SilentAim.getCurrentMouseHitPosition = getCurrentMouseHitPosition
SilentAim.shouldSendZeehoodAssistShot = shouldSendZeehoodAssistShot
SilentAim.clearRedirectState = clearFakeState
SilentAim.prepareShootData = prepareShootData
SilentAim.recordShootArgs = recordShootArgs
SilentAim.shouldRedirectFireServer = shouldRedirectFireServer
SilentAim.applyFireServerRedirect = applyFireServerRedirect

return SilentAim
