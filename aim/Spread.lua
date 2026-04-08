local Spread = {}

local Settings, LP, ClosestPoint
local patchedSpreadTables = {}

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

local function getSpreadAimPosition(part)
    if not part then return nil end
    if isClosestPointMode() then
        local closestPos, closestPart = ClosestPoint.getAimPosition(part)
        if closestPos then return closestPos, (closestPart or part) end
    end
    return part.Position, part
end

local function getCamlockAimPosition(part)
    if not part then return nil end
    if isClosestPointMode() then
        local closestPos, closestPart = ClosestPoint.getAimPosition(part)
        if closestPos then return closestPos, (closestPart or part) end
    end
    return part.Position, part
end

-- Returns the configured multiplier for a weapon (0.0 = no spread, 1.0 = full spread).
-- Returns nil if the weapon has no entry or Spread Modifications is disabled.
local function resolveSpreadMultiplier(toolName)
    local sm = Settings.SpreadMod
    if type(sm) ~= "table" then return nil end
    if sm["Enabled"] == false then return nil end
    local v = sm[toolName]
    if type(v) ~= "number" then return nil end
    return math.clamp(v, 0, 1)
end

-- Searches an Activated connection's upvalues for the gun's spread table {X, Y, Z}.
-- This is the u7 table used by the game's GunClient scripts.
local function findSpreadTable(tool)
    if type(getconnections) ~= "function" then return nil end
    if type(getupvalues) ~= "function" then return nil end
    local ok, conns = pcall(getconnections, tool.Activated)
    if not ok then return nil end
    for _, conn in ipairs(conns) do
        local fn = conn.Function
        if not fn then continue end
        local upOk, upvals = pcall(getupvalues, fn)
        if not upOk then continue end
        for _, v in next, upvals do
            if type(v) == "table"
                and type(v.X) == "number"
                and type(v.Y) == "number"
                and type(v.Z) == "number" then
                return v
            end
        end
    end
    return nil
end

-- Applies the configured spread multiplier to the given tool.
-- Setting all axes to 0 forces all pellets to the same point (maximum damage).
-- Setting to 1 restores default gun spread. No-op if weapon has no config entry.
local function applySpreadMod(tool)
    if not tool or not tool:IsA("Tool") then return end
    local multiplier = resolveSpreadMultiplier(tool.Name)
    if multiplier == nil then return end
    local spreadTable = findSpreadTable(tool)
    if not spreadTable then return end
    spreadTable.X = multiplier
    spreadTable.Y = multiplier
    spreadTable.Z = multiplier
    patchedSpreadTables[spreadTable] = true
end

-- Restores all patched spread tables to their default values (full spread).
local function cleanup()
    for spreadTable in next, patchedSpreadTables do
        if type(spreadTable) == "table" then
            spreadTable.X = 1
            spreadTable.Y = 1
            spreadTable.Z = 1
        end
    end
    table.clear(patchedSpreadTables)
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
Spread.applySpreadMod = applySpreadMod
Spread.cleanup = cleanup

return Spread
