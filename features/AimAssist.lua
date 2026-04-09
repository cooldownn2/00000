local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")

local AimAssist = {}

local LP = Players.LocalPlayer
local Settings, State, safeCall, Camera
local getCamlockAimPosition
local Movement

local _cachedFocalLen = nil
local _cachedFOV = nil
local _cachedVpY = nil

local function getTriggerbotBounds()
    local width = Settings.TriggerbotFOVWidth
    local height = Settings.TriggerbotFOVHeight
    local left = type(width) == "table" and tonumber(width[1]) or tonumber(width)
    local right = type(width) == "table" and tonumber(width[2]) or tonumber(width)
    local up = type(height) == "table" and tonumber(height[1]) or tonumber(height)
    local down = type(height) == "table" and tonumber(height[2]) or tonumber(height)
    return math.max(left or 1, 0), math.max(right or 1, 0), math.max(up or 1, 0), math.max(down or 1, 0)
end

local function getCamlockBounds()
    local width = Settings.CamlockFOVWidth
    local height = Settings.CamlockFOVHeight
    local left = type(width) == "table" and tonumber(width[1]) or tonumber(width)
    local right = type(width) == "table" and tonumber(width[2]) or tonumber(width)
    local up = type(height) == "table" and tonumber(height[1]) or tonumber(height)
    local down = type(height) == "table" and tonumber(height[2]) or tonumber(height)
    return math.max(left or 6, 0), math.max(right or 6, 0), math.max(up or 6, 0), math.max(down or 6, 0)
end

local function getTriggerbotDelaySeconds()
    local raw = tonumber(Settings.TriggerbotDelay) or 0
    raw = math.max(raw, 0)
    if raw >= 1 then return raw / 1000 end
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

local function studsToPixels(studs, depth)
    local vpY = Camera.ViewportSize.Y
    local fov = Camera.FieldOfView
    if fov ~= _cachedFOV or vpY ~= _cachedVpY then
        _cachedFOV = fov
        _cachedVpY = vpY
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
    local cx = screenRoot.X
    local cy = screenRoot.Y
    local pixTop = studsToPixels(3.0 + padUp, depth)
    local pixBottom = studsToPixels(2.0 + padDown, depth)
    local pixLeft = studsToPixels(1.0 + padLeft, depth)
    local pixRight = studsToPixels(1.0 + padRight, depth)

    return {
        left = cx - pixLeft,
        top = cy - pixTop,
        width = pixLeft + pixRight,
        height = pixTop + pixBottom,
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
    local mode = string.lower(tostring(Settings.TriggerbotFOVType or "Box"))
    local mousePos = UIS:GetMouseLocation()
    local box = precomputedBox or getTriggerbotBoxForPart(part)
    if not box then return false end

    if mode == "direct" then
        local dx = box.centerX - mousePos.X
        local dy = box.centerY - mousePos.Y
        return (dx * dx + dy * dy) <= 9
    end

    return mousePos.X >= box.left and mousePos.X <= (box.left + box.width)
        and mousePos.Y >= box.top and mousePos.Y <= (box.top + box.height)
end

local function isPartInsideCamlockFOV(part, precomputedBox)
    if not part or not Camera then return false end
    local mode = string.lower(tostring(Settings.CamlockFOVType or "Box"))
    local mousePos = UIS:GetMouseLocation()
    local box = precomputedBox or getCamlockBoxForPart(part)
    if not box then return false end

    if mode == "direct" then
        local dx = box.centerX - mousePos.X
        local dy = box.centerY - mousePos.Y
        return (dx * dx + dy * dy) <= 9
    end

    return mousePos.X >= box.left and mousePos.X <= (box.left + box.width)
        and mousePos.Y >= box.top and mousePos.Y <= (box.top + box.height)
end

local function isPartInTriggerDistance(part)
    if not part then return false end
    local maxDistance = tonumber(Settings.TriggerbotDistance) or 210
    if maxDistance <= 0 then return true end

    local char = LP.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local origin = root and root.Position or (Camera and Camera.CFrame.Position)
    if not origin then return false end

    local diff = part.Position - origin
    return (diff.X * diff.X + diff.Y * diff.Y + diff.Z * diff.Z) <= (maxDistance * maxDistance)
end

local function isPartInCamlockDistance(part)
    if not part then return false end
    local maxDistance = tonumber(Settings.CamlockDistance) or 300
    if maxDistance <= 0 then return true end

    local char = LP.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
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

    local equippedTool = Movement.getEquippedTool()
    if not equippedTool then return end
    if Movement.isKnifeTool(equippedTool) then return end

    if Movement.getReloadingFlag() then return end
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

local function init(deps)
    Settings = deps.Settings
    State = deps.State
    safeCall = deps.safeCall
    Camera = deps.Camera
    getCamlockAimPosition = deps.getCamlockAimPosition
    Movement = deps.Movement
end

AimAssist.init = init
AimAssist.runTriggerbot = runTriggerbot
AimAssist.runCamlock = runCamlock
AimAssist.getTriggerbotBoxForPart = getTriggerbotBoxForPart
AimAssist.getCamlockBoxForPart = getCamlockBoxForPart
AimAssist.isPartInTriggerDistance = isPartInTriggerDistance
AimAssist.isPartInCamlockDistance = isPartInCamlockDistance

return AimAssist