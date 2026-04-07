local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local UIS        = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local LP         = Players.LocalPlayer
local Camera     = workspace.CurrentCamera
local MainEvent  = RS:WaitForChild("MainEvent")
local GH         = require(RS.Modules.GunHandler)

local HttpService = game:GetService("HttpService")

local GENV = getgenv and getgenv() or _G
if not GENV.SauceConfig then
    error("No config found. Run the table not just the loading string.", 2)
end
if GENV.__SilentAimCleanup then
    pcall(GENV.__SilentAimCleanup)
end


local BASE = "https://raw.githubusercontent.com/cooldownn2/00000/main/"
local function load(name)
    return loadstring(game:HttpGet(BASE .. name .. ".lua?t=" .. tostring(os.time())))()
end
local Config     = load("Registry")
local StateLib   = load("State")
local ESP        = load("ESP")
local TargetCard = load("TargetCard")
local Features   = load("Features")
local Hooks      = load("Hooks")
local Visuals    = load("Visuals")
local ForceHit      = load("ForceHit")
local BodyParts     = load("BodyParts")
local ClosestPoint  = load("ClosestPoint")
local DelayChanger  = load("DelayChanger")

local settings   = Config.settings
local Settings   = Config.Settings

if GENV.SauceConfig then
    local c = GENV.SauceConfig
    local function resolve(root, path)
        local cur = root
        for i = 1, #path do
            if type(cur) ~= "table" then return nil end
            cur = cur[path[i]]
        end
        return cur
    end
    local function apply(value, path)
        if value == nil then return end
        local cur = settings
        for i = 1, #path - 1 do
            if type(cur[path[i]]) ~= "table" then cur[path[i]] = {} end
            cur = cur[path[i]]
        end
        cur[path[#path]] = value
    end

    local CONFIG_MAP = {
        -- Silent Aim
        { {"Silent Aim","Enabled"},                        {"Main","Enabled"} },
        { {"Silent Aim","Target Part"},                    {"Main","Target Part"} },
        { {"Silent Aim","Scale"},                          {"Main","Closest Point Scale"} },
        { {"Silent Aim","Selection"},                      {"Main","Selection System"} },
        { {"Silent Aim","Selection Color"},                {"Main","Selection Color"} },
        { {"Main","Keybinds","Target"},                    {"Main","Keybinds","Target"} },
        { {"Silent Aim","Checks","Visible"},               {"Main","Checks","Target","Visible Check"} },
        { {"Silent Aim","Checks","Persist Lock On Death"}, {"Main","Checks","Target","Persist Lock On Death"} },
        { {"Silent Aim","Checks","Death Check"},           {"Main","Checks","Target","Death Check"} },
        -- Camlock
        { {"Camlock","Enabled"},                             {"Camlock","Enabled"} },
        { {"Camlock","Distance"},                            {"Camlock","Distance"} },
        { {"Camlock","Smoothness"},                          {"Camlock","Smoothness"} },
        { {"Camlock","Click Type"},                          {"Camlock","Click Type"} },
        { {"Camlock","Easing Style"},                        {"Camlock","Easing Style"} },
        { {"Camlock","Easing Direction"},                    {"Camlock","Easing Direction"} },
        { {"Camlock","FOV","Type"},                          {"Camlock","FOV","Type"} },
        { {"Camlock","Width"},                               {"Camlock","Width"} },
        { {"Camlock","Height"},                              {"Camlock","Height"} },
        { {"Camlock","FOV","Width"},                         {"Camlock","Width"} },
        { {"Camlock","FOV","Height"},                        {"Camlock","Height"} },
        { {"Camlock","Visualize","Enabled"},                 {"Camlock","Visualize","Enabled"} },
        { {"Camlock","Visualize","Color"},                   {"Camlock","Visualize","Color"} },
        { {"Camlock","Visualize","Change Color On Hover"},   {"Camlock","Visualize","Change Color On Hover"} },
        { {"Camlock","Visualize","Hover Color"},             {"Camlock","Visualize","Change Color On Hover"} },
        { {"Camlock","FOV","Visualize","Enabled"},           {"Camlock","Visualize","Enabled"} },
        { {"Camlock","FOV","Visualize","Color"},             {"Camlock","Visualize","Color"} },
        { {"Camlock","FOV","Visualize","Hover Color"},       {"Camlock","Visualize","Change Color On Hover"} },
        { {"Camlock","FOV","Visualize","Change Color On Hover"}, {"Camlock","Visualize","Change Color On Hover"} },
        { {"Camlock","Keybind"},                             {"Main","Keybinds","Camlock"} },
        { {"Main","Keybinds","Camlock"},                     {"Main","Keybinds","Camlock"} },
        -- Triggerbot
        { {"Triggerbot","Enabled"},                          {"Triggerbot","Enabled"} },
        { {"Triggerbot","Visible"},                          {"Triggerbot","VisCheck"} },
        { {"Triggerbot","Distance"},                         {"Triggerbot","Distance"} },
        { {"Triggerbot","Delay"},                            {"Triggerbot","Delay"} },
        { {"Triggerbot","Click Type"},                       {"Triggerbot","Click Type"} },
        { {"Triggerbot","FOV","Type"},                       {"Triggerbot","FOV","Type"} },
        { {"Triggerbot","FOV","Width"},                      {"Main","FOV","Triggerbot","Width"} },
        { {"Triggerbot","FOV","Height"},                     {"Main","FOV","Triggerbot","Height"} },
        { {"Triggerbot","FOV","Visualize","Enabled"},        {"Main","FOV","Triggerbot","Visualize","Enabled"} },
        { {"Triggerbot","FOV","Visualize","Color"},          {"Main","FOV","Triggerbot","Visualize","Color"} },
        { {"Triggerbot","FOV","Visualize","Hover Color"},    {"Main","FOV","Triggerbot","Visualize","Change Color On Hover"} },
        { {"Main","Keybinds","Triggerbot"},                  {"Main","Keybinds","Triggerbot"} },
        -- ESP
        { {"ESP","Enabled"},                                 {"ESP","Enabled"} },
        { {"ESP","Name Size"},                               {"ESP","Name Size"} },
        { {"Main","Keybinds","ESP"},                         {"Main","Keybinds","ESP"} },
        { {"ESP","Line","Enabled"},                        {"ESP","Line","Enabled"} },
        { {"ESP","Line","Visible Color"},                    {"ESP","Line","Visible Color"} },
        { {"ESP","Line","Blocked Color"},                    {"ESP","Line","Blocked Color"} },
        { {"ESP","Line","Line Color"},                       {"ESP","Line","Line Color"} },
        -- Weapon Modifications
        { {"Weapon Modifications","Infinite Range"},                  {"Weapon Modifications","Infinite Range"} },
        { {"Weapon Modifications","Custom Spread"},                   {"Weapon Modifications","Custom Spread"} },
        { {"Weapon Modifications","Custom Delays"},                   {"Weapon Modifications","Custom Delays"} },
        { {"Weapon Modifications","Taps"},                            {"Weapon Modifications","Taps"} },
        -- ForceHit
        { {"Weapon Modifications","ForceHit","Enabled"},              {"Weapon Modifications","ForceHit","Enabled"} },
        { {"Weapon Modifications","ForceHit","Full Damage"},          {"Weapon Modifications","ForceHit","Full Damage"} },
        { {"Weapon Modifications","ForceHit","Weapon Distances"},     {"Weapon Modifications","ForceHit","Weapon Distances"} },
        { {"Weapon Modifications","ForceHit","Shotgun Pellets"},      {"Weapon Modifications","ForceHit","Shotgun Pellets"} },
        { {"Weapon Modifications","ForceHit","Full Damage Shots"},    {"Weapon Modifications","ForceHit","Full Damage Shots"} },
        -- Speed
        { {"Speed","Enabled"},                               {"Character","Speed Override","Enabled"} },
        { {"Main","Keybinds","Speed"},                       {"Main","Keybinds","Speed"} },
        { {"Speed","Anti Trip"},                             {"Character","Anti Trip","Enabled"} },
        { {"Speed","Panic Ground","Enabled"},                {"Character","Panic Ground","Enabled"} },
        { {"Speed","Panic Ground","Keybind"},                {"Character","Panic Ground","Key"} },
        { {"Speed","Data"},                                  {"Character","Speed Override","Data"} },
        -- Hotkeys
        { {"Hotkeys","Enabled"},                               {"Hotkeys","Enabled"} },
        { {"Hotkeys","Title"},                                 {"Hotkeys","Title"} },
        { {"Hotkeys","Dynamic Header"},                        {"Hotkeys","Dynamic Header"} },
        { {"Hotkeys","Position","X"},                          {"Hotkeys","Position","X"} },
        { {"Hotkeys","Position","Y"},                          {"Hotkeys","Position","Y"} },
        { {"Hotkeys","Colors","HeaderBg"},                     {"Hotkeys","Colors","HeaderBg"} },
        { {"Hotkeys","Colors","HeaderAlpha"},                  {"Hotkeys","Colors","HeaderAlpha"} },
        { {"Hotkeys","Colors","ChipBg"},                       {"Hotkeys","Colors","ChipBg"} },
        { {"Hotkeys","Colors","ChipAlpha"},                    {"Hotkeys","Colors","ChipAlpha"} },
        { {"Hotkeys","Colors","StrokeColor"},                  {"Hotkeys","Colors","StrokeColor"} },
        { {"Hotkeys","Colors","StrokeAlpha"},                  {"Hotkeys","Colors","StrokeAlpha"} },
        { {"Hotkeys","Colors","StrokeThick"},                  {"Hotkeys","Colors","StrokeThick"} },
        { {"Hotkeys","Colors","LabelText"},                    {"Hotkeys","Colors","LabelText"} },
        { {"Hotkeys","Colors","ValueText"},                    {"Hotkeys","Colors","ValueText"} },
        { {"Hotkeys","Colors","HeaderText"},                   {"Hotkeys","Colors","HeaderText"} },
        { {"Hotkeys","Colors","HeaderIcon"},                   {"Hotkeys","Colors","HeaderIcon"} },
        { {"Hotkeys","Colors","TargetText"},                   {"Hotkeys","Colors","TargetText"} },
        { {"Hotkeys","Colors","ToggleOnBg"},                   {"Hotkeys","Colors","ToggleOnBg"} },
        { {"Hotkeys","Colors","ToggleOnThumb"},                {"Hotkeys","Colors","ToggleOnThumb"} },
        { {"Hotkeys","Colors","ToggleOffBg"},                  {"Hotkeys","Colors","ToggleOffBg"} },
        { {"Hotkeys","Colors","ToggleOffThumb"},               {"Hotkeys","Colors","ToggleOffThumb"} },
        -- Visuals (non-hotkeys)
        { {"Visuals","Target Card"},                         {"Main","Target Card"} },
    }

    for _, entry in ipairs(CONFIG_MAP) do
        apply(resolve(c, entry[1]), entry[2])
    end
end

do
    local function vWarn(msg) warn("[SauceConfig] " .. msg) end
    local function expectType(path, value, expected)
        if value == nil then return end
        if type(value) ~= expected then
            vWarn(path .. " expected " .. expected .. ", got " .. type(value))
        end
    end
    local function expectEnum(path, value, valid)
        if value == nil then return end
        local lower = string.lower(tostring(value))
        for _, v in ipairs(valid) do
            if string.lower(v) == lower then return end
        end
        vWarn(path .. ' invalid value "' .. tostring(value) .. '", expected one of: ' .. table.concat(valid, ", "))
    end
    local function expectRange(path, value, lo, hi)
        if value == nil then return end
        local n = tonumber(value)
        if not n then vWarn(path .. " expected number, got " .. type(value)); return end
        if n < lo or n > hi then
            vWarn(path .. " = " .. tostring(n) .. " out of range [" .. lo .. ", " .. hi .. "]")
        end
    end
    local function expectKey(path, value)
        if value == nil then return end
        if typeof(value) == "EnumItem" then return end
        if type(value) ~= "string" then vWarn(path .. " expected string or KeyCode, got " .. type(value)); return end
        local ok = pcall(function() return Enum.KeyCode[string.upper(value)] end)
        if not ok then vWarn(path .. ' invalid key "' .. tostring(value) .. '"') end
    end
    local S = Settings
    expectType("Main.Enabled", S.Enabled, "boolean")
    expectEnum("Main.Target Part", S.TargetPart, {"Head","HumanoidRootPart","Torso","UpperTorso","LowerTorso","Closest Point"})
    expectRange("Main.Closest Point Scale", S.ClosestPointScale, 0, 1)
    expectEnum("Main.Selection System", S.SelectionSystem, {"Target","Auto"})
    expectType("Main.Checks.Visible Check", S.VisCheck, "boolean")
    expectType("Main.Checks.Persist Lock On Death", S.PersistLockOnDeath, "boolean")
    expectType("Main.Checks.Death Check", S.DeathCheck, "boolean")
    expectKey("Keybinds.Target", S.ToggleKey)
    expectKey("Keybinds.Camlock", S.CamlockKey)
    expectKey("Keybinds.Speed", S.SpeedKey)
    expectKey("Keybinds.ESP", S.ESPKey)
    expectKey("Keybinds.Triggerbot", S.TriggerbotKey)
    expectType("Camlock.Enabled", S.CamlockEnabled, "boolean")
    expectRange("Camlock.Smoothness", S.CamlockSmoothness, 0, 1)
    expectEnum("Camlock.Click Type", S.CamlockClickType, {"Hold","Toggle"})
    expectEnum("Camlock.Easing Style", S.CamlockEasingStyle, {"Linear","Quad","Quart","Sine","Cubic","Back","Bounce","Elastic","Exponential","Circular"})
    expectEnum("Camlock.Easing Direction", S.CamlockEasingDirection, {"In","Out","InOut"})
    expectType("Triggerbot.Enabled", S.TriggerbotEnabled, "boolean")
    expectRange("Triggerbot.Distance", S.TriggerbotDistance, 0, 10000)
    expectRange("Triggerbot.Delay", S.TriggerbotDelay, 0, 10)
    expectEnum("Triggerbot.Click Type", S.TriggerbotClickType, {"Hold","Toggle"})
    expectType("Weapon Modifications.Infinite Range", S.InfiniteRange, "boolean")
    expectRange("Weapon Modifications.Taps", S.Taps, 1, 20)
    expectType("ForceHit.Enabled", S.ForceHitEnabled, "boolean")
    expectType("ForceHit.Full Damage", S.ForceHitFullDamage, "boolean")
    expectType("ESP.Enabled", S.ESPAllowed, "boolean")
    expectType("Hotkeys.Enabled", S.HotkeysEnabled, "boolean")
    expectType("Hotkeys.Dynamic Header", S.HotkeysDynamicHeader, "boolean")
    expectEnum("Triggerbot.FOV.Type", S.TriggerbotFOVType, {"Box","Direct"})
    expectEnum("Camlock.FOV.Type", S.CamlockFOVType, {"Box","Direct"})
end

local State      = StateLib.State
local safeCall   = StateLib.safeCall
local connect    = StateLib.connect
local isUnloaded = StateLib.isUnloaded
local disconnectAllTracked = StateLib.disconnectAllTracked

local screenGui = Instance.new("ScreenGui")
screenGui.Name             = "SilentAimTargetLock"
screenGui.ResetOnSpawn     = false
screenGui.IgnoreGuiInset   = true
screenGui.ZIndexBehavior   = Enum.ZIndexBehavior.Sibling
screenGui.Parent           = game:GetService("CoreGui")

local SHOOT_CMD = "ShootGun"
local tclone    = table.clone
local mt        = getrawmetatable(game)
local oldNamecall = mt.__namecall
local oldShoot    = GH.shoot

local spreadRng = Random.new()

local DEATH_CHECK_HP_THRESHOLD = 9

local function cfgEnabled(pathArr, defaultIfMissing)
    local v = Config.getPathValue(settings, pathArr)
    if v == nil then return defaultIfMissing end
    return v == true
end

local function isTargetFeatureAllowed()
    return cfgEnabled({"Main", "Enabled"}, true)
end

local function cloneArgs(args)
    if tclone then return tclone(args) end
    local out = {}; for i = 1, #args do out[i] = args[i] end; return out
end

local function isStoredShootArgsValid(args)
    return type(args) == "table" and args[1] == SHOOT_CMD and #args >= 6
end

local function applyRangePolicy(dataTable)
    if type(dataTable) ~= "table" then return end
    if Settings.InfiniteRange then dataTable.Range = 1e9 end
end

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

local TargetLine = Drawing.new("Line")
TargetLine.Visible      = false
TargetLine.Color        = Settings.LineColor or Color3.fromRGB(0, 255, 255)
TargetLine.Thickness    = 1
TargetLine.Transparency = 1

local function hideUI()
    local line = TargetLine
    if line then pcall(function() line.Visible = false end) end
end

local RayParams = RaycastParams.new()
RayParams.FilterType  = Enum.RaycastFilterType.Exclude
RayParams.IgnoreWater = true

local isAlive
isAlive = function(character)
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0
end

local function isDeathCheckState(character)
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0 and hum.Health <= DEATH_CHECK_HP_THRESHOLD
end

local function raycastVisible(part, targetCharacter)
    if not part or not Camera then return false end
    local origin    = Camera.CFrame.Position
    local direction = part.Position - origin
    local filter    = { LP.Character }
    RayParams.FilterDescendantsInstances = filter
    local result = workspace:Raycast(origin, direction, RayParams)
    if not result then return true end
    return targetCharacter and result.Instance:IsDescendantOf(targetCharacter) or false
end

local function isPartVisible(part, targetCharacter)
    if not part then return false end
    if not Settings.VisCheck then return true end
    return raycastVisible(part, targetCharacter)
end

local function isPartVisibleRaw(part, targetCharacter)
    return raycastVisible(part, targetCharacter)
end

local function getTargetPartForPlayer(player)
    if not player then return nil, nil end
    local char = player.Character
    if not char or not isAlive(char) then return nil, nil end
    local part = resolveLockPartForCharacter(char)
    return part, char
end

local function getConfigKeyCode(value)
    if typeof(value) == "EnumItem" and value.EnumType == Enum.KeyCode then return value end
    if type(value) == "string" then return Enum.KeyCode[string.upper(value)] end
    return nil
end

local function getToggleKeyCode()      return getConfigKeyCode(Settings.ToggleKey) end
local function getSpeedKeyCode()       return getConfigKeyCode(Settings.SpeedKey) end
local function getESPKeyCode()         return getConfigKeyCode(Settings.ESPKey) end
local function getPanicGroundKeyCode() return getConfigKeyCode(Settings.PanicGroundKey) end
local function getTriggerbotKeyCode()  return getConfigKeyCode(Settings.TriggerbotKey) end
local function getCamlockKeyCode()     return getConfigKeyCode(Settings.CamlockKey) or getToggleKeyCode() end

local function isAutoMode()
    local sys = string.lower(tostring(Settings.SelectionSystem or "target"))
    return sys == "auto"
end

local deathCheckConn = nil
local function clearDeathCheckConn()
    if deathCheckConn then
        pcall(function() deathCheckConn:Disconnect() end)
        deathCheckConn = nil
    end
end

local function clearTargetState(clearLastArgs)
    clearDeathCheckConn()
    State.LockedTarget = nil; State.CurrentPart = nil; State.FakePart = nil; State.FakePos = nil
    State.TriggerbotToggleActive = false
    ClosestPoint.resetCache()
    if clearLastArgs then State.LastShootArgs = nil end
end

local function clearCombatState(keepLastArgs)
    State.FakePart, State.FakePos = nil, nil; State.CurrentPart = nil
    if not keepLastArgs then State.LastShootArgs = nil end
end

local function passesDeathCheckRetargetThreshold(character)
    if not Settings.DeathCheck then return true end
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > DEATH_CHECK_HP_THRESHOLD
end

local function hasValidLockedTarget()
    if not State.LockedTarget or State.LockedTarget.Parent ~= Players then return false end
    local char = State.LockedTarget.Character
    if not char then return false end
    if Settings.DeathCheck and not passesDeathCheckRetargetThreshold(char) then return false end
    local part = getTargetPartForPlayer(State.LockedTarget)
    return part ~= nil
end

local function enforceDeathCheckOnCurrentLock()
    if not Settings.DeathCheck then return end
    local lockedTarget = State.LockedTarget
    if not lockedTarget or lockedTarget.Parent ~= Players then return end
    local char = lockedTarget.Character
    if not char or not isDeathCheckState(char) then return end
    State.Enabled = false
    clearTargetState(true)
    ForceHit.onTargetChanged(false)
    hideUI()
    TargetCard.bumpToggleId()
    TargetCard.hideCard()
end

local function getClosestPlayerFiltered(opts)
    if not Camera then return nil, nil end
    local mousePos = UIS:GetMouseLocation()
    local bestPart, bestPlayer, bestDistSq = nil, nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and plr.Character and isAlive(plr.Character) then
            if not opts.deathCheck or passesDeathCheckRetargetThreshold(plr.Character) then
                local part = resolveLockPartForCharacter(plr.Character)
                if part and (not opts.distanceFilter or opts.distanceFilter(part)) then
                    local passesVis = true
                    if opts.visCheck then
                        passesVis = opts.visCheck(part, plr.Character)
                    end
                    if passesVis then
                        local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                        if onScreen and screenPos.Z > 0 then
                            local dx = screenPos.X - mousePos.X; local dy = screenPos.Y - mousePos.Y
                            local distSq = dx * dx + dy * dy
                            if distSq < bestDistSq then bestDistSq = distSq; bestPart = part; bestPlayer = plr end
                        end
                    end
                end
            end
        end
    end
    return bestPart, bestPlayer
end

local function getClosestPlayerAndPart()
    return getClosestPlayerFiltered({
        deathCheck = true,
        visCheck = Settings.VisCheck and isPartVisible or nil,
    })
end

local function getClosestTriggerbotPart()
    if not Settings.TriggerbotEnabled then return nil end
    return getClosestPlayerFiltered({
        deathCheck = false,
        distanceFilter = Features.isPartInTriggerDistance,
        visCheck = Settings.TriggerbotVisCheck and isPartVisibleRaw or nil,
    })
end

local function getClosestCamlockPart()
    if not Settings.CamlockEnabled then return nil end
    return getClosestPlayerFiltered({
        deathCheck = true,
        distanceFilter = Features.isPartInCamlockDistance,
        visCheck = Settings.VisCheck and isPartVisible or nil,
    })
end

local function lockClosestTarget()
    local prevTarget = State.LockedTarget
    local _, plr = getClosestPlayerAndPart()
    if plr then
        if prevTarget ~= plr then
            ClosestPoint.resetCache()
            clearDeathCheckConn()
        end
        State.LockedTarget = plr; State.CurrentPart = nil
        if prevTarget ~= plr or not TargetCard.getToggleId() then
            TargetCard.bumpToggleId()
            if cfgEnabled({"Main", "Target Card"}, true) then
                TargetCard.showCardForTarget(plr)
            end
        end
        return true
    end

    if isAutoMode() and State.LockedTarget then
        local char = State.LockedTarget.Character
        if State.LockedTarget.Parent == Players and char and isAlive(char) then
            return true 
        end
    end
    clearDeathCheckConn()
    State.LockedTarget = nil; State.CurrentPart = nil
    State.TriggerbotToggleActive = false
    TargetCard.bumpToggleId(); TargetCard.hideCard()
    return false
end

local function resolveCurrentPartFromLinePart(linePart)
    if not linePart then return nil end
    if not Settings.VisCheck then return linePart end
    local lockedCharacter = State.LockedTarget and State.LockedTarget.Character or nil
    if not lockedCharacter or not isAlive(lockedCharacter) then return nil end
    return isPartVisible(linePart, lockedCharacter) and linePart or nil
end

local function ensureValidLockedTarget()
    if not State.LockedTarget then State.CurrentPart = nil; return nil, nil end
    if State.LockedTarget.Parent ~= Players then
        ForceHit.onTargetChanged(false)
        clearTargetState(true); TargetCard.bumpToggleId(); TargetCard.hideCard(); return nil, nil
    end
    local char = State.LockedTarget.Character
    if not char then
        State.CurrentPart = nil; hideUI()
        ForceHit.onTargetChanged(false)
        if not Settings.PersistLockOnDeath then
            clearTargetState(true); TargetCard.bumpToggleId(); TargetCard.hideCard()
        end
        return nil, nil
    end

    if Settings.DeathCheck and isDeathCheckState(char) then
        State.CurrentPart = nil; hideUI()
        State.Enabled = false
        ForceHit.onTargetChanged(false)
        clearTargetState(true); TargetCard.bumpToggleId(); TargetCard.hideCard()
        return nil, nil
    end

    local part, lockedChar = getTargetPartForPlayer(State.LockedTarget)
    if not part then
        State.CurrentPart = nil; hideUI()
        ForceHit.onTargetChanged(false)
        if not Settings.PersistLockOnDeath then
            clearTargetState(true); TargetCard.bumpToggleId(); TargetCard.hideCard()
        end
        return nil, nil
    end
    return part, lockedChar
end

local function tryRetarget(force)
    if not isAutoMode() and not State.Enabled then return false end
    if not isTargetFeatureAllowed() then return false end
    local now = os.clock()
    local retargetInterval = Settings.RetargetInterval or 0.15
    if not force and (now - State.LastRetarget) < retargetInterval then return false end
    State.LastRetarget = now
    return lockClosestTarget()
end

local sharedDeps = {
    Camera                 = Camera,
    Settings               = Settings,
    settings               = settings,
    State                  = State,
    safeCall               = safeCall,
    isUnloaded             = isUnloaded,
    MainEvent              = MainEvent,
    GH                     = GH,
    cloneArgs              = cloneArgs,
    applyRangePolicy       = applyRangePolicy,
    getSpreadAimPosition   = getSpreadAimPosition,
    getCamlockAimPosition  = getCamlockAimPosition,
    isTargetFeatureAllowed = isTargetFeatureAllowed,
    isStoredShootArgsValid = isStoredShootArgsValid,
    SHOOT_CMD              = SHOOT_CMD,
    LP                     = LP,
    Players                = Players,
    UIS                    = UIS,
}

local function mergeDeps(extra)
    local t = {}
    for k, v in pairs(sharedDeps) do t[k] = v end
    for k, v in pairs(extra) do t[k] = v end
    return t
end

ClosestPoint.init(mergeDeps({ BODY_PART_NAMES = BodyParts }))

ESP.init(mergeDeps({ screenGui = screenGui }))

TargetCard.init(mergeDeps({ screenGui = screenGui, ESP = ESP }))

Features.init(mergeDeps({}))

Hooks.init(mergeDeps({
    oldShoot       = oldShoot,
    mt             = mt,
    oldNamecall    = oldNamecall,
}))

Hooks.install()
Visuals.init(mergeDeps({ screenGui = screenGui, ForceHitModule = ForceHit, ESPModule = ESP, BODY_PART_NAMES = BodyParts }))

ForceHit.init(mergeDeps({}))
DelayChanger.init(mergeDeps({}))

local function cleanup()
    if State.Unloaded then return end
    State.Unloaded = true
    ClosestPoint.pruneCaches(true)
    TargetCard.bumpToggleId()
    ForceHit.cleanup()
    DelayChanger.cleanup()
    State.FakePart, State.FakePos = nil, nil
    State.CurrentPart = nil; State.LockedTarget = nil; State.LastShootData = nil
    State.TriggerbotHoldActive = false; State.TriggerbotToggleActive = false
    State.CamlockHoldActive = false; State.CamlockToggleActive = false
    State.CardCapabilityBlocked = false; State.ESPEnabled = false; State.SpeedActive = false
    clearDeathCheckConn()
    Features.resetSpeedModification()
    State.Enabled = false
    clearTargetState(true)
    disconnectAllTracked(); State.Connections = {}
    ESP.cleanupEsp()
    hideUI()
    safeCall(function()
        if TargetLine then TargetLine.Visible = false; TargetLine:Remove(); TargetLine = nil end
    end, "CleanupFails")
    Features.cleanupFOVBox()
    Visuals.cleanup()
    safeCall(function() TargetCard.destroyCard() end, "CleanupFails")
    safeCall(function() if screenGui and screenGui.Parent then screenGui:Destroy() end end, "CleanupFails")
    Hooks.uninstall()
    if GENV.__SilentAimCleanup == cleanup then GENV.__SilentAimCleanup = nil end
end

GENV.__SilentAimCleanup = cleanup

connect(UIS.InputBegan, function(input, gpe)
    if State.Unloaded or gpe then return end
    local triggerKey = getTriggerbotKeyCode()
    local camlockKey = getCamlockKeyCode()
    local toggleKey = getToggleKeyCode()
    local isTriggerKey = triggerKey and input.KeyCode == triggerKey and Settings.TriggerbotEnabled
    local isCamlockKey = camlockKey and input.KeyCode == camlockKey and Settings.CamlockEnabled
    local isToggleKey = toggleKey and input.KeyCode == toggleKey and isTargetFeatureAllowed() and not isAutoMode()
    local triggerClickType = string.lower(tostring(Settings.TriggerbotClickType or "Hold"))
    local camlockClickType = string.lower(tostring(Settings.CamlockClickType or "Hold"))

    if isTriggerKey and triggerClickType ~= "toggle" then
        State.TriggerbotHoldActive = true
    end

    if isCamlockKey and camlockClickType ~= "toggle" then
        State.CamlockHoldActive = true
    end

    if isToggleKey then
        if State.LockedTarget then
            State.Enabled = false
            clearTargetState(true); hideUI()
            ForceHit.onTargetChanged(false)
            TargetCard.bumpToggleId(); TargetCard.hideCard()
        else
            local _, candidate = getClosestPlayerAndPart()
            if not candidate then
                State.Enabled = false
                clearCombatState(true)
                hideUI()
            else
                State.Enabled = true
                State.LastRetarget = 0
                local locked = tryRetarget(true)
                if not locked then
                    State.Enabled = false
                    clearCombatState(true)
                    hideUI()
                else
                    ForceHit.onTargetChanged(true)
                end
            end
        end
    end

    if isTriggerKey and triggerClickType == "toggle" then
        if State.TriggerbotToggleActive then
            State.TriggerbotToggleActive = false
        elseif hasValidLockedTarget() then
            State.TriggerbotToggleActive = true
        end
    end

    if isCamlockKey and camlockClickType == "toggle" then
        if State.CamlockToggleActive then
            State.CamlockToggleActive = false
        else
            local camlockPart = getClosestCamlockPart()
            if camlockPart then
                State.CamlockToggleActive = true
            end
        end
    end

    if isToggleKey then
        return
    end
    local speedKey = getSpeedKeyCode()
    if speedKey and input.KeyCode == speedKey then
        if not Settings.SpeedEnabled then return end
        State.SpeedActive = not State.SpeedActive
        if not State.SpeedActive then Features.resetSpeedModification() end
        return
    end
    local espKey = getESPKeyCode()
    if espKey and input.KeyCode == espKey then
        if not Settings.ESPAllowed then return end
        State.ESPEnabled = not State.ESPEnabled
        if not State.ESPEnabled then
            ESP.hideAllEsp()
        else
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LP then ESP.createPlayerEsp(player) end
            end
        end
        return
    end
    local panicKey = getPanicGroundKeyCode()
    if panicKey and input.KeyCode == panicKey and Settings.PanicGroundEnabled then
        Features.panicGround(); return
    end
end)

connect(UIS.InputEnded, function(input, gpe)
    if State.Unloaded or gpe then return end
    local triggerKey = getTriggerbotKeyCode()
    local camlockKey = getCamlockKeyCode()
    if triggerKey and input.KeyCode == triggerKey and Settings.TriggerbotEnabled then
        State.TriggerbotHoldActive = false
    end
    if camlockKey and input.KeyCode == camlockKey and Settings.CamlockEnabled then
        State.CamlockHoldActive = false
    end
end)

connect(LP.CharacterAdded, function()
    if State.Unloaded then return end
    clearCombatState(true)
    State.SpeedCharacter = nil; State.DefaultWalkSpeed = nil; State.SpeedStatesPatched = false
end)

connect(RunService.RenderStepped, function(deltaTime)
    if State.Unloaded then return end
    if Camera ~= workspace.CurrentCamera then Camera = workspace.CurrentCamera end
    ClosestPoint.pruneCaches(false)
    enforceDeathCheckOnCurrentLock()
    ESP.updateEsp()
    Visuals.update()
    local equippedTool = Features.getEquippedTool()
    Features.applySpeedModification(equippedTool, deltaTime)
    local camlockPart = getClosestCamlockPart()
    local camlockBox  = Features.runCamlock(camlockPart)
    Features.updateCamlockFOVBox(camlockPart, camlockBox)
    local triggerbotPart = getClosestTriggerbotPart()
    local triggerbotBox  = Features.runTriggerbot(triggerbotPart)
    Features.updateTriggerbotFOVBox(triggerbotPart, triggerbotBox)
    if not isTargetFeatureAllowed() then
        hideUI()
        if State.Enabled or State.LockedTarget then
            State.Enabled = false; clearTargetState(true)
            ForceHit.onTargetChanged(false)
            TargetCard.bumpToggleId(); TargetCard.hideCard()
        end
        return
    end
    if not State.Enabled and not isAutoMode() then hideUI(); return end
    if isAutoMode() then
        local prevTarget = State.LockedTarget
        tryRetarget(false)
        State.Enabled = State.LockedTarget ~= nil
        if State.LockedTarget ~= prevTarget then
            ForceHit.onTargetChanged(State.LockedTarget ~= nil)
        end
    end
    if State.LockedTarget then
        if cfgEnabled({"Main", "Target Card"}, true) then
            TargetCard.updateCardStats(State.LockedTarget)
        else
            TargetCard.bumpToggleId(); TargetCard.hideCard()
        end
    end
    local aimPart, lockedChar = ensureValidLockedTarget()
    if not aimPart then clearCombatState(true); hideUI(); return end
    local canUseAimPart = resolveCurrentPartFromLinePart(aimPart) ~= nil
    State.CurrentPart = canUseAimPart and aimPart or nil

    local lineAnchorPart = (lockedChar and lockedChar:FindFirstChild("Head")) or aimPart
    local screenPos, onScreen = Camera:WorldToViewportPoint(lineAnchorPart.Position)
    if not onScreen or screenPos.Z <= 0 then hideUI(); return end
    local mousePos = UIS:GetMouseLocation()
    if Settings.VisCheck then
        TargetLine.Color = canUseAimPart and Settings.LineColorVisible or Settings.LineColorBlocked
    else
        TargetLine.Color = Settings.LineColor or Color3.fromRGB(0, 255, 255)
    end
    TargetLine.Visible = Settings.LineEnabled ~= false
    TargetLine.From    = Vector2.new(mousePos.X, mousePos.Y)
    TargetLine.To      = Vector2.new(screenPos.X, screenPos.Y)
end)

State.ESPEnabled = Settings.ESPAllowed ~= false

for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LP then ESP.createPlayerEsp(player); ESP.watchEspPlayer(player) end
end

connect(Players.PlayerAdded, function(player)
    if State.Unloaded or player == LP then return end
    ESP.watchEspPlayer(player)
    if player.Character then ESP.createPlayerEsp(player) end
end)

connect(Players.PlayerRemoving, function(player)
    if State.Unloaded then return end
    ClosestPoint.pruneCaches(true)
    ESP.removePlayerEsp(player)
    if State.LockedTarget == player then
        clearTargetState(true); hideUI()
        ForceHit.onTargetChanged(false)
        TargetCard.bumpToggleId(); TargetCard.hideCard()
    end
end)