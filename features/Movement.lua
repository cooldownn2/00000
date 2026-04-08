local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")

local Movement = {}

local LP = Players.LocalPlayer
local Settings, State

local MOUSE1 = Enum.UserInputType.MouseButton1
local ACCEL_RATE = 35
local DECEL_RATE = 8
local GROUND_BRAKE_FACTOR = 0.88
local MOVE_INPUT_THRESHOLD = 0.05
local BASE_WALK_SPEED = 16

-- Per-character cache — refreshed once whenever the character instance changes,
-- so FindFirstChild/FindFirstChildOfClass are not called every RenderStepped frame.
local cachedHum, cachedRoot, cachedBodyEffects

local function refreshCharacterCache(char)
    cachedHum         = char:FindFirstChildOfClass("Humanoid")
    cachedRoot        = char:FindFirstChild("HumanoidRootPart")
    cachedBodyEffects = char:FindFirstChild("BodyEffects")
end

local function getEquippedTool()
    local char = LP.Character
    return char and char:FindFirstChildOfClass("Tool") or nil
end

local function isKnifeTool(tool)
    return tool and string.find(string.lower(tool.Name), "knife", 1, true) ~= nil
end

local function getReloadingFlag()
    local bodyEffects = cachedBodyEffects
    if not bodyEffects then return false end
    local flag = bodyEffects:FindFirstChild("Reload") or bodyEffects:FindFirstChild("Reloading")
    if not flag then return false end
    if flag:IsA("BoolValue") then return flag.Value end
    if flag:IsA("NumberValue") or flag:IsA("IntValue") then return flag.Value > 0 end
    return false
end

local function resolveSpeedState(humanoid, tool, isReloading)
    local mode = "Normal"
    if tool and string.find(string.lower(tool.Name), "knife", 1, true) then
        mode = "Knife"
    elseif isReloading then
        mode = "Reloading"
    elseif humanoid.MaxHealth > 0 and humanoid.Health <= (humanoid.MaxHealth * 0.35) then
        mode = "Low Health"
    elseif tool and UIS:IsMouseButtonPressed(MOUSE1) then
        mode = "Shooting"
    end
    return mode
end

local function resetSpeedModification()
    local hum = cachedHum
    if hum then
        if State.DefaultWalkSpeed and hum.WalkSpeed ~= State.DefaultWalkSpeed then
            hum.WalkSpeed = State.DefaultWalkSpeed
        end
        if State.SpeedStatesPatched then
            hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
            hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
            State.SpeedStatesPatched = false
        end
    end
end

local function applyAntiTrip(hum)
    if Settings.AntiTripEnabled == false then
        if State.SpeedStatesPatched then
            hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
            hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
            State.SpeedStatesPatched = false
        end
        return
    end

    if not State.SpeedStatesPatched then
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
        State.SpeedStatesPatched = true
    end

    if hum.PlatformStand then hum.PlatformStand = false end
    if hum.Sit then hum.Sit = false end

    local currentState = hum:GetState()
    if currentState == Enum.HumanoidStateType.FallingDown
        or currentState == Enum.HumanoidStateType.Ragdoll
        or currentState == Enum.HumanoidStateType.Physics
        or currentState == Enum.HumanoidStateType.PlatformStanding then
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        hum:ChangeState(Enum.HumanoidStateType.Running)
    end
end

local function applySpeedModification(tool, deltaTime)
    local char = LP.Character
    if not char then
        cachedHum, cachedRoot, cachedBodyEffects = nil, nil, nil
        State.SpeedCharacter = nil
        State.DefaultWalkSpeed = nil
        State.SpeedStatesPatched = false
        return
    end

    if State.SpeedCharacter ~= char then
        State.SpeedCharacter = char
        refreshCharacterCache(char)
        State.DefaultWalkSpeed = cachedHum and cachedHum.WalkSpeed or BASE_WALK_SPEED
        State.SpeedStatesPatched = false
    end

    local hum = cachedHum
    if not hum then return end

    local dt = deltaTime or (1 / 60)

    if not Settings.SpeedEnabled or not State.SpeedActive then
        -- Smooth deceleration back to base speed before fully resetting.
        -- Anti-trip stays active during the ramp so the player doesn't trip at high speed.
        if hum.WalkSpeed > BASE_WALK_SPEED + 0.5 then
            local newSpeed = hum.WalkSpeed + (BASE_WALK_SPEED - hum.WalkSpeed) * (1 - math.exp(-DECEL_RATE * dt))
            if math.abs(newSpeed - BASE_WALK_SPEED) < 0.5 then newSpeed = BASE_WALK_SPEED end
            hum.WalkSpeed = newSpeed
            return
        end
        resetSpeedModification()
        return
    end

    local speedData = Settings.SpeedData or {}
    local mode = resolveSpeedState(hum, tool, getReloadingFlag())
    local multiplier = speedData[mode] or speedData["Normal"] or 1
    local targetSpeed = math.max(0, BASE_WALK_SPEED * multiplier)
    local grounded = hum.FloorMaterial ~= Enum.Material.Air

    applyAntiTrip(hum)

    local rate = targetSpeed > hum.WalkSpeed and ACCEL_RATE or DECEL_RATE
    local newSpeed = hum.WalkSpeed + (targetSpeed - hum.WalkSpeed) * (1 - math.exp(-rate * dt))
    if math.abs(newSpeed - targetSpeed) < 0.5 then newSpeed = targetSpeed end
    hum.WalkSpeed = newSpeed

    if grounded then
        local root = cachedRoot
        if root then
            local vel = root.AssemblyLinearVelocity
            local moveDir = hum.MoveDirection
            if moveDir.Magnitude >= MOVE_INPUT_THRESHOLD then
                -- Directly set horizontal velocity to match the current lerped speed,
                -- bypassing Roblox's internal humanoid physics cap.
                root.AssemblyLinearVelocity = Vector3.new(
                    moveDir.X * newSpeed,
                    vel.Y,
                    moveDir.Z * newSpeed
                )
            else
                local brakeFactor = GROUND_BRAKE_FACTOR ^ (dt * 60)
                root.AssemblyLinearVelocity = Vector3.new(vel.X * brakeFactor, vel.Y, vel.Z * brakeFactor)
            end
        end
    end
end

local function panicGround()
    if Settings.PanicGroundEnabled == false then return end
    local hum = cachedHum
    local root = cachedRoot
    if not hum or not root then return end
    if hum.FloorMaterial ~= Enum.Material.Air then return end

    local currentVel = root.AssemblyLinearVelocity
    local horizontal = Vector3.new(currentVel.X, 0, currentVel.Z)
    local moveDir = hum.MoveDirection
    if moveDir.Magnitude > 0.05 then
        local desiredHorizontal = moveDir.Unit * math.max((State.DefaultWalkSpeed or BASE_WALK_SPEED) * 2.4, hum.WalkSpeed, 48)
        horizontal = desiredHorizontal
    end

    root.AssemblyLinearVelocity = Vector3.new(horizontal.X, math.min(currentVel.Y, -650), horizontal.Z)
end

local function init(deps)
    Settings = deps.Settings
    State = deps.State
end

Movement.init = init
Movement.getEquippedTool = getEquippedTool
Movement.isKnifeTool = isKnifeTool
Movement.getReloadingFlag = getReloadingFlag
Movement.applySpeedModification = applySpeedModification
Movement.resetSpeedModification = resetSpeedModification
Movement.panicGround = panicGround

return Movement