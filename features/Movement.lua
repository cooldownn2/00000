local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")

local Movement = {}

local LP       = Players.LocalPlayer
local Settings, State, gameStyle

local MOUSE1          = Enum.UserInputType.MouseButton1
local GROUND_BRAKE    = 0.93
local MOVE_THRESH_SQ  = 0.0025 -- 0.05^2, avoids Magnitude + sqrt in hot path
local ANTI_TRIP_HSQ   = 3600   -- 60^2, avoids sqrt in hot path
local BASE_WALK_SPEED = 16
local CLAMP_DETECT_GAP = 4

local lerpedSpeed     = 0
local antiTripPatched = false

-- Character-scoped caches; refreshed lazily when LP.Character changes.
local _char, _hum, _root
local _bodyEffects, _reloadFlag

local function refreshCharCache(char)
    local hum  = char and char:FindFirstChildOfClass("Humanoid") or nil
    local root = char and char:FindFirstChild("HumanoidRootPart")  or nil
    local bodyEffects = char and char:FindFirstChild("BodyEffects") or nil

    local staleHum = _hum and _hum.Parent ~= char
    local staleRoot = _root and _root.Parent ~= char
    local staleBodyEffects = _bodyEffects and _bodyEffects.Parent ~= char

    if char == _char
        and hum == _hum
        and root == _root
        and bodyEffects == _bodyEffects
        and not staleHum
        and not staleRoot
        and not staleBodyEffects then
        return
    end

    _char = char
    _hum  = hum
    _root = root
    _bodyEffects = bodyEffects
    _reloadFlag  = _bodyEffects and (
        _bodyEffects:FindFirstChild("Reload") or
        _bodyEffects:FindFirstChild("Reloading")
    ) or nil

    State.SpeedCharacter   = char
    State.DefaultWalkSpeed = _hum and _hum.WalkSpeed or BASE_WALK_SPEED
    lerpedSpeed    = 0
    antiTripPatched = false
end

-- Exported helpers ----------------------------------------------------------------

local function getEquippedTool()
    local char = LP.Character
    return char and char:FindFirstChildOfClass("Tool") or nil
end

local function isKnifeTool(tool)
    return tool and string.find(string.lower(tool.Name), "knife", 1, true) ~= nil
end

local function getReloadingFlag()
    if not _bodyEffects then return false end
    local flag = _reloadFlag
    if not flag then
        -- Lazy one-time find in case the flag was added after character spawn.
        flag = _bodyEffects:FindFirstChild("Reload") or
               _bodyEffects:FindFirstChild("Reloading")
        _reloadFlag = flag
    end
    if not flag then return false end
    if flag:IsA("BoolValue")   then return flag.Value end
    if flag:IsA("NumberValue") or flag:IsA("IntValue") then return flag.Value > 0 end
    return false
end

local function shouldBypassReduceWalk()
    if gameStyle ~= "zeehood" then return false end
    return State.Enabled
        or State.LockedTarget ~= nil
        or State.TriggerbotHoldActive
        or State.TriggerbotToggleActive
        or State.CamlockHoldActive
        or State.CamlockToggleActive
        or State.ForceHitActive
end

local function clearReduceWalkFlags()
    if not _bodyEffects then return end
    local movementFolder = _bodyEffects:FindFirstChild("Movement")
    if not movementFolder then return end
    for _, child in ipairs(movementFolder:GetChildren()) do
        if child.Name == "ReduceWalk" then
            pcall(child.Destroy, child)
        end
    end
end

local function restoreBaselineWalkSpeed(hum)
    if not hum then return end
    local baseline = State.DefaultWalkSpeed or BASE_WALK_SPEED
    if math.abs((hum.WalkSpeed or baseline) - baseline) > 0.05 then
        hum.WalkSpeed = baseline
    end
end

-- Internal utilities --------------------------------------------------------------

local function resolveSpeedState(hum, tool, isReloading)
    if tool and string.find(string.lower(tool.Name), "knife", 1, true) then
        return "Knife"
    elseif isReloading then
        return "Reloading"
    elseif hum.MaxHealth > 0 and hum.Health <= hum.MaxHealth * 0.35 then
        return "Low Health"
    elseif tool and UIS:IsMouseButtonPressed(MOUSE1) then
        return "Shooting"
    end
    return "Normal"
end

local function resolveTargetSpeed(speedData, mode)
    local value = tonumber(speedData[mode]) or tonumber(speedData["Normal"]) or 1

    -- Zeehood users configure absolute speed values (e.g. 26 means 26 WS),
    -- while older profiles use multipliers. Keep both behaviors.
    if gameStyle == "zeehood" then
        if value <= 0 then return BASE_WALK_SPEED end
        return value
    end

    return BASE_WALK_SPEED * value
end

local function restoreAntiTripStates(hum)
    if not antiTripPatched then return end
    if hum then
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
    end
    antiTripPatched = false
end

local function applyAntiTrip(hum, root)
    if Settings.AntiTripEnabled == false then
        restoreAntiTripStates(hum)
        return
    end

    if not antiTripPatched then
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
        antiTripPatched = true
    end

    if hum.PlatformStand then hum.PlatformStand = false end
    if hum.Sit then hum.Sit = false end

    -- Single GetState() call; result reused for both blocks below.
    local st = hum:GetState()
    if st == Enum.HumanoidStateType.FallingDown
        or st == Enum.HumanoidStateType.Ragdoll
        or st == Enum.HumanoidStateType.Physics
        or st == Enum.HumanoidStateType.PlatformStanding then
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        hum:ChangeState(Enum.HumanoidStateType.Running)
    end

    -- Cancel horizontal fling only; preserve upward Y so jumping still works.
    if root and hum.FloorMaterial ~= Enum.Material.Air
        and st ~= Enum.HumanoidStateType.Jumping
        and st ~= Enum.HumanoidStateType.Freefall then
        local vel = root.AssemblyLinearVelocity
        local vx, vz = vel.X, vel.Z
        -- Squared comparison avoids a Vector3 allocation + sqrt every frame.
        if vx * vx + vz * vz >= ANTI_TRIP_HSQ and vel.Y > 10 then
            root.AssemblyLinearVelocity = Vector3.new(vx, 0, vz)
        end
    end
end

local function resetSpeedModification()
    lerpedSpeed = 0
    if antiTripPatched and (State.Unloaded or Settings.AntiTripEnabled == false) then
        restoreAntiTripStates(_hum)
    end
end

-- Main per-frame update -----------------------------------------------------------

local function applySpeedModification(tool, deltaTime)
    local char = LP.Character
    refreshCharCache(char)
    local hum, root = _hum, _root

    if not char or not hum then
        State.SpeedCharacter   = nil
        State.DefaultWalkSpeed = nil
        return
    end

    if hum.Health <= 0 then
        restoreAntiTripStates(hum)
        lerpedSpeed = 0
        return
    end

    applyAntiTrip(hum, root)

    if shouldBypassReduceWalk() then
        clearReduceWalkFlags()
        if not Settings.SpeedEnabled or not State.SpeedActive then
            restoreBaselineWalkSpeed(hum)
        end
    end

    if not Settings.SpeedEnabled or not State.SpeedActive then
        resetSpeedModification()
        return
    end

    local speedData   = Settings.SpeedData or {}
    local mode        = resolveSpeedState(hum, tool, getReloadingFlag())
    local targetSpeed = resolveTargetSpeed(speedData, mode)

    local dt    = deltaTime or (1 / 60)
    local alpha = dt * 30
    if alpha > 1 then alpha = 1 end
    lerpedSpeed = lerpedSpeed + (targetSpeed - lerpedSpeed) * alpha

    -- Zeehood's framework continuously rewrites WalkSpeed (e.g. 20.8), which can
    -- cause visible slowdown fights. Prefer velocity drive there and avoid writing
    -- WalkSpeed every frame.
    if gameStyle ~= "zeehood" then
        if math.abs(hum.WalkSpeed - lerpedSpeed) > 0.05 then
            hum.WalkSpeed = lerpedSpeed
        end
    end

    if root then
        local moveDir   = hum.MoveDirection
        local mx, mz    = moveDir.X, moveDir.Z
        local moveMagSq = mx * mx + mz * mz

        if moveMagSq > MOVE_THRESH_SQ then
            local useVelocityInjection = Settings.SpeedVelocityInjection ~= false
            if gameStyle == "zeehood" then
                useVelocityInjection = true
            end
            -- Framework scripts on Zeehood can clamp WalkSpeed back to ~20.8
            -- every frame. If detected, switch to velocity drive automatically.
            if gameStyle == "zeehood" and hum.WalkSpeed + CLAMP_DETECT_GAP < lerpedSpeed then
                useVelocityInjection = true
            end

            if useVelocityInjection then
                local vel   = root.AssemblyLinearVelocity
                -- Scalar normalisation: one Vector3 alloc instead of two.
                local scale = lerpedSpeed / math.sqrt(moveMagSq)
                root.AssemblyLinearVelocity = Vector3.new(mx * scale, vel.Y, mz * scale)
            end
        elseif hum.FloorMaterial ~= Enum.Material.Air
            and Settings.SpeedVelocityInjection == false then
            local vel   = root.AssemblyLinearVelocity
            local brake = GROUND_BRAKE ^ (dt * 60)
            root.AssemblyLinearVelocity = Vector3.new(vel.X * brake, vel.Y, vel.Z * brake)
        end
    end
end

local function panicGround()
    if Settings.PanicGroundEnabled == false then return end
    local char = LP.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not char or not hum or not root then return end
    if hum.FloorMaterial ~= Enum.Material.Air then return end

    local vel    = root.AssemblyLinearVelocity
    local hx, hz = vel.X, vel.Z
    local md     = hum.MoveDirection
    if md.Magnitude > 0.05 then
        local speed = math.max((State.DefaultWalkSpeed or BASE_WALK_SPEED) * 2.4, hum.WalkSpeed, 48)
        local dir   = md.Unit
        hx, hz = dir.X * speed, dir.Z * speed
    end
    root.AssemblyLinearVelocity = Vector3.new(hx, math.min(vel.Y, -650), hz)
end

-- Init ----------------------------------------------------------------------------

local function init(deps)
    Settings = deps.Settings
    State    = deps.State
    gameStyle = deps.gameStyle
end

Movement.init                   = init
Movement.getEquippedTool        = getEquippedTool
Movement.isKnifeTool            = isKnifeTool
Movement.getReloadingFlag       = getReloadingFlag
Movement.applySpeedModification = applySpeedModification
Movement.resetSpeedModification = resetSpeedModification
Movement.panicGround            = panicGround

return Movement