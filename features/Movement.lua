local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")

local Movement = {}

local LP = Players.LocalPlayer
local Settings, State

local MOUSE1 = Enum.UserInputType.MouseButton1
local GROUND_BRAKE_FACTOR = 0.93
local MOVE_INPUT_THRESHOLD = 0.05
local BASE_WALK_SPEED = 16

local lerpedSpeed = 0
local wasSpeedActive = false
local antiTripPatched = false

local function getEquippedTool()
    local char = LP.Character
    return char and char:FindFirstChildOfClass("Tool") or nil
end

local function isKnifeTool(tool)
    return tool and string.find(string.lower(tool.Name), "knife", 1, true) ~= nil
end

local function getReloadingFlag(char)
    if not char then return false end
    local bodyEffects = char:FindFirstChild("BodyEffects")
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

-- Restores ragdoll/fallingdown states on the given humanoid and clears the patch flag.
local function restoreAntiTripStates(hum)
    if not antiTripPatched then return end
    if hum then
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
    end
    antiTripPatched = false
end

-- Runs every frame independently of speed. Keeps the character upright.
-- root is passed so we can clamp upward velocity spikes from geometry collisions.
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

    local currentState = hum:GetState()
    if currentState == Enum.HumanoidStateType.FallingDown
        or currentState == Enum.HumanoidStateType.Ragdoll
        or currentState == Enum.HumanoidStateType.Physics
        or currentState == Enum.HumanoidStateType.PlatformStanding then
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        hum:ChangeState(Enum.HumanoidStateType.Running)
    end

    -- Only clamp upward fling spikes when moving at high speed (150+ studs/s horizontal).
    -- Skip entirely if the player is jumping so we don't cancel jump velocity.
    if root and hum.FloorMaterial ~= Enum.Material.Air then
        local state = hum:GetState()
        local isJumping = state == Enum.HumanoidStateType.Jumping
            or state == Enum.HumanoidStateType.Freefall
        if not isJumping then
            local vel = root.AssemblyLinearVelocity
            local horizontalSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
            if horizontalSpeed >= 150 and vel.Y > 10 then
                root.AssemblyLinearVelocity = Vector3.new(vel.X, 0, vel.Z)
            end
        end
    end
end

local function resetSpeedModification()
    lerpedSpeed = 0
    wasSpeedActive = false
    -- Restore anti-trip states on unload or if anti-trip config is disabled
    if antiTripPatched and (State.Unloaded or Settings.AntiTripEnabled == false) then
        local char = LP.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        restoreAntiTripStates(hum)
    end
end

local function applySpeedModification(tool, deltaTime)
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not hum then
        State.SpeedCharacter = nil
        State.DefaultWalkSpeed = nil
        return
    end

    if State.SpeedCharacter ~= char then
        State.SpeedCharacter = char
        State.DefaultWalkSpeed = hum.WalkSpeed
        lerpedSpeed = 0
        wasSpeedActive = false
        antiTripPatched = false
    end

    -- Anti-trip always runs when char exists, regardless of speed toggle
    local root = char:FindFirstChild("HumanoidRootPart")
    applyAntiTrip(hum, root)

    if not Settings.SpeedEnabled or not State.SpeedActive then
        resetSpeedModification()
        return
    end
    wasSpeedActive = true

    local speedData = Settings.SpeedData or {}
    local mode = resolveSpeedState(hum, tool, getReloadingFlag(char))
    local multiplier = speedData[mode] or speedData["Normal"] or 1
    local targetSpeed = math.max(0, BASE_WALK_SPEED * multiplier)
    local alpha = math.min(1, (deltaTime or (1 / 60)) * 30)
    lerpedSpeed = lerpedSpeed + (targetSpeed - lerpedSpeed) * alpha
    local grounded = hum.FloorMaterial ~= Enum.Material.Air

    hum.WalkSpeed = lerpedSpeed

    if root then
        local moveDir = hum.MoveDirection
        local vel = root.AssemblyLinearVelocity
        local injecting = Settings.SpeedVelocityInjection ~= false
        if moveDir.Magnitude > MOVE_INPUT_THRESHOLD then
            if injecting then
                local targetVel = moveDir.Unit * lerpedSpeed
                root.AssemblyLinearVelocity = Vector3.new(targetVel.X, vel.Y, targetVel.Z)
            end
        elseif grounded and not injecting then
            local dtScale = math.max((deltaTime or (1 / 60)) * 60, 0)
            local brakeFactor = GROUND_BRAKE_FACTOR ^ dtScale
            root.AssemblyLinearVelocity = Vector3.new(vel.X * brakeFactor, vel.Y, vel.Z * brakeFactor)
        end
    end
end

local function panicGround()
    if Settings.PanicGroundEnabled == false then return end
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not char or not hum or not root then return end
    if hum.FloorMaterial ~= Enum.Material.Air then return end

    local currentVel = root.AssemblyLinearVelocity
    local horizontal = Vector3.new(currentVel.X, 0, currentVel.Z)
    local moveDir = hum.MoveDirection
    if moveDir.Magnitude > 0.05 then
        local baseWalk = State.DefaultWalkSpeed or 16
        local desiredHorizontal = moveDir.Unit * math.max(baseWalk * 2.4, hum.WalkSpeed, 48)
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