local Spread = {}

local Settings, LP, ClosestPoint
local spreadRng = Random.new()

local function isClosestPointMode()
    local mode = string.lower(tostring(Settings.TargetPart or ""))
    return mode == "closest point" or mode == "closestpoint"
end

local function resolveLockPartForCharacter(char)
    if not char then return nil end
    if isClosestPointMode() then
        return char:FindFirstChild("HumanoidRootPart")
            or char:FindFirstChild("UpperTorso")
            or char:FindFirstChild("Torso")
            or char:FindFirstChild("Head")
            or char:FindFirstChildWhichIsA("BasePart")
    end
    return char:FindFirstChild(Settings.TargetPart)
end

local function resolveSpreadValue()
    local raw = Settings.CustomSpread
    if type(raw) ~= "table" then return 0 end
    if raw["Enabled"] == false then return 0 end

    local char = LP.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    local name = tool and tool.Name or ""
    local v = raw[name]
    if type(v) == "number" then return v end
    return 0
end

local function getSpreadAimPosition(part)
    if not part then return nil end

    local aimPos = part.Position
    if isClosestPointMode() then
        local closestPos, closestPart = ClosestPoint.getAimPosition(part)
        if closestPos then aimPos = closestPos end
        if closestPart then part = closestPart end
    end

    local spread = math.clamp(resolveSpreadValue(), 0, 100)
    if spread <= 0 then
        return aimPos, part
    end

    local scale = spread / 100
    local size = part.Size
    local ox = spreadRng:NextNumber(-0.5, 0.5) * size.X * scale
    local oy = spreadRng:NextNumber(-0.5, 0.5) * size.Y * scale
    local oz = spreadRng:NextNumber(-0.5, 0.5) * size.Z * scale
    return aimPos + Vector3.new(ox, oy, oz), part
end

local function getCamlockAimPosition(part)
    if not part then return nil end
    if isClosestPointMode() then
        local closestPos, closestPart = ClosestPoint.getAimPosition(part)
        if closestPos then return closestPos, (closestPart or part) end
    end
    return part.Position, part
end

local function init(deps)
    Settings     = deps.Settings
    LP           = deps.LP
    ClosestPoint = deps.ClosestPoint
end

Spread.init = init
Spread.isClosestPointMode = isClosestPointMode
Spread.resolveLockPartForCharacter = resolveLockPartForCharacter
Spread.getSpreadAimPosition = getSpreadAimPosition
Spread.getCamlockAimPosition = getCamlockAimPosition

return Spread
