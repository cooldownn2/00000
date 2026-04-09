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
local Config     = load("core/Registry")
local ConfigBridge = load("core/ConfigBridge")
local StateLib   = load("core/State")
local ESP        = load("ui/ESP")
local TargetCard = load("ui/TargetCard")
local Features   = load("Features")
local Movement   = load("features/Movement")
local AimAssist  = load("features/AimAssist")
local FOVBoxes   = load("features/FOVBoxes")
local Hooks      = load("core/Hooks")
local Visuals    = load("ui/Visuals")
local ForceHit      = load("aim/ForceHit")
local BodyParts     = load("core/BodyParts")
local ClosestPoint  = load("aim/ClosestPoint")
local DelayChanger  = load("core/DelayChanger")
local Spread        = load("aim/Spread")
local Taps          = load("aim/Taps")
local Targeting     = load("core/Targeting")

local settings   = Config.settings
local Settings   = Config.Settings

if GENV.SauceConfig then
    ConfigBridge.applyUserConfig(settings, GENV.SauceConfig)
end

ConfigBridge.validateSettings(Settings)

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
    return Spread.isClosestPointMode()
end

local function resolveLockPartForCharacter(char)
    return Spread.resolveLockPartForCharacter(char)
end

local function getSpreadAimPosition(part)
    return Spread.getSpreadAimPosition(part)
end

local function getCamlockAimPosition(part)
    return Spread.getCamlockAimPosition(part)
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

local function clearDeathCheckConn()
    Targeting.clearDeathCheckConn()
end

local function clearTargetState(clearLastArgs)
    Targeting.clearTargetState(clearLastArgs)
end

local function clearCombatState(keepLastArgs)
    Targeting.clearCombatState(keepLastArgs)
end

local function hasValidLockedTarget()
    return Targeting.hasValidLockedTarget()
end

local function enforceDeathCheckOnCurrentLock()
    Targeting.enforceDeathCheckOnCurrentLock()
end

local function getClosestPlayerAndPart()
    return Targeting.getClosestPlayerAndPart()
end

local function getClosestTriggerbotPart()
    return Targeting.getClosestTriggerbotPart()
end

local function getClosestCamlockPart()
    return Targeting.getClosestCamlockPart()
end

local function lockClosestTarget()
    return Targeting.lockClosestTarget()
end

local function resolveCurrentPartFromLinePart(linePart)
    return Targeting.resolveCurrentPartFromLinePart(linePart)
end

local function ensureValidLockedTarget()
    return Targeting.ensureValidLockedTarget()
end

local function tryRetarget(force)
    return Targeting.tryRetarget(force)
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

Spread.init(mergeDeps({ ClosestPoint = ClosestPoint }))

ESP.init(mergeDeps({ screenGui = screenGui }))

TargetCard.init(mergeDeps({ screenGui = screenGui, ESP = ESP }))

Features.init(mergeDeps({
    Movement = Movement,
    AimAssist = AimAssist,
    FOVBoxes = FOVBoxes,
}))

Taps.init(mergeDeps({}))
Hooks.init(mergeDeps({
    oldShoot                 = oldShoot,
    mt                       = mt,
    oldNamecall              = oldNamecall,
    Taps                     = Taps,
    isPartInsideSilentAimFOV = AimAssist.isPartInsideSilentAimFOV,
}))

Hooks.install()
Visuals.init(mergeDeps({ screenGui = screenGui, ForceHitModule = ForceHit, ESPModule = ESP, BODY_PART_NAMES = BodyParts }))

ForceHit.init(mergeDeps({}))
DelayChanger.init(mergeDeps({}))
Targeting.init(mergeDeps({
    Features = Features,
    ForceHit = ForceHit,
    TargetCard = TargetCard,
    ClosestPoint = ClosestPoint,
    hideUI = hideUI,
    getPathValue = Config.getPathValue,
    resolveLockPartForCharacter = resolveLockPartForCharacter,
}))

local function watchCharacterTools(char)
    if not char then return end
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Tool") then Spread.applySpreadMod(child) end
    end
    connect(char.ChildAdded, function(child)
        if State.Unloaded then return end
        if child:IsA("Tool") then Spread.applySpreadMod(child) end
    end)
end

if LP.Character then watchCharacterTools(LP.Character) end

local function cleanup()
    if State.Unloaded then return end
    State.Unloaded = true
    ClosestPoint.pruneCaches(true)
    TargetCard.bumpToggleId()
    ForceHit.cleanup()
    DelayChanger.cleanup()
    Spread.cleanup()
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

connect(LP.CharacterAdded, function(char)
    if State.Unloaded then return end
    clearCombatState(true)
    State.SpeedCharacter = nil; State.DefaultWalkSpeed = nil; State.SpeedStatesPatched = false
    watchCharacterTools(char)
end)

connect(RunService.RenderStepped, function(deltaTime)
    if State.Unloaded then return end
    if Camera ~= workspace.CurrentCamera then Camera = workspace.CurrentCamera end
    ClosestPoint.pruneCaches(false)
    enforceDeathCheckOnCurrentLock()
    ESP.updateEsp()
    Visuals.update()
    local equippedTool = (Settings.SpeedEnabled and State.SpeedActive) and Features.getEquippedTool() or nil
    Features.applySpeedModification(equippedTool, deltaTime)

    if Settings.CamlockEnabled and (State.CamlockHoldActive or State.CamlockToggleActive) then
        local camlockPart = getClosestCamlockPart()
        Features.runCamlock(camlockPart)
        Features.updateCamlockFOVBox(camlockPart)
    else
        local camlockPart = getClosestCamlockPart()
        Features.updateCamlockFOVBox(camlockPart)
    end

    if Settings.TriggerbotEnabled and (State.TriggerbotHoldActive or State.TriggerbotToggleActive) then
        local triggerPart = getClosestTriggerbotPart()
        Features.runTriggerbot(triggerPart)
        Features.updateTriggerbotFOVBox(triggerPart)
    else
        local triggerPart = getClosestTriggerbotPart()
        Features.updateTriggerbotFOVBox(triggerPart)
    end
    if not isTargetFeatureAllowed() then
        hideUI()
        Features.hideSilentAimFOVBox()
        if State.Enabled or State.LockedTarget then
            State.Enabled = false; clearTargetState(true)
            ForceHit.onTargetChanged(false)
            TargetCard.bumpToggleId(); TargetCard.hideCard()
        end
        return
    end
    if not State.Enabled and not isAutoMode() then hideUI(); Features.hideSilentAimFOVBox(); return end
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
    if not aimPart then clearCombatState(true); hideUI(); Features.hideSilentAimFOVBox(); return end
    local canUseAimPart = resolveCurrentPartFromLinePart(aimPart) ~= nil
    State.CurrentPart = canUseAimPart and aimPart or nil
    Features.updateSilentAimFOVBox(State.CurrentPart)

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