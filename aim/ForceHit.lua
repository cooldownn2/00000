local Players = game:GetService("Players")
local LP      = Players.LocalPlayer

-- Localize hot-path globals — avoids _ENV table lookup on every call
local pcall   = pcall
local random  = math.random
local floor   = math.floor
local tspawn  = task.spawn
local twait   = task.wait

local Settings, State, isUnloaded
local MainEvent, GH
local playerShotFn = nil
local rawShoot     = nil  -- original GH.shoot, bypasses the silent aim hook
local gameStyle    = nil

local TIMESTAMP_JITTER_SCALE = 0.4
local TIMESTAMP_STEP         = 1 / 60
local WAIT_CANNOT_SHOOT      = 0.15
local WAIT_NO_TOOL           = 0.08
local WAIT_NO_TARGET         = 0.05
local WAIT_BETWEEN_BURSTS    = 0.02
-- Cached constant — avoids a Color3 allocation on every burst
local BEAM_COLOR = Color3.new(1, 0.545098, 0.14902)

-- Shotgun weapons fire multiple pellet events per trigger pull
local SHOTGUN_NAMES = {
    ["[Shotgun]"]          = true,
    ["[TacticalShotgun]"]  = true,
    ["[Drum-Shotgun]"]     = true,
    ["[Double-Barrel SG]"] = true,
}
local SHOTGUN_PELLETS    = 5  -- ShootGun events per burst for shotguns
local SHOTS_SHOTGUN_FULL = 5  -- 5 blasts × 5 pellets = 25 events — guarantees kill
local SHOTS_DEFAULT_FULL = 8  -- 8 headshots — guarantees kill on any HP pool
local SHOTS_SINGLE       = 1  -- bursts when Full Damage is off
-- Yield after EVERY shot so the network flushes before the next group.
-- Max events per frame = SHOTGUN_PELLETS (5) — identical to what the real
-- client fires naturally. Zero ping spike possible at this rate.
local BURST_BATCH_SIZE   = 1
-- R15 torso priority list for shotgun body-shot targeting
local TORSO_PARTS = { "UpperTorso", "LowerTorso", "HumanoidRootPart" }

local function canSelfShoot()
    local char = LP.Character
    if not char then return false end
    local hum = char:FindFirstChild("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    -- FULLY_LOADED_CHAR is on the SHOOTER's character — server requires it
    if not char:FindFirstChild("FULLY_LOADED_CHAR") then return false end
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
    if char:FindFirstChild("FORCEFIELD") then return false end
    local be = char:FindFirstChild("BodyEffects")
    if not be then return true end
    local ko   = be:FindFirstChild("K.O")
    local dead = be:FindFirstChild("Dead")
    if ko   and ko.Value   then return false end
    if dead and dead.Value then return false end
    return true
end

local function getEquippedGun()
    local char = LP.Character
    if not char then return nil end
    local tool = char:FindFirstChildOfClass("Tool")
    if not tool then return nil end
    if not tool:FindFirstChild("Handle") then return nil end
    -- Zeehood tools are fired via the global MainRemoteEvent and have no
    -- per-tool RemoteEvent child; skip that check for the zeehood style.
    if gameStyle ~= "zeehood" and not tool:FindFirstChild("RemoteEvent") then
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
    return SHOTGUN_NAMES[tool.Name] and SHOTGUN_PELLETS or 1
end

local function getShotCount(isShotgun)
    if not Settings.ForceHitFullDamage then return SHOTS_SINGLE end
    return isShotgun and SHOTS_SHOTGUN_FULL or SHOTS_DEFAULT_FULL
end

-- Returns the body part to use as the hit target.
-- Shotguns  → UpperTorso (largest hitbox, all pellets land, max total damage)
-- All others → Head (highest damage multiplier per hit)
local function getTargetPart(tool, targetChar)
    if SHOTGUN_NAMES[tool.Name] then
        for i = 1, #TORSO_PARTS do
            local part = targetChar:FindFirstChild(TORSO_PARTS[i])
            if part then return part end
        end
    end
    return targetChar:FindFirstChild("Head")
end

local function buildShotParams(tool, targetChar)
    -- Re-check FORCEFIELD — may have appeared between isTargetValid and now
    if targetChar:FindFirstChild("FORCEFIELD") then return nil end

    local handle = tool:FindFirstChild("Handle")
    local ammo   = tool:FindFirstChild("Ammo")
    if ammo and ammo.Value <= 0 then return nil end

    local hitPart = getTargetPart(tool, targetChar)
    local hum     = targetChar:FindFirstChildOfClass("Humanoid")
    if not handle or not hitPart or not hum or hum.Health <= 0 then return nil end

    local pellets   = getPellets(tool)
    local isShotgun = pellets > 1
    local shots     = getShotCount(isShotgun)
    local muzzlePos = getMuzzlePos(tool, handle)
    local targetPos = hitPart.Position
    local origin    = getSpoofedOrigin(tool, muzzlePos, targetPos)

    return {
        handle    = handle,
        ammo      = ammo,
        hitPart   = hitPart,
        hum       = hum,
        remote    = tool:FindFirstChild("RemoteEvent"),
        pellets   = pellets,
        shots     = shots,
        muzzlePos = muzzlePos,
        targetPos = targetPos,
        origin    = origin,
    }
end

-- Reusable args table for GH.shoot — avoids a fresh allocation every burst.
-- Fields are overwritten before each call so this is safe.
local _shootArgs = {
    Shooter      = nil,
    Handle       = nil,
    ForcedOrigin = nil,
    AimPosition  = nil,
    BeamColor    = BEAM_COLOR,
    Range        = 1e9,
}

local function fireBurst(tool, targetChar, forcedShots)
    local p = buildShotParams(tool, targetChar)
    if not p then return end

    local isShotgun = SHOTGUN_NAMES[tool.Name]

    -- Clear ShotgunDebounce + LastGunShot on the SHOOTER (local player).
    -- The server's canShoot blocks shotgun shots when these are set.
    if isShotgun then
        pcall(LP.Character.SetAttribute, LP.Character, "ShotgunDebounce", nil)
        pcall(LP.Character.SetAttribute, LP.Character, "LastGunShot", nil)
    end

    if p.remote then
        pcall(p.remote.FireServer, p.remote, "Shoot")
    end

    if playerShotFn then
        pcall(playerShotFn, p.handle)
    end

    -- Dashood: call GH.shoot to produce the visual tracer beam.
    -- Zeehood has no GunHandler so we skip this entirely.
    if gameStyle ~= "zeehood" then
        _shootArgs.Shooter      = LP.Character
        _shootArgs.Handle       = p.handle
        _shootArgs.ForcedOrigin = p.muzzlePos
        _shootArgs.AimPosition  = p.targetPos
        pcall(rawShoot or GH.shoot, _shootArgs)
    end

    local baseTime = getServerNow()
    if not baseTime then return end

    -- Hoist method ref — avoids repeated __index on MainEvent for every shot
    local fireServer = MainEvent.FireServer
    local step       = TIMESTAMP_STEP
    local totalShots = tonumber(forcedShots) or p.shots
    if totalShots < 1 then totalShots = 1 end
    for i = 1, totalShots do
        if p.hum.Health <= 0 then break end
        if p.ammo and p.ammo.Value <= 0 then break end
        if isShotgun then
            pcall(LP.Character.SetAttribute, LP.Character, "ShotgunDebounce", nil)
            pcall(LP.Character.SetAttribute, LP.Character, "LastGunShot", nil)
        end

        local jitter    = (random() - 0.5) * step * TIMESTAMP_JITTER_SCALE
        local timestamp = baseTime + (i * step) + jitter

        if gameStyle == "zeehood" then
            -- Zeehood style: single FireServer("GunFired", tablePayload) call.
            -- Shotguns pack all pellets into a Pellets array in one call.
            if isShotgun then
                local pellets = {}
                for j = 1, p.pellets do
                    pellets[j] = { HitPosition = p.targetPos, HitInstance = p.hitPart }
                end
                local payload = {
                    ToolName   = tool.Name,
                    StartPoint = p.origin,
                    Pellets    = pellets,
                    Timestamp  = timestamp,
                }
                pcall(fireServer, MainEvent, "GunFired", payload)
            else
                local payload = {
                    ToolName    = tool.Name,
                    StartPoint  = p.origin,
                    HitPosition = p.targetPos,
                    HitInstance = p.hitPart,
                    Timestamp   = timestamp,
                }
                pcall(fireServer, MainEvent, "GunFired", payload)
            end
        else
            -- Dashood style: positional args, repeat per pellet.
            for _ = 1, p.pellets do
                pcall(
                    fireServer, MainEvent,
                    "ShootGun",
                    p.handle,
                    p.origin,
                    p.hitPart,
                    p.muzzlePos,
                    p.targetPos,
                    timestamp
                )
            end
        end

        -- Yield every BURST_BATCH_SIZE shots so the network stack flushes
        -- the current packet before we send the next group.
        -- Without this all shots land in one frame = one giant packet = ping spike.
        if i % BURST_BATCH_SIZE == 0 then
            twait()
            -- Re-check target is still alive and lock is still valid after yield
            if p.hum.Health <= 0 then break end
            if not Settings.ForceHitEnabled or isUnloaded() then break end
        end
    end

    if p.remote then
        pcall(p.remote.FireServer, p.remote)
    end
end

local function sendAssistShot()
    if not Settings or not State then return false end
    if isUnloaded() then return false end
    if Settings.ForceHitEnabled then return false end

    local myChar = LP.Character
    if not myChar then return false end
    local myHum = myChar:FindFirstChild("Humanoid")
    if not myHum or myHum.Health <= 0 then return false end
    if not myChar:FindFirstChild("FULLY_LOADED_CHAR") then return false end

    local myBe = myChar:FindFirstChild("BodyEffects")
    if myBe then
        if myBe:FindFirstChild("K.O") and myBe["K.O"].Value then return false end
        if myBe:FindFirstChild("Dead") and myBe.Dead.Value then return false end
        if myBe:FindFirstChild("Cuff") and myBe.Cuff.Value then return false end
        if myBe:FindFirstChild("Grabbed") and myBe.Grabbed.Value then return false end
    end
    if myChar:FindFirstChild("GRABBING_CONSTRAINT") then return false end
    if myChar:FindFirstChild("FORCEFIELD") then return false end

    local tool = getEquippedGun()
    if not tool then return false end

    local target = State.LockedTarget
    local char   = target and target.Character
    if not char or not isTargetValid(char) then return false end
    if not isInRange(tool, char) then return false end

    local ok = pcall(fireBurst, tool, char, 1)
    return ok
end

local function startLoop()
    State.ForceHitLoopId = State.ForceHitLoopId + 1
    local myId = State.ForceHitLoopId
    State.ForceHitActive = true

    tspawn(function()
        while State.ForceHitLoopId == myId and not isUnloaded() do
            if not Settings.ForceHitEnabled then break end

            if not canSelfShoot() then
                twait(WAIT_CANNOT_SHOOT)
            else
                local tool = getEquippedGun()
                if not tool then
                    twait(WAIT_NO_TOOL)
                else
                    local target = State.LockedTarget
                    local char   = target and target.Character
                    if not char or not isTargetValid(char) then
                        twait(WAIT_NO_TARGET)
                    else
                        if isInRange(tool, char) then
                            pcall(fireBurst, tool, char)
                        end
                        if not Settings.ForceHitEnabled then break end
                        twait(WAIT_BETWEEN_BURSTS)
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
    return floor(dist), inRange
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
    gameStyle  = deps.gameStyle
    rawShoot   = deps.oldShoot  -- pre-hook original; keeps tracers independent of silent aim
    if type(shared) == "table" and type(shared.playerShot) == "function" then
        playerShotFn = shared.playerShot
    end
end

return {
    init            = init,
    startLoop       = startLoop,
    stopLoop        = stopLoop,
    sendAssistShot  = sendAssistShot,
    onTargetChanged = onTargetChanged,
    isActive        = isActive,
    getDistanceInfo = getDistanceInfo,
    cleanup         = cleanup,
}
