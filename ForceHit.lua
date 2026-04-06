local Players = game:GetService("Players")
local LP      = Players.LocalPlayer

local Settings, State, isUnloaded
local MainEvent, GH
local playerShotFn = nil

local TIMESTAMP_JITTER_SCALE = 0.4
local TIMESTAMP_STEP         = 1 / 60
local WAIT_CANNOT_SHOOT      = 0.15
local WAIT_NO_TOOL           = 0.08
local WAIT_NO_TARGET         = 0.05
local WAIT_BETWEEN_BURSTS    = 0.02

local function canSelfShoot()
    local char = LP.Character
    if not char then return false end
    local hum = char:FindFirstChild("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    local be = char:FindFirstChild("BodyEffects")
    if not be then return true end
    if be:FindFirstChild("K.O")       and be["K.O"].Value   then return false end
    if be:FindFirstChild("Dead")      and be.Dead.Value      then return false end
    if be:FindFirstChild("Cuff")      and be.Cuff.Value      then return false end
    if be:FindFirstChild("Grabbed")   and be.Grabbed.Value   then return false end
    if be:FindFirstChild("Attacking") and be.Attacking.Value then return false end
    if be:FindFirstChild("Reload")    and be.Reload.Value    then return false end
    if char:FindFirstChild("GRABBING_CONSTRAINT")            then return false end
    if char:FindFirstChild("FORCEFIELD")                     then return false end
    return true
end

local function isTargetValid(char)
    if not char then return false end
    local hum = char:FindFirstChild("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    local be = char:FindFirstChild("BodyEffects")
    if not be then return true end
    local ko   = be:FindFirstChild("K.O")
    local dead = be:FindFirstChild("Dead")
    if ko   and ko.Value   then return false end
    if dead and dead.Value then return false end
    if char:FindFirstChild("FORCEFIELD") then return false end
    return true
end

local function getEquippedGun()
    local char = LP.Character
    if not char then return nil end
    local tool = char:FindFirstChildOfClass("Tool")
    if not tool then return nil end
    if not tool:FindFirstChild("Handle") or not tool:FindFirstChild("RemoteEvent") then
        return nil
    end
    return tool
end

local function getServerNow()
    local ok, t = pcall(workspace.GetServerTimeNow, workspace)
    return ok and t or nil
end

local function getMuzzlePos(tool, handle)
    local def = tool:FindFirstChild("Default")
    if def then
        local mesh = def:FindFirstChild("Mesh") or def:FindFirstChild("MeshPart")
        if mesh then
            local m = mesh:FindFirstChild("Muzzle")
            if m then
                if m:IsA("Attachment") then return m.WorldPosition end
                if m:IsA("BasePart")   then return m.Position end
            end
        end
    end
    local m = handle:FindFirstChild("Muzzle")
    if m then
        if m:IsA("Attachment") then return m.WorldPosition end
        if m:IsA("BasePart")   then return m.Position end
    end
    return handle.Position
end

local function getWeaponMaxDist(tool)
    local distances = Settings.ForceHitDistances
    return distances and distances[tool.Name] or nil
end

local function getPlayerDistance(targetChar)
    local myChar = LP.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local tRoot  = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
    if not myRoot or not tRoot then return nil end
    return (tRoot.Position - myRoot.Position).Magnitude
end

local function isInRange(tool, targetChar)
    if Settings.InfiniteRange then return true end
    local maxDist = getWeaponMaxDist(tool)
    if not maxDist then return true end
    local dist = getPlayerDistance(targetChar)
    if not dist then return false end
    return dist <= maxDist
end

local function getSpoofedOrigin(tool, muzzlePos, targetPos)
    if Settings.InfiniteRange then return targetPos end
    local maxDist       = getWeaponMaxDist(tool)
    local range         = tool:FindFirstChild("Range")
    local effectiveDist = maxDist or (range and range.Value) or nil
    if not effectiveDist then return targetPos end
    local diff = targetPos - muzzlePos
    if diff.Magnitude <= effectiveDist then return muzzlePos end
    return targetPos - diff.Unit * effectiveDist
end

local function getPellets(tool)
    local pellets = Settings.ShotgunPellets
    return (pellets and pellets[tool.Name]) or 1
end

local function getShotCount(isShotgun)
    if not Settings.ForceHitFullDamage then
        return isShotgun and 5 or 1
    end
    if isShotgun then
        return Settings.FullDamageShotgun or 8
    end
    return Settings.FullDamageDefault or 15
end

local function buildShotParams(tool, targetChar)
    local handle = tool:FindFirstChild("Handle")
    local ammo   = tool:FindFirstChild("Ammo")
    if ammo and ammo.Value <= 0 then return nil end

    local head = targetChar:FindFirstChild("Head")
    local hum  = targetChar:FindFirstChildOfClass("Humanoid")
    if not handle or not head or not hum or hum.Health <= 0 then return nil end

    local baseTime = getServerNow()
    if not baseTime then return nil end

    local pellets   = getPellets(tool)
    local isShotgun = pellets > 1
    local shots     = getShotCount(isShotgun)
    local muzzlePos = getMuzzlePos(tool, handle)
    local targetPos = head.Position
    local origin    = getSpoofedOrigin(tool, muzzlePos, targetPos)

    return {
        handle    = handle,
        head      = head,
        hum       = hum,
        remote    = tool:FindFirstChild("RemoteEvent"),
        pellets   = pellets,
        shots     = shots,
        muzzlePos = muzzlePos,
        targetPos = targetPos,
        origin    = origin,
        baseTime  = baseTime,
    }
end

local function fireBurst(tool, targetChar)
    if not Settings.ForceHitEnabled or not canSelfShoot() then return end
    if isUnloaded() then return end
    if not isInRange(tool, targetChar) then return end

    local p = buildShotParams(tool, targetChar)
    if not p then return end

    if p.remote then
        pcall(p.remote.FireServer, p.remote, "Shoot")
    end

    if playerShotFn then
        pcall(playerShotFn, p.handle)
    end

    pcall(GH.shoot, {
        Shooter      = LP.Character,
        Handle       = p.handle,
        ForcedOrigin = p.muzzlePos,
        AimPosition  = p.targetPos,
        BeamColor    = Color3.new(1, 0.545098, 0.14902),
        Range        = 1e9,
    })

    local step = TIMESTAMP_STEP
    for i = 1, p.shots do
        if not Settings.ForceHitEnabled or isUnloaded() or p.hum.Health <= 0 then break end

        local jitter    = (math.random() - 0.5) * step * TIMESTAMP_JITTER_SCALE
        local timestamp = p.baseTime + (i * step) + jitter

        for _ = 1, p.pellets do
            pcall(
                MainEvent.FireServer, MainEvent,
                "ShootGun",
                p.handle,
                p.origin,
                p.head,
                p.muzzlePos,
                p.targetPos,
                timestamp
            )
        end

        if i < p.shots then
            task.wait()
        end
    end

    if p.remote then
        pcall(p.remote.FireServer, p.remote)
    end
end

local function startLoop()
    State.ForceHitLoopId = State.ForceHitLoopId + 1
    local myId = State.ForceHitLoopId
    State.ForceHitActive = true

    task.spawn(function()
        while State.ForceHitLoopId == myId and not isUnloaded() do
            if not Settings.ForceHitEnabled then break end

            if not canSelfShoot() then
                task.wait(WAIT_CANNOT_SHOOT)
            else
                local tool = getEquippedGun()
                if not tool then
                    task.wait(WAIT_NO_TOOL)
                else
                    local target = State.LockedTarget
                    local char   = target and target.Character
                    if not char or not isTargetValid(char) then
                        task.wait(WAIT_NO_TARGET)
                    else
                        pcall(fireBurst, tool, char)
                        if not Settings.ForceHitEnabled then break end
                        task.wait(WAIT_BETWEEN_BURSTS)
                    end
                end
            end
        end

        State.ForceHitActive = false
    end)
end

local function stopLoop()
    State.ForceHitLoopId = State.ForceHitLoopId + 1
    State.ForceHitActive = false
end

local function onTargetChanged(hasTarget)
    if not Settings.ForceHitEnabled then
        if State.ForceHitActive then stopLoop() end
        return
    end
    if hasTarget and not State.ForceHitActive then
        startLoop()
    elseif not hasTarget and State.ForceHitActive then
        stopLoop()
    end
end

local function isActive()
    return Settings.ForceHitEnabled and State.ForceHitActive and State.LockedTarget ~= nil
end

local function getDistanceInfo(tool)
    local target = State.LockedTarget
    local char   = target and target.Character
    if not char then return nil, nil end
    local dist = getPlayerDistance(char)
    if not dist then return nil, nil end
    tool = tool or getEquippedGun()
    local inRange = true
    if not Settings.InfiniteRange and tool then
        local maxDist = getWeaponMaxDist(tool)
        if maxDist then
            inRange = dist <= maxDist
        end
    end
    return math.floor(dist), inRange
end

local function cleanup()
    stopLoop()
end

local function init(deps)
    Settings   = deps.Settings
    State      = deps.State
    isUnloaded = deps.isUnloaded
    MainEvent  = deps.MainEvent
    GH         = deps.GH
    if type(shared) == "table" and type(shared.playerShot) == "function" then
        playerShotFn = shared.playerShot
    end
end

return {
    init            = init,
    startLoop       = startLoop,
    stopLoop        = stopLoop,
    onTargetChanged = onTargetChanged,
    isActive        = isActive,
    getDistanceInfo = getDistanceInfo,
    cleanup         = cleanup,
}