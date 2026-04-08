local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local UIS        = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local LP         = Players.LocalPlayer
local Camera     = workspace.CurrentCamera
local MainEvent  = RS:WaitForChild("MainEvent")
local GH         = require(RS.Modules.GunHandler)

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
local ConfigBootstrap = load("core/ConfigBootstrap")
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
local Spread        = load("aim/Spread")
local Targeting     = load("core/Targeting")
local TargetLineUI  = load("core/TargetLine")

local settings   = Config.settings
local Settings   = Config.Settings

if GENV.SauceConfig then
    ConfigBootstrap.applyUserConfig(GENV.SauceConfig, settings)
end
ConfigBootstrap.validateSettings(Settings)

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

local function hideUI()
    TargetLineUI.hide()
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
    Targeting.clearTargetState(clearLastArgs)
end

local function clearCombatState(keepLastArgs)
    Targeting.clearCombatState(keepLastArgs)
end

local function hasValidLockedTarget()
    return Targeting.hasValidLockedTarget()
end

local function enforceDeathCheckOnCurrentLock()
    if not Settings.DeathCheck then return end
    local lockedTarget = State.LockedTarget
    if not lockedTarget or lockedTarget.Parent ~= Players then return end
    local char = lockedTarget.Character
    if not char or not Targeting.isDeathCheckState(char) then return end
    State.Enabled = false
    clearTargetState(true)
    ForceHit.onTargetChanged(false)
    hideUI()
    TargetCard.bumpToggleId()
    TargetCard.hideCard()
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
        if State.LockedTarget.Parent == Players and char and Targeting.isAlive(char) then
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
    return Targeting.resolveCurrentPartFromLinePart(linePart)
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

    if Settings.DeathCheck and Targeting.isDeathCheckState(char) then
        State.CurrentPart = nil; hideUI()
        State.Enabled = false
        ForceHit.onTargetChanged(false)
        clearTargetState(true); TargetCard.bumpToggleId(); TargetCard.hideCard()
        return nil, nil
    end

    local part, lockedChar = Targeting.getTargetPartForPlayer(State.LockedTarget)
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
    getSpreadAimPosition   = Spread.getSpreadAimPosition,
    getCamlockAimPosition  = Spread.getCamlockAimPosition,
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

Spread.init(mergeDeps({ ClosestPoint = ClosestPoint }))

Features.init(mergeDeps({}))

Targeting.init(mergeDeps({
    Features = Features,
    ClosestPoint = ClosestPoint,
    Spread = Spread,
    getCamera = function() return Camera end,
}))

TargetLineUI.init(mergeDeps({}))

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
    safeCall(function() TargetLineUI.cleanup() end, "CleanupFails")
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
    local mousePos = UIS:GetMouseLocation()
    TargetLineUI.update(Camera, lineAnchorPart, canUseAimPart, mousePos)
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