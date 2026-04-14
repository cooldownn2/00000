local Players = game:GetService("Players")

local CharacterModel = {}

local Settings
local LP
local isUnloaded

local CharAvatarSpoofer
local CharUISpoofer

local avatar = nil
local uiSpoofer = nil

local enabledState = false
local targetState = ""
local uiEnabledState = false
local uiTargetState = ""
local lastUpdate = 0
local UPDATE_INTERVAL = 0.1
local switchApplyToken = 0

local TARGET_STABILIZE_REAPPLY_DELAY = 0.72
local RESPAWN_REAPPLY_DELAY = 1.02

local ENV_STATE_KEY = "__SauceCharacterModelState"
local GETGENV_FN = rawget(_G, "getgenv")

local function getSpooferEnabled()
    if not Settings then return false end
    return Settings.AvatarSpooferEnabled == true
end

local function getSpooferUserTarget()
    if not Settings then return "" end

    local target = Settings.AvatarSpooferUser
    if target == nil then return "" end

    local text = tostring(target)
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

local function getApplyRespawnEnabled()
    if not Settings then return true end
    if Settings.AvatarSpooferApplyRespawn == nil then return true end
    return Settings.AvatarSpooferApplyRespawn == true
end

local function getUISpooferEnabled()
    if not Settings then return false end
    return Settings.UISpooferEnabled == true
end

local function getUISpooferUserTarget()
    if not Settings then return "" end

    local target = Settings.UISpooferUser
    if target == nil then return "" end

    local text = tostring(target)
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

local function normalizeTarget(raw)
    if raw == nil then return "" end
    local text = tostring(raw)
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

local function ensureModules()
    if avatar and uiSpoofer then
        return true
    end

    if not CharAvatarSpoofer or not CharUISpoofer then
        return false
    end

    avatar = CharAvatarSpoofer.new({
        localPlayer = LP,
    })
    uiSpoofer = CharUISpoofer.new(LP)

    return true
end

local function setEnabled(enabled)
    enabled = enabled == true
    if enabledState == enabled then return end

    enabledState = enabled

    if not ensureModules() then return end

    avatar:setEnabled(enabled)
end

local function setUISpooferEnabled(enabled)
    enabled = enabled == true
    if uiEnabledState == enabled then return end

    uiEnabledState = enabled

    if not ensureModules() then return end

    uiSpoofer:setEnabled(enabled)
end

local function switchTargetSafe(target)
    if not ensureModules() then return false end
    if not enabledState then return false end
    if target == nil or target == "" then return false end

    switchApplyToken = switchApplyToken + 1
    local applyToken = switchApplyToken

    local function canApplyForToken()
        return enabledState and applyToken == switchApplyToken and target == targetState
    end

    local avatarOk = avatar:setTarget(target)

    -- Stabilization pass: one delayed reapply to mirror the old "char twice" safety.
    task.delay(TARGET_STABILIZE_REAPPLY_DELAY, function()
        if not canApplyForToken() then return end
        avatar:reapply()
    end)

    return avatarOk
end

local function switchUITargetSafe(target)
    if not ensureModules() then return false end
    if not uiEnabledState then return false end
    if target == nil or target == "" then return false end

    local ok = uiSpoofer:setTarget(target)
    if ok then
        uiTargetState = target
    end
    return ok
end

local function reapplyAll()
    if not ensureModules() then return false end

    local ok = false
    if enabledState then
        ok = avatar:reapply() or ok
    end
    if uiEnabledState then
        ok = uiSpoofer:reapply() or ok
    end
    return ok
end

local function installEnvApi()
    local ok, env = pcall(function() return GETGENV_FN and GETGENV_FN() or nil end)
    if not ok or not env then return end

    local prev = env[ENV_STATE_KEY]
    if type(prev) == "table" and type(prev.cleanup) == "function" then
        pcall(prev.cleanup)
    end

    local state = {
        cleanup = function()
            CharacterModel.cleanup()
        end,
    }

    env[ENV_STATE_KEY] = state

    local function setTargetAny(target)
        if type(target) == "number" then
            target = tostring(math.floor(target))
        end
        targetState = normalizeTarget(target)
        if targetState == "" then return false end

        if Settings then
            Settings.AvatarSpooferUser = targetState
            Settings.AvatarSpooferEnabled = true
        end
        setEnabled(true)

        return switchTargetSafe(targetState)
    end

    local function setAvatarOnly(target)
        if not setTargetAny(target) then return false end
        if not ensureModules() then return false end
        return avatar:setTarget(targetState)
    end

    local function setUiTargetAny(target)
        if type(target) == "number" then
            target = tostring(math.floor(target))
        end
        local normalized = normalizeTarget(target)
        if normalized == "" then return false end

        if Settings then
            Settings.UISpooferUser = normalized
            Settings.UISpooferEnabled = true
        end

        setUISpooferEnabled(true)
        return switchUITargetSafe(normalized)
    end

    local function fullCleanup()
        CharacterModel.cleanup()
    end

    env.CharacterModel = {
        SetTarget = setTargetAny,
        Reapply = function()
            return reapplyAll()
        end,
        Cleanup = fullCleanup,
    }

    env.AvatarSpoofer = {
        SetTarget = setTargetAny,
        SetUser = setTargetAny,
        Reapply = function()
            return avatar and avatar:reapply() or false
        end,
        Cleanup = fullCleanup,
    }

    -- Keep legacy alias for existing scripts while backing it with AvatarSpoofer.
    env.OutfitCopy = {
        SetTarget = setAvatarOnly,
        SetTargetUserId = setAvatarOnly,
        SetTargetUsername = setAvatarOnly,
        Reapply = function() return avatar and avatar:reapply() or false end,
        Cleanup = fullCleanup,
    }

    env.UISpoofer = {
        SetTarget = setUiTargetAny,
        SetUser = setUiTargetAny,
        Reapply = function() return uiSpoofer and uiSpoofer:reapply() or false end,
        Stop = function()
            if Settings then Settings.UISpooferEnabled = false end
            setUISpooferEnabled(false)
        end,
        Info = function() return uiSpoofer and uiSpoofer:getTargetInfo() or nil end,
        Cleanup = fullCleanup,
    }

    env.SwitchTargetSafe = setTargetAny
    env.SetTargetSafe = setTargetAny

    env.CopySetUserId = setAvatarOnly
    env.CopyReapplyOutfit = function() return avatar and avatar:reapply() or false end
    env.CopyOutfitCleanup = fullCleanup
    env.FullComboCleanup = fullCleanup
    env.CloneFullCleanup = fullCleanup
end

local function update()
    if isUnloaded and isUnloaded() then return end

    local now = os.clock()
    if now - lastUpdate < UPDATE_INTERVAL then return end
    lastUpdate = now

    local enabled = getSpooferEnabled()
    setEnabled(enabled)

    if enabled then
        local target = getSpooferUserTarget()
        if target ~= "" and target ~= targetState then
            targetState = target
            switchTargetSafe(targetState)
        end
    end

    local uiEnabled = getUISpooferEnabled()
    setUISpooferEnabled(uiEnabled)

    if uiEnabled then
        local uiTarget = getUISpooferUserTarget()
        if uiTarget ~= "" and uiTarget ~= uiTargetState then
            switchUITargetSafe(uiTarget)
        end
    else
        uiTargetState = ""
    end
end

local function onCharacterAdded(char)
    local shouldEnable = getSpooferEnabled()
    if shouldEnable and not enabledState then
        setEnabled(true)
    end

    local shouldUiEnable = getUISpooferEnabled()
    if shouldUiEnable and not uiEnabledState then
        setUISpooferEnabled(true)
    end
    if uiEnabledState and uiSpoofer then
        task.defer(function()
            if uiEnabledState then
                uiSpoofer:reapply()
            end
        end)
    end

    if not enabledState then return end
    if not ensureModules() then return end
    if not getApplyRespawnEnabled() then return end

    switchApplyToken = switchApplyToken + 1
    local applyToken = switchApplyToken

    local configuredTarget = getSpooferUserTarget()
    local target = normalizeTarget(targetState ~= "" and targetState or configuredTarget)
    if target == "" then
        avatar:onCharacterAdded(char)
        return
    end
    if targetState == "" or target ~= targetState then
        targetState = target
    end

    avatar:onCharacterAdded(char)

    task.delay(RESPAWN_REAPPLY_DELAY, function()
        if not (enabledState and applyToken == switchApplyToken and target == targetState and char and char.Parent) then
            return
        end
        avatar:reapply()
    end)
end

local function cleanup()
    enabledState = false
    targetState = ""
    uiEnabledState = false
    uiTargetState = ""
    switchApplyToken = switchApplyToken + 1

    if avatar then avatar:cleanup() end
    if uiSpoofer then uiSpoofer:cleanup() end

    avatar = nil
    uiSpoofer = nil
end

local function init(deps)
    Settings = deps.Settings
    LP = deps.LP or Players.LocalPlayer
    isUnloaded = deps.isUnloaded

    CharAvatarSpoofer = deps.CharAvatarSpoofer
    CharUISpoofer = deps.CharUISpoofer

    installEnvApi()
end

CharacterModel.init = init
CharacterModel.update = update
CharacterModel.onCharacterAdded = onCharacterAdded
CharacterModel.cleanup = cleanup
CharacterModel.switchTargetSafe = switchTargetSafe
CharacterModel.reapplyAll = reapplyAll

return CharacterModel
