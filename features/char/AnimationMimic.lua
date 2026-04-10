local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local AnimationMimic = {}
AnimationMimic.__index = AnimationMimic

local R15_FALLBACK_ANIMATIONS = {
    climb = "rbxassetid://507765644",
    fall = "rbxassetid://507765000",
    jump = "rbxassetid://507765000",
    run = "rbxassetid://913376220",
    walk = "rbxassetid://913402848",
    swim = "rbxassetid://913384386",
    idle1 = "rbxassetid://507766388",
    idle2 = "rbxassetid://507766666",
}

local SLOT_SPECS = {
    { folder = "climb", fallback = R15_FALLBACK_ANIMATIONS.climb },
    { folder = "fall", fallback = R15_FALLBACK_ANIMATIONS.fall },
    { folder = "jump", fallback = R15_FALLBACK_ANIMATIONS.jump },
    { folder = "run", fallback = R15_FALLBACK_ANIMATIONS.run },
    { folder = "walk", fallback = R15_FALLBACK_ANIMATIONS.walk },
    { folder = "swim", fallback = R15_FALLBACK_ANIMATIONS.swim },
}

local ANIM_KEYS = { "climb", "fall", "jump", "run", "walk", "swim", "idle" }

local function getFirstAnimationInFolder(folder)
    if not folder then return nil end
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("Animation") then return child end
    end
    return nil
end

local function hasAnimationFolderData(fd)
    return fd ~= nil and fd.first ~= nil
end

local function countAnimationSetCoverage(animationSet)
    if not animationSet then return 0 end
    local covered = 0
    for _, k in ipairs(ANIM_KEYS) do
        if hasAnimationFolderData(animationSet[k]) then covered = covered + 1 end
    end
    return covered
end

local function getLocalRigType(localPlayer)
    local character = localPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    return humanoid and humanoid.RigType or Enum.HumanoidRigType.R15
end

local function hardResetAnimator(humanoid)
    if not humanoid then return end
    local tracks = humanoid:GetPlayingAnimationTracks()
    for _, track in ipairs(tracks) do track:Stop(0) end
end

local function flushAnimationState(character)
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    local tracks = humanoid:GetPlayingAnimationTracks()
    for _, track in ipairs(tracks) do track:Stop(0) end
end

local function refreshAnimate(character)
    local animate = character and character:FindFirstChild("Animate")
    if animate and animate:IsA("LocalScript") then
        animate.Disabled = true
        task.wait()
        animate.Disabled = false
    end

    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        local tracks = humanoid:GetPlayingAnimationTracks()
        for _, track in ipairs(tracks) do track:Stop(0) end
        humanoid:ChangeState(Enum.HumanoidStateType.Running)
    end
end

local function forceAnimationKick(character)
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    humanoid:Move(Vector3.new(0, 0, 0), true)
    humanoid:ChangeState(Enum.HumanoidStateType.RunningNoPhysics)
    task.wait()
    humanoid:ChangeState(Enum.HumanoidStateType.Running)

    task.defer(function()
        if not character.Parent then return end
        local playingTracks = humanoid:GetPlayingAnimationTracks()
        if #playingTracks > 0 then return end
        humanoid:ChangeState(Enum.HumanoidStateType.RunningNoPhysics)
        task.wait()
        humanoid:ChangeState(Enum.HumanoidStateType.Running)
    end)
end

local function scrubTracksForDuration(character, seconds)
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    local tracksStart = humanoid:GetPlayingAnimationTracks()
    for _, track in ipairs(tracksStart) do track:Stop(0) end

    task.wait(seconds or 0.2)

    local tracksEnd = humanoid:GetPlayingAnimationTracks()
    for _, track in ipairs(tracksEnd) do track:Stop(0) end
end

local function hasAnyPlayingTrack(humanoid)
    if not humanoid then return false end
    local tracks = humanoid:GetPlayingAnimationTracks()
    return #tracks > 0
end

local function isActionPriority(priority)
    return priority == Enum.AnimationPriority.Action
        or priority == Enum.AnimationPriority.Action2
        or priority == Enum.AnimationPriority.Action3
        or priority == Enum.AnimationPriority.Action4
end

local function hashAnimationSet(animationSet)
    if not animationSet then return "none" end

    local parts = {}
    for _, key in ipairs(ANIM_KEYS) do
        local folderData = animationSet[key]
        if folderData then
            parts[#parts + 1] = key
            parts[#parts + 1] = ":"
            if folderData.byName then
                local names = {}
                for n in pairs(folderData.byName) do names[#names + 1] = tostring(n) end
                table.sort(names)
                for i = 1, #names do
                    local name = names[i]
                    parts[#parts + 1] = name
                    parts[#parts + 1] = "="
                    parts[#parts + 1] = tostring(folderData.byName[name] or "")
                    parts[#parts + 1] = ";"
                end
            end
            if folderData.ordered then
                parts[#parts + 1] = "|o="
                for i = 1, #folderData.ordered do
                    parts[#parts + 1] = tostring(folderData.ordered[i] or "")
                    parts[#parts + 1] = ","
                end
            end
            parts[#parts + 1] = "#"
        end
    end

    return table.concat(parts, "")
end

function AnimationMimic.new(deps)
    local self = setmetatable({}, AnimationMimic)

    self.shared = deps.shared
    self.localPlayer = deps.localPlayer
    self.onAfterApply = deps.onAfterApply

    self.active = true
    self.connections = {}
    self.originalByCharacter = {}
    self.directControllerByChar = {}
    self.posePrimerByChar = {}
    self.recoveryWatcherByChar = {}
    self.replicateStateByChar = {}

    self.lastTargetInput = nil
    self.pinnedTargetUserId = nil
    self.lastSourceUserId = nil
    self.applyToken = 0

    self.settings = {
        useFallbackWhenMissing = true,
        useDirectTrackFallback = true,
        cacheTtlSeconds = 22,
        minLiveCoverage = 1,
        replicateDescriptionToOthers = true,
        invalidateAnimationCacheOnTargetSwitch = false,
        alwaysAssistAfterApply = false,
        adaptiveAssistAfterApply = true,
        assistGraceSeconds = 0.18,
        directControllerStep = 0.03,
        assistControllerStep = 0.05,
        recoveryWatcherStep = 0.12,
        recoveryNoTrackGrace = 0.22,
        replicateMinIntervalSeconds = 0.45,
        forceReplicateOnTargetSwitch = true,
        forceReplicateOnRestore = true,
    }

    self.fallbackNumericIds = {
        climb = self.shared:numericIdFromContentId(R15_FALLBACK_ANIMATIONS.climb),
        fall = self.shared:numericIdFromContentId(R15_FALLBACK_ANIMATIONS.fall),
        jump = self.shared:numericIdFromContentId(R15_FALLBACK_ANIMATIONS.jump),
        run = self.shared:numericIdFromContentId(R15_FALLBACK_ANIMATIONS.run),
        walk = self.shared:numericIdFromContentId(R15_FALLBACK_ANIMATIONS.walk),
        swim = self.shared:numericIdFromContentId(R15_FALLBACK_ANIMATIONS.swim),
        idle1 = self.shared:numericIdFromContentId(R15_FALLBACK_ANIMATIONS.idle1),
    }

    return self
end

function AnimationMimic:getGuaranteedFallbackSet()
    return {
        climb = self:makeSingleAnimationData("ClimbAnim", R15_FALLBACK_ANIMATIONS.climb),
        fall = self:makeSingleAnimationData("FallAnim", R15_FALLBACK_ANIMATIONS.fall),
        jump = self:makeSingleAnimationData("JumpAnim", R15_FALLBACK_ANIMATIONS.jump),
        run = self:makeSingleAnimationData("RunAnim", R15_FALLBACK_ANIMATIONS.run),
        walk = self:makeSingleAnimationData("WalkAnim", R15_FALLBACK_ANIMATIONS.walk),
        swim = self:makeSingleAnimationData("Swim", R15_FALLBACK_ANIMATIONS.swim),
        idle = {
            byName = {
                Animation1 = self.shared:normalizeAnimationId(R15_FALLBACK_ANIMATIONS.idle1),
                Animation2 = self.shared:normalizeAnimationId(R15_FALLBACK_ANIMATIONS.idle2),
            },
            ordered = {
                self.shared:normalizeAnimationId(R15_FALLBACK_ANIMATIONS.idle1),
                self.shared:normalizeAnimationId(R15_FALLBACK_ANIMATIONS.idle2),
            },
            first = self.shared:normalizeAnimationId(R15_FALLBACK_ANIMATIONS.idle1),
        },
    }
end

function AnimationMimic:hasNativePlayingTrack(character)
    if not character then return false end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end

    local ignored = {}
    local controller = self.directControllerByChar[character]
    if controller and controller.tracks then
        for _, t in pairs(controller.tracks) do
            ignored[t] = true
        end
    end

    local primer = self.posePrimerByChar[character]
    if primer and primer.track then
        ignored[primer.track] = true
    end

    for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
        if track.IsPlaying and not ignored[track] then
            return true
        end
    end

    return false
end

function AnimationMimic:hasNativeLocomotionTrack(character)
    if not character then return false end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end

    local ignored = {}
    local controller = self.directControllerByChar[character]
    if controller and controller.tracks then
        for _, t in pairs(controller.tracks) do
            ignored[t] = true
        end
    end

    local primer = self.posePrimerByChar[character]
    if primer and primer.track then
        ignored[primer.track] = true
    end

    for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
        if track.IsPlaying and not ignored[track] and not isActionPriority(track.Priority) then
            return true
        end
    end

    return false
end

function AnimationMimic:stopRecoveryWatcher(character)
    if not character then return end
    local watcher = self.recoveryWatcherByChar[character]
    if not watcher then return end
    if watcher.connection and watcher.connection.Connected then
        watcher.connection:Disconnect()
    end
    self.recoveryWatcherByChar[character] = nil
end

function AnimationMimic:stopAllRecoveryWatchers()
    local chars = {}
    for c in pairs(self.recoveryWatcherByChar) do chars[#chars + 1] = c end
    for _, c in ipairs(chars) do self:stopRecoveryWatcher(c) end
end

function AnimationMimic:startRecoveryWatcher(character, animationSet)
    if not character then return end
    if not self.settings.useDirectTrackFallback then return end

    self:stopRecoveryWatcher(character)

    local watcher = {
        connection = nil,
        nextCheckAt = 0,
        noTrackSince = nil,
        set = animationSet,
    }

    self.recoveryWatcherByChar[character] = watcher

    watcher.connection = RunService.Heartbeat:Connect(function()
        if not self.active or not character.Parent then
            self:stopRecoveryWatcher(character)
            return
        end

        local now = os.clock()
        if now < watcher.nextCheckAt then return end
        watcher.nextCheckAt = now + (self.settings.recoveryWatcherStep or 0.12)

        if self.directControllerByChar[character] then
            watcher.noTrackSince = nil
            return
        end

        if self:hasNativeLocomotionTrack(character) then
            watcher.noTrackSince = nil
            self:stopPosePrimer(character)
            return
        end

        if not watcher.noTrackSince then
            watcher.noTrackSince = now
            return
        end

        if now - watcher.noTrackSince < (self.settings.recoveryNoTrackGrace or 0.22) then
            return
        end

        watcher.noTrackSince = nil

        local sourceSet = watcher.set or self:getGuaranteedFallbackSet()
        self:ensureIdlePrimer(character, sourceSet)

        local started = self:ensureAssistController(character, sourceSet)
        if not started then
            self:ensureAssistController(character, self:getGuaranteedFallbackSet())
        end
    end)
end

function AnimationMimic:ensureAssistController(character, animationSet)
    if not self.settings.useDirectTrackFallback then return false end
    local existing = self.directControllerByChar[character]
    if existing and existing.assistMode then
        return true
    end
    return self:startDirectController(character, animationSet, { assistMode = true })
end

function AnimationMimic:stopPosePrimer(character)
    if not character then return end
    local rec = self.posePrimerByChar[character]
    if not rec then return end
    rec.active = false
    if rec.track then
        pcall(function() rec.track:Stop(0.08) end)
        pcall(function() rec.track:Destroy() end)
    end
    if rec.anim then
        pcall(function() rec.anim:Destroy() end)
    end
    self.posePrimerByChar[character] = nil
end

function AnimationMimic:stopAllPosePrimers()
    local chars = {}
    for c in pairs(self.posePrimerByChar) do chars[#chars + 1] = c end
    for _, c in ipairs(chars) do self:stopPosePrimer(c) end
end

function AnimationMimic:ensureIdlePrimer(character, animationSet)
    if not character or not character.Parent then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    if hasAnyPlayingTrack(humanoid) then return end

    local idleId = self:resolveIdFromFolderDataWithFallback(
        animationSet and animationSet.idle,
        "Animation1",
        1,
        R15_FALLBACK_ANIMATIONS.idle1
    )
    if not idleId then return end

    local existing = self.posePrimerByChar[character]
    if existing and existing.active then return end

    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        local okNew, newAnimator = pcall(function() return Instance.new("Animator") end)
        if okNew and newAnimator then
            newAnimator.Parent = humanoid
            animator = newAnimator
        end
    end
    if not animator then return end

    local anim = Instance.new("Animation")
    anim.Name = "Mimic_IdlePrimer"
    anim.AnimationId = idleId

    local okTrack, track = pcall(function() return animator:LoadAnimation(anim) end)
    if not okTrack or not track then
        anim:Destroy()
        return
    end

    track.Priority = Enum.AnimationPriority.Idle
    track.Looped = true

    local primer = { active = true, anim = anim, track = track }
    self.posePrimerByChar[character] = primer

    pcall(function() track:Play(0.08, 1, 1) end)

    task.defer(function()
        local deadline = os.clock() + 1.8
        while primer.active and self.active and character.Parent and os.clock() < deadline do
            task.wait(0.06)

            local tracks = humanoid:GetPlayingAnimationTracks()
            local hasOtherTrack = false
            for _, t in ipairs(tracks) do
                if t ~= track and t.IsPlaying then
                    hasOtherTrack = true
                    break
                end
            end

            if hasOtherTrack then
                break
            end
        end

        if primer.active then
            self:stopPosePrimer(character)
        end
    end)
end

function AnimationMimic:unstickPoseAfterApply(character, animationSet)
    if not character or not character.Parent then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    forceAnimationKick(character)

    task.defer(function()
        task.wait(0.07)
        if not self.active or not character.Parent then return end

        if hasAnyPlayingTrack(humanoid) then
            self:stopPosePrimer(character)
            return
        end

        self:ensureIdlePrimer(character, animationSet)

        task.wait(0.22)
        if not self.active or not character.Parent then return end
        if self:hasNativePlayingTrack(character) then
            self:stopPosePrimer(character)
            return
        end

        refreshAnimate(character)
        forceAnimationKick(character)
        self:ensureIdlePrimer(character, animationSet)

        task.wait(0.30)
        if not self.active or not character.Parent then return end
        if self:hasNativePlayingTrack(character) then
            self:stopPosePrimer(character)
            return
        end

        if self.directControllerByChar[character] then
            return
        end

        local started = self:startDirectController(character, animationSet, { assistMode = true })
        if not started then
            self:startDirectController(character, self:getGuaranteedFallbackSet(), { assistMode = true })
        end
    end)
end

function AnimationMimic:scheduleAssistIfNeeded(character, animationSet)
    if not character or not character.Parent then return end
    if not self.settings.useDirectTrackFallback then return end

    local token = self.applyToken
    local grace = self.settings.assistGraceSeconds or 0.18

    task.defer(function()
        task.wait(grace)

        if not self.active then return end
        if token ~= self.applyToken then return end
        if not character.Parent then return end

        if self:hasNativePlayingTrack(character) then
            self:stopPosePrimer(character)
            return
        end

        if self.directControllerByChar[character] then
            return
        end

        local started = self:ensureAssistController(character, animationSet)
        if not started then
            self:ensureAssistController(character, self:getGuaranteedFallbackSet())
        end
    end)
end

function AnimationMimic:rememberOriginal(character, animationObject)
    if not character or not animationObject then return end
    if not self.originalByCharacter[character] then
        self.originalByCharacter[character] = {}
    end
    if self.originalByCharacter[character][animationObject] == nil then
        self.originalByCharacter[character][animationObject] = animationObject.AnimationId
    end
end

function AnimationMimic:resetCharacterAnimations(character)
    local saved = self.originalByCharacter[character]
    if not saved then return false end
    for animationObject, originalId in pairs(saved) do
        if animationObject and animationObject.Parent then
            animationObject.AnimationId = originalId
        end
    end
    self.originalByCharacter[character] = nil
    return true
end

function AnimationMimic:extractFolderAnimationData(animate, folderName)
    local folder = animate and animate:FindFirstChild(folderName)
    if not folder then return nil end

    local data = { byName = {}, ordered = {}, first = nil }
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("Animation") then
            local id = self.shared:normalizeAnimationId(child.AnimationId)
            if id then
                if not data.first then data.first = id end
                data.byName[child.Name] = id
                data.ordered[#data.ordered + 1] = id
            end
        end
    end

    return data
end

function AnimationMimic:buildAnimationSetFromAnimate(animate)
    if not animate then return nil end
    return {
        climb = self:extractFolderAnimationData(animate, "climb"),
        fall = self:extractFolderAnimationData(animate, "fall"),
        jump = self:extractFolderAnimationData(animate, "jump"),
        run = self:extractFolderAnimationData(animate, "run"),
        walk = self:extractFolderAnimationData(animate, "walk"),
        swim = self:extractFolderAnimationData(animate, "swim"),
        idle = self:extractFolderAnimationData(animate, "idle"),
    }
end

function AnimationMimic:resolveIdFromFolderData(folderData, childName, index)
    local chosen
    if folderData then
        chosen = folderData.byName[childName] or folderData.ordered[index] or folderData.first
    end
    return self.shared:normalizeAnimationId(chosen)
end

function AnimationMimic:resolveIdFromFolderDataWithFallback(folderData, childName, index, fallbackId)
    if self.settings.useFallbackWhenMissing then
        return self:resolveIdFromFolderData(folderData, childName, index) or self.shared:normalizeAnimationId(fallbackId)
    end
    return self:resolveIdFromFolderData(folderData, childName, index)
end

function AnimationMimic:makeSingleAnimationData(name, rawId)
    local cleaned = self.shared:normalizeAnimationId(rawId)
    if not cleaned then return nil end
    return { byName = { [name] = cleaned }, ordered = { cleaned }, first = cleaned }
end

function AnimationMimic:makeIdleAnimationData(rawIdleId)
    local cleaned = self.shared:normalizeAnimationId(rawIdleId)
    if not cleaned then return nil end
    return {
        byName = { Animation1 = cleaned, Animation2 = cleaned },
        ordered = { cleaned, cleaned },
        first = cleaned,
    }
end

function AnimationMimic:getCachedAnimationSet(userId)
    local entry = self.shared:cacheGetEntry(self.shared.animationSetCache, userId, self.settings.cacheTtlSeconds)
    if not entry then return nil end
    return entry.set
end

function AnimationMimic:setCachedAnimationSet(userId, set)
    if not userId or not set then return end
    self.shared:cacheSetEntry(
        self.shared.animationSetCache,
        userId,
        { set = set, timestamp = os.clock() },
        self.shared:getCacheMaxEntries("animationSet")
    )
end

function AnimationMimic:getAnimationSetFromLivePlayer(userId)
    local ok, player = pcall(function() return Players:GetPlayerByUserId(userId) end)
    if not ok or not player then return nil end

    local character = player.Character
    if not character then return nil end

    local animate = character:FindFirstChild("Animate")
    if not animate then return nil end

    local set = self:buildAnimationSetFromAnimate(animate)
    return (countAnimationSetCoverage(set) > 0) and set or nil
end

function AnimationMimic:getAnimationSetFromDescription(userId)
    local desc = self.shared:getTargetDescriptionCached(userId)
    if not desc then return nil end

    return {
        climb = self:makeSingleAnimationData("ClimbAnim", desc.ClimbAnimation),
        fall = self:makeSingleAnimationData("FallAnim", desc.FallAnimation),
        jump = self:makeSingleAnimationData("JumpAnim", desc.JumpAnimation),
        run = self:makeSingleAnimationData("RunAnim", desc.RunAnimation),
        walk = self:makeSingleAnimationData("WalkAnim", desc.WalkAnimation),
        swim = self:makeSingleAnimationData("Swim", desc.SwimAnimation),
        idle = self:makeIdleAnimationData(desc.IdleAnimation),
    }
end

function AnimationMimic:getAnimationSetFromTempRig(userId)
    local rigType = getLocalRigType(self.localPlayer)
    local ok, rig = pcall(function() return Players:CreateHumanoidModelFromUserId(userId, rigType) end)
    if not ok or not rig then return nil end

    rig.Name = "AnimationMimicTempRig"
    local animate = rig:FindFirstChild("Animate") or rig:WaitForChild("Animate", 5)
    if not animate then
        rig:Destroy()
        return nil
    end

    local set = self:buildAnimationSetFromAnimate(animate)
    rig:Destroy()
    return set
end

function AnimationMimic:getAnimationSetFromUserId(userId)
    local cached = self:getCachedAnimationSet(userId)
    if cached then return cached end

    local fromLive = self:getAnimationSetFromLivePlayer(userId)
    local liveCoverage = countAnimationSetCoverage(fromLive)
    if liveCoverage >= (self.settings.minLiveCoverage or 1) and liveCoverage > 0 then
        self:setCachedAnimationSet(userId, fromLive)
        return fromLive
    end

    local fromDesc = self:getAnimationSetFromDescription(userId)
    local fromRig = self:getAnimationSetFromTempRig(userId)

    local function pickBetter(currentBest, candidate)
        if not candidate then return currentBest end
        local coverage = countAnimationSetCoverage(candidate.set)
        if coverage <= 0 then return currentBest end
        if not currentBest then
            return { set = candidate.set, coverage = coverage, priority = candidate.priority }
        end
        if coverage > currentBest.coverage then
            return { set = candidate.set, coverage = coverage, priority = candidate.priority }
        end
        if coverage == currentBest.coverage and candidate.priority > currentBest.priority then
            return { set = candidate.set, coverage = coverage, priority = candidate.priority }
        end
        return currentBest
    end

    local best = nil
    best = pickBetter(best, { set = fromLive, priority = 3 })
    best = pickBetter(best, { set = fromRig, priority = 2 })
    best = pickBetter(best, { set = fromDesc, priority = 1 })

    if not best or not best.set then return nil end

    self:setCachedAnimationSet(userId, best.set)
    return best.set
end

function AnimationMimic:getAnimationSetFromUserIdWithRetry(userId, attempts)
    attempts = attempts or 2
    for i = 1, attempts do
        local set = self:getAnimationSetFromUserId(userId)
        if set then return set end
        if i < attempts then task.wait(0.12) end
    end
    return nil
end

function AnimationMimic:applyAnimationSetToDescriptionFields(desc, animationSet)
    if not desc or not animationSet then return false end

    local function resolveNumeric(folder, childName, idx, fallback)
        return self.shared:numericIdFromContentId(
            self:resolveIdFromFolderDataWithFallback(animationSet[folder], childName, idx, fallback)
        )
    end

    desc.ClimbAnimation = resolveNumeric("climb", "ClimbAnim", 1, R15_FALLBACK_ANIMATIONS.climb) or self.fallbackNumericIds.climb
    desc.FallAnimation = resolveNumeric("fall", "FallAnim", 1, R15_FALLBACK_ANIMATIONS.fall) or self.fallbackNumericIds.fall
    desc.JumpAnimation = resolveNumeric("jump", "JumpAnim", 1, R15_FALLBACK_ANIMATIONS.jump) or self.fallbackNumericIds.jump
    desc.RunAnimation = resolveNumeric("run", "RunAnim", 1, R15_FALLBACK_ANIMATIONS.run) or self.fallbackNumericIds.run
    desc.WalkAnimation = resolveNumeric("walk", "WalkAnim", 1, R15_FALLBACK_ANIMATIONS.walk) or self.fallbackNumericIds.walk
    desc.SwimAnimation = resolveNumeric("swim", "Swim", 1, R15_FALLBACK_ANIMATIONS.swim) or self.fallbackNumericIds.swim
    desc.IdleAnimation = resolveNumeric("idle", "Animation1", 1, R15_FALLBACK_ANIMATIONS.idle1) or self.fallbackNumericIds.idle1

    return true
end

function AnimationMimic:replicateAnimationStateForOthers(character, animationSet)
    if not self.settings.replicateDescriptionToOthers then return true end

    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end

    local force = self._forceReplicateThisApply == true
    local signature = hashAnimationSet(animationSet)
    local now = os.clock()
    local replicateState = self.replicateStateByChar[character]
    if not force and replicateState and replicateState.signature == signature then
        local dt = now - (replicateState.timestamp or 0)
        if dt < (self.settings.replicateMinIntervalSeconds or 0.45) then
            return true
        end
    end

    local liveColorSnapshot = self.shared:snapshotCharacterColors(character)
    local scales = self.shared:getCurrentScaleValues(humanoid)

    local ok, currentDesc = pcall(function() return humanoid:GetAppliedDescription() end)
    if not ok or not currentDesc then
        self.shared:destroyColorSnapshot(liveColorSnapshot)
        return false
    end

    if scales then
        self.shared:applyScaleValuesToDescription(currentDesc, scales)
    end

    if not self:applyAnimationSetToDescriptionFields(currentDesc, animationSet) then
        self.shared:destroyColorSnapshot(liveColorSnapshot)
        return false
    end

    if humanoid.ApplyDescriptionClientServer then
        local okCS = pcall(function() humanoid:ApplyDescriptionClientServer(currentDesc) end)
        if okCS then
            self.replicateStateByChar[character] = {
                signature = signature,
                timestamp = now,
            }
            self.shared:restoreCharacterColors(character, liveColorSnapshot)
            task.defer(function()
                task.wait(0.08)
                self.shared:restoreCharacterColors(character, liveColorSnapshot)
                self.shared:destroyColorSnapshot(liveColorSnapshot)
            end)
            return true
        end
    end

    self.shared:destroyColorSnapshot(liveColorSnapshot)
    return false
end

function AnimationMimic:applyAnimationSetViaDescription(humanoid, animationSet)
    if not humanoid or not animationSet then return false end

    local ok, currentDesc = pcall(function() return humanoid:GetAppliedDescription() end)
    if not ok or not currentDesc then return false end

    if not self:applyAnimationSetToDescriptionFields(currentDesc, animationSet) then return false end

    if humanoid.ApplyDescriptionClientServer then
        local okCS = pcall(function() humanoid:ApplyDescriptionClientServer(currentDesc) end)
        if okCS then return true, true end
    end

    return pcall(function() humanoid:ApplyDescription(currentDesc) end), false
end

function AnimationMimic:stopDirectController(character)
    if not character then return end

    local controller = self.directControllerByChar[character]
    if not controller then return end

    if controller.connection and controller.connection.Connected then
        controller.connection:Disconnect()
    end

    if controller.tracks then
        for _, track in pairs(controller.tracks) do
            pcall(function() track:Stop(0.08) end)
        end
    end

    if controller.animations then
        for _, animation in pairs(controller.animations) do
            pcall(function() animation:Destroy() end)
        end
    end

    self.directControllerByChar[character] = nil
end

function AnimationMimic:stopAllDirectControllers()
    local chars = {}
    for c in pairs(self.directControllerByChar) do chars[#chars + 1] = c end
    for _, c in ipairs(chars) do self:stopDirectController(c) end
    self.directControllerByChar = {}
end

function AnimationMimic:pruneStaleCharacterAnimationState(currentCharacter)
    for character in pairs(self.originalByCharacter) do
        if character ~= currentCharacter and (not character.Parent or character ~= self.localPlayer.Character) then
            self:resetCharacterAnimations(character)
            self.originalByCharacter[character] = nil
        end
    end

    for character in pairs(self.directControllerByChar) do
        if character ~= currentCharacter and (not character.Parent or character ~= self.localPlayer.Character) then
            self:stopDirectController(character)
        end
    end

    for character in pairs(self.posePrimerByChar) do
        if character ~= currentCharacter and (not character.Parent or character ~= self.localPlayer.Character) then
            self:stopPosePrimer(character)
        end
    end

    for character in pairs(self.recoveryWatcherByChar) do
        if character ~= currentCharacter and (not character.Parent or character ~= self.localPlayer.Character) then
            self:stopRecoveryWatcher(character)
        end
    end
end

function AnimationMimic:startDirectController(character, animationSet, opts)
    opts = opts or {}
    local assistMode = opts.assistMode == true

    if not self.settings.useDirectTrackFallback then return false end

    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or not animationSet then return false end

    self:stopDirectController(character)
    self:stopPosePrimer(character)

    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        local ok, a = pcall(function() return Instance.new("Animator") end)
        if ok and a then a.Parent = humanoid; animator = a end
    end
    if not animator then return false end

    local function getAnimId(folder, childName, idx, fb)
        return self:resolveIdFromFolderDataWithFallback(animationSet[folder], childName, idx, fb)
    end

    local idMap = {
        idle = getAnimId("idle", "Animation1", 1, R15_FALLBACK_ANIMATIONS.idle1),
        run = getAnimId("run", "RunAnim", 1, R15_FALLBACK_ANIMATIONS.run),
        walk = getAnimId("walk", "WalkAnim", 1, R15_FALLBACK_ANIMATIONS.walk),
        jump = getAnimId("jump", "JumpAnim", 1, R15_FALLBACK_ANIMATIONS.jump),
        fall = getAnimId("fall", "FallAnim", 1, R15_FALLBACK_ANIMATIONS.fall),
        climb = getAnimId("climb", "ClimbAnim", 1, R15_FALLBACK_ANIMATIONS.climb),
        swim = getAnimId("swim", "Swim", 1, R15_FALLBACK_ANIMATIONS.swim),
    }

    local tracks, animations = {}, {}
    local createdAny = false
    for stateName, animId in pairs(idMap) do
        if animId then
            local animation = Instance.new("Animation")
            animation.Name = "Mimic_" .. stateName
            animation.AnimationId = animId
            animations[stateName] = animation

            local okT, track = pcall(function() return animator:LoadAnimation(animation) end)
            if okT and track then
                track.Priority = (stateName == "idle") and Enum.AnimationPriority.Idle or Enum.AnimationPriority.Movement
                track.Looped = (stateName ~= "jump" and stateName ~= "fall")
                tracks[stateName] = track
                createdAny = true
            end
        end
    end

    if not createdAny then
        for _, a in pairs(animations) do pcall(function() a:Destroy() end) end
        return false
    end

    local ownTrackSet = {}
    for _, t in pairs(tracks) do ownTrackSet[t] = true end

    local controller = {
        tracks = tracks,
        trackSet = ownTrackSet,
        animations = animations,
        connection = nil,
        active = nil,
        nextUpdateAt = 0,
        assistMode = assistMode,
    }
    self.directControllerByChar[character] = controller

    local function playState(nextState)
        if controller.active == nextState then
            local t = controller.tracks[nextState]
            if t and not t.IsPlaying then pcall(function() t:Play(0.08, 1, 1) end) end
            return
        end

        controller.active = nextState
        for name, track in pairs(controller.tracks) do
            if name == nextState then
                pcall(function() if not track.IsPlaying then track:Play(0.08, 1, 1) end end)
            else
                pcall(function() if track.IsPlaying then track:Stop(0.08) end end)
            end
        end
    end

    controller.connection = RunService.Heartbeat:Connect(function()
        if not self.active or not character.Parent then
            self:stopDirectController(character)
            return
        end

        if controller.assistMode then
            if self:hasNativeLocomotionTrack(character) then
                controller.active = nil
                for _, track in pairs(controller.tracks) do
                    pcall(function() if track.IsPlaying then track:Stop(0.08) end end)
                end
                return
            end
        end

        local now = os.clock()
        if now < controller.nextUpdateAt then return end
        local step = controller.assistMode and (self.settings.assistControllerStep or 0.05)
            or (self.settings.directControllerStep or 0.03)
        controller.nextUpdateAt = now + step

        local moveMag = humanoid.MoveDirection.Magnitude
        local humState = humanoid:GetState()

        if humState == Enum.HumanoidStateType.Freefall then
            if tracks.fall then playState("fall") elseif tracks.jump then playState("jump") end
            return
        end
        if humState == Enum.HumanoidStateType.Jumping and tracks.jump then playState("jump"); return end
        if humState == Enum.HumanoidStateType.Climbing and tracks.climb then playState("climb"); return end
        if humState == Enum.HumanoidStateType.Swimming and tracks.swim then playState("swim"); return end

        if moveMag > 0.08 then
            if tracks.run then playState("run") elseif tracks.walk then playState("walk") end
            return
        end

        if tracks.idle then playState("idle") end
    end)

    return true
end

function AnimationMimic:applyFolderDataToFolder(character, folder, folderData, shouldRemember)
    if not folder then return 0 end

    local changed = 0
    local idx = 0
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("Animation") then
            idx = idx + 1
            local resolvedId = self:resolveIdFromFolderData(folderData, child.Name, idx)
            if resolvedId then
                if shouldRemember then self:rememberOriginal(character, child) end
                child.AnimationId = resolvedId
                changed = changed + 1
            end
        end
    end

    return changed
end

function AnimationMimic:applySlotFromSet(character, animate, animationSet, folderName, fallbackId, shouldRemember)
    local folder = animate:FindFirstChild(folderName)
    local setData = animationSet and animationSet[folderName]

    if self:applyFolderDataToFolder(character, folder, setData, shouldRemember) > 0 then
        return true
    end

    local firstAnim = getFirstAnimationInFolder(folder)
    if not firstAnim or not self.settings.useFallbackWhenMissing then return false end

    local fallback = self.shared:normalizeAnimationId(fallbackId)
    if not fallback then return false end

    if shouldRemember then self:rememberOriginal(character, firstAnim) end
    firstAnim.AnimationId = fallback
    return true
end

function AnimationMimic:applyIdleFromSet(character, animate, idleData, shouldRemember)
    local idleFolder = animate:FindFirstChild("idle")
    if not idleFolder then return false end

    local applied = 0
    local idx = 0
    for _, child in ipairs(idleFolder:GetChildren()) do
        if child:IsA("Animation") then
            idx = idx + 1
            local fallback = nil
            if self.settings.useFallbackWhenMissing then
                fallback = (child.Name == "Animation2") and R15_FALLBACK_ANIMATIONS.idle2 or R15_FALLBACK_ANIMATIONS.idle1
            end
            local resolvedIdle = self:resolveIdFromFolderDataWithFallback(idleData, child.Name, idx, fallback)
            if resolvedIdle then
                if shouldRemember then self:rememberOriginal(character, child) end
                child.AnimationId = resolvedIdle
                applied = applied + 1
            end
        end
    end

    return applied > 0
end

function AnimationMimic:applyAnimationSetToCharacter(character, animationSet)
    if not character or not animationSet then return false end

    local animate = character:FindFirstChild("Animate")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end

    hardResetAnimator(humanoid)

    local applied = 0
    local usedDescriptionPath = false
    local descReplicatedNetwork = false
    if animate then
        for _, spec in ipairs(SLOT_SPECS) do
            if self:applySlotFromSet(character, animate, animationSet, spec.folder, spec.fallback, true) then
                applied = applied + 1
            end
        end
        if self:applyIdleFromSet(character, animate, animationSet.idle, true) then
            applied = applied + 1
        end
    end

    if applied > 0 then
        self:stopDirectController(character)
        self:stopPosePrimer(character)
        refreshAnimate(character)
    else
        local descApplied, replicatedNetwork = self:applyAnimationSetViaDescription(humanoid, animationSet)
        usedDescriptionPath = true
        descReplicatedNetwork = replicatedNetwork == true
        if descApplied then
            self:stopDirectController(character)
            self:stopPosePrimer(character)
        else
            if not self:startDirectController(character, animationSet) then return false end
        end
    end

    if self.settings.alwaysAssistAfterApply then
        local startedAssist = self:ensureAssistController(character, animationSet)
        if not startedAssist then
            self:ensureAssistController(character, self:getGuaranteedFallbackSet())
        end
    elseif self.settings.adaptiveAssistAfterApply then
        self:scheduleAssistIfNeeded(character, animationSet)
    end

    self:unstickPoseAfterApply(character, animationSet)
    if usedDescriptionPath and descReplicatedNetwork then
        self.replicateStateByChar[character] = {
            signature = hashAnimationSet(animationSet),
            timestamp = os.clock(),
        }
    else
        self:replicateAnimationStateForOthers(character, animationSet)
    end
    self:startRecoveryWatcher(character, animationSet)

    if type(self.onAfterApply) == "function" then
        task.defer(function()
            pcall(self.onAfterApply)
        end)
    end

    return true
end

function AnimationMimic:restoreOwnAnimationsHard(character)
    if not character then return false end

    local ownSet = self:getAnimationSetFromUserId(self.localPlayer.UserId)
    if not ownSet then return false end

    local animate = character:FindFirstChild("Animate")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end

    hardResetAnimator(humanoid)

    local applied = 0
    local usedDescriptionPath = false
    local descReplicatedNetwork = false
    if animate then
        for _, spec in ipairs(SLOT_SPECS) do
            if self:applySlotFromSet(character, animate, ownSet, spec.folder, spec.fallback, false) then
                applied = applied + 1
            end
        end
        if self:applyIdleFromSet(character, animate, ownSet.idle, false) then
            applied = applied + 1
        end
    end

    if applied > 0 then
        self:stopDirectController(character)
        self:stopPosePrimer(character)
        refreshAnimate(character)
    else
        local descApplied, replicatedNetwork = self:applyAnimationSetViaDescription(humanoid, ownSet)
        usedDescriptionPath = true
        descReplicatedNetwork = replicatedNetwork == true
        if descApplied then
            self:stopDirectController(character)
            self:stopPosePrimer(character)
        else
            if not self.active then return false end
            if not self:startDirectController(character, ownSet) then return false end
        end
    end

    if self.settings.alwaysAssistAfterApply then
        local startedAssist = self:ensureAssistController(character, ownSet)
        if not startedAssist then
            self:ensureAssistController(character, self:getGuaranteedFallbackSet())
        end
    elseif self.settings.adaptiveAssistAfterApply then
        self:scheduleAssistIfNeeded(character, ownSet)
    end

    self:unstickPoseAfterApply(character, ownSet)
    self._forceReplicateThisApply = self.settings.forceReplicateOnRestore == true
    if usedDescriptionPath and descReplicatedNetwork then
        self.replicateStateByChar[character] = {
            signature = hashAnimationSet(ownSet),
            timestamp = os.clock(),
        }
    else
        self:replicateAnimationStateForOthers(character, ownSet)
    end
    self._forceReplicateThisApply = false
    self:startRecoveryWatcher(character, ownSet)

    return true
end

function AnimationMimic:mimicFromUserId(userId, forceApply)
    if not self.active then return false end

    forceApply = forceApply == true

    local numericUserId = tonumber(userId)
    if not numericUserId then return false end

    local character = self.localPlayer.Character
    if not character then return false end
    if not self.shared:isCharacterR15(character) then return false end

    self:pruneStaleCharacterAnimationState(character)

    if not forceApply and self.lastSourceUserId == numericUserId then
        return true
    end

    self.applyToken = self.applyToken + 1
    local applyToken = self.applyToken

    local targetAvatarType = self.shared:getUserAvatarType(numericUserId)
    if targetAvatarType == "R6" then
        self.lastSourceUserId = nil
        self:restoreOwnAnimationsHard(character)
        flushAnimationState(character)
        return false
    end

    local animationSet = self:getAnimationSetFromUserIdWithRetry(numericUserId, 3)
    if not animationSet then
        self.lastSourceUserId = nil
        return false
    end

    if applyToken ~= self.applyToken then return false end

    local switchedTarget = self.lastSourceUserId and self.lastSourceUserId ~= numericUserId
    if switchedTarget then
        self:restoreOwnAnimationsHard(character)
        flushAnimationState(character)
        scrubTracksForDuration(character, 0.18)
        if applyToken ~= self.applyToken then return false end
    end

    self.lastSourceUserId = numericUserId
    self.pinnedTargetUserId = numericUserId

    self._forceReplicateThisApply = switchedTarget and self.settings.forceReplicateOnTargetSwitch == true
    local ok = self:applyAnimationSetToCharacter(character, animationSet)
    self._forceReplicateThisApply = false
    if not ok then return false end

    task.defer(function()
        task.wait(0.2)
        if applyToken ~= self.applyToken then return end
        if not character.Parent then return end

        local hum = character:FindFirstChildOfClass("Humanoid")
        if not hum then return end

        if #hum:GetPlayingAnimationTracks() == 0 then
            self:restoreOwnAnimationsHard(character)
            self:applyAnimationSetToCharacter(character, animationSet)
        end
    end)

    return ok
end

function AnimationMimic:mimicFromTarget(target)
    if not self.active then return false end

    local userId = self.shared:resolveUserToId(target)
    if not userId then return false end

    self.lastTargetInput = target
    self.pinnedTargetUserId = userId

    if self.settings.invalidateAnimationCacheOnTargetSwitch then
        self.shared.animationSetCache[userId] = nil
    end

    return self:mimicFromUserId(userId, true)
end

function AnimationMimic:reapply()
    if self.pinnedTargetUserId then
        return self:mimicFromUserId(self.pinnedTargetUserId, true)
    end
    if self.lastSourceUserId then
        return self:mimicFromUserId(self.lastSourceUserId, true)
    end
    if self.lastTargetInput ~= nil then
        return self:mimicFromTarget(self.lastTargetInput)
    end
    return false
end

function AnimationMimic:onCharacterAdded(newCharacter)
    if not self.active then return end

    self.applyToken = self.applyToken + 1
    local respawnToken = self.applyToken

    self:pruneStaleCharacterAnimationState(newCharacter)

    local hum = newCharacter:WaitForChild("Humanoid", 10)
    if not hum or respawnToken ~= self.applyToken or not self.active then return end

    task.wait(0.15)
    if respawnToken ~= self.applyToken or not self.active or not newCharacter.Parent then return end

    task.spawn(function()
        local backoff = 0.25
        for _ = 1, 4 do
            if not self.active or respawnToken ~= self.applyToken or not newCharacter.Parent then return end
            if self.pinnedTargetUserId and self:mimicFromUserId(self.pinnedTargetUserId, true) then return end
            if self.lastSourceUserId and self:mimicFromUserId(self.lastSourceUserId, true) then return end
            if self.lastTargetInput ~= nil and self:mimicFromTarget(self.lastTargetInput) then return end
            task.wait(backoff)
            if not self.active or respawnToken ~= self.applyToken then return end
            backoff = math.min(backoff * 2, 2)
        end
    end)
end

function AnimationMimic:setEnabled(enabled)
    enabled = enabled == true
    if self.active == enabled then return end

    self.active = enabled
    self.applyToken = self.applyToken + 1

    if not enabled then
        self.lastSourceUserId = nil
        self.pinnedTargetUserId = nil
        self._forceReplicateThisApply = false
        self.replicateStateByChar = {}
        local character = self.localPlayer.Character
        self:stopAllDirectControllers()
        self:stopAllPosePrimers()
        self:stopAllRecoveryWatchers()
        self:resetCharacterAnimations(character)
        self.originalByCharacter = {}
        flushAnimationState(character)
    else
        local character = self.localPlayer.Character
        if character and character.Parent and self.lastSourceUserId then
            task.defer(function()
                if self.active then
                    self:mimicFromUserId(self.lastSourceUserId, true)
                end
            end)
        end
    end
end

function AnimationMimic:cleanup()
    self.active = false
    self.lastSourceUserId = nil
    self.pinnedTargetUserId = nil
    self.lastTargetInput = nil
    self.applyToken = self.applyToken + 1
    self._forceReplicateThisApply = false
    self.replicateStateByChar = {}

    local character = self.localPlayer.Character
    self:stopAllDirectControllers()
    self:stopAllPosePrimers()
    self:stopAllRecoveryWatchers()
    self:resetCharacterAnimations(character)
    self.originalByCharacter = {}

    flushAnimationState(character)
end

return AnimationMimic
