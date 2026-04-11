local Players = game:GetService("Players")

local CharacterModel = {}

local Settings
local LP
local isUnloaded

local CharCommon
local CharOutfit
local CharAnimation
local CharEmote

local shared = nil
local outfit = nil
local animation = nil
local emote = nil

local enabledState = false
local targetState = ""
local lastUpdate = 0
local UPDATE_INTERVAL = 0.1
local switchApplyToken = 0

local STABILIZE_INITIAL_ANIM_DELAY = 0.10
local STABILIZE_ANIM_DELAY = 0.34
local STABILIZE_FULL_REAPPLY_DELAY = 0.72
local STABILIZE_POST_REAPPLY_ANIM_DELAY = 1.05
local RESPAWN_ANIM_DELAY = 0.68
local RESPAWN_REAPPLY_DELAY = 1.02
local RESPAWN_POST_REAPPLY_ANIM_DELAY = 1.30

local ENV_STATE_KEY = "__SauceCharacterModelState"
local GETGENV_FN = rawget(_G, "getgenv")

local function normalizeTarget(raw)
    if raw == nil then return "" end
    local text = tostring(raw)
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

local function ensureModules()
    if shared and outfit and animation and emote then
        return true
    end

    if not CharCommon or not CharOutfit or not CharAnimation or not CharEmote then
        return false
    end

    shared = CharCommon.new(LP)
    emote = CharEmote.new({
        shared = shared,
        localPlayer = LP,
    })
    animation = CharAnimation.new({
        shared = shared,
        localPlayer = LP,
    })
    outfit = CharOutfit.new({
        shared = shared,
        localPlayer = LP,
    })

    return true
end

local function setEnabled(enabled)
    enabled = enabled == true
    if enabledState == enabled then return end

    enabledState = enabled

    if not ensureModules() then return end

    outfit:setEnabled(enabled)
    animation:setEnabled(enabled)
    emote:setEnabled(enabled)
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

    local function applyAnimAndEmote()
        if not canApplyForToken() then return end
        emote:mimicFromTarget(target)
        animation:mimicFromTarget(target)
    end

    local outfitOk = outfit:setTarget(target)

    -- Run animation shortly after switch instead of immediate defer so outfit
    -- apply/body-description writes have a chance to settle first.
    task.delay(STABILIZE_INITIAL_ANIM_DELAY, applyAnimAndEmote)

    -- Stabilization pass: re-run animation + emote after initial settle.
    task.delay(STABILIZE_ANIM_DELAY, function()
        applyAnimAndEmote()
    end)

    -- Full stabilization pass: mirror the successful "char twice" behavior.
    task.delay(STABILIZE_FULL_REAPPLY_DELAY, function()
        if not canApplyForToken() then return end
        outfit:reapply()
    end)

    -- Apply animation/emote after reapply has had time to finish async work.
    task.delay(STABILIZE_POST_REAPPLY_ANIM_DELAY, function()
        applyAnimAndEmote()
    end)

    return outfitOk
end

local function reapplyAll()
    if not ensureModules() then return false end
    if not enabledState then return false end

    local ok = false
    ok = outfit:reapply() or ok
    ok = animation:reapply() or ok
    ok = emote:reapply() or ok
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
            Settings.CharacterModelUserId = targetState
            Settings.CharacterModelEnabled = true
        end
        setEnabled(true)

        return switchTargetSafe(targetState)
    end

    local function setOutfitOnly(target)
        if not setTargetAny(target) then return false end
        if not ensureModules() then return false end
        return outfit:setTarget(targetState)
    end

    local function setAnimationOnly(target)
        if not setTargetAny(target) then return false end
        if not ensureModules() then return false end
        return animation:mimicFromTarget(targetState)
    end

    local function setEmoteOnly(target)
        if not setTargetAny(target) then return false end
        if not ensureModules() then return false end
        return emote:mimicFromTarget(targetState)
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

    env.OutfitCopy = {
        SetTarget = setOutfitOnly,
        SetTargetUserId = setOutfitOnly,
        SetTargetUsername = setOutfitOnly,
        Reapply = function() return outfit and outfit:reapply() or false end,
        Cleanup = fullCleanup,
    }

    env.EmoteMimic = {
        SetTarget = setEmoteOnly,
        SetTargetUserId = function(target)
            if not setTargetAny(target) then return false end
            if not ensureModules() then return false end
            local userId = shared:resolveUserToId(targetState)
            return userId and emote:mimicFromUserId(userId) or false
        end,
        Reapply = function() return emote and emote:reapply() or false end,
        Cleanup = fullCleanup,
    }

    env.SwitchTargetSafe = setTargetAny
    env.SetTargetSafe = setTargetAny

    env.CopySetUserId = setOutfitOnly
    env.CopyReapplyOutfit = function() return outfit and outfit:reapply() or false end
    env.CopyOutfitCleanup = fullCleanup

    env.CloneAnimationsFromTarget = setAnimationOnly
    env.AnimationMimicCleanup = fullCleanup
    env.CloneEmotesFromTarget = setEmoteOnly
    env.EmoteMimicCleanup = fullCleanup
    env.FullComboCleanup = fullCleanup
    env.CloneFullCleanup = fullCleanup
end

local function update()
    if isUnloaded and isUnloaded() then return end

    local now = os.clock()
    if now - lastUpdate < UPDATE_INTERVAL then return end
    lastUpdate = now

    local enabled = Settings.CharacterModelEnabled == true
    setEnabled(enabled)
    if not enabled then return end

    local target = normalizeTarget(Settings.CharacterModelUserId)
    if target == "" then return end

    if target ~= targetState then
        targetState = target
        switchTargetSafe(targetState)
    end
end

local function onCharacterAdded(char)
    if not enabledState then return end
    if not ensureModules() then return end

    switchApplyToken = switchApplyToken + 1
    local applyToken = switchApplyToken

    local target = normalizeTarget(targetState ~= "" and targetState or (Settings and Settings.CharacterModelUserId))
    if target == "" then
        outfit:onCharacterAdded(char)
        return
    end
    if targetState == "" then
        targetState = target
    end

    local function canApplyForToken()
        return enabledState and applyToken == switchApplyToken and target == targetState and char and char.Parent
    end

    local function applyAnimAndEmote()
        if not canApplyForToken() then return end
        animation:mimicFromTarget(target)
        emote:mimicFromTarget(target)
    end

    outfit:onCharacterAdded(char)

    -- Respawn stabilization sequence: outfit first, then animation/emote after
    -- outfit's delayed apply, then one full reapply pass.
    task.delay(RESPAWN_ANIM_DELAY, function()
        applyAnimAndEmote()
    end)

    task.delay(RESPAWN_REAPPLY_DELAY, function()
        if not canApplyForToken() then return end
        outfit:reapply()
    end)

    task.delay(RESPAWN_POST_REAPPLY_ANIM_DELAY, function()
        applyAnimAndEmote()
    end)
end

local function cleanup()
    enabledState = false
    targetState = ""
    switchApplyToken = switchApplyToken + 1

    if outfit then outfit:cleanup() end
    if animation then animation:cleanup() end
    if emote then emote:cleanup() end

    outfit = nil
    animation = nil
    emote = nil

    if shared then shared:destroy() end
    shared = nil
end

local function init(deps)
    Settings = deps.Settings
    LP = deps.LP or Players.LocalPlayer
    isUnloaded = deps.isUnloaded

    CharCommon = deps.CharCommon
    CharOutfit = deps.CharOutfit
    CharAnimation = deps.CharAnimation
    CharEmote = deps.CharEmote

    installEnvApi()
end

CharacterModel.init = init
CharacterModel.update = update
CharacterModel.onCharacterAdded = onCharacterAdded
CharacterModel.cleanup = cleanup
CharacterModel.switchTargetSafe = switchTargetSafe
CharacterModel.reapplyAll = reapplyAll

return CharacterModel