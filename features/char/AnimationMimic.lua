local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local InsertService = game:GetService("InsertService")

local AnimationMimic = {}
AnimationMimic.__index = AnimationMimic

local SLOT_SPECS = {
    { folder = "climb" },
    { folder = "fall" },
    { folder = "jump" },
    { folder = "run" },
    { folder = "walk" },
    { folder = "swim" },
}

local ANIM_KEYS = { "climb", "fall", "jump", "run", "walk", "swim", "idle" }
local ANIM_KEY_COUNT = #ANIM_KEYS

local SLOT_NAME_HINTS = {
    climb = { "climb" },
    fall = { "fall" },
    jump = { "jump" },
    run = { "run" },
    walk = { "walk" },
    swim = { "swim" },
    idle = { "idle", "animation1", "animation2" },
}

local SCALE_NAMES = {
    "BodyHeightScale", "BodyWidthScale", "BodyDepthScale",
    "HeadScale", "BodyTypeScale", "BodyProportionScale",
}

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

local function hardResetAnimator(humanoid)
    if not humanoid then return end
    local tracks = humanoid:GetPlayingAnimationTracks()
    for _, track in ipairs(tracks) do track:Stop(0.15) end
end

local function flushAnimationState(character)
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    hardResetAnimator(humanoid)
end

local function refreshAnimate(character)
    local animate = character and character:FindFirstChild("Animate")
    if animate and animate:IsA("LocalScript") then
        animate.Disabled = true
        task.wait(0.2)
        animate.Disabled = false
    end

    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        local tracks = humanoid:GetPlayingAnimationTracks()
        for _, track in ipairs(tracks) do track:Stop(0.15) end

        local currentState = humanoid:GetState()
        local desiredState = Enum.HumanoidStateType.Running
        if currentState == Enum.HumanoidStateType.Swimming then
            desiredState = Enum.HumanoidStateType.Swimming
        elseif currentState == Enum.HumanoidStateType.Climbing then
            desiredState = Enum.HumanoidStateType.Climbing
        elseif currentState == Enum.HumanoidStateType.Jumping or currentState == Enum.HumanoidStateType.Freefall then
            desiredState = Enum.HumanoidStateType.Freefall
        end

        humanoid:ChangeState(desiredState)
    end
end

local function forceAnimationKick(character)
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    local function hasTracksNow()
        return #humanoid:GetPlayingAnimationTracks() > 0
    end

    for i = 1, 2 do
        humanoid:Move(Vector3.new(0, 0, 0), true)
        humanoid:ChangeState(Enum.HumanoidStateType.RunningNoPhysics)
        task.wait(i == 1 and 0.03 or 0.06)

        if not character.Parent then return end
        humanoid:ChangeState(Enum.HumanoidStateType.Running)
        task.wait(0.03)

        if hasTracksNow() then return end
    end

    task.defer(function()
        if not character.Parent then return end
        if hasTracksNow() then return end
        humanoid:ChangeState(Enum.HumanoidStateType.RunningNoPhysics)
        task.wait(0.06)
        humanoid:ChangeState(Enum.HumanoidStateType.Running)
    end)
end

local function scrubTracksForDuration(character, seconds)
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    local deadline = os.clock() + (seconds or 0.2)

    local function stopAllTracks()
        local tracks = humanoid:GetPlayingAnimationTracks()
        for _, track in ipairs(tracks) do track:Stop(0) end
        return #tracks
    end

    local remaining = stopAllTracks()
    while remaining > 0 and os.clock() < deadline do
        task.wait(0.03)
        remaining = stopAllTracks()
    end
end

local function hasAnyPlayingTrack(humanoid)
    if not humanoid then return false end
    local tracks = humanoid:GetPlayingAnimationTracks()
    return #tracks > 0
end

-- Snapshot the humanoid's scale NumberValues directly (most accurate source)
local function snapshotHumanoidScales(humanoid)
    if not humanoid then return nil end
    local snapshot = {}
    for _, name in ipairs(SCALE_NAMES) do
        local nv = humanoid:FindFirstChild(name)
        snapshot[name] = nv and nv.Value or 1
    end
    return snapshot
end

-- Apply scale snapshot back into a HumanoidDescription before applying
local function applyScaleSnapshotToDesc(desc, snapshot)
    if not desc or not snapshot then return end
    desc.HeightScale     = snapshot.BodyHeightScale     or desc.HeightScale
    desc.WidthScale      = snapshot.BodyWidthScale      or desc.WidthScale
    desc.DepthScale      = snapshot.BodyDepthScale      or desc.DepthScale
    desc.HeadScale       = snapshot.HeadScale           or desc.HeadScale
    desc.BodyTypeScale   = snapshot.BodyTypeScale       or desc.BodyTypeScale
    desc.ProportionScale = snapshot.BodyProportionScale or desc.ProportionScale
end

function AnimationMimic.new(deps)
    local self = setmetatable({}, AnimationMimic)

    self.shared = deps.shared
    self.localPlayer = deps.localPlayer
    self.onAfterApply = deps.onAfterApply

    self.active = true
    self.originalByCharacter = {}
    self.directControllerByChar = {}
    self.posePrimerByChar = {}
    self.unstickSerialByChar = {}

    self.lastTargetInput = nil
    self.pinnedTargetUserId = nil
    self.lastSourceUserId = nil
    self.resumeUserId = nil
    self.applyToken = 0
    self.resolvedAnimationIdCache = {}
    self.pendingAnimationResolve = {}

    self.settings = {
        useDirectTrackFallback = true,
        cacheTtlSeconds = 22,
        minLiveCoverage = 7,
        liveSourceWaitSeconds = 1.5,
        replicateDescriptionToOthers = false,
        useDescriptionAnimationApply = false,
        useDescriptionSetFallback = false,
        replicationRetryDelays = { 0.15, 0.4 },
        invalidateAnimationCacheOnTargetSwitch = true,
        alwaysAssistAfterApply = false,
        adaptiveAssistAfterApply = false,
        assistGraceSeconds = 0.18,
        directControllerStep = 0.03,
        assistControllerStep = 0.05,
    }

    return self
end

function AnimationMimic:isDescriptionAnimationAssetIdValid(numericId)
    if not numericId or numericId <= 0 then return false end
    return true
end

function AnimationMimic:getSlotHints(slotName)
    return SLOT_NAME_HINTS[slotName] or { tostring(slotName or "") }
end

function AnimationMimic:findBestAnimationInAsset(assetModel, slotName)
    if not assetModel then return nil end

    local allAnimations = {}
    for _, inst in ipairs(assetModel:GetDescendants()) do
        if inst:IsA("Animation") then
            allAnimations[#allAnimations + 1] = inst
        end
    end

    if #allAnimations == 0 then return nil end

    local hints = self:getSlotHints(slotName)

    local function matchesHint(candidateName)
        local lower = string.lower(candidateName or "")
        for _, hint in ipairs(hints) do
            if hint ~= "" and lower:find(hint, 1, true) then
                return true
            end
        end
        return false
    end

    for _, anim in ipairs(allAnimations) do
        if matchesHint(anim.Name) then
            return anim
        end
    end

    for _, anim in ipairs(allAnimations) do
        local parentName = anim.Parent and anim.Parent.Name or ""
        if matchesHint(parentName) then
            return anim
        end
    end

    return allAnimations[1]
end

function AnimationMimic:resolvePlayableAnimationId(rawId, slotName)
    local cleaned = self.shared:normalizeAnimationId(rawId)
    if not cleaned then return nil end

    local numericId = self.shared:numericIdFromContentId(cleaned)
    if not numericId then return cleaned end
    local likelyPackageId = numericId >= 10000000000

    local cacheKey = tostring(numericId) .. "|" .. tostring(slotName or "")
    if self.resolvedAnimationIdCache[cacheKey] ~= nil then
        local cached = self.resolvedAnimationIdCache[cacheKey]
        return cached ~= false and cached or nil
    end

    if self.pendingAnimationResolve[cacheKey] then
        local started = os.clock()
        while self.pendingAnimationResolve[cacheKey] and os.clock() - started < 2 do
            task.wait(0.03)
        end
        local waited = self.resolvedAnimationIdCache[cacheKey]
        if waited ~= nil then
            return waited ~= false and waited or nil
        end
    end

    self.pendingAnimationResolve[cacheKey] = true

    local resolved = cleaned
    local okAsset, assetModel = pcall(function()
        return InsertService:LoadAsset(numericId)
    end)
    if okAsset and assetModel then
        local chosen = self:findBestAnimationInAsset(assetModel, slotName)
        if chosen and chosen.AnimationId and chosen.AnimationId ~= "" then
            resolved = self.shared:normalizeAnimationId(chosen.AnimationId) or cleaned
        elseif likelyPackageId then
            resolved = nil
        end
        pcall(function() assetModel:Destroy() end)
    elseif likelyPackageId then
        resolved = nil
    end

    self.resolvedAnimationIdCache[cacheKey] = resolved or false
    self.pendingAnimationResolve[cacheKey] = nil
    return resolved
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
    if rec.trackConn and rec.trackConn.Connected then
        rec.trackConn:Disconnect()
    end
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

function AnimationMimic:nextUnstickSerial(character)
    local serial = (self.unstickSerialByChar[character] or 0) + 1
    self.unstickSerialByChar[character] = serial
    return serial
end

function AnimationMimic:isUnstickStillCurrent(character, serial, applyToken)
    if not self.active then return false end
    if not character or not character.Parent then return false end
    if applyToken and applyToken ~= self.applyToken then return false end
    return self.unstickSerialByChar[character] == serial
end

function AnimationMimic:ensureIdlePrimer(character, animationSet)
    if not character or not character.Parent then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    if hasAnyPlayingTrack(humanoid) then return end

    local idleId = self:resolveIdFromFolderData(animationSet and animationSet.idle, "Animation1", 1, "idle")
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

    track.Priority = Enum.AnimationPriority.Core
    track.Looped = true

    local primer = { active = true, anim = anim, track = track, trackConn = nil }
    self.posePrimerByChar[character] = primer

    local okConn, conn = pcall(function()
        return humanoid.AnimationPlayed:Connect(function(playedTrack)
            if not primer.active then return end
            if playedTrack ~= track and playedTrack.IsPlaying then
                self:stopPosePrimer(character)
            end
        end)
    end)
    if okConn and conn then
        primer.trackConn = conn
    end

    pcall(function() track:Play(0.08, 1, 1) end)

    task.defer(function()
        local deadline = os.clock() + 1.8
        while primer.active and self.active and character.Parent and os.clock() < deadline do
            task.wait(0.03)

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

function AnimationMimic:unstickPoseAfterApply(character, animationSet, applyToken)
    if not character or not character.Parent then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    local serial = self:nextUnstickSerial(character)
    if not self:isUnstickStillCurrent(character, serial, applyToken) then return end

    forceAnimationKick(character)

    task.defer(function()
        task.wait(0.07)
        if not self:isUnstickStillCurrent(character, serial, applyToken) then return end

        if hasAnyPlayingTrack(humanoid) then
            self:stopPosePrimer(character)
            return
        end

        self:ensureIdlePrimer(character, animationSet)

        task.wait(0.22)
        if not self:isUnstickStillCurrent(character, serial, applyToken) then return end
        if self:hasNativePlayingTrack(character) then
            self:stopPosePrimer(character)
            return
        end

        refreshAnimate(character)
        forceAnimationKick(character)
        self:ensureIdlePrimer(character, animationSet)

        task.wait(0.30)
        if not self:isUnstickStillCurrent(character, serial, applyToken) then return end
        if self:hasNativePlayingTrack(character) then
            self:stopPosePrimer(character)
            return
        end

        if self.directControllerByChar[character] then
            return
        end

        local started = self:startDirectController(character, animationSet, { assistMode = true })
        if not started then
            self:startDirectController(character, animationSet, { assistMode = true })
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
            self:ensureAssistController(character, animationSet)
        end
    end)
end

function AnimationMimic:rememberOriginal(character, animationObject)
    if not character or not animationObject then return end
    local saved = self.originalByCharacter[character]

    -- Keep only live animation references so this table cannot grow forever.
    if saved then
        for trackedAnimation in pairs(saved) do
            if not trackedAnimation or not trackedAnimation.Parent then
                saved[trackedAnimation] = nil
            end
        end
        if next(saved) == nil then
            self.originalByCharacter[character] = nil
            saved = nil
        end
    end

    if not saved then
        saved = {}
        self.originalByCharacter[character] = saved
    end

    if saved[animationObject] == nil then
        saved[animationObject] = animationObject.AnimationId
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

function AnimationMimic:resolveIdFromFolderData(folderData, childName, index, slotName)
    local chosen
    if folderData then
        chosen = folderData.byName[childName] or folderData.ordered[index] or folderData.first
    end
    return self:sanitizeResolvedAnimationId(chosen, nil, slotName)
end

function AnimationMimic:sanitizeResolvedAnimationId(rawId, fallbackRawId, slotName)
    local cleaned = self:resolvePlayableAnimationId(rawId, slotName)
    if cleaned then return cleaned end
    return self:resolvePlayableAnimationId(fallbackRawId, slotName)
end

function AnimationMimic:makeSingleAnimationData(name, rawId, slotName)
    local cleaned = self:sanitizeResolvedAnimationId(rawId, nil, slotName)
    if not cleaned then return nil end
    return { byName = { [name] = cleaned }, ordered = { cleaned }, first = cleaned }
end

function AnimationMimic:makeIdleAnimationData(rawIdleId)
    local cleaned = self:sanitizeResolvedAnimationId(rawIdleId, nil, "idle")
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
    if countAnimationSetCoverage(set) <= 0 then
        return nil
    end
    set.__descriptionCompatible = true
    set.__source = "live-animate"
    return set
end

function AnimationMimic:getAnimationSetFromLivePlayerWithWait(userId, timeoutSeconds)
    local okPlayer, player = pcall(function() return Players:GetPlayerByUserId(userId) end)
    if not okPlayer or not player then
        return nil
    end

    local deadline = os.clock() + math.max(timeoutSeconds or 0, 0)
    local bestSet, bestCoverage = nil, 0

    repeat
        local liveSet = self:getAnimationSetFromLivePlayer(userId)
        local coverage = countAnimationSetCoverage(liveSet)
        if coverage > bestCoverage then
            bestSet = liveSet
            bestCoverage = coverage
        end

        if coverage >= (self.settings.minLiveCoverage or 1) and coverage > 0 then
            return liveSet
        end

        if os.clock() < deadline then
            task.wait(0.08)
        end
    until os.clock() >= deadline

    return bestSet
end

function AnimationMimic:getAnimationSetFromDescription(userId)
    local desc = self.shared:getTargetDescriptionCached(userId)
    if not desc then return nil end

    local set = {
        climb = self:makeSingleAnimationData("ClimbAnim", desc.ClimbAnimation, "climb"),
        fall = self:makeSingleAnimationData("FallAnim", desc.FallAnimation, "fall"),
        jump = self:makeSingleAnimationData("JumpAnim", desc.JumpAnimation, "jump"),
        run = self:makeSingleAnimationData("RunAnim", desc.RunAnimation, "run"),
        walk = self:makeSingleAnimationData("WalkAnim", desc.WalkAnimation, "walk"),
        swim = self:makeSingleAnimationData("Swim", desc.SwimAnimation, "swim"),
        idle = self:makeIdleAnimationData(desc.IdleAnimation),
    }
    set.__descriptionCompatible = true
    set.__source = "user-description"
    return set
end

function AnimationMimic:getAnimationSetFromTempRig(userId)
    -- Use the TARGET's rig type, not local player's
    local targetRigType = Enum.HumanoidRigType.R15
    local avatarType = self.shared:getUserAvatarType(userId)
    if avatarType == "R6" then
        targetRigType = Enum.HumanoidRigType.R6
    end

    local ok, rig = pcall(function() return Players:CreateHumanoidModelFromUserId(userId, targetRigType) end)
    if not ok or not rig then return nil end

    rig.Name = "AnimationMimicTempRig"
    local animate = rig:FindFirstChild("Animate") or rig:WaitForChild("Animate", 5)
    if not animate then
        rig:Destroy()
        return nil
    end

    -- Wait for essential animation folders to populate (not swim/climb which may be absent)
    local folderNames = { "run", "walk", "jump", "fall", "idle" }
    local deadline = os.clock() + 5
    repeat
        task.wait(0.1)
        local allReady = true
        for _, name in ipairs(folderNames) do
            local folder = animate:FindFirstChild(name)
            if not folder or #folder:GetChildren() == 0 then
                allReady = false
                break
            end
        end
        if allReady then break end
    until os.clock() >= deadline

    local set = self:buildAnimationSetFromAnimate(animate)
    if set and countAnimationSetCoverage(set) < 4 then
        set = nil
    end
    if set then
        -- FIXED: mark as compatible so replication path is used
        set.__descriptionCompatible = true
        set.__source = "temp-rig"
    end
    rig:Destroy()
    return set
end

function AnimationMimic:getAnimationSetFromUserId(userId)
    local cached = self:getCachedAnimationSet(userId)
    if cached then return cached end

    local fromLive = self:getAnimationSetFromLivePlayerWithWait(userId, self.settings.liveSourceWaitSeconds)

    -- If live Animate data already has full coverage, it is always the chosen
    -- source (highest priority at max coverage). Skip heavy fallback fetches.
    if fromLive and countAnimationSetCoverage(fromLive) >= ANIM_KEY_COUNT then
        self:setCachedAnimationSet(userId, fromLive)
        return fromLive
    end

    local fromRig = self:getAnimationSetFromTempRig(userId)
    local fromDesc = nil
    if self.settings.useDescriptionSetFallback == true then
        fromDesc = self:getAnimationSetFromDescription(userId)
    end

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
    -- Require at least 5 slots (swim/climb optional)
    if (best.coverage or 0) < 5 then return nil end

    self:setCachedAnimationSet(userId, best.set)
    return best.set
end

function AnimationMimic:getAnimationSetFromUserIdWithRetry(userId, attempts)
    attempts = attempts or 2
    for i = 1, attempts do
        if not self.active then return nil end
        local set = self:getAnimationSetFromUserId(userId)
        if set then
            return set
        elseif i < attempts then
            task.wait(0.5)
            if not self.active then return nil end
        end
    end
    return nil
end

function AnimationMimic:applyAnimationSetToDescriptionFields(desc, animationSet)
    if not desc or not animationSet then return false end

    local function resolveNumeric(folder, childName, idx)
        return self.shared:numericIdFromContentId(
            self:resolveIdFromFolderData(animationSet[folder], childName, idx, folder)
        )
    end

    local climb = resolveNumeric("climb", "ClimbAnim", 1)
    local fall = resolveNumeric("fall", "FallAnim", 1)
    local jump = resolveNumeric("jump", "JumpAnim", 1)
    local run = resolveNumeric("run", "RunAnim", 1)
    local walk = resolveNumeric("walk", "WalkAnim", 1)
    local swim = resolveNumeric("swim", "Swim", 1)
    local idle = resolveNumeric("idle", "Animation1", 1)

    if not (climb and fall and jump and run and walk and swim and idle) then
        return false
    end

    local toValidate = { climb, fall, jump, run, walk, swim, idle }
    for i = 1, #toValidate do
        local id = toValidate[i]
        if not self:isDescriptionAnimationAssetIdValid(id) then
            return false
        end
    end

    desc.ClimbAnimation = climb
    desc.FallAnimation = fall
    desc.JumpAnimation = jump
    desc.RunAnimation = run
    desc.WalkAnimation = walk
    desc.SwimAnimation = swim
    desc.IdleAnimation = idle

    return true
end

-- FIXED: Core replication function with scale preservation and double-apply
-- to prevent the "fat" visual glitch caused by server overwriting body scales
function AnimationMimic:replicateAnimationStateForOthers(character, animationSet)
    if not self.settings.replicateDescriptionToOthers then return true end
    if not animationSet or animationSet.__descriptionCompatible ~= true then
        return true
    end

    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end

    -- Snapshot scales from NumberValues BEFORE any apply (most accurate)
    local scaleSnapshot = snapshotHumanoidScales(humanoid)
    local colorSnapshot = self.shared:snapshotCharacterColors(character)

    local ok, currentDesc = pcall(function() return humanoid:GetAppliedDescription() end)
    if not ok or not currentDesc then
        self.shared:destroyColorSnapshot(colorSnapshot)
        return false
    end

    -- Apply our scale snapshot into the description so it doesn't change us
    applyScaleSnapshotToDesc(currentDesc, scaleSnapshot)

    if not self:applyAnimationSetToDescriptionFields(currentDesc, animationSet) then
        self.shared:destroyColorSnapshot(colorSnapshot)
        return false
    end

    local function doApply(desc)
        if humanoid.ApplyDescriptionClientServer then
            local okCS = pcall(function() humanoid:ApplyDescriptionClientServer(desc) end)
            if okCS then return true end
        end
        return false
    end

    -- First apply: sets the animations + scales
    local applied = doApply(currentDesc)
    if not applied then
        self.shared:destroyColorSnapshot(colorSnapshot)
        return false
    end

    -- Second apply immediately: fights server overwrite of body scales
    -- This is the key fix - applying twice back-to-back eliminates fat flash
    doApply(currentDesc)

    -- Restore colors after apply
    self.shared:restoreCharacterColors(character, colorSnapshot)

    -- Third apply after short delay as final scale insurance
    task.defer(function()
        task.wait(0.12)
        if not character or not character.Parent then
            self.shared:destroyColorSnapshot(colorSnapshot)
            return
        end
        -- Re-snapshot in case something changed
        local freshScales = snapshotHumanoidScales(humanoid)
        local okDesc2, desc2 = pcall(function() return humanoid:GetAppliedDescription() end)
        if okDesc2 and desc2 then
            applyScaleSnapshotToDesc(desc2, freshScales)
            if self:applyAnimationSetToDescriptionFields(desc2, animationSet) then
                doApply(desc2)
            end
        end
        self.shared:restoreCharacterColors(character, colorSnapshot)
        self.shared:destroyColorSnapshot(colorSnapshot)
    end)

    return true
end

function AnimationMimic:scheduleReplicationRetry(character, animationSet, token)
    if self.settings.replicateDescriptionToOthers ~= true then return end
    local retryDelays = self.settings.replicationRetryDelays or {}
    if #retryDelays == 0 then return end

    for _, delayTime in ipairs(retryDelays) do
        local dt = tonumber(delayTime) or 0
        task.defer(function()
            task.wait(math.max(dt, 0))
            if not self.active then return end
            if token ~= self.applyToken then return end
            if not character or not character.Parent then return end
            self:replicateAnimationStateForOthers(character, animationSet)
        end)
    end
end

-- FIXED: applyAnimationSetViaDescription also preserves scales
function AnimationMimic:applyAnimationSetViaDescription(humanoid, animationSet)
    if not humanoid or not animationSet then return false end

    local scaleSnapshot = snapshotHumanoidScales(humanoid)

    local ok, currentDesc = pcall(function() return humanoid:GetAppliedDescription() end)
    if not ok or not currentDesc then return false end

    applyScaleSnapshotToDesc(currentDesc, scaleSnapshot)

    if not self:applyAnimationSetToDescriptionFields(currentDesc, animationSet) then return false end

    if humanoid.ApplyDescriptionClientServer then
        local okCS = pcall(function() humanoid:ApplyDescriptionClientServer(currentDesc) end)
        if okCS then
            -- Double apply to prevent fat flash
            pcall(function() humanoid:ApplyDescriptionClientServer(currentDesc) end)
            return true
        end
    end

    return pcall(function() humanoid:ApplyDescription(currentDesc) end)
end

function AnimationMimic:applyTargetDescriptionAnimations(userId, token)
    if not self.active then return false end

    local character = self.localPlayer.Character
    if not character or not character.Parent then return false end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end

    self:stopDirectController(character)
    self:stopPosePrimer(character)

    local okTarget, targetDesc = pcall(function()
        return Players:GetHumanoidDescriptionFromUserId(userId)
    end)
    if not okTarget or not targetDesc then
        targetDesc = self.shared:getTargetDescriptionCached(userId)
    end
    if not targetDesc then return false end

    local okCurrent, currentDesc = pcall(function() return humanoid:GetAppliedDescription() end)
    if not okCurrent or not currentDesc then return false end

    local function resolveDescFieldToNumeric(rawId, slotName)
        local resolved = self:sanitizeResolvedAnimationId(rawId, nil, slotName)
        return resolved and self.shared:numericIdFromContentId(resolved) or nil
    end

    local function copyAnimationFields(into, from)
        local run = resolveDescFieldToNumeric(from.RunAnimation, "run")
        local walk = resolveDescFieldToNumeric(from.WalkAnimation, "walk")
        local idle = resolveDescFieldToNumeric(from.IdleAnimation, "idle")
        local jump = resolveDescFieldToNumeric(from.JumpAnimation, "jump")
        local fall = resolveDescFieldToNumeric(from.FallAnimation, "fall")
        local climb = resolveDescFieldToNumeric(from.ClimbAnimation, "climb")
        local swim = resolveDescFieldToNumeric(from.SwimAnimation, "swim")

        if not (run and walk and idle and jump and fall and climb and swim) then
            return false
        end

        into.RunAnimation = run
        into.WalkAnimation = walk
        into.IdleAnimation = idle
        into.JumpAnimation = jump
        into.FallAnimation = fall
        into.ClimbAnimation = climb
        into.SwimAnimation = swim
        return true
    end

    if not copyAnimationFields(currentDesc, targetDesc) then
        return false
    end
    applyScaleSnapshotToDesc(currentDesc, snapshotHumanoidScales(humanoid))

    local function doApply(desc)
        if humanoid.ApplyDescriptionClientServer then
            local okCS = pcall(function() humanoid:ApplyDescriptionClientServer(desc) end)
            if okCS then return true end
        end
        return pcall(function() humanoid:ApplyDescription(desc) end)
    end

    if not doApply(currentDesc) then return false end
    doApply(currentDesc)

    task.defer(function()
        task.wait(0.1)
        if not self.active then return end
        if token and token ~= self.applyToken then return end
        if not character.Parent then return end

        local okDesc2, desc2 = pcall(function() return humanoid:GetAppliedDescription() end)
        if not okDesc2 or not desc2 then return end

        if not copyAnimationFields(desc2, targetDesc) then
            return
        end
        applyScaleSnapshotToDesc(desc2, snapshotHumanoidScales(humanoid))
        doApply(desc2)
    end)

    if type(self.onAfterApply) == "function" then
        task.defer(function()
            pcall(self.onAfterApply)
        end)
    end

    return true
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

    for character in pairs(self.unstickSerialByChar) do
        if character ~= currentCharacter and (not character.Parent or character ~= self.localPlayer.Character) then
            self.unstickSerialByChar[character] = nil
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

    local function getAnimId(folder, childName, idx)
        return self:resolveIdFromFolderData(animationSet[folder], childName, idx, folder)
    end

    local idMap = {
        idle = getAnimId("idle", "Animation1", 1),
        run = getAnimId("run", "RunAnim", 1),
        walk = getAnimId("walk", "WalkAnim", 1),
        jump = getAnimId("jump", "JumpAnim", 1),
        fall = getAnimId("fall", "FallAnim", 1),
        climb = getAnimId("climb", "ClimbAnim", 1),
        swim = getAnimId("swim", "Swim", 1),
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

    local function speedForLocomotionTrack(stateName)
        if stateName ~= "run" and stateName ~= "walk" then
            return 1
        end

        local baseWalk = humanoid.WalkSpeed > 0 and humanoid.WalkSpeed or 16
        local baseRatio = baseWalk / 16
        local moveRatio = math.clamp(humanoid.MoveDirection.Magnitude, 0, 1)
        local speed = baseRatio * (0.75 + moveRatio * 0.5)
        return math.clamp(speed, 0.7, 2.2)
    end

    local function applyTrackSpeed(track, stateName)
        if not track then return end
        pcall(function()
            track:AdjustSpeed(speedForLocomotionTrack(stateName))
        end)
    end

    local function playState(nextState)
        if controller.active == nextState then
            local t = controller.tracks[nextState]
            if t and not t.IsPlaying then pcall(function() t:Play(0.08, 1, 1) end) end
            applyTrackSpeed(t, nextState)
            return
        end

        controller.active = nextState
        for name, track in pairs(controller.tracks) do
            if name == nextState then
                pcall(function() if not track.IsPlaying then track:Play(0.08, 1, 1) end end)
                applyTrackSpeed(track, name)
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
            local hasNativeTrack = false
            for _, t in ipairs(humanoid:GetPlayingAnimationTracks()) do
                if t.IsPlaying and not controller.trackSet[t] then
                    hasNativeTrack = true
                    break
                end
            end
            if hasNativeTrack then
                self:stopDirectController(character)
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

function AnimationMimic:applyFolderDataToFolder(character, folder, folderData, shouldRemember, slotName)
    if not folder then return 0 end

    local changed = 0
    local idx = 0
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("Animation") then
            idx = idx + 1
            local resolvedId = self:resolveIdFromFolderData(folderData, child.Name, idx, slotName)
            if resolvedId then
                if shouldRemember then self:rememberOriginal(character, child) end
                child.AnimationId = resolvedId
                changed = changed + 1
            end
        end
    end

    return changed
end

function AnimationMimic:applySlotFromSet(character, animate, animationSet, folderName, shouldRemember)
    local folder = animate:FindFirstChild(folderName)
    local setData = animationSet and animationSet[folderName]

    if self:applyFolderDataToFolder(character, folder, setData, shouldRemember, folderName) > 0 then
        return true
    end

    return false
end

function AnimationMimic:applyIdleFromSet(character, animate, idleData, shouldRemember)
    local idleFolder = animate:FindFirstChild("idle")
    if not idleFolder then return false end

    local applied = 0
    local idx = 0
    for _, child in ipairs(idleFolder:GetChildren()) do
        if child:IsA("Animation") then
            idx = idx + 1
            local resolvedIdle = self:resolveIdFromFolderData(idleData, child.Name, idx, "idle")
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
    if animate then
        for _, spec in ipairs(SLOT_SPECS) do
            if self:applySlotFromSet(character, animate, animationSet, spec.folder, true) then
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
        local descApplied = self:applyAnimationSetViaDescription(humanoid, animationSet)
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
            self:ensureAssistController(character, animationSet)
        end
    elseif self.settings.adaptiveAssistAfterApply then
        self:scheduleAssistIfNeeded(character, animationSet)
    end

    self:unstickPoseAfterApply(character, animationSet, self.applyToken)
    local replicated = self:replicateAnimationStateForOthers(character, animationSet)
    if not replicated then
        self:scheduleReplicationRetry(character, animationSet, self.applyToken)
    end

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
    if animate then
        for _, spec in ipairs(SLOT_SPECS) do
            if self:applySlotFromSet(character, animate, ownSet, spec.folder, false) then
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
        if self:applyAnimationSetViaDescription(humanoid, ownSet) then
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
            self:ensureAssistController(character, ownSet)
        end
    elseif self.settings.adaptiveAssistAfterApply then
        self:scheduleAssistIfNeeded(character, ownSet)
    end

    self:unstickPoseAfterApply(character, ownSet, self.applyToken)
    local replicated = self:replicateAnimationStateForOthers(character, ownSet)
    if not replicated then
        self:scheduleReplicationRetry(character, ownSet, self.applyToken)
    end

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

    local switchedTarget = self.lastSourceUserId and self.lastSourceUserId ~= numericUserId
    if switchedTarget then
        self.shared.animationSetCache[numericUserId] = nil
        self:stopDirectController(character)
        self:stopPosePrimer(character)
        flushAnimationState(character)
        scrubTracksForDuration(character, 0.12)
        if applyToken ~= self.applyToken then return false end
    end

    local directDescriptionApplied = false
    if self.settings.useDescriptionAnimationApply == true then
        directDescriptionApplied = self:applyTargetDescriptionAnimations(numericUserId, applyToken)
    end
    if directDescriptionApplied then
        self.lastSourceUserId = numericUserId
        self.pinnedTargetUserId = numericUserId
        self.resumeUserId = numericUserId
        return true
    end

    local animationSet = self:getAnimationSetFromUserIdWithRetry(numericUserId, 3)
    if not animationSet then
        if switchedTarget then
            self:restoreOwnAnimationsHard(character)
            flushAnimationState(character)
            scrubTracksForDuration(character, 0.18)
        end
        self.lastSourceUserId = nil
        return false
    end

    if applyToken ~= self.applyToken then return false end

    self.lastSourceUserId = numericUserId
    self.pinnedTargetUserId = numericUserId
    self.resumeUserId = numericUserId

    local ok = self:applyAnimationSetToCharacter(character, animationSet)
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

    local previousTargetUserId = self.pinnedTargetUserId or self.lastSourceUserId

    self.lastTargetInput = target
    self.pinnedTargetUserId = userId

    if self.settings.invalidateAnimationCacheOnTargetSwitch
        and previousTargetUserId
        and previousTargetUserId ~= userId then
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
        self.resumeUserId = self.pinnedTargetUserId or self.lastSourceUserId or self.resumeUserId
        self.lastSourceUserId = nil
        self.pinnedTargetUserId = nil
        local character = self.localPlayer.Character
        self:stopAllDirectControllers()
        self:stopAllPosePrimers()
        self:resetCharacterAnimations(character)
        self.originalByCharacter = {}
        self.unstickSerialByChar = {}
        flushAnimationState(character)
    else
        local character = self.localPlayer.Character
        local resumeTarget = self.pinnedTargetUserId or self.lastSourceUserId or self.resumeUserId
        if character and character.Parent and resumeTarget then
            task.defer(function()
                if self.active then
                    self:mimicFromUserId(resumeTarget, true)
                end
            end)
        end
    end
end

function AnimationMimic:cleanup()
    self.active = false
    self.lastSourceUserId = nil
    self.pinnedTargetUserId = nil
    self.resumeUserId = nil
    self.lastTargetInput = nil
    self.applyToken = self.applyToken + 1

    local character = self.localPlayer.Character
    self:stopAllDirectControllers()
    self:stopAllPosePrimers()
    self:resetCharacterAnimations(character)
    self.originalByCharacter = {}
    self.unstickSerialByChar = {}

    flushAnimationState(character)
end

return AnimationMimic