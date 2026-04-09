local UIS = game:GetService("UserInputService")

-- Localize hot-path globals
local clock  = os.clock
local floor  = math.floor
local clamp  = math.clamp
local sqrt   = math.sqrt
local tan    = math.tan
local rad    = math.rad
local huge   = math.huge
local max    = math.max
local min    = math.min
local V3new  = Vector3.new

local Settings, State, BODY_PART_NAMES

-- ── Constants ─────────────────────────────────────────────────────────────────
local CLOSEST_POINT_CACHE_MAX_AGE      = 1 / 120
local BODY_PART_SNAPSHOT_MAX_AGE       = 1 / 30
local CLOSEST_POINT_TIME_BUDGET_NORMAL = 0.0012
local CLOSEST_POINT_ACCEPT_DIST_SQ     = 3 * 3
local CLOSEST_POINT_EARLY_EXIT_DIST_SQ = 1.5 * 1.5
local CROSSHAIR_RAY_DISTANCE           = 5000
local CACHE_PRUNE_INTERVAL             = 5
local RAY_MAX_LOCK_DIST_SQ             = 28 * 28
local DEFAULT_SAMPLE_BUDGET            = 1200
local SCALE_STEP_MIN                   = 0.025
local SCALE_STEP_MAX                   = 0.50
local CENTER_SKIP_THRESHOLD            = 0.85

-- Lower value = higher priority (part is preferred when closest to crosshair).
-- HumanoidRootPart removed — it's no longer in BodyParts and is invisible.
local PART_PRIORITY = {
    Head       = 0.70,
    UpperTorso = 0.85,
    Torso      = 0.85,
}

-- ── Caches ────────────────────────────────────────────────────────────────────
-- Weak-keyed so entries are evicted automatically when their Instance is GC'd.
local closestPointCache      = setmetatable({}, { __mode = "k" })
local bodyPartsSnapshotCache = setmetatable({}, { __mode = "k" })
local surfaceSampleCache     = setmetatable({}, { __mode = "k" })
local sortedSampleCache      = setmetatable({}, { __mode = "k" })
local lastCachePrune         = 0

-- ── Cached ClosestPointScale — read from Settings once, not every frame ───────
-- Updated by getAimPosition on first call and whenever the value changes.
local _cachedScale      = nil
local _cachedScaleRaw   = nil  -- the raw settings value it was computed from

local function getClosestPointScale()
    local raw = Settings.ClosestPointScale
    if raw == _cachedScaleRaw then return _cachedScale end
    _cachedScaleRaw = raw
    local v = tonumber(raw)
    _cachedScale = v and clamp(v, 0, 1) or 0.35
    return _cachedScale
end

-- ── RaycastParams — reused, FilterDescendantsInstances only reassigned when
--    the body-parts snapshot has actually changed (avoids internal rebuild cost).
local PartRayParams = RaycastParams.new()
PartRayParams.FilterType  = Enum.RaycastFilterType.Include
PartRayParams.IgnoreWater = true
local _lastRayPartsRef = nil  -- reference to the last assigned parts array

-- ── Body parts snapshot ───────────────────────────────────────────────────────
local function collectBodyParts(char)
    local out = {}
    for _, part in ipairs(char:GetChildren()) do
        if part:IsA("BasePart") and BODY_PART_NAMES[part.Name] and part.Transparency < 1 then
            out[#out + 1] = part
        end
    end
    return out
end

local function getBodyPartsSnapshot(char)
    if not char then return {} end
    local now   = clock()
    local entry = bodyPartsSnapshotCache[char]
    if entry and (now - entry.timestamp) <= BODY_PART_SNAPSHOT_MAX_AGE then
        return entry.parts
    end
    local parts = collectBodyParts(char)
    if entry then
        -- Reuse the entry table — mutate in place to avoid a new allocation.
        entry.timestamp = now
        entry.parts     = parts
    else
        bodyPartsSnapshotCache[char] = { timestamp = now, parts = parts }
    end
    return parts
end

-- ── Cache management ──────────────────────────────────────────────────────────
local function resetCache()
    for k in pairs(closestPointCache) do closestPointCache[k] = nil end
end

local function pruneCaches(force)
    local now = clock()
    if not force and (now - lastCachePrune) < CACHE_PRUNE_INTERVAL then return end
    lastCachePrune = now
    for char in pairs(bodyPartsSnapshotCache) do
        if not char or char.Parent == nil then bodyPartsSnapshotCache[char] = nil end
    end
    for part in pairs(surfaceSampleCache) do
        if not part or part.Parent == nil then surfaceSampleCache[part] = nil end
    end
    for part in pairs(sortedSampleCache) do
        if not part or part.Parent == nil then sortedSampleCache[part] = nil end
    end
end

-- ── Screen-space distance helpers ────────────────────────────────────────────
local function getPartScreenDistanceSq(part, mouseX, mouseY)
    if not part then return huge end
    local cam = workspace.CurrentCamera
    if not cam then return huge end
    local screenPos, onScreen = cam:WorldToViewportPoint(part.Position)
    if not onScreen or screenPos.Z <= 0 then return huge end
    local dx = screenPos.X - mouseX
    local dy = screenPos.Y - mouseY
    return dx * dx + dy * dy
end

local function getWorldScreenDistanceSq(worldPos, mouseX, mouseY)
    if not worldPos then return huge end
    local cam = workspace.CurrentCamera
    if not cam then return huge end
    local screenPos, onScreen = cam:WorldToViewportPoint(worldPos)
    if not onScreen or screenPos.Z <= 0 then return huge end
    local dx = screenPos.X - mouseX
    local dy = screenPos.Y - mouseY
    return dx * dx + dy * dy
end

-- ── Part scoring ──────────────────────────────────────────────────────────────
local function getClosestPartToCrosshair(char, mouseX, mouseY)
    if not char then return nil end
    local cam      = workspace.CurrentCamera
    local fallback = char:FindFirstChild("Head") or char:FindFirstChildWhichIsA("BasePart")
    if not cam then return fallback end
    local bestPart, bestScore = nil, huge
    local parts = getBodyPartsSnapshot(char)
    for i = 1, #parts do
        local part = parts[i]
        local screenPos, onScreen = cam:WorldToViewportPoint(part.Position)
        if onScreen and screenPos.Z > 0 then
            local dx    = screenPos.X - mouseX
            local dy    = screenPos.Y - mouseY
            local score = (dx * dx + dy * dy) * max(screenPos.Z, 1) * (PART_PRIORITY[part.Name] or 1)
            if score < bestScore then
                bestScore = score
                bestPart  = part
            end
        end
    end
    return bestPart or fallback
end

-- ── Geometry helpers ──────────────────────────────────────────────────────────
local function getClosestPointOnPart(part, fromPos)
    if not part then return nil end
    local localPos = part.CFrame:PointToObjectSpace(fromPos)
    local half     = part.Size * 0.5
    return part.CFrame:PointToWorldSpace(V3new(
        clamp(localPos.X, -half.X, half.X),
        clamp(localPos.Y, -half.Y, half.Y),
        clamp(localPos.Z, -half.Z, half.Z)
    ))
end

local function quantizePointOnPart(part, worldPos, step)
    if not part or not step or step <= 0 then return worldPos end
    local localPos = part.CFrame:PointToObjectSpace(worldPos)
    local half     = part.Size * 0.5
    return part.CFrame:PointToWorldSpace(V3new(
        clamp(floor((localPos.X / step) + 0.5) * step, -half.X, half.X),
        clamp(floor((localPos.Y / step) + 0.5) * step, -half.Y, half.Y),
        clamp(floor((localPos.Z / step) + 0.5) * step, -half.Z, half.Z)
    ))
end

local function getProjectedPointOnRay(origin, dir, worldPos)
    if not origin or not dir or not worldPos then return worldPos end
    local t = (worldPos - origin):Dot(dir)
    return origin + dir * (t > 0 and t or 0)
end

-- ── Step / sample budget ──────────────────────────────────────────────────────
local function getStepFromScale(scale)
    return SCALE_STEP_MIN + clamp(scale, 0, 1) * (SCALE_STEP_MAX - SCALE_STEP_MIN)
end

local function estimateSurfaceSampleCount(size, step)
    if not size or not step or step <= 0 then return huge end
    local nx = max(2, floor(size.X / step) + 1)
    local ny = max(2, floor(size.Y / step) + 1)
    local nz = max(2, floor(size.Z / step) + 1)
    return 2 * (ny * nz + nx * nz + nx * ny)
end

local function computeStep(scale, part)
    local step      = getStepFromScale(scale)
    local estimated = estimateSurfaceSampleCount(part.Size, step)
    if estimated > DEFAULT_SAMPLE_BUDGET then
        local minDim = min(part.Size.X, part.Size.Y, part.Size.Z)
        step = min(step * sqrt(estimated / DEFAULT_SAMPLE_BUDGET), minDim)
    end
    return step
end

-- ── Surface sample point generation ──────────────────────────────────────────
local function makeAxisValues(minV, maxV, step)
    local vals = {}
    local v    = minV
    while v <= maxV do
        vals[#vals + 1] = v
        v = v + step
    end
    if maxV - (v - step) > 0.001 then vals[#vals + 1] = maxV end
    return vals
end

local function buildSurfaceSamplePoints(part, step)
    local hx, hy, hz = part.Size.X * 0.5, part.Size.Y * 0.5, part.Size.Z * 0.5
    local xs = makeAxisValues(-hx, hx, step)
    local ys = makeAxisValues(-hy, hy, step)
    local zs = makeAxisValues(-hz, hz, step)
    local points = {}
    local p = 0
    -- ±X faces
    for yi = 1, #ys do
        local y = ys[yi]
        for zi = 1, #zs do
            local z = zs[zi]
            p = p + 1; points[p] = V3new( hx, y, z)
            p = p + 1; points[p] = V3new(-hx, y, z)
        end
    end
    -- ±Y faces (skip corners already covered by X faces)
    for xi = 2, #xs - 1 do
        local x = xs[xi]
        for zi = 1, #zs do
            local z = zs[zi]
            p = p + 1; points[p] = V3new(x,  hy, z)
            p = p + 1; points[p] = V3new(x, -hy, z)
        end
    end
    -- ±Z faces (skip edges already covered by X/Y faces)
    for xi = 2, #xs - 1 do
        local x = xs[xi]
        for yi = 2, #ys - 1 do
            local y = ys[yi]
            p = p + 1; points[p] = V3new(x, y,  hz)
            p = p + 1; points[p] = V3new(x, y, -hz)
        end
    end
    return points
end

local function getSurfaceSamplePoints(part, step)
    local size    = part.Size
    local stepKey = floor(step * 1000 + 0.5)
    local entry   = surfaceSampleCache[part]
    if entry
        and entry.stepKey == stepKey
        and entry.sx == size.X
        and entry.sy == size.Y
        and entry.sz == size.Z then
        return entry.points
    end
    local points = buildSurfaceSamplePoints(part, step)
    if entry then
        entry.stepKey = stepKey
        entry.sx      = size.X
        entry.sy      = size.Y
        entry.sz      = size.Z
        entry.points  = points
    else
        surfaceSampleCache[part] = {
            stepKey = stepKey, sx = size.X, sy = size.Y, sz = size.Z, points = points,
        }
    end
    return points
end

-- ── Octant-sorted samples (avoids allocating inner closure for sign fn) ───────
local function _sign(v) return v > 0.15 and 1 or (v < -0.15 and -1 or 0) end
local function getOctantKey(viewDirLocal)
    return _sign(viewDirLocal.X) * 9 + _sign(viewDirLocal.Y) * 3 + _sign(viewDirLocal.Z)
end

local function getSortedSamples(part, samplePoints, viewDirLocal)
    local octant = getOctantKey(viewDirLocal)
    local n      = #samplePoints
    local entry  = sortedSampleCache[part]
    if entry and entry.octant == octant and entry.count == n then
        return entry.sorted
    end
    local dots    = table.create(n)
    local indices = table.create(n)
    for i = 1, n do
        dots[i]    = samplePoints[i]:Dot(viewDirLocal)
        indices[i] = i
    end
    table.sort(indices, function(a, b) return dots[a] > dots[b] end)
    local sorted = table.create(n)
    for i = 1, n do sorted[i] = samplePoints[indices[i]] end
    if entry then
        entry.octant = octant
        entry.count  = n
        entry.sorted = sorted
    else
        sortedSampleCache[part] = { octant = octant, count = n, sorted = sorted }
    end
    return sorted
end

-- ── Inner sample loop — manual camera projection for maximum throughput ───────
local function getClosestSampleOnPart(part, mouseX, mouseY, step, sampleBudget, timeBudget, rayDir)
    if not part then return nil end
    local cam = workspace.CurrentCamera
    if not cam then return nil end

    local samplePoints = getSurfaceSamplePoints(part, step)
    local cf           = part.CFrame

    if rayDir then
        samplePoints = getSortedSamples(part, samplePoints, cf:VectorToObjectSpace(rayDir))
    end

    local limit = #samplePoints
    if sampleBudget and sampleBudget > 0 and sampleBudget < limit then
        limit = sampleBudget
    end

    -- Decompose camera matrix once — avoids per-point CFrame overhead
    local camCF  = cam.CFrame
    local camPos = camCF.Position
    local _, _, _,
          r00, r01, r02,
          r10, r11, r12,
          r20, r21, r22 = camCF:GetComponents()

    local vpSize   = cam.ViewportSize
    local halfVpX  = vpSize.X * 0.5
    local halfVpY  = vpSize.Y * 0.5
    local focalLen = halfVpY / tan(rad(cam.FieldOfView) * 0.5)

    local startClock = clock()
    local bestPoint  = nil
    local bestDistSq = huge

    for i = 1, limit do
        local wp = cf:PointToWorldSpace(samplePoints[i])
        local ox = wp.X - camPos.X
        local oy = wp.Y - camPos.Y
        local oz = wp.Z - camPos.Z
        local rz = -(r20 * ox + r21 * oy + r22 * oz)
        if rz > 0 then
            local rx = r00 * ox + r01 * oy + r02 * oz
            local ry = r10 * ox + r11 * oy + r12 * oz
            local sx = halfVpX + (rx / rz) * focalLen
            local sy = halfVpY - (ry / rz) * focalLen
            local dx = sx - mouseX
            local dy = sy - mouseY
            local d2 = dx * dx + dy * dy
            if d2 < bestDistSq then
                bestDistSq = d2
                bestPoint  = wp
                if bestDistSq <= CLOSEST_POINT_EARLY_EXIT_DIST_SQ then break end
            end
        end
        if timeBudget and (i % 48) == 0 and (clock() - startClock) >= timeBudget then break end
    end
    return bestPoint
end

-- ── Crosshair ray ─────────────────────────────────────────────────────────────
local function getCrosshairRay()
    local cam = workspace.CurrentCamera
    if not cam then return nil, nil end
    local mousePos = UIS:GetMouseLocation()
    local mx       = floor(mousePos.X + 0.5)
    local my       = floor(mousePos.Y + 0.5)
    local ray      = cam:ViewportPointToRay(mx, my)
    return ray.Origin, ray.Direction, mx, my
end

-- ── Raycast hit detection ─────────────────────────────────────────────────────
local function getCrosshairHitPart(char, rayOrigin, rayDir)
    if not char or not rayOrigin or not rayDir then return nil end
    local bodyParts = getBodyPartsSnapshot(char)
    if #bodyParts == 0 then return nil end
    -- Only rebuild the filter when the snapshot array reference has changed.
    if bodyParts ~= _lastRayPartsRef then
        PartRayParams.FilterDescendantsInstances = bodyParts
        _lastRayPartsRef = bodyParts
    end
    local result = workspace:Raycast(rayOrigin, rayDir * CROSSHAIR_RAY_DISTANCE, PartRayParams)
    if not result then return nil end
    local hitPart = result.Instance
    if hitPart and hitPart:IsA("BasePart") and hitPart:IsDescendantOf(char) and BODY_PART_NAMES[hitPart.Name] then
        return hitPart
    end
    return nil
end

local function getClosestPointFromPartByCrosshair(part, rayOrigin, rayDir, step)
    if not part then return nil end
    local surface = getClosestPointOnPart(part, getProjectedPointOnRay(rayOrigin, rayDir, part.Position))
    if not surface then return nil end
    return quantizePointOnPart(part, surface, step)
end

-- ── Public: getAimPosition ────────────────────────────────────────────────────
local function getAimPosition(part)
    if not part or not Settings or not State then return nil end

    local scaleValue = getClosestPointScale()
    local rayOrigin, rayDir, mouseX, mouseY = getCrosshairRay()

    if not rayOrigin or not rayDir then
        local cam      = workspace.CurrentCamera
        local fallback = cam and cam.CFrame.Position or part.Position
        local surface  = getClosestPointOnPart(part, fallback)
        local q        = quantizePointOnPart(part, surface or part.Position, getStepFromScale(scaleValue))
        return q:Lerp(part.Position, clamp(scaleValue, 0, 1)), part
    end

    local char      = (State.LockedTarget and State.LockedTarget.Character) or part.Parent
    local targetKey = State.LockedTarget or char
    local now       = clock()

    -- Cache hit
    local cached = closestPointCache[targetKey]
    if cached
        and (now - cached.timestamp)  <= CLOSEST_POINT_CACHE_MAX_AGE
        and cached.scale   == scaleValue
        and cached.mouseX  == mouseX
        and cached.mouseY  == mouseY
        and cached.part
        and cached.part.Parent then
        return cached.point, cached.part
    end

    -- Part selection
    local rayHitPart  = getCrosshairHitPart(char, rayOrigin, rayDir)
    local nearestPart = getClosestPartToCrosshair(char, mouseX, mouseY)
    local targetPart  = nearestPart or part
    if rayHitPart then
        local rayDistSq     = getPartScreenDistanceSq(rayHitPart, mouseX, mouseY)
        local nearestDistSq = getPartScreenDistanceSq(nearestPart, mouseX, mouseY)
        if rayDistSq <= RAY_MAX_LOCK_DIST_SQ or rayDistSq <= (nearestDistSq + 64) then
            targetPart = rayHitPart
        end
    end

    -- Point computation
    local centerBias = clamp(scaleValue, 0, 1)
    local step       = computeStep(scaleValue, targetPart)
    local finalPoint

    if centerBias >= CENTER_SKIP_THRESHOLD then
        local directPoint = getClosestPointFromPartByCrosshair(targetPart, rayOrigin, rayDir, step) or part.Position
        finalPoint = directPoint:Lerp(targetPart.Position, centerBias)
    else
        local directPoint  = getClosestPointFromPartByCrosshair(targetPart, rayOrigin, rayDir, step) or part.Position
        local directDistSq = getWorldScreenDistanceSq(directPoint, mouseX, mouseY)
        local basePoint
        if directDistSq > CLOSEST_POINT_ACCEPT_DIST_SQ then
            basePoint = getClosestSampleOnPart(
                targetPart, mouseX, mouseY, step,
                DEFAULT_SAMPLE_BUDGET, CLOSEST_POINT_TIME_BUDGET_NORMAL,
                rayDir
            ) or directPoint
        else
            basePoint = directPoint
        end
        finalPoint = basePoint:Lerp(targetPart.Position, centerBias)
    end

    -- Write cache — reuse entry if it already exists for this key
    if cached then
        cached.scale     = scaleValue
        cached.mouseX    = mouseX
        cached.mouseY    = mouseY
        cached.part      = targetPart
        cached.point     = finalPoint
        cached.timestamp = now
    else
        closestPointCache[targetKey] = {
            scale     = scaleValue,
            mouseX    = mouseX,
            mouseY    = mouseY,
            part      = targetPart,
            point     = finalPoint,
            timestamp = now,
        }
    end

    return finalPoint, targetPart
end

-- ── Init ──────────────────────────────────────────────────────────────────────
local function init(deps)
    Settings        = deps.Settings
    State           = deps.State
    BODY_PART_NAMES = deps.BODY_PART_NAMES
    -- Camera dep removed — always read workspace.CurrentCamera inline
    -- so no stale reference is ever cached across respawns or reloads.
end

return {
    init                 = init,
    getAimPosition       = getAimPosition,
    getBodyPartsSnapshot = getBodyPartsSnapshot,
    pruneCaches          = pruneCaches,
    resetCache           = resetCache,
}
