local Targeting = {}

local Settings, State, Players, LP, UIS, Features, ClosestPoint, Spread
local getCamera

local DEATH_CHECK_HP_THRESHOLD = 9

local RayParams = RaycastParams.new()
RayParams.FilterType  = Enum.RaycastFilterType.Exclude
RayParams.IgnoreWater = true
local raycastFilter = {nil}

local function isAlive(character)
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0
end

local function isDeathCheckState(character)
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0 and hum.Health <= DEATH_CHECK_HP_THRESHOLD
end

local function passesDeathCheckRetargetThreshold(character)
    if not Settings.DeathCheck then return true end
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > DEATH_CHECK_HP_THRESHOLD
end

local function raycastVisible(part, targetCharacter)
    local camera = getCamera and getCamera() or workspace.CurrentCamera
    if not part or not camera then return false end

    local origin = camera.CFrame.Position
    local direction = part.Position - origin

    raycastFilter[1] = LP.Character
    RayParams.FilterDescendantsInstances = raycastFilter

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

local function resolveLockPartForCharacter(char)
    if Spread and Spread.resolveLockPartForCharacter then
        return Spread.resolveLockPartForCharacter(char)
    end
    return nil
end

local function getTargetPartForPlayer(player)
    if not player then return nil, nil end
    local char = player.Character
    if not char or not isAlive(char) then return nil, nil end
    local part = resolveLockPartForCharacter(char)
    return part, char
end

local function getClosestPlayerFiltered(opts)
    local camera = getCamera and getCamera() or workspace.CurrentCamera
    if not camera then return nil, nil end

    local mousePos = UIS:GetMouseLocation()
    local bestPart, bestPlayer, bestDistSq = nil, nil, math.huge

    local playerList = Players:GetPlayers()
    for i = 1, #playerList do
        local plr = playerList[i]
        if plr ~= LP then
            local char = plr.Character
            if char and isAlive(char) then
                if (not opts.deathCheck) or passesDeathCheckRetargetThreshold(char) then
                    local part = resolveLockPartForCharacter(char)
                    if part and (not opts.distanceFilter or opts.distanceFilter(part)) then
                        local passesVis = true
                        if opts.visCheck then
                            passesVis = opts.visCheck(part, char)
                        end
                        if passesVis then
                            local screenPos, onScreen = camera:WorldToViewportPoint(part.Position)
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
    end

    return bestPart, bestPlayer
end

local function getClosestPlayerAndPart()
    return getClosestPlayerFiltered({
        deathCheck = true,
        visCheck = Settings.VisCheck and isPartVisible or nil,
    })
end

local function getClosestTriggerbotPart()
    if not Settings.TriggerbotEnabled then return nil end
    return getClosestPlayerFiltered({
        deathCheck = false,
        distanceFilter = Features.isPartInTriggerDistance,
        visCheck = Settings.TriggerbotVisCheck and isPartVisibleRaw or nil,
    })
end

local function getClosestCamlockPart()
    if not Settings.CamlockEnabled then return nil end
    return getClosestPlayerFiltered({
        deathCheck = true,
        distanceFilter = Features.isPartInCamlockDistance,
        visCheck = Settings.VisCheck and isPartVisible or nil,
    })
end

local function hasValidLockedTarget()
    if not State.LockedTarget or State.LockedTarget.Parent ~= Players then return false end
    local char = State.LockedTarget.Character
    if not char then return false end
    if Settings.DeathCheck and not passesDeathCheckRetargetThreshold(char) then return false end
    local part = getTargetPartForPlayer(State.LockedTarget)
    return part ~= nil
end

local function resolveCurrentPartFromLinePart(linePart)
    if not linePart then return nil end
    if not Settings.VisCheck then return linePart end
    local lockedCharacter = State.LockedTarget and State.LockedTarget.Character or nil
    if not lockedCharacter or not isAlive(lockedCharacter) then return nil end
    return isPartVisible(linePart, lockedCharacter) and linePart or nil
end

local function clearTargetState(clearLastArgs)
    State.LockedTarget = nil
    State.CurrentPart = nil
    State.FakePart = nil
    State.FakePos = nil
    State.TriggerbotToggleActive = false
    if ClosestPoint and ClosestPoint.resetCache then
        ClosestPoint.resetCache()
    end
    if clearLastArgs then State.LastShootArgs = nil end
end

local function clearCombatState(keepLastArgs)
    State.FakePart = nil
    State.FakePos = nil
    State.CurrentPart = nil
    if not keepLastArgs then State.LastShootArgs = nil end
end

local function init(deps)
    Settings     = deps.Settings
    State        = deps.State
    Players      = deps.Players
    LP           = deps.LP
    UIS          = deps.UIS
    Features     = deps.Features
    ClosestPoint = deps.ClosestPoint
    Spread       = deps.Spread
    getCamera    = deps.getCamera
end

Targeting.init = init
Targeting.isAlive = isAlive
Targeting.isDeathCheckState = isDeathCheckState
Targeting.passesDeathCheckRetargetThreshold = passesDeathCheckRetargetThreshold
Targeting.isPartVisible = isPartVisible
Targeting.isPartVisibleRaw = isPartVisibleRaw
Targeting.getTargetPartForPlayer = getTargetPartForPlayer
Targeting.getClosestPlayerAndPart = getClosestPlayerAndPart
Targeting.getClosestTriggerbotPart = getClosestTriggerbotPart
Targeting.getClosestCamlockPart = getClosestCamlockPart
Targeting.hasValidLockedTarget = hasValidLockedTarget
Targeting.resolveCurrentPartFromLinePart = resolveCurrentPartFromLinePart
Targeting.clearTargetState = clearTargetState
Targeting.clearCombatState = clearCombatState

return Targeting
