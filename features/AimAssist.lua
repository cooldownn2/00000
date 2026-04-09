local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")

local AimAssist = {}

-- Localized globals — avoids _ENV table lookup on every hot-path call
local clamp = math.clamp
local tan   = math.tan
local rad   = math.rad
local cos   = math.cos
local sin   = math.sin
local sqrt  = math.sqrt
local CFnew = CFrame.new
local V3new = Vector3.new

local LP = Players.LocalPlayer
local Settings, State
local getCamlockAimPosition

-- ── Focal length cache ────────────────────────────────────────────────────────
-- Only recomputed when FOV or viewport height actually changes.
local _cachedFocalLen = nil
local _cachedFOV      = nil
local _cachedVpY      = nil

-- ── Reusable box tables — zero per-frame heap allocation ──────────────────────
local _cbBox = { left = 0, top = 0, width = 0, height = 0, centerX = 0, centerY = 0 }

-- ── Settings cached once in init — none change at runtime ─────────────────────
local _cbLeft, _cbRight, _cbUp, _cbDown   -- camlock FOV padding (studs)
local _cbFOVMode      = "box"
local _cbClickToggle  = false
local _cbMaxDistSq    = 0
local _cbSmooth       = 0.043             -- camlock lerp alpha
local _cbEaseDir      = "in"              -- cached lowercase ease direction

-- ── Easing — all closures allocated once at module load, never per-frame ──────
local _pi = math.pi

local function _bounceOut(x)
    if x < 1 / 2.75 then
        return 7.5625 * x * x
    elseif x < 2 / 2.75 then
        x = x - 1.5 / 2.75; return 7.5625 * x * x + 0.75
    elseif x < 2.5 / 2.75 then
        x = x - 2.25 / 2.75; return 7.5625 * x * x + 0.9375
    else
        x = x - 2.625 / 2.75; return 7.5625 * x * x + 0.984375
    end
end

local EASE_IN = {
    linear      = function(x) return x end,
    quad        = function(x) return x * x end,
    cubic       = function(x) return x * x * x end,
    quart       = function(x) return x * x * x * x end,
    sine        = function(x) return 1 - cos(x * _pi * 0.5) end,
    exponential = function(x) return x == 0 and 0 or (2 ^ (10 * (x - 1))) end,
    circular    = function(x) return 1 - sqrt(1 - x * x) end,
    back        = function(x) local c = 1.70158; return x * x * ((c + 1) * x - c) end,
    bounce      = function(x) return 1 - _bounceOut(1 - x) end,
    elastic     = function(x)
        if x == 0 or x == 1 then return x end
        return -(2 ^ (10 * (x - 1))) * sin((x - 1.1) * 2 * _pi / 0.4)
    end,
}

-- Resolved once in init — no per-frame lookup or allocation.
local _easeInFn = EASE_IN.linear

local function applyEase(t)
    t = clamp(t, 0, 1)
    local fn = _easeInFn
    if _cbEaseDir == "out" then
        return 1 - fn(1 - t)
    elseif _cbEaseDir == "inout" then
        if t < 0.5 then return 0.5 * fn(t * 2) end
        return 1 - 0.5 * fn((1 - t) * 2)
    end
    return fn(t)
end

-- ── Projection ────────────────────────────────────────────────────────────────
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

-- ── Box computation ───────────────────────────────────────────────────────────
-- Writes into the reusable `out` table. Returns `out` on success, nil on failure.
local function computeBox(part, padLeft, padRight, padUp, padDown, out)
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

    -- Project actual head top for accurate upper bound (handles crouching/jumping).
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

    local padTopPx    = studsToPixels(padUp,         depth, cam)
    local padBottomPx = studsToPixels(padDown,        depth, cam)
    local padLeftPx   = studsToPixels(1.0 + padLeft,  depth, cam)
    local padRightPx  = studsToPixels(1.0 + padRight, depth, cam)

    out.left    = cx - padLeftPx
    out.top     = topY - padTopPx
    out.width   = padLeftPx + padRightPx
    out.height  = (bottomY - topY) + padTopPx + padBottomPx
    out.centerX = cx
    out.centerY = (topY + bottomY) * 0.5
    return out
end

local function getCamlockBoxForPart(part)
    return computeBox(part, _cbLeft, _cbRight, _cbUp, _cbDown, _cbBox)
end

local function isPartInsideCamlockFOV(box)
    if not box then return false end
    local mousePos = UIS:GetMouseLocation()
    if _cbFOVMode == "direct" then
        local dx = box.centerX - mousePos.X
        local dy = box.centerY - mousePos.Y
        return (dx * dx + dy * dy) <= 9
    end
    return mousePos.X >= box.left and mousePos.X <= (box.left + box.width)
        and mousePos.Y >= box.top  and mousePos.Y <= (box.top  + box.height)
end

local function isPartInCamlockDistance(part)
    if _cbMaxDistSq <= 0 then return true end
    local char   = LP.Character
    local root   = char and char:FindFirstChild("HumanoidRootPart")
    local cam    = workspace.CurrentCamera
    local origin = root and root.Position or (cam and cam.CFrame.Position)
    if not origin then return false end
    local diff = part.Position - origin
    return (diff.X * diff.X + diff.Y * diff.Y + diff.Z * diff.Z) <= _cbMaxDistSq
end

-- ── Armed state ───────────────────────────────────────────────────────────────
local function isCamlockArmed()
    if _cbClickToggle then return State.CamlockToggleActive end
    return State.CamlockHoldActive
end

local function runCamlock(part)
    if not Settings.CamlockEnabled  then return nil end
    if not isCamlockArmed()          then return nil end
    if not part                       then return nil end
    if not isPartInCamlockDistance(part) then return nil end

    local lookAtPos = part.Position
    local resolvedPos, resolvedPart = getCamlockAimPosition(part)
    if resolvedPos  then lookAtPos = resolvedPos end
    if resolvedPart then part = resolvedPart end

    local box = getCamlockBoxForPart(part)
    if not isPartInsideCamlockFOV(box) then return box end

    local cam = workspace.CurrentCamera
    if not cam then return box end

    local desired = CFnew(cam.CFrame.Position, lookAtPos)
    cam.CFrame    = cam.CFrame:Lerp(desired, clamp(applyEase(_cbSmooth), 0, 1))
    return box
end

-- ── Init — parse and cache all settings values for the session ────────────────
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
    Settings              = deps.Settings
    State                 = deps.State
    getCamlockAimPosition = deps.getCamlockAimPosition
    _cbLeft, _cbRight, _cbUp, _cbDown =
        parseBounds(Settings.CamlockFOVWidth, Settings.CamlockFOVHeight, 6)
    _cbFOVMode = string.lower(tostring(Settings.CamlockFOVType    or "Box"))
    _cbClickToggle = string.lower(tostring(Settings.CamlockClickType    or "Hold")) == "toggle"
    local cbDist = tonumber(Settings.CamlockDistance)    or 300
    _cbMaxDistSq = cbDist > 0 and (cbDist * cbDist) or 0

    _cbSmooth  = tonumber(Settings.CamlockSmoothness)        or 0.043
    _cbEaseDir = string.lower(tostring(Settings.CamlockEasingDirection or "In"))
    _easeInFn  = EASE_IN[string.lower(tostring(Settings.CamlockEasingStyle or "Linear"))]
              or EASE_IN.linear
end

-- ── Exports ───────────────────────────────────────────────────────────────────
AimAssist.init                    = init
AimAssist.runCamlock              = runCamlock
AimAssist.getCamlockBoxForPart    = getCamlockBoxForPart
AimAssist.isPartInCamlockDistance = isPartInCamlockDistance

return AimAssist