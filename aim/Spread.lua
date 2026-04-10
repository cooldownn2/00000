local Spread = {}

local RS = game:GetService("ReplicatedStorage")

local Settings, LP, ClosestPoint, gameStyle
local patchedSpreadTables = {}
local patchedOffsetWeapons = {}
local gunOffsetsTable = nil

local function isClosestPointMode()
    local mode = string.lower(tostring(Settings.TargetPart or ""))
    return mode == "closest point" or mode == "closestpoint"
end

local function resolveLockPartForCharacter(char)
    if not char then return nil end
    if isClosestPointMode() then
        if gameStyle == "zeehood" then
            return char:FindFirstChild("Head")
                or char:FindFirstChild("UpperTorso")
                or char:FindFirstChild("Torso")
                or char:FindFirstChild("LowerTorso")
                or char:FindFirstChild("HumanoidRootPart")
                or char:FindFirstChildWhichIsA("BasePart")
        end
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
    if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
        return nil
    end
    if isClosestPointMode() then
        local closestPos, closestPart = ClosestPoint.getAimPosition(part)
        if closestPos then return closestPos, (closestPart or part) end
    end
    return part.Position, part
end

local function getCamlockAimPosition(part)
    if not part then return nil end
    if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
        return nil
    end
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

local function getGunOffsetsTable()
    if gunOffsetsTable ~= nil then
        return gunOffsetsTable
    end

    local offsetsModule = RS:FindFirstChild("GunOffsets")
    if not offsetsModule then
        gunOffsetsTable = false
        return nil
    end

    local ok, offsets = pcall(require, offsetsModule)
    if not ok or type(offsets) ~= "table" then
        gunOffsetsTable = false
        return nil
    end

    gunOffsetsTable = offsets
    return gunOffsetsTable
end

local function snapshotWeaponOffsets(weaponOffsets)
    local snap = {}
    for presetKey, preset in pairs(weaponOffsets) do
        if type(preset) == "table" then
            local presetSnap = {}
            for pelletKey, vec in pairs(preset) do
                if typeof(vec) == "Vector3" then
                    presetSnap[pelletKey] = vec
                end
            end
            if next(presetSnap) ~= nil then
                snap[presetKey] = presetSnap
            end
        end
    end
    return next(snap) and snap or nil
end

local function restoreZeehoodOffsets(toolName)
    local state = patchedOffsetWeapons[toolName]
    if not state or type(state.current) ~= "table" or type(state.original) ~= "table" then
        patchedOffsetWeapons[toolName] = nil
        return
    end

    for presetKey, presetSnap in pairs(state.original) do
        local currentPreset = state.current[presetKey]
        if type(currentPreset) == "table" then
            for pelletKey, vec in pairs(presetSnap) do
                currentPreset[pelletKey] = vec
            end
        end
    end

    patchedOffsetWeapons[toolName] = nil
end

local function applyZeehoodSpreadMod(toolName, multiplier)
    if not toolName then return end

    if multiplier == nil then
        restoreZeehoodOffsets(toolName)
        return
    end

    local offsets = getGunOffsetsTable()
    if type(offsets) ~= "table" then return end

    local weaponOffsets = offsets[toolName]
    if type(weaponOffsets) ~= "table" then return end

    local state = patchedOffsetWeapons[toolName]
    if not state or state.current ~= weaponOffsets then
        local original = snapshotWeaponOffsets(weaponOffsets)
        if not original then return end
        state = { current = weaponOffsets, original = original }
        patchedOffsetWeapons[toolName] = state
    end

    for presetKey, presetSnap in pairs(state.original) do
        local currentPreset = state.current[presetKey]
        if type(currentPreset) == "table" then
            for pelletKey, originalVec in pairs(presetSnap) do
                currentPreset[pelletKey] = originalVec * multiplier
            end
        end
    end
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
    if gameStyle == "zeehood" then
        applyZeehoodSpreadMod(tool.Name, multiplier)
        return
    end
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

    for toolName in pairs(patchedOffsetWeapons) do
        restoreZeehoodOffsets(toolName)
    end
end

local function init(deps)
    Settings     = deps.Settings
    LP           = deps.LP
    ClosestPoint = deps.ClosestPoint
    gameStyle    = deps.gameStyle
end

Spread.init = init
Spread.isClosestPointMode = isClosestPointMode
Spread.resolveLockPartForCharacter = resolveLockPartForCharacter
Spread.getSpreadAimPosition = getSpreadAimPosition
Spread.getCamlockAimPosition = getCamlockAimPosition
Spread.applySpreadMod = applySpreadMod
Spread.cleanup = cleanup

return Spread
