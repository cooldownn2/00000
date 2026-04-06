local UIS = game:GetService("UserInputService")

local Camera, Settings, State, BODY_PART_NAMES

local CLOSEST_POINT_CACHE_MAX_AGE      = 1 / 120
local BODY_PART_SNAPSHOT_MAX_AGE       = 1 / 30
local CLOSEST_POINT_TIME_BUDGET_NORMAL = 0.0012
local CLOSEST_POINT_ACCEPT_DIST_SQ     = 3 * 3
local CLOSEST_POINT_EARLY_EXIT_DIST_SQ = 1.5 * 1.5
local CROSSHAIR_RAY_DISTANCE           = 5000
local CACHE_PRUNE_INTERVAL             = 5
local RAY_MAX_LOCK_DIST_SQ             = 28 * 28
local DEFAULT_SAMPLE_BUDGET            = 1200

local SCALE_STEP_MIN = 0.025
local SCALE_STEP_MAX = 0.50
local CENTER_SKIP_THRESHOLD = 0.85

local PART_PRIORITY = {
    Head             = 0.70,
    UpperTorso       = 0.85,
    Torso            = 0.85,
    HumanoidRootPart = 0.90,
}

local closestPointCache      = setmetatable({}, { __mode = "k" })
local bodyPartsSnapshotCache = setmetatable({}, { __mode = "k" })
local surfaceSampleCache     = setmetatable({}, { __mode = "k" })
local sortedSampleCache      = setmetatable({}, { __mode = "k" })
local lastCachePrune         = 0

local function resetCache()
    for k in pairs(closestPointCache) do
        closestPointCache[k] = nil
    end
end

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
    local now   = os.clock()
    local cache = bodyPartsSnapshotCache[char]
    if cache and (now - cache.timestamp) <= BODY_PART_SNAPSHOT_MAX_AGE then
        return cache.parts
    end
    local parts = collectBodyParts(char)
    bodyPartsSnapshotCache[char] = { timestamp = now, parts = parts }
    return parts
end

local function pruneCaches(force)
    local now = os.clock()
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

local function getPartScreenDistanceSq(part, mouseX, mouseY)
    if not part or not Camera then return math.huge end
    local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
    if not onScreen or screenPos.Z <= 0 then return math.huge end
    local dx = screenPos.X - mouseX
    local dy = screenPos.Y - mouseY
    return dx * dx + dy * dy
end

local function getWorldScreenDistanceSq(worldPos, mouseX, mouseY)
    if not worldPos or not Camera then return math.huge end
    local screenPos, onScreen = Camera:WorldToViewportPoint(worldPos)
    if not onScreen or screenPos.Z <= 0 then return math.huge end
    local dx = screenPos.X - mouseX
    local dy = screenPos.Y - mouseY
    return dx * dx + dy * dy
end

local function getClosestPartToCrosshair(char, mouseX, mouseY)
    if not char then return nil end
    local fallback = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
    if not Camera then return fallback or char:FindFirstChildWhichIsA("BasePart") end
    local mx, my = mouseX, mouseY
    if not mx or not my then
        local mousePos = UIS:GetMouseLocation()
        mx = mousePos.X
        my = mousePos.Y
    end
    local bestPart, bestScore = nil, math.huge
    local parts = getBodyPartsSnapshot(char)
    for i = 1, #parts do
        local part = parts[i]
        local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
        if onScreen and screenPos.Z > 0 then
            local dx    = screenPos.X - mx
            local dy    = screenPos.Y - my
            local distSq = dx * dx + dy * dy
            local depthFactor    = math.max(screenPos.Z, 1)
            local priorityFactor = PART_PRIORITY[part.Name] or 1
            local score = distSq * depthFactor * priorityFactor
            if score < bestScore then
                bestScore = score
                bestPart  = part
            end
        end
    end
    return bestPart or fallback or char:FindFirstChildWhichIsA("BasePart")
end

local function getClosestPointOnPart(part, fromPos)
    if not part then return nil end
    local localPos = part.CFrame:PointToObjectSpace(fromPos)
    local half     = part.Size * 0.5
    local clamped  = Vector3.new(
        math.clamp(localPos.X, -half.X, half.X),
        math.clamp(localPos.Y, -half.Y, half.Y),
        math.clamp(localPos.Z, -half.Z, half.Z)
    )
    return part.CFrame:PointToWorldSpace(clamped)
end

local function quantizePointOnPart(part, worldPos, step)
    if not part then return worldPos end
    if not step or step <= 0 then return worldPos end
    local localPos = part.CFrame:PointToObjectSpace(worldPos)
    local half     = part.Size * 0.5
    local qx = math.floor((localPos.X / step) + 0.5) * step
    local qy = math.floor((localPos.Y / step) + 0.5) * step
    local qz = math.floor((localPos.Z / step) + 0.5) * step
    local snapped = Vector3.new(
        math.clamp(qx, -half.X, half.X),
        math.clamp(qy, -half.Y, half.Y),
        math.clamp(qz, -half.Z, half.Z)
    )
    return part.CFrame:PointToWorldSpace(snapped)
end

local function getCrosshairRay()
    if not Camera then return nil, nil end
    local mousePos = UIS:GetMouseLocation()
    local mx       = math.floor(mousePos.X + 0.5)
    local my       = math.floor(mousePos.Y + 0.5)
    local ray      = Camera:ViewportPointToRay(mx, my)
    return ray.Origin, ray.Direction, mx, my
end

local function getProjectedPointOnRay(origin, dir, worldPos)
    if not origin or not dir or not worldPos then return worldPos end
    local t = (worldPos - origin):Dot(dir)
    if t < 0 then t = 0 end
    return origin + dir * t
end

local function getStepFromScale(scale)
    local t = math.clamp(scale, 0, 1)
    return SCALE_STEP_MIN + t * (SCALE_STEP_MAX - SCALE_STEP_MIN)
end

local function estimateSurfaceSampleCount(size, step)
    if not size or not step or step <= 0 then return math.huge end
    local nx = math.max(2, math.floor(size.X / step) + 1)
    local ny = math.max(2, math.floor(size.Y / step) + 1)
    local nz = math.max(2, math.floor(size.Z / step) + 1)
    return 2 * (ny * nz + nx * nz + nx * ny)
end

local function computeStep(scale, part)
    local step      = getStepFromScale(scale)
    local estimated = estimateSurfaceSampleCount(part.Size, step)
    if estimated > DEFAULT_SAMPLE_BUDGET then
        local ratio  = math.sqrt(estimated / DEFAULT_SAMPLE_BUDGET)
        local minDim = math.min(part.Size.X, part.Size.Y, part.Size.Z)
        step = math.min(step * ratio, minDim)
    end
    return step
end

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
    local p      = 0

    for yi = 1, #ys do
        local y = ys[yi]
        for zi = 1, #zs do
            local z = zs[zi]
            p = p + 1; points[p] = Vector3.new( hx, y, z)
            p = p + 1; points[p] = Vector3.new(-hx, y, z)
        end
    end

    for xi = 2, #xs - 1 do
        local x = xs[xi]
        for zi = 1, #zs do
            local z = zs[zi]
            p = p + 1; points[p] = Vector3.new(x,  hy, z)
            p = p + 1; points[p] = Vector3.new(x, -hy, z)
        end
    end

    for xi = 2, #xs - 1 do
        local x = xs[xi]
        for yi = 2, #ys - 1 do
            local y = ys[yi]
            p = p + 1; points[p] = Vector3.new(x, y,  hz)
            p = p + 1; points[p] = Vector3.new(x, y, -hz)
        end
    end

    return points
end

local function getSurfaceSamplePoints(part, step)
    local size    = part.Size
    local stepKey = math.floor(step * 1000 + 0.5)
    local cache   = surfaceSampleCache[part]
    if cache
        and cache.stepKey == stepKey
        and cache.sx == size.X
        and cache.sy == size.Y
        and cache.sz == size.Z then
        return cache.points
    end
    local points = buildSurfaceSamplePoints(part, step)
    surfaceSampleCache[part] = {
        stepKey = stepKey, sx = size.X, sy = size.Y, sz = size.Z, points = points,
    }
    return points
end


local function getOctantKey(viewDirLocal)
    local function sign(v) return v > 0.15 and 1 or (v < -0.15 and -1 or 0) end
    return sign(viewDirLocal.X) * 9 + sign(viewDirLocal.Y) * 3 + sign(viewDirLocal.Z)
end

local function getSortedSamples(part, samplePoints, viewDirLocal)
    local octant = getOctantKey(viewDirLocal)
    local cache  = sortedSampleCache[part]
    if cache and cache.octant == octant and cache.count == #samplePoints then
        return cache.sorted
    end
    local dots = {}
    for i = 1, #samplePoints do
        dots[i] = samplePoints[i]:Dot(viewDirLocal)
    end
    local indices = {}
    for i = 1, #samplePoints do indices[i] = i end
    table.sort(indices, function(a, b) return dots[a] > dots[b] end)
    local sorted = {}
    for i = 1, #indices do sorted[i] = samplePoints[indices[i]] end
    sortedSampleCache[part] = { octant = octant, count = #samplePoints, sorted = sorted }
    return sorted
end

local function getClosestSampleOnPart(part, mouseX, mouseY, step, sampleBudget, timeBudget, rayDir)
    if not part or not Camera then return nil, math.huge end
    local samplePoints = getSurfaceSamplePoints(part, step)
    local cf           = part.CFrame

    if rayDir then
        local viewDirLocal = cf:VectorToObjectSpace(rayDir)
        samplePoints = getSortedSamples(part, samplePoints, viewDirLocal)
    end

    local limit = #samplePoints
    if sampleBudget and sampleBudget > 0 and sampleBudget < limit then
        limit = sampleBudget
    end

    local camCF   = Camera.CFrame
    local camPos  = camCF.Position
    local _, _, _,
          r00, r01, r02,
          r10, r11, r12,
          r20, r21, r22 = camCF:GetComponents()

    local vpSize   = Camera.ViewportSize
    local halfVpX  = vpSize.X * 0.5
    local halfVpY  = vpSize.Y * 0.5
    local fovRad   = math.rad(Camera.FieldOfView)
    local focalLen = halfVpY / math.tan(fovRad * 0.5)

    local startClock = os.clock()
    local bestPoint  = nil
    local bestDistSq = math.huge
    for i = 1, limit do
        local worldPoint = cf:PointToWorldSpace(samplePoints[i])
        local ox = worldPoint.X - camPos.X
        local oy = worldPoint.Y - camPos.Y
        local oz = worldPoint.Z - camPos.Z
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
                bestPoint  = worldPoint
                if bestDistSq <= CLOSEST_POINT_EARLY_EXIT_DIST_SQ then break end
            end
        end
        if timeBudget and (i % 48) == 0 and (os.clock() - startClock) >= timeBudget then break end
    end
    return bestPoint
end

local PartRayParams = RaycastParams.new()
PartRayParams.FilterType  = Enum.RaycastFilterType.Include
PartRayParams.IgnoreWater = true

local function getCrosshairHitPart(char, rayOrigin, rayDir)
    if not char or not rayOrigin or not rayDir then return nil end
    local bodyParts = getBodyPartsSnapshot(char)
    if #bodyParts == 0 then return nil end
    PartRayParams.FilterDescendantsInstances = bodyParts
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
    local projected = getProjectedPointOnRay(rayOrigin, rayDir, part.Position)
    local surface   = getClosestPointOnPart(part, projected)
    if not surface then return nil end
    return quantizePointOnPart(part, surface, step)
end

local function getClosestPointScale()
    local v = tonumber(Settings.ClosestPointScale)
    if not v then return 0.35 end
    return math.clamp(v, 0, 1)
end


local function getAimPosition(part)
    if not part then return nil end
    if not Settings or not State then return nil end

    Camera = workspace.CurrentCamera
    local scaleValue = getClosestPointScale()

    local rayOrigin, rayDir, mouseX, mouseY = getCrosshairRay()
    if not rayOrigin or not rayDir then
        local fallback = Camera and Camera.CFrame.Position or part.Position
        local step     = getStepFromScale(scaleValue)
        local surface  = getClosestPointOnPart(part, fallback)
        local q = quantizePointOnPart(part, surface or part.Position, step)
        local centerBias = math.clamp(scaleValue, 0, 1)
        return q:Lerp(part.Position, centerBias), part
    end

    local char      = (State.LockedTarget and State.LockedTarget.Character) or part.Parent
    local targetKey = State.LockedTarget or char
    local now       = os.clock()

    local cached = closestPointCache[targetKey]
    if cached
        and (now - cached.timestamp) <= CLOSEST_POINT_CACHE_MAX_AGE
        and cached.scale   == scaleValue
        and cached.mouseX  == mouseX
        and cached.mouseY  == mouseY
        and cached.part
        and cached.part.Parent then
        return cached.point, cached.part
    end

    local rayHitPart    = getCrosshairHitPart(char, rayOrigin, rayDir)
    local nearestPart   = getClosestPartToCrosshair(char, mouseX, mouseY)
    local targetPart    = nearestPart or part
    if rayHitPart then
        local rayDistSq     = getPartScreenDistanceSq(rayHitPart, mouseX, mouseY)
        local nearestDistSq = getPartScreenDistanceSq(nearestPart, mouseX, mouseY)
        if rayDistSq <= RAY_MAX_LOCK_DIST_SQ or rayDistSq <= (nearestDistSq + 64) then
            targetPart = rayHitPart
        end
    end

    local centerBias = math.clamp(scaleValue, 0, 1)
    local step = computeStep(scaleValue, targetPart)

    local finalPoint
    if centerBias >= CENTER_SKIP_THRESHOLD then
        local directPoint = getClosestPointFromPartByCrosshair(targetPart, rayOrigin, rayDir, step) or part.Position
        finalPoint = directPoint:Lerp(targetPart.Position, centerBias)
    else
        local directPoint  = getClosestPointFromPartByCrosshair(targetPart, rayOrigin, rayDir, step) or part.Position
        local directDistSq = getWorldScreenDistanceSq(directPoint, mouseX, mouseY)

        local basePoint
        if directDistSq > CLOSEST_POINT_ACCEPT_DIST_SQ then
            local sampled = getClosestSampleOnPart(
                targetPart, mouseX, mouseY, step,
                DEFAULT_SAMPLE_BUDGET, CLOSEST_POINT_TIME_BUDGET_NORMAL,
                rayDir
            )
            basePoint = sampled or directPoint
        else
            basePoint = directPoint
        end

        finalPoint = basePoint:Lerp(targetPart.Position, centerBias)
    end

    closestPointCache[targetKey] = {
        scale     = scaleValue,
        mouseX    = mouseX,
        mouseY    = mouseY,
        part      = targetPart,
        point     = finalPoint,
        timestamp = now,
    }

    return finalPoint, targetPart
end

local function init(deps)
    Camera          = deps.Camera
    Settings        = deps.Settings
    State           = deps.State
    BODY_PART_NAMES = deps.BODY_PART_NAMES
end

return {
    init                 = init,
    getAimPosition       = getAimPosition,
    getBodyPartsSnapshot = getBodyPartsSnapshot,
    pruneCaches          = pruneCaches,
    resetCache           = resetCache,
}
