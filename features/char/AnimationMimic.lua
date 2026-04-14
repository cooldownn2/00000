local Players = game:GetService("Players")
local InsertService = game:GetService("InsertService")

local AnimationMimic = {}
AnimationMimic.__index = AnimationMimic

local ANIM_FIELDS = {
    { desc = "RunAnimation", folder = "run", child = "RunAnim" },
    { desc = "WalkAnimation", folder = "walk", child = "WalkAnim" },
    { desc = "IdleAnimation", folder = "idle", child = "Animation1" },
    { desc = "JumpAnimation", folder = "jump", child = "JumpAnim" },
    { desc = "FallAnimation", folder = "fall", child = "FallAnim" },
    { desc = "ClimbAnimation", folder = "climb", child = "ClimbAnim" },
    { desc = "SwimAnimation", folder = "swim", child = "Swim" },
}

local ANIM_FOLDERS = { "run", "walk", "idle", "jump", "fall", "climb", "swim" }

local ROBLOX_DEFAULTS = {
    run = { "rbxassetid://913376220" },
    walk = { "rbxassetid://913492848" },
    idle = { "rbxassetid://507766388", "rbxassetid://507766666" },
    jump = { "rbxassetid://507765000" },
    fall = { "rbxassetid://507767968" },
    climb = { "rbxassetid://507765644" },
    swim = { "rbxassetid://913384386" },
}

local SCALE_MAP = {
    BodyHeightScale = "HeightScale",
    BodyWidthScale = "WidthScale",
    BodyDepthScale = "DepthScale",
    HeadScale = "HeadScale",
    BodyTypeScale = "BodyTypeScale",
    BodyProportionScale = "ProportionScale",
}

local function normalizeId(rawId)
    local numeric = tostring(rawId or ""):match("(%d+)")
    if not numeric then return nil end
    return "rbxassetid://" .. numeric
end

local function toNumeric(rawId)
    local numeric = tostring(rawId or ""):match("(%d+)")
    return numeric and tonumber(numeric) or nil
end

local function snapshotScales(humanoid)
    if not humanoid then return nil end

    local snapshot = {}
    for humProp in pairs(SCALE_MAP) do
        local scaleValue = humanoid:FindFirstChild(humProp)
        snapshot[humProp] = (scaleValue and scaleValue.Value) or 1
    end
    return snapshot
end

local function applyScalesToDescription(desc, snapshot)
    if not desc or not snapshot then return end

    for humProp, descProp in pairs(SCALE_MAP) do
        if snapshot[humProp] ~= nil then
            desc[descProp] = snapshot[humProp]
        end
    end
end

local function readFolderData(folder)
    if not folder then return nil end

    local data = { byName = {}, ordered = {}, first = nil }
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("Animation") then
            local id = normalizeId(child.AnimationId)
            if id then
                if not data.first then data.first = id end
                data.byName[child.Name] = id
                data.ordered[#data.ordered + 1] = id
            end
        end
    end

    return data.first and data or nil
end

local function patchFolder(folder, folderData)
    if not folder or not folderData then return 0 end

    local changed = 0
    local idx = 0
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("Animation") then
            idx = idx + 1
            local id = folderData.byName[child.Name] or folderData.ordered[idx] or folderData.first
            if id and id ~= "" then
                child.AnimationId = id
                changed = changed + 1
            end
        end
    end

    return changed
end

local function makeFolderData(folderName, ids)
    local first = ids and ids[1]
    if not first then return nil end

    local childName = "Animation1"
    for _, field in ipairs(ANIM_FIELDS) do
        if field.folder == folderName then
            childName = field.child
            break
        end
    end

    local data = {
        first = first,
        byName = { [childName] = first },
        ordered = { first },
    }

    if folderName == "idle" then
        local second = ids[2] or first
        data.byName.Animation1 = first
        data.byName.Animation2 = second
        data.ordered[2] = second
    end

    return data
end

function AnimationMimic.new(deps)
    local self = setmetatable({}, AnimationMimic)

    self.shared = deps.shared
    self.localPlayer = deps.localPlayer
    self.onAfterApply = deps.onAfterApply

    self.active = true
    self.targetInput = nil
    self.currentUserId = nil
    self.lastAppliedCharacter = nil
    self.applyToken = 0

    self.descTtlSeconds = 60
    self.resolveCache = {}
    self.descCache = {}
    self.originalSnapshots = setmetatable({}, { __mode = "k" })

    return self
end

function AnimationMimic:isApplyStillCurrent(token)
    return self.active and token == self.applyToken
end

function AnimationMimic:getDescription(userId)
    local cacheKey = tostring(userId)
    local entry = self.descCache[cacheKey]
    if entry and (os.clock() - (entry.timestamp or 0)) <= self.descTtlSeconds then
        return entry.desc
    end

    local desc = nil
    if self.shared and type(self.shared.getTargetDescriptionCached) == "function" then
        desc = self.shared:getTargetDescriptionCached(userId)
    end

    if not desc then
        local ok, fetched = pcall(Players.GetHumanoidDescriptionFromUserIdAsync, Players, userId)
        if ok and fetched then
            desc = fetched
        end
    end

    if not desc then
        return nil
    end

    self.descCache[cacheKey] = {
        desc = desc,
        timestamp = os.clock(),
    }
    return desc
end

function AnimationMimic:resolveAnimationId(rawId, slotHint)
    local id = normalizeId(rawId)
    if not id then return nil end

    local numeric = toNumeric(id)
    if not numeric or numeric == 0 then return nil end

    local slotLower = string.lower(slotHint or "")
    local cacheKey = tostring(numeric) .. "|" .. slotLower
    local cached = self.resolveCache[cacheKey]
    if cached ~= nil then
        return cached ~= false and cached or nil
    end

    local function pickBest(container)
        local fallback = nil
        for _, inst in ipairs(container:GetDescendants()) do
            if inst:IsA("Animation") and inst.AnimationId ~= "" then
                local resolved = normalizeId(inst.AnimationId)
                if resolved then
                    if not fallback then fallback = resolved end
                    if slotLower ~= "" then
                        local n = string.lower(inst.Name or "")
                        local p = string.lower((inst.Parent and inst.Parent.Name) or "")
                        if n:find(slotLower, 1, true) or p:find(slotLower, 1, true) then
                            return resolved
                        end
                    end
                end
            end
        end
        return fallback
    end

    local okObjects, objects = pcall(function()
        return game:GetObjects("rbxassetid://" .. tostring(numeric))
    end)
    if okObjects and type(objects) == "table" then
        for _, root in ipairs(objects) do
            local resolved = pickBest(root)
            pcall(function() root:Destroy() end)
            if resolved then
                self.resolveCache[cacheKey] = resolved
                return resolved
            end
        end
    end

    local okAsset, model = pcall(function()
        return InsertService:LoadAsset(numeric)
    end)
    if okAsset and model then
        local best = pickBest(model)
        pcall(function() model:Destroy() end)
        if best then
            self.resolveCache[cacheKey] = best
            return best
        end
    end

    self.resolveCache[cacheKey] = id
    return id
end

function AnimationMimic:buildAnimationSet(desc)
    local set = {}

    for _, field in ipairs(ANIM_FIELDS) do
        local raw = tonumber(desc[field.desc]) or 0
        if raw > 0 then
            local resolved = self:resolveAnimationId(raw, field.folder)
            if resolved then
                set[field.folder] = {
                    first = resolved,
                    byName = { [field.child] = resolved },
                    ordered = { resolved },
                }
            end
        end
    end

    if set.idle then
        set.idle.byName.Animation2 = set.idle.first
        set.idle.ordered[2] = set.idle.first
    end

    for _, folderName in ipairs(ANIM_FOLDERS) do
        if not set[folderName] then
            set[folderName] = makeFolderData(folderName, ROBLOX_DEFAULTS[folderName])
        end
    end

    return set
end

function AnimationMimic:captureOriginalAnimate(character)
    if not character or self.originalSnapshots[character] then return end

    local animate = character:FindFirstChild("Animate")
    if not (animate and animate:IsA("LocalScript")) then return end

    local snap = {}
    for _, folderName in ipairs(ANIM_FOLDERS) do
        snap[folderName] = readFolderData(animate:FindFirstChild(folderName))
    end

    self.originalSnapshots[character] = snap
end

function AnimationMimic:reloadAnimate(character)
    local animate = character and character:FindFirstChild("Animate")
    if animate and animate:IsA("LocalScript") then
        animate.Disabled = true
        task.wait(0.08)
        animate.Disabled = false
    end

    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
        pcall(function() track:Stop(0.1) end)
    end

    local state = humanoid:GetState()
    local targetState = Enum.HumanoidStateType.Running
    if state == Enum.HumanoidStateType.Swimming then
        targetState = Enum.HumanoidStateType.Swimming
    elseif state == Enum.HumanoidStateType.Climbing then
        targetState = Enum.HumanoidStateType.Climbing
    elseif state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall then
        targetState = Enum.HumanoidStateType.Freefall
    end
    humanoid:ChangeState(targetState)
end

function AnimationMimic:restoreOriginalAnimate(character)
    if not character then return end

    local snapshot = self.originalSnapshots[character]
    local animate = character:FindFirstChild("Animate")
    if not (snapshot and animate and animate:IsA("LocalScript")) then return end

    local changed = 0
    for _, folderName in ipairs(ANIM_FOLDERS) do
        changed = changed + patchFolder(animate:FindFirstChild(folderName), snapshot[folderName])
    end

    if changed > 0 then
        self:reloadAnimate(character)
    end

    self.originalSnapshots[character] = nil
end

function AnimationMimic:applyViaNativeAnimate(character, animSet)
    local animate = character and character:FindFirstChild("Animate")
    if not (animate and animate:IsA("LocalScript")) then
        return false
    end

    local changed = 0
    for _, folderName in ipairs(ANIM_FOLDERS) do
        changed = changed + patchFolder(animate:FindFirstChild(folderName), animSet[folderName])
    end

    if changed == 0 then
        return false
    end

    self:reloadAnimate(character)
    return true
end

function AnimationMimic:applyViaDescription(character, descValues, applyToken)
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end

    local okDesc, currentDesc = pcall(function()
        return humanoid:GetAppliedDescription()
    end)
    if not okDesc or not currentDesc then return false end

    local copied = 0
    for _, field in ipairs(ANIM_FIELDS) do
        local value = descValues[field.desc]
        if value and value > 0 then
            currentDesc[field.desc] = value
            copied = copied + 1
        else
            currentDesc[field.desc] = 0
        end
    end
    if copied < 1 then return false end

    applyScalesToDescription(currentDesc, snapshotScales(humanoid))

    local function doApply(desc)
        if humanoid.ApplyDescriptionClientServer then
            local okCS = pcall(function() humanoid:ApplyDescriptionClientServer(desc) end)
            if okCS then return true end
        end
        return pcall(function() humanoid:ApplyDescription(desc) end)
    end

    local ok = doApply(currentDesc)
    doApply(currentDesc)

    task.delay(0.1, function()
        if not self:isApplyStillCurrent(applyToken) then return end
        if not character.Parent then return end

        local okDesc2, desc2 = pcall(function()
            return humanoid:GetAppliedDescription()
        end)
        if not okDesc2 or not desc2 then return end

        for _, field in ipairs(ANIM_FIELDS) do
            local value = descValues[field.desc]
            if value and value > 0 then
                desc2[field.desc] = value
            else
                desc2[field.desc] = 0
            end
        end

        applyScalesToDescription(desc2, snapshotScales(humanoid))
        doApply(desc2)
    end)

    return ok
end

function AnimationMimic:prewarm(userId)
    local desc = self:getDescription(userId)
    if desc then
        self:buildAnimationSet(desc)
    end
end

function AnimationMimic:applyToCharacter(userId, character, applyToken)
    if not self:isApplyStillCurrent(applyToken) then return false end
    if not character or not character.Parent then return false end

    local desc = self:getDescription(userId)
    if not desc then return false end

    self:captureOriginalAnimate(character)
    self:restoreOriginalAnimate(character)
    self:captureOriginalAnimate(character)

    local animSet = self:buildAnimationSet(desc)
    local descValues = {}
    for _, field in ipairs(ANIM_FIELDS) do
        local raw = tonumber(desc[field.desc]) or 0
        descValues[field.desc] = raw > 0 and raw or 0
    end

    local nativeOk = self:applyViaNativeAnimate(character, animSet)
    if not nativeOk then
        local animate = character:FindFirstChild("Animate")
        if animate and animate:IsA("LocalScript") then
            animate.Disabled = false
        end
    end

    task.spawn(function()
        self:applyViaDescription(character, descValues, applyToken)
    end)

    if type(self.onAfterApply) == "function" then
        task.defer(function()
            pcall(self.onAfterApply)
        end)
    end

    return true
end

function AnimationMimic:mimicFromUserId(userId, forceApply)
    if not self.active then return false end

    local numericUserId = tonumber(userId)
    if not numericUserId then return false end

    local character = self.localPlayer and self.localPlayer.Character
    if not character then return false end

    if forceApply ~= true and self.currentUserId == numericUserId and self.lastAppliedCharacter == character then
        return true
    end

    self.applyToken = self.applyToken + 1
    local applyToken = self.applyToken

    self:prewarm(numericUserId)

    if not self:isApplyStillCurrent(applyToken) then
        return false
    end

    local ok = self:applyToCharacter(numericUserId, character, applyToken)
    if ok then
        self.currentUserId = numericUserId
        self.lastAppliedCharacter = character
    end

    return ok
end

function AnimationMimic:mimicFromTarget(target)
    if not self.active then return false end

    local userId = nil
    if self.shared and type(self.shared.resolveUserToId) == "function" then
        userId = self.shared:resolveUserToId(target)
    end
    if not userId then
        userId = tonumber(target)
    end
    if not userId then return false end

    self.targetInput = target
    if self.currentUserId and tonumber(self.currentUserId) ~= tonumber(userId) then
        self.currentUserId = nil
    end
    return self:mimicFromUserId(userId, true)
end

function AnimationMimic:reapply()
    if self.targetInput ~= nil then
        return self:mimicFromTarget(self.targetInput)
    end
    if self.currentUserId then
        return self:mimicFromUserId(self.currentUserId, true)
    end
    return false
end

function AnimationMimic:onCharacterAdded(char)
    if not self.active then return end

    self.lastAppliedCharacter = nil
    self.applyToken = self.applyToken + 1
    local respawnToken = self.applyToken

    task.spawn(function()
        local humanoid = char:WaitForChild("Humanoid", 10)
        if not humanoid then return end
        if not self:isApplyStillCurrent(respawnToken) then return end
        if not char.Parent then return end

        local userId = self.currentUserId
        if not userId and self.targetInput ~= nil then
            if self.shared and type(self.shared.resolveUserToId) == "function" then
                userId = self.shared:resolveUserToId(self.targetInput)
            end
            if not userId then
                userId = tonumber(self.targetInput)
            end
        end
        if not userId then return end

        self:prewarm(userId)

        local delays = { 0.2, 0.45, 0.8 }
        for _, delayTime in ipairs(delays) do
            if not self:isApplyStillCurrent(respawnToken) then return end
            if not char.Parent then return end

            task.wait(delayTime)

            if not self:isApplyStillCurrent(respawnToken) then return end
            if not char.Parent then return end

            if self:applyToCharacter(userId, char, respawnToken) then
                self.currentUserId = userId
                self.lastAppliedCharacter = char
                break
            end
        end
    end)
end

function AnimationMimic:setEnabled(enabled)
    enabled = enabled == true
    if self.active == enabled then return end

    self.active = enabled
    self.applyToken = self.applyToken + 1

    if not enabled then
        local character = self.localPlayer and self.localPlayer.Character
        self:restoreOriginalAnimate(character)
        self.lastAppliedCharacter = nil
        return
    end

    local character = self.localPlayer and self.localPlayer.Character
    if not (character and character.Parent) then return end

    local resumeId = self.currentUserId
    if not resumeId and self.targetInput ~= nil then
        if self.shared and type(self.shared.resolveUserToId) == "function" then
            resumeId = self.shared:resolveUserToId(self.targetInput)
        end
        if not resumeId then
            resumeId = tonumber(self.targetInput)
        end
    end

    if resumeId then
        task.defer(function()
            if self.active then
                self:mimicFromUserId(resumeId, true)
            end
        end)
    end
end

function AnimationMimic:cleanup()
    self.active = false
    self.applyToken = self.applyToken + 1

    local character = self.localPlayer and self.localPlayer.Character
    self:restoreOriginalAnimate(character)

    self.targetInput = nil
    self.currentUserId = nil
    self.lastAppliedCharacter = nil

    for key in pairs(self.resolveCache) do
        self.resolveCache[key] = nil
    end
    for key in pairs(self.descCache) do
        self.descCache[key] = nil
    end
    for key in pairs(self.originalSnapshots) do
        self.originalSnapshots[key] = nil
    end
end

return AnimationMimic
