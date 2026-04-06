local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")
local LP      = Players.LocalPlayer
local MOUSE1  = Enum.UserInputType.MouseButton1

local Settings, State, safeCall
local MainEvent, GH, Camera
local cloneArgs, applyRangePolicy, getSpreadAimPosition, getCamlockAimPosition
local isTargetFeatureAllowed

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

local function resetSpeedModification()
    local char = LP.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if hum and State.DefaultWalkSpeed and hum.WalkSpeed ~= State.DefaultWalkSpeed then
        hum.WalkSpeed = State.DefaultWalkSpeed
    end
    if hum and State.SpeedStatesPatched then
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
        State.SpeedStatesPatched = false
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

local SPEED_MULTIPLIER     = 15
local GROUND_BRAKE_FACTOR  = 0.93
local MOVE_INPUT_THRESHOLD = 0.05

local function applySpeedModification(tool, deltaTime)
    local char = LP.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not hum then
        State.SpeedCharacter = nil; State.DefaultWalkSpeed = nil; State.SpeedStatesPatched = false
        return
    end
    if State.SpeedCharacter ~= char then
        State.SpeedCharacter = char; State.DefaultWalkSpeed = hum.WalkSpeed; State.SpeedStatesPatched = false
    end
    if not Settings.SpeedEnabled or not State.SpeedActive then
        resetSpeedModification()
        return
    end
    local speedData = Settings.SpeedData or {}
    local mode = resolveSpeedState(hum, tool, getReloadingFlag(char))
    local baseSpeed  = speedData[mode] or speedData["Normal"] or State.DefaultWalkSpeed or hum.WalkSpeed
    local targetSpeed = math.max(0, baseSpeed * SPEED_MULTIPLIER)
    local grounded    = hum.FloorMaterial ~= Enum.Material.Air
    applyAntiTrip(hum)
    if hum.WalkSpeed ~= targetSpeed then hum.WalkSpeed = targetSpeed end
    if grounded then
        local moveDir = hum.MoveDirection
        if moveDir.Magnitude < MOVE_INPUT_THRESHOLD then
            local root = char:FindFirstChild("HumanoidRootPart")
            if root then
                local vel = root.AssemblyLinearVelocity
                local dtScale = math.max((deltaTime or (1 / 60)) * 60, 0)
                local brakeFactor = GROUND_BRAKE_FACTOR ^ dtScale
                root.AssemblyLinearVelocity = Vector3.new(vel.X * brakeFactor, vel.Y, vel.Z * brakeFactor)
            end
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
    local currentVel  = root.AssemblyLinearVelocity
    local horizontal  = Vector3.new(currentVel.X, 0, currentVel.Z)
    local moveDir     = hum.MoveDirection
    if moveDir.Magnitude > 0.05 then
        local baseWalk = State.DefaultWalkSpeed or 16
        local desiredHorizontal = moveDir.Unit * math.max(baseWalk * 2.4, hum.WalkSpeed, 48)
        horizontal = desiredHorizontal
    end
    root.AssemblyLinearVelocity = Vector3.new(horizontal.X, math.min(currentVel.Y, -650), horizontal.Z)
end

local function getTriggerbotBounds()
    local width  = Settings.TriggerbotFOVWidth
    local height = Settings.TriggerbotFOVHeight
    local left  = type(width)  == "table" and tonumber(width[1])  or tonumber(width)
    local right = type(width)  == "table" and tonumber(width[2])  or tonumber(width)
    local up    = type(height) == "table" and tonumber(height[1]) or tonumber(height)
    local down  = type(height) == "table" and tonumber(height[2]) or tonumber(height)
    return math.max(left or 1, 0), math.max(right or 1, 0), math.max(up or 1, 0), math.max(down or 1, 0)
end

local function getCamlockBounds()
    local width  = Settings.CamlockFOVWidth
    local height = Settings.CamlockFOVHeight
    local left  = type(width)  == "table" and tonumber(width[1])  or tonumber(width)
    local right = type(width)  == "table" and tonumber(width[2])  or tonumber(width)
    local up    = type(height) == "table" and tonumber(height[1]) or tonumber(height)
    local down  = type(height) == "table" and tonumber(height[2]) or tonumber(height)
    return math.max(left or 6, 0), math.max(right or 6, 0), math.max(up or 6, 0), math.max(down or 6, 0)
end

local function getTriggerbotDelaySeconds()
    local raw = tonumber(Settings.TriggerbotDelay) or 0
    raw = math.max(raw, 0)
    if raw >= 1 then
        return raw / 1000
    end
    return raw
end

local function canTriggerbotShootNow()
    return (os.clock() - (State.LastTriggerShot or 0)) >= getTriggerbotDelaySeconds()
end

local function isTriggerbotArmed()
    local clickType = string.lower(tostring(Settings.TriggerbotClickType or "Hold"))
    if clickType == "toggle" then return State.TriggerbotToggleActive end
    return State.TriggerbotHoldActive
end

local function isCamlockArmed()
    local clickType = string.lower(tostring(Settings.CamlockClickType or "Hold"))
    if clickType == "toggle" then return State.CamlockToggleActive end
    return State.CamlockHoldActive
end

local _cachedFocalLen = nil
local _cachedFOV      = nil
local _cachedVpY      = nil

local function studsToPixels(studs, depth)
    local vpY    = Camera.ViewportSize.Y
    local fov    = Camera.FieldOfView
    if fov ~= _cachedFOV or vpY ~= _cachedVpY then
        _cachedFOV      = fov
        _cachedVpY      = vpY
        _cachedFocalLen = vpY / (2 * math.tan(math.rad(fov) * 0.5))
    end
    return (studs / depth) * _cachedFocalLen
end

local function getRootAnchoredBoxForPart(part, padLeft, padRight, padUp, padDown)
    if not part or not Camera then return nil end
    local char = part.Parent
    if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local screenRoot, onScreen = Camera:WorldToViewportPoint(root.Position)
    if not onScreen or screenRoot.Z <= 0 then return nil end
    local depth = screenRoot.Z
    local cx    = screenRoot.X
    local cy    = screenRoot.Y
    local pixTop    = studsToPixels(3.0 + padUp,    depth)
    local pixBottom = studsToPixels(2.0 + padDown,  depth)
    local pixLeft   = studsToPixels(1.0 + padLeft,  depth)
    local pixRight  = studsToPixels(1.0 + padRight, depth)
    return {
        left    = cx - pixLeft,
        top     = cy - pixTop,
        width   = pixLeft + pixRight,
        height  = pixTop + pixBottom,
        centerX = cx,
        centerY = cy,
    }
end

local function getTriggerbotBoxForPart(part)
    local padLeft, padRight, padUp, padDown = getTriggerbotBounds()
    return getRootAnchoredBoxForPart(part, padLeft, padRight, padUp, padDown)
end

local function getCamlockBoxForPart(part)
    local padLeft, padRight, padUp, padDown = getCamlockBounds()
    return getRootAnchoredBoxForPart(part, padLeft, padRight, padUp, padDown)
end

local function isPartInsideTriggerFOV(part, precomputedBox)
    if not part or not Camera then return false end
    local mode     = string.lower(tostring(Settings.TriggerbotFOVType or "Box"))
    local mousePos = UIS:GetMouseLocation()
    local box      = precomputedBox or getTriggerbotBoxForPart(part)
    if not box then return false end
    if mode == "direct" then
        local dx = box.centerX - mousePos.X; local dy = box.centerY - mousePos.Y
        return (dx * dx + dy * dy) <= 9
    end
    return mousePos.X >= box.left and mousePos.X <= (box.left + box.width)
        and mousePos.Y >= box.top  and mousePos.Y <= (box.top  + box.height)
end

local function isPartInsideCamlockFOV(part, precomputedBox)
    if not part or not Camera then return false end
    local mode     = string.lower(tostring(Settings.CamlockFOVType or "Box"))
    local mousePos = UIS:GetMouseLocation()
    local box      = precomputedBox or getCamlockBoxForPart(part)
    if not box then return false end
    if mode == "direct" then
        local dx = box.centerX - mousePos.X; local dy = box.centerY - mousePos.Y
        return (dx * dx + dy * dy) <= 9
    end
    return mousePos.X >= box.left and mousePos.X <= (box.left + box.width)
        and mousePos.Y >= box.top  and mousePos.Y <= (box.top  + box.height)
end

local function isPartInTriggerDistance(part)
    if not part then return false end
    local maxDistance = tonumber(Settings.TriggerbotDistance) or 210
    if maxDistance <= 0 then return true end
    local char   = LP.Character
    local root   = char and char:FindFirstChild("HumanoidRootPart")
    local origin = root and root.Position or (Camera and Camera.CFrame.Position)
    if not origin then return false end
    local diff = part.Position - origin
    return (diff.X * diff.X + diff.Y * diff.Y + diff.Z * diff.Z) <= (maxDistance * maxDistance)
end

local function isPartInCamlockDistance(part)
    if not part then return false end
    local maxDistance = tonumber(Settings.CamlockDistance) or 300
    if maxDistance <= 0 then return true end
    local char   = LP.Character
    local root   = char and char:FindFirstChild("HumanoidRootPart")
    local origin = root and root.Position or (Camera and Camera.CFrame.Position)
    if not origin then return false end
    local diff = part.Position - origin
    return (diff.X * diff.X + diff.Y * diff.Y + diff.Z * diff.Z) <= (maxDistance * maxDistance)
end

local function applyEase(t, style, direction)
    t = math.clamp(t, 0, 1)
    local s = string.lower(tostring(style or "Linear"))
    local d = string.lower(tostring(direction or "In"))
    if s == "linear" then return t end
    local inFn
    if s == "quad" then
        inFn = function(x) return x * x end
    elseif s == "cubic" then
        inFn = function(x) return x * x * x end
    elseif s == "quart" then
        inFn = function(x) return x * x * x * x end
    elseif s == "sine" then
        inFn = function(x) return 1 - math.cos((x * math.pi) * 0.5) end
    elseif s == "exponential" then
        inFn = function(x) return x == 0 and 0 or (2 ^ (10 * (x - 1))) end
    elseif s == "circular" then
        inFn = function(x) return 1 - math.sqrt(1 - x * x) end
    elseif s == "back" then
        inFn = function(x) local c = 1.70158; return x * x * ((c + 1) * x - c) end
    elseif s == "bounce" then
        local function bounceOut(x)
            if x < 1 / 2.75 then return 7.5625 * x * x
            elseif x < 2 / 2.75 then x = x - 1.5 / 2.75; return 7.5625 * x * x + 0.75
            elseif x < 2.5 / 2.75 then x = x - 2.25 / 2.75; return 7.5625 * x * x + 0.9375
            else x = x - 2.625 / 2.75; return 7.5625 * x * x + 0.984375 end
        end
        inFn = function(x) return 1 - bounceOut(1 - x) end
    elseif s == "elastic" then
        inFn = function(x)
            if x == 0 or x == 1 then return x end
            return -(2 ^ (10 * (x - 1))) * math.sin((x - 1.1) * 2 * math.pi / 0.4)
        end
    else
        inFn = function(x) return x end
    end
    if d == "out" then
        return 1 - inFn(1 - t)
    elseif d == "inout" then
        if t < 0.5 then return 0.5 * inFn(t * 2) end
        return 1 - 0.5 * inFn((1 - t) * 2)
    end
    return inFn(t)
end

local function fireTriggerbotAtPart(part)
    if not part then return end
    local equippedTool = getEquippedTool()
    if not equippedTool then return end
    if isKnifeTool(equippedTool) then return end
    local char = LP.Character
    if getReloadingFlag(char) then return end
    if not canTriggerbotShootNow() then return end

    local now = os.clock()
    local delaySeconds = getTriggerbotDelaySeconds()
    State.LastTriggerShot = now
    State.NextTriggerShot = now + delaySeconds

    local activated = safeCall(function() equippedTool:Activate() end, "FireServerFails")
    if not activated then
        State.NextTriggerShot = now
    end
end

local function runTriggerbot(part)
    if not Settings.TriggerbotEnabled then return nil end
    if not isTriggerbotArmed() then return nil end
    if not part then return nil end
    Camera = workspace.CurrentCamera
    if not isPartInTriggerDistance(part) then return nil end
    local box = getTriggerbotBoxForPart(part)
    if not isPartInsideTriggerFOV(part, box) then return box end
    if not canTriggerbotShootNow() then return box end
    fireTriggerbotAtPart(part)
    return box
end

local function runCamlock(part)
    if not Settings.CamlockEnabled then return nil end
    if not isCamlockArmed() then return nil end
    if not part then return nil end
    if not isPartInCamlockDistance(part) then return nil end
    Camera = workspace.CurrentCamera

    local lookAtPos = part.Position
    local resolvedPos, resolvedPart = getCamlockAimPosition(part)
    if resolvedPos then lookAtPos = resolvedPos end
    if resolvedPart then part = resolvedPart end

    local box = getCamlockBoxForPart(part)
    if not isPartInsideCamlockFOV(part, box) then return box end
    local camPos = Camera and Camera.CFrame.Position
    if not camPos then return box end
    local desired = CFrame.new(camPos, lookAtPos)
    local smooth = tonumber(Settings.CamlockSmoothness) or 0.043
    local alpha = applyEase(smooth, Settings.CamlockEasingStyle, Settings.CamlockEasingDirection)
    Camera.CFrame = Camera.CFrame:Lerp(desired, math.clamp(alpha, 0, 1))
    return box
end

local TriggerbotFOVBox = nil
local CamlockFOVBox = nil

local function hideTriggerbotFOVBox()
    if TriggerbotFOVBox then TriggerbotFOVBox.Visible = false end
end

local function ensureTriggerbotFOVBox()
    if TriggerbotFOVBox or not Drawing then return end
    local ok, box = pcall(function() return Drawing.new("Square") end)
    if not ok or not box then return end
    box.Visible = false; box.Filled = false; box.Thickness = 1
    box.Transparency = 1; box.Color = Color3.fromRGB(255, 255, 255)
    TriggerbotFOVBox = box
end

local function updateTriggerbotFOVBox(part, precomputedBox)
    if not Settings.TriggerbotFOVVisualizeEnabled then hideTriggerbotFOVBox(); return end
    ensureTriggerbotFOVBox()
    if not TriggerbotFOVBox then return end
    if not part then hideTriggerbotFOVBox(); return end
    local box = precomputedBox or getTriggerbotBoxForPart(part)
    if not box then hideTriggerbotFOVBox(); return end
    TriggerbotFOVBox.Size     = Vector2.new(box.width, box.height)
    TriggerbotFOVBox.Position = Vector2.new(box.left, box.top)
    local baseColor     = Settings.TriggerbotFOVVisualizeColor or Color3.fromRGB(255, 255, 255)
    local hoverEnabled  = Settings.TriggerbotFOVVisualizeHover ~= false
    local mousePos      = UIS:GetMouseLocation()
    local isHovering    = mousePos.X >= box.left and mousePos.X <= (box.left + box.width)
                       and mousePos.Y >= box.top  and mousePos.Y <= (box.top  + box.height)
    TriggerbotFOVBox.Color   = (isHovering and hoverEnabled) and (Settings.SelectionColor or baseColor) or baseColor
    TriggerbotFOVBox.Visible = true
end

local function hideCamlockFOVBox()
    if CamlockFOVBox then CamlockFOVBox.Visible = false end
end

local function ensureCamlockFOVBox()
    if CamlockFOVBox or not Drawing then return end
    local ok, box = pcall(function() return Drawing.new("Square") end)
    if not ok or not box then return end
    box.Visible = false; box.Filled = false; box.Thickness = 1
    box.Transparency = 1; box.Color = Color3.fromRGB(255, 255, 255)
    CamlockFOVBox = box
end

local function updateCamlockFOVBox(part, precomputedBox)
    if not Settings.CamlockFOVVisualizeEnabled then hideCamlockFOVBox(); return end
    ensureCamlockFOVBox()
    if not CamlockFOVBox then return end
    if not part then hideCamlockFOVBox(); return end
    local box = precomputedBox or getCamlockBoxForPart(part)
    if not box then hideCamlockFOVBox(); return end
    CamlockFOVBox.Size     = Vector2.new(box.width, box.height)
    CamlockFOVBox.Position = Vector2.new(box.left, box.top)
    local baseColor     = Settings.CamlockFOVVisualizeColor or Color3.fromRGB(255, 255, 255)
    local hoverEnabled  = Settings.CamlockFOVVisualizeHover == true
    local mousePos      = UIS:GetMouseLocation()
    local isHovering    = mousePos.X >= box.left and mousePos.X <= (box.left + box.width)
                       and mousePos.Y >= box.top  and mousePos.Y <= (box.top  + box.height)
    CamlockFOVBox.Color   = (isHovering and hoverEnabled) and (Settings.SelectionColor or baseColor) or baseColor
    CamlockFOVBox.Visible = true
end

local function cleanupFOVBox()
    if TriggerbotFOVBox then
        pcall(function() TriggerbotFOVBox.Visible = false; TriggerbotFOVBox:Remove() end)
        TriggerbotFOVBox = nil
    end
    if CamlockFOVBox then
        pcall(function() CamlockFOVBox.Visible = false; CamlockFOVBox:Remove() end)
        CamlockFOVBox = nil
    end
end

local function init(deps)
    Settings             = deps.Settings
    State                = deps.State
    safeCall             = deps.safeCall
    MainEvent            = deps.MainEvent
    GH                   = deps.GH
    Camera               = deps.Camera
    cloneArgs            = deps.cloneArgs
    applyRangePolicy     = deps.applyRangePolicy
    getSpreadAimPosition = deps.getSpreadAimPosition
    getCamlockAimPosition= deps.getCamlockAimPosition
    isTargetFeatureAllowed = deps.isTargetFeatureAllowed
end

return {
    init                    = init,
    applySpeedModification  = applySpeedModification,
    resetSpeedModification  = resetSpeedModification,
    panicGround             = panicGround,

    runTriggerbot           = runTriggerbot,
    runCamlock              = runCamlock,
    updateTriggerbotFOVBox  = updateTriggerbotFOVBox,
    updateCamlockFOVBox     = updateCamlockFOVBox,
    hideTriggerbotFOVBox    = hideTriggerbotFOVBox,
    hideCamlockFOVBox       = hideCamlockFOVBox,
    cleanupFOVBox           = cleanupFOVBox,
    isPartInTriggerDistance = isPartInTriggerDistance,
    isPartInCamlockDistance = isPartInCamlockDistance,
    getEquippedTool         = getEquippedTool,
    isKnifeTool             = isKnifeTool,
    getReloadingFlag        = getReloadingFlag,
}
