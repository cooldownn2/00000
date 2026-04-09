local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")

local Triggerbot = {}

-- Localized globals for hot-path usage.
local tan   = math.tan
local rad   = math.rad
local clock = os.clock
local V3new = Vector3.new

local LP = Players.LocalPlayer
local Settings, State, safeCall, Movement

-- Focal-length cache only recomputed when viewport/FOV changes.
local _cachedFocalLen = nil
local _cachedFOV      = nil
local _cachedVpY      = nil

-- Reused table to avoid per-frame allocations while drawing/validating FOV box.
local _tbBox = { left = 0, top = 0, width = 0, height = 0, centerX = 0, centerY = 0 }

local _tbLeft, _tbRight, _tbUp, _tbDown
local _tbDelaySeconds = 0
local _tbFOVMode      = "box"
local _tbClickToggle  = false
local _tbMaxDistSq    = 0

local function studsToPixels(studs, depth, cam)
    local vpY = cam.ViewportSize.Y
    local fov = cam.FieldOfView
    if fov ~= _cachedFOV or vpY ~= _cachedVpY then
        _cachedFOV      = fov
        _cachedVpY      = vpY
        _cachedFocalLen = vpY / (2 * tan(rad(fov) * 0.5))
    end
    return (studs / depth) * _cachedFocalLen
end

local function computeBox(part, out)
    local cam = workspace.CurrentCamera
    if not part or not cam then return nil end

    local char = part.Parent
    if not char then return nil end

    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end

    local screenRoot, onScreen = cam:WorldToViewportPoint(root.Position)
    if not onScreen or screenRoot.Z <= 0 then return nil end

    local depth = screenRoot.Z
    local cx    = screenRoot.X
    local cy    = screenRoot.Y

    local topY
    local head = char:FindFirstChild("Head")
    if head then
        local screenHead, headVisible = cam:WorldToViewportPoint(
            head.Position + V3new(0, head.Size.Y * 0.5, 0)
        )
        if headVisible and screenHead.Z > 0 then
            topY = screenHead.Y
        end
    end

    if not topY then
        topY = cy - studsToPixels(3.0, depth, cam)
    end

    local bottomY = cy + studsToPixels(2.5, depth, cam)

    local padTopPx    = studsToPixels(_tbUp,           depth, cam)
    local padBottomPx = studsToPixels(_tbDown,         depth, cam)
    local padLeftPx   = studsToPixels(1.0 + _tbLeft,   depth, cam)
    local padRightPx  = studsToPixels(1.0 + _tbRight,  depth, cam)

    out.left    = cx - padLeftPx
    out.top     = topY - padTopPx
    out.width   = padLeftPx + padRightPx
    out.height  = (bottomY - topY) + padTopPx + padBottomPx
    out.centerX = cx
    out.centerY = (topY + bottomY) * 0.5
    return out
end

local function getBoxForPart(part)
    return computeBox(part, _tbBox)
end

local function isPartInsideTriggerFOV(box)
    if not box then return false end
    local mousePos = UIS:GetMouseLocation()
    if _tbFOVMode == "direct" then
        local dx = box.centerX - mousePos.X
        local dy = box.centerY - mousePos.Y
        return (dx * dx + dy * dy) <= 9
    end

    return mousePos.X >= box.left and mousePos.X <= (box.left + box.width)
        and mousePos.Y >= box.top and mousePos.Y <= (box.top + box.height)
end

local function isPartInDistance(part)
    if _tbMaxDistSq <= 0 then return true end

    local char   = LP.Character
    local root   = char and char:FindFirstChild("HumanoidRootPart")
    local cam    = workspace.CurrentCamera
    local origin = root and root.Position or (cam and cam.CFrame.Position)
    if not origin then return false end

    local diff = part.Position - origin
    return (diff.X * diff.X + diff.Y * diff.Y + diff.Z * diff.Z) <= _tbMaxDistSq
end

local function isArmed()
    if _tbClickToggle then return State.TriggerbotToggleActive end
    return State.TriggerbotHoldActive
end

local function canShootNow()
    return (clock() - (State.LastTriggerShot or 0)) >= _tbDelaySeconds
end

local function fireAtPart(part)
    local equippedTool = Movement.getEquippedTool()
    if not equippedTool then return end
    if Movement.isKnifeTool(equippedTool) then return end
    if Movement.getReloadingFlag() then return end

    local now = clock()
    State.LastTriggerShot = now
    State.NextTriggerShot = now + _tbDelaySeconds

    local activated = safeCall(function() equippedTool:Activate() end, "FireServerFails")
    if not activated then
        State.NextTriggerShot = now
    end
end

local function run(part)
    if not Settings.TriggerbotEnabled then return nil end
    if not isArmed() then return nil end
    if not part then return nil end
    if not isPartInDistance(part) then return nil end

    local box = getBoxForPart(part)
    if not isPartInsideTriggerFOV(box) then return box end
    if not canShootNow() then return box end

    fireAtPart(part)
    return box
end

local function parseBounds(widthSetting, heightSetting, defaultPad)
    local w     = widthSetting
    local h     = heightSetting
    local left  = type(w) == "table" and tonumber(w[1]) or tonumber(w)
    local right = type(w) == "table" and tonumber(w[2]) or tonumber(w)
    local up    = type(h) == "table" and tonumber(h[1]) or tonumber(h)
    local down  = type(h) == "table" and tonumber(h[2]) or tonumber(h)
    local d     = defaultPad
    return math.max(left  or d, 0), math.max(right or d, 0),
           math.max(up    or d, 0), math.max(down  or d, 0)
end

local function init(deps)
    Settings = deps.Settings
    State    = deps.State
    safeCall = deps.safeCall
    Movement = deps.Movement

    _tbLeft, _tbRight, _tbUp, _tbDown =
        parseBounds(Settings.TriggerbotFOVWidth, Settings.TriggerbotFOVHeight, 1)

    local rawDelay = math.max(tonumber(Settings.TriggerbotDelay) or 0, 0)
    _tbDelaySeconds = rawDelay >= 1 and (rawDelay / 1000) or rawDelay

    _tbFOVMode = string.lower(tostring(Settings.TriggerbotFOVType or "Box"))
    _tbClickToggle = string.lower(tostring(Settings.TriggerbotClickType or "Hold")) == "toggle"

    local tbDist = tonumber(Settings.TriggerbotDistance) or 210
    _tbMaxDistSq = tbDist > 0 and (tbDist * tbDist) or 0
end

Triggerbot.init = init
Triggerbot.run = run
Triggerbot.getBoxForPart = getBoxForPart
Triggerbot.isPartInDistance = isPartInDistance

return Triggerbot
