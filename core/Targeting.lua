local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")
local LP      = Players.LocalPlayer

local Settings, settings, State, Camera
local Features, ForceHit, TargetCard, ClosestPoint
local getPathValue, isTargetFeatureAllowed, hideUI, resolveLockPartForCharacter

local deathCheckConn = nil
local DEATH_CHECK_HP_THRESHOLD = 9

local RayParams = RaycastParams.new()
RayParams.FilterType  = Enum.RaycastFilterType.Exclude
RayParams.IgnoreWater = true

local function cfgEnabled(pathArr, defaultIfMissing)
    if not getPathValue then return defaultIfMissing end
    local v = getPathValue(settings, pathArr)
    if v == nil then return defaultIfMissing end
    return v == true
end

local function isAutoMode()
    local sys = string.lower(tostring(Settings.SelectionSystem or "target"))
    return sys == "auto"
end

local function isAlive(character)
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0
end

local function isDeathCheckState(character)
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0 and hum.Health <= DEATH_CHECK_HP_THRESHOLD
end

local function raycastVisible(part, targetCharacter)
    Camera = workspace.CurrentCamera
    if not part or not Camera then return false end
    local origin = Camera.CFrame.Position
    local direction = part.Position - origin
    RayParams.FilterDescendantsInstances = { LP.Character }
    local result = workspace:Raycast(origin, direction, RayParams)
    if not result then return true end
    return targetCharacter and result.Instance:IsDescendantOf(targetCharacter) or false
end

local function isPartVisible(part, targetCharacter)
    if not part then return false end
    if not Settings.VisCheck then return true end
    return raycastVisible(part, targetCharacter)
end

local function isPartVisibleRaw(part, targetCharacter)
    return raycastVisible(part, targetCharacter)
end

local function getTargetPartForPlayer(player)
    if not player then return nil, nil end
    local char = player.Character
    if not char or not isAlive(char) then return nil, nil end
    local part = resolveLockPartForCharacter(char)
    return part, char
end

local function getClosestPlayerFiltered(opts)
    Camera = workspace.CurrentCamera
    if not Camera then return nil, nil end

    local mousePos = UIS:GetMouseLocation()
    local bestPart, bestPlayer, bestDistSq = nil, nil, math.huge

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and plr.Character and isAlive(plr.Character) then
            if not opts.deathCheck or (not Settings.DeathCheck) or opts.passesDeathCheckRetargetThreshold(plr.Character) then
                local part = resolveLockPartForCharacter(plr.Character)
                if part and (not opts.distanceFilter or opts.distanceFilter(part)) then
                    local passesVis = true
                    if opts.visCheck then
                        passesVis = opts.visCheck(part, plr.Character)
                    end
                    if passesVis then
                        local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                        if onScreen and screenPos.Z > 0 then
                            local dx = screenPos.X - mousePos.X
                            local dy = screenPos.Y - mousePos.Y
                            local distSq = dx * dx + dy * dy
                            if distSq < bestDistSq then
                                bestDistSq = distSq
                                bestPart = part
                                bestPlayer = plr
                            end
                        end
                    end
                end
            end
        end
    end

    return bestPart, bestPlayer
end

local function clearDeathCheckConn()
    if deathCheckConn then
        pcall(function() deathCheckConn:Disconnect() end)
        deathCheckConn = nil
    end
end

local function clearTargetState(clearLastArgs)
    clearDeathCheckConn()
    State.LockedTarget = nil
    State.CurrentPart = nil
    State.FakePart = nil
    State.FakePos = nil
    State.TriggerbotPart = nil
    State.TriggerbotPos = nil
    State.TriggerbotAimExpires = 0
    State.TriggerbotToggleActive = false
    ClosestPoint.resetCache()
    if clearLastArgs then State.LastShootArgs = nil end
end

local function clearCombatState(keepLastArgs)
    State.FakePart = nil
    State.FakePos = nil
    State.CurrentPart = nil
    State.TriggerbotPart = nil
    State.TriggerbotPos = nil
    State.TriggerbotAimExpires = 0
    if not keepLastArgs then State.LastShootArgs = nil end
end

local function passesDeathCheckRetargetThreshold(character)
    if not Settings.DeathCheck then return true end
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > DEATH_CHECK_HP_THRESHOLD
end

local function hasValidLockedTarget()
    if not State.LockedTarget or State.LockedTarget.Parent ~= Players then return false end
    local char = State.LockedTarget.Character
    if not char then return false end
    if Settings.DeathCheck and not passesDeathCheckRetargetThreshold(char) then return false end
    local part = getTargetPartForPlayer(State.LockedTarget)
    return part ~= nil
end

local function enforceDeathCheckOnCurrentLock()
    if not Settings.DeathCheck then return end
    local lockedTarget = State.LockedTarget
    if not lockedTarget or lockedTarget.Parent ~= Players then return end
    local char = lockedTarget.Character
    if not char or not isDeathCheckState(char) then return end

    State.Enabled = false
    clearTargetState(true)
    ForceHit.onTargetChanged(false)
    hideUI()
    TargetCard.bumpToggleId()
    TargetCard.hideCard()
end

local function getClosestPlayerAndPart()
    return getClosestPlayerFiltered({
        deathCheck = true,
        visCheck = Settings.VisCheck and isPartVisible or nil,
        passesDeathCheckRetargetThreshold = passesDeathCheckRetargetThreshold,
    })
end

local function getClosestTriggerbotPart()
    if not Settings.TriggerbotEnabled then return nil end
    return getClosestPlayerFiltered({
        deathCheck = false,
        distanceFilter = Features.isPartInTriggerDistance,
        visCheck = Settings.TriggerbotVisCheck and isPartVisibleRaw or nil,
        passesDeathCheckRetargetThreshold = passesDeathCheckRetargetThreshold,
    })
end

local function getClosestCamlockPart()
    if not Settings.CamlockEnabled then return nil end
    return getClosestPlayerFiltered({
        deathCheck = true,
        distanceFilter = Features.isPartInCamlockDistance,
        visCheck = Settings.VisCheck and isPartVisible or nil,
        passesDeathCheckRetargetThreshold = passesDeathCheckRetargetThreshold,
    })
end

local function lockClosestTarget()
    local prevTarget = State.LockedTarget
    local _, plr = getClosestPlayerAndPart()
    if plr then
        if prevTarget ~= plr then
            ClosestPoint.resetCache()
            clearDeathCheckConn()
        end
        State.LockedTarget = plr
        State.CurrentPart = nil
        if prevTarget ~= plr or not TargetCard.getToggleId() then
            TargetCard.bumpToggleId()
            if cfgEnabled({"Main", "Target Card"}, true) then
                TargetCard.showCardForTarget(plr)
            end
        end
        return true
    end

    if isAutoMode() and State.LockedTarget then
        local char = State.LockedTarget.Character
        if State.LockedTarget.Parent == Players and char and isAlive(char) then
            return true
        end
    end

    clearDeathCheckConn()
    State.LockedTarget = nil
    State.CurrentPart = nil
    State.TriggerbotToggleActive = false
    TargetCard.bumpToggleId()
    TargetCard.hideCard()
    return false
end

local function resolveCurrentPartFromLinePart(linePart)
    if not linePart then return nil end
    if not Settings.VisCheck then return linePart end
    local lockedCharacter = State.LockedTarget and State.LockedTarget.Character or nil
    if not lockedCharacter or not isAlive(lockedCharacter) then return nil end
    return isPartVisible(linePart, lockedCharacter) and linePart or nil
end

local function ensureValidLockedTarget()
    if not State.LockedTarget then
        State.CurrentPart = nil
        return nil, nil
    end

    if State.LockedTarget.Parent ~= Players then
        ForceHit.onTargetChanged(false)
        clearTargetState(true)
        TargetCard.bumpToggleId()
        TargetCard.hideCard()
        return nil, nil
    end

    local char = State.LockedTarget.Character
    if not char then
        State.CurrentPart = nil
        hideUI()
        ForceHit.onTargetChanged(false)
        if not Settings.PersistLockOnDeath then
            clearTargetState(true)
            TargetCard.bumpToggleId()
            TargetCard.hideCard()
        end
        return nil, nil
    end

    if Settings.DeathCheck and isDeathCheckState(char) then
        State.CurrentPart = nil
        hideUI()
        State.Enabled = false
        ForceHit.onTargetChanged(false)
        clearTargetState(true)
        TargetCard.bumpToggleId()
        TargetCard.hideCard()
        return nil, nil
    end

    local part, lockedChar = getTargetPartForPlayer(State.LockedTarget)
    if not part then
        State.CurrentPart = nil
        hideUI()
        ForceHit.onTargetChanged(false)
        if not Settings.PersistLockOnDeath then
            clearTargetState(true)
            TargetCard.bumpToggleId()
            TargetCard.hideCard()
        end
        return nil, nil
    end

    return part, lockedChar
end

local function tryRetarget(force)
    if not isAutoMode() and not State.Enabled then return false end
    if not isTargetFeatureAllowed() then return false end

    local now = os.clock()
    local retargetInterval = Settings.RetargetInterval or 0.15
    if not force and (now - State.LastRetarget) < retargetInterval then return false end
    State.LastRetarget = now
    return lockClosestTarget()
end

local function init(deps)
    Settings                     = deps.Settings
    settings                     = deps.settings
    State                        = deps.State
    Camera                       = deps.Camera
    Features                     = deps.Features
    ForceHit                     = deps.ForceHit
    TargetCard                   = deps.TargetCard
    ClosestPoint                 = deps.ClosestPoint
    getPathValue                 = deps.getPathValue
    isTargetFeatureAllowed       = deps.isTargetFeatureAllowed
    hideUI                       = deps.hideUI
    resolveLockPartForCharacter  = deps.resolveLockPartForCharacter
end

return {
    init                         = init,
    clearDeathCheckConn          = clearDeathCheckConn,
    clearTargetState             = clearTargetState,
    clearCombatState             = clearCombatState,
    hasValidLockedTarget         = hasValidLockedTarget,
    enforceDeathCheckOnCurrentLock = enforceDeathCheckOnCurrentLock,
    getClosestPlayerAndPart      = getClosestPlayerAndPart,
    getClosestTriggerbotPart     = getClosestTriggerbotPart,
    getClosestCamlockPart        = getClosestCamlockPart,
    lockClosestTarget            = lockClosestTarget,
    resolveCurrentPartFromLinePart = resolveCurrentPartFromLinePart,
    ensureValidLockedTarget      = ensureValidLockedTarget,
    tryRetarget                  = tryRetarget,
}
