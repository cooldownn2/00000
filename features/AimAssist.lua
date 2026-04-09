local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")

local AimAssist = {}

local LP       = Players.LocalPlayer
local Settings, State, safeCall, Camera
local getCamlockAimPosition
local Movement

-- ── Fixed-pixel FOV helpers ───────────────────────────────────────────────────
-- Box is anchored to the target's screen position (not the cursor).
-- Size is fixed pixels — does NOT scale with distance.
-- Width/Height configs are {Left, Right} / {Up, Down} in pixels.
local function readPad(cfg, fallback, firstKey, secondKey)
    if type(cfg) == "table" then
        local a = tonumber(cfg[firstKey]) or tonumber(cfg[1]) or fallback
        local b = tonumber(cfg[secondKey]) or tonumber(cfg[2]) or fallback
        return a, b
    end
    local v = tonumber(cfg) or fallback
    return v, v
end

local function isInsideTargetBox(cam, part, wKey, hKey)
    local sp, onScreen = cam:WorldToViewportPoint(part.Position)
    if not onScreen or sp.Z <= 0 then return false end
    local mp = UIS:GetMouseLocation()
    local padL, padR = readPad(Settings[wKey], 10, "Left", "Right")
    local padU, padD = readPad(Settings[hKey], 10, "Up", "Down")
    local dx = mp.X - sp.X
    local dy = mp.Y - sp.Y
    return dx >= -padL and dx <= padR
        and dy >= -padU and dy <= padD
end

local function isInsideDirect(cam, part)
    local sp, onScreen = cam:WorldToViewportPoint(part.Position)
    if not onScreen or sp.Z <= 0 then return false end
    local mp = UIS:GetMouseLocation()
    local dx, dy = sp.X - mp.X, sp.Y - mp.Y
    return (dx * dx + dy * dy) <= 9
end

-- ── Triggerbot ────────────────────────────────────────────────────────────────

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

local function isPartInsideTriggerFOV(part)
    if not part then return false end
    local cam = workspace.CurrentCamera
    if not cam then return false end
    if string.lower(tostring(Settings.TriggerbotFOVType or "Box")) == "direct" then
        return isInsideDirect(cam, part)
    end
    return isInsideTargetBox(cam, part, "TriggerbotFOVWidth", "TriggerbotFOVHeight")
end

local function isPartInsideCamlockFOV(part)
    if not part then return false end
    local cam = workspace.CurrentCamera
    if not cam then return false end
    if string.lower(tostring(Settings.CamlockFOVType or "Box")) == "direct" then
        return isInsideDirect(cam, part)
    end
    return isInsideTargetBox(cam, part, "CamlockFOVWidth", "CamlockFOVHeight")
end

local function isPartInTriggerDistance(part)
    if not part then return false end
    local maxDistance = tonumber(Settings.TriggerbotDistance) or 210
    if maxDistance <= 0 then return true end
    local char   = LP.Character
    local root   = char and char:FindFirstChild("HumanoidRootPart")
    local origin = root and root.Position or (Camera and Camera.CFrame.Position)
    if not origin then return false end
    local d = part.Position - origin
    return (d.X * d.X + d.Y * d.Y + d.Z * d.Z) <= (maxDistance * maxDistance)
end

local function isPartInCamlockDistance(part)
    if not part then return false end
    local maxDistance = tonumber(Settings.CamlockDistance) or 300
    if maxDistance <= 0 then return true end
    local char   = LP.Character
    local root   = char and char:FindFirstChild("HumanoidRootPart")
    local origin = root and root.Position or (Camera and Camera.CFrame.Position)
    if not origin then return false end
    local d = part.Position - origin
    return (d.X * d.X + d.Y * d.Y + d.Z * d.Z) <= (maxDistance * maxDistance)
end

-- ── Silent Aim FOV ────────────────────────────────────────────────────────────
-- Gates whether the shot redirect should fire:
--   SilentAimFOVEnabled = false  → no gate, always redirect (default behaviour)
--   SilentAimFOVEnabled = true   → only redirect when target is inside the box
--   SilentAimIgnoreFOV  = true   → bypass — always redirect regardless of box
local function isPartInsideSilentAimFOV(part)
    if not Settings.SilentAimFOVEnabled then return true end
    if Settings.SilentAimIgnoreFOV       then return true end
    if not part then return false end
    local cam = workspace.CurrentCamera
    if not cam then return false end
    return isInsideTargetBox(cam, part, "SilentAimFOVWidth", "SilentAimFOVHeight")
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
    if not Settings.TriggerbotEnabled then return end
    if not isTriggerbotArmed() then return end
    if not part then return end
    if not isPartInTriggerDistance(part) then return end
    if not isPartInsideTriggerFOV(part) then return end
    if not canTriggerbotShootNow() then return end
    fireTriggerbotAtPart(part)
end

local function runCamlock(part)
    if not Settings.CamlockEnabled then return end
    if not isCamlockArmed() then return end
    if not part then return end
    if not isPartInCamlockDistance(part) then return end
    if not isPartInsideCamlockFOV(part) then return end
    local cam = workspace.CurrentCamera
    if not cam then return end
    Camera = cam
    local lookAtPos = part.Position
    local resolvedPos, resolvedPart = getCamlockAimPosition(part)
    if resolvedPos then lookAtPos = resolvedPos end
    if resolvedPart then part = resolvedPart end
    local desired = CFrame.new(cam.CFrame.Position, lookAtPos)
    local smooth  = tonumber(Settings.CamlockSmoothness) or 0.043
    local alpha   = applyEase(smooth, Settings.CamlockEasingStyle, Settings.CamlockEasingDirection)
    cam.CFrame    = cam.CFrame:Lerp(desired, math.clamp(alpha, 0, 1))
end

local function init(deps)
    Settings = deps.Settings
    State = deps.State
    safeCall = deps.safeCall
    Camera = deps.Camera
    getCamlockAimPosition = deps.getCamlockAimPosition
    Movement = deps.Movement
end

AimAssist.init                     = init
AimAssist.runTriggerbot            = runTriggerbot
AimAssist.runCamlock               = runCamlock
AimAssist.isPartInsideTriggerFOV   = isPartInsideTriggerFOV
AimAssist.isPartInsideCamlockFOV   = isPartInsideCamlockFOV
AimAssist.isPartInsideSilentAimFOV = isPartInsideSilentAimFOV
AimAssist.isPartInTriggerDistance  = isPartInTriggerDistance
AimAssist.isPartInCamlockDistance  = isPartInCamlockDistance

return AimAssist