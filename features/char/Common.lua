local Players = game:GetService("Players")
local InsertService = game:GetService("InsertService")

local Common = {}
Common.__index = Common

local AVATAR_CACHE_TTL_SECONDS = 20
local RESOLVED_USERID_TTL_SECONDS = 600
local FETCH_WAIT_TIMEOUT_SECONDS = 4
local FETCH_WAIT_STEP_SECONDS = 0.03

local CACHE_MAX_ENTRIES = {
    faceTexture = 80,
    faceAssetTexture = 120,
    description = 40,
    appearanceModel = 24,
    appearanceInfo = 60,
    resolvedUserId = 120,
    animationSet = 64,
    emoteData = 80,
}

local NO_FACE_TOKEN = "__NO_FACE__"

local function waitForPending(pendingMap, key, timeoutSeconds)
    local started = os.clock()
    while pendingMap[key] do
        if os.clock() - started >= (timeoutSeconds or FETCH_WAIT_TIMEOUT_SECONDS) then
            return false
        end
        task.wait(FETCH_WAIT_STEP_SECONDS)
    end
    return true
end

local function countMapEntries(map)
    local count = 0
    for _ in pairs(map) do count = count + 1 end
    return count
end

local function pruneTimestampedCache(cache, maxEntries, onEvict)
    local count = countMapEntries(cache)
    while count > maxEntries do
        local oldestKey, oldestTs = nil, math.huge
        for k, entry in pairs(cache) do
            local ts = (entry and entry.timestamp) or 0
            if ts < oldestTs then
                oldestTs = ts
                oldestKey = k
            end
        end
        if oldestKey == nil then break end
        local evicted = cache[oldestKey]
        cache[oldestKey] = nil
        if onEvict then onEvict(oldestKey, evicted) end
        count = count - 1
    end
end

local function prunePairedTimestampCache(valueCache, timeCache, maxEntries)
    local count = countMapEntries(valueCache)
    while count > maxEntries do
        local oldestKey, oldestTs = nil, math.huge
        for k in pairs(valueCache) do
            local ts = timeCache[k] or 0
            if ts < oldestTs then
                oldestTs = ts
                oldestKey = k
            end
        end
        if oldestKey == nil then break end
        valueCache[oldestKey] = nil
        timeCache[oldestKey] = nil
        count = count - 1
    end
end

local function normalizeForLookup(value)
    local v = string.lower(tostring(value or ""))
    v = string.gsub(v, "^@", "")
    v = string.gsub(v, "%s+", "")
    v = string.gsub(v, "_+", "")
    return v
end

local function firstDecalTextureFromHead(head)
    if not head then return nil end
    for _, child in ipairs(head:GetChildren()) do
        if child:IsA("Decal") and child.Face == Enum.NormalId.Front and child.Texture ~= "" then
            return child.Texture
        end
    end
    for _, child in ipairs(head:GetChildren()) do
        if child:IsA("Decal") and child.Texture ~= "" then
            return child.Texture
        end
    end
    return nil
end

local function normalizeAvatarType(rawType)
    if rawType == nil then return nil end
    local s = tostring(rawType):upper()
    if s:find("R15") or s == "2" then return "R15" end
    if s:find("R6") or s == "1" then return "R6" end
    return nil
end

function Common.new(localPlayer)
    local self = setmetatable({}, Common)

    self.LocalPlayer = localPlayer or Players.LocalPlayer

    self.faceTextureCache = {}
    self.faceTextureCacheTime = {}
    self.faceAssetTextureCache = {}
    self.faceAssetTextureCacheTime = {}

    self.descriptionCache = {}
    self.appearanceModelCache = {}
    self.appearanceInfoCache = {}

    self.resolvedUserIdCache = {}
    self.resolvedUserIdCacheTime = {}

    self.animationSetCache = {}
    self.emoteDataCache = {}

    self.pendingAppearanceModel = {}
    self.pendingDescription = {}
    self.pendingAppearanceInfo = {}
    self.pendingFaceAsset = {}

    return self
end

function Common:destroyColorSnapshot(snapshot)
    if not snapshot then return end
    if snapshot.bodyColors then
        pcall(function() snapshot.bodyColors:Destroy() end)
        snapshot.bodyColors = nil
    end
end

function Common:clearAvatarCaches()
    for userId, entry in pairs(self.descriptionCache) do
        if entry and entry.desc then pcall(function() entry.desc:Destroy() end) end
        self.descriptionCache[userId] = nil
    end

    for userId, entry in pairs(self.appearanceModelCache) do
        if entry and entry.model then pcall(function() entry.model:Destroy() end) end
        self.appearanceModelCache[userId] = nil
    end

    for userId in pairs(self.appearanceInfoCache) do
        self.appearanceInfoCache[userId] = nil
    end

    for userId in pairs(self.faceTextureCache) do
        self.faceTextureCache[userId] = nil
        self.faceTextureCacheTime[userId] = nil
    end

    for assetId in pairs(self.faceAssetTextureCache) do
        self.faceAssetTextureCache[assetId] = nil
        self.faceAssetTextureCacheTime[assetId] = nil
    end

    for cacheKey in pairs(self.resolvedUserIdCacheTime) do
        self.resolvedUserIdCache[cacheKey] = nil
        self.resolvedUserIdCacheTime[cacheKey] = nil
    end

    self.animationSetCache = {}
    self.emoteDataCache = {}

    self.pendingAppearanceModel = {}
    self.pendingDescription = {}
    self.pendingAppearanceInfo = {}
    self.pendingFaceAsset = {}
end

function Common:destroy()
    self:clearAvatarCaches()
end

function Common:getCacheMaxEntries(key)
    return CACHE_MAX_ENTRIES[key]
end

function Common:cacheGetTimed(valueCache, timeCache, key, ttlSeconds)
    local value = valueCache[key]
    local ts = timeCache[key]
    if value ~= nil and ts and os.clock() - ts <= ttlSeconds then
        return value
    end
    if value ~= nil then valueCache[key] = nil end
    if ts ~= nil then timeCache[key] = nil end
    return nil
end

function Common:cacheSetTimed(valueCache, timeCache, key, value, maxEntries)
    valueCache[key] = value
    timeCache[key] = os.clock()
    prunePairedTimestampCache(valueCache, timeCache, maxEntries)
    return value
end

function Common:cacheGetEntry(cache, key, ttlSeconds, onExpire)
    local entry = cache[key]
    if not entry then return nil end
    if os.clock() - (entry.timestamp or 0) <= ttlSeconds then return entry end
    if onExpire then onExpire(entry) end
    cache[key] = nil
    return nil
end

function Common:cacheSetEntry(cache, key, entry, maxEntries, onEvict)
    cache[key] = entry
    pruneTimestampedCache(cache, maxEntries, onEvict)
    return entry
end

function Common:snapshotCharacterColors(char)
    if not char then return nil end
    local snapshot = { bodyColors = nil, partColors = {} }
    local bc = char:FindFirstChildOfClass("BodyColors")
    if bc then snapshot.bodyColors = bc:Clone() end

    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("BasePart") then
            snapshot.partColors[child.Name] = child.BrickColor
        end
    end

    return snapshot
end

function Common:restoreCharacterColors(character, snapshot)
    if not character or not snapshot then return end

    if snapshot.bodyColors then
        local src = snapshot.bodyColors
        local ok, clone = pcall(function() return src:Clone() end)
        if ok and clone then
            local current = character:FindFirstChildOfClass("BodyColors")
            if current then pcall(function() current:Destroy() end) end
            local applied = pcall(function() clone.Parent = character end)
            if not applied then
                pcall(function() clone:Destroy() end)
            end
        end
    end

    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("BasePart") then
            local saved = snapshot.partColors[child.Name]
            if saved then child.BrickColor = saved end
        end
    end
end

function Common:restoreCharacterColorsSafely(character, snapshot)
    if not snapshot then return end

    self:restoreCharacterColors(character, snapshot)

    task.defer(function()
        task.wait(0.06)
        if character and character.Parent then
            self:restoreCharacterColors(character, snapshot)
        end
    end)

    task.defer(function()
        task.wait(0.2)
        if character and character.Parent then
            self:restoreCharacterColors(character, snapshot)
        end
        self:destroyColorSnapshot(snapshot)
    end)
end

function Common:deepCopyTable(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end

    local out = {}
    seen[value] = out
    for k, v in pairs(value) do
        out[self:deepCopyTable(k, seen)] = self:deepCopyTable(v, seen)
    end
    return out
end

function Common:normalizeAnimationId(rawId)
    if rawId == nil then return nil end
    local numeric = tostring(rawId):match("%d+")
    if not numeric then return nil end
    if (tonumber(numeric) or 0) <= 0 then return nil end
    return "rbxassetid://" .. numeric
end

function Common:numericIdFromContentId(rawId)
    if not rawId then return nil end
    local numeric = tostring(rawId):match("%d+")
    return numeric and tonumber(numeric) or nil
end

function Common:getCurrentScaleValues(humanoid)
    if not humanoid then return nil end

    local function readSV(name, fallback)
        local nv = humanoid:FindFirstChild(name)
        return (nv and nv:IsA("NumberValue") and nv.Value) or fallback
    end

    local okDesc, desc = pcall(function() return humanoid:GetAppliedDescription() end)

    return {
        height = readSV("BodyHeightScale", okDesc and desc and desc.HeightScale or 1),
        width = readSV("BodyWidthScale", okDesc and desc and desc.WidthScale or 1),
        depth = readSV("BodyDepthScale", okDesc and desc and desc.DepthScale or 1),
        head = readSV("HeadScale", okDesc and desc and desc.HeadScale or 1),
        bodyType = readSV("BodyTypeScale", okDesc and desc and desc.BodyTypeScale or 0),
        proportion = readSV("BodyProportionScale", okDesc and desc and desc.ProportionScale or 0),
    }
end

function Common:applyScaleValuesToDescription(desc, scales)
    if not desc or not scales then return end
    desc.HeightScale = scales.height
    desc.WidthScale = scales.width
    desc.DepthScale = scales.depth
    desc.HeadScale = scales.head
    desc.BodyTypeScale = scales.bodyType
    desc.ProportionScale = scales.proportion
end

function Common:isCharacterR15(character)
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    return humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R15
end

function Common:getUserAvatarType(userId)
    local info = self:getCharacterAppearanceInfoCached(userId)
    return normalizeAvatarType(info and (info.playerAvatarType or info.PlayerAvatarType))
end

function Common:findUserIdInServerByNameOrDisplay(inputText)
    local rawInput = tostring(inputText or ""):gsub("^%s+",""):gsub("%s+$","")
    local needleRaw = string.lower(rawInput)
    local needleNorm = normalizeForLookup(rawInput)
    if needleNorm == "" then return nil end

    local exactNameUserId = nil
    local exactDisplayUserId = nil
    local exactDisplayCount = 0
    local prefixCandidates = {}

    for _, player in ipairs(Players:GetPlayers()) do
        local nameRaw = string.lower(player.Name)
        local displayRaw = string.lower(player.DisplayName)
        local nameNorm = normalizeForLookup(player.Name)
        local displayNorm = normalizeForLookup(player.DisplayName)

        if nameRaw == needleRaw or nameNorm == needleNorm then
            exactNameUserId = player.UserId
            break
        end

        if displayRaw == needleRaw or displayNorm == needleNorm then
            exactDisplayUserId = player.UserId
            exactDisplayCount = exactDisplayCount + 1
        end

        local namePrefix = (needleRaw ~= "" and string.sub(nameRaw, 1, #needleRaw) == needleRaw)
            or string.sub(nameNorm, 1, #needleNorm) == needleNorm
        local displayPrefix = (needleRaw ~= "" and string.sub(displayRaw, 1, #needleRaw) == needleRaw)
            or string.sub(displayNorm, 1, #needleNorm) == needleNorm

        if namePrefix or displayPrefix then
            prefixCandidates[#prefixCandidates + 1] = player.UserId
        end
    end

    if exactNameUserId then return exactNameUserId end
    if exactDisplayCount == 1 then return exactDisplayUserId end
    if #prefixCandidates > 0 then return prefixCandidates[1] end
    if exactDisplayUserId then return exactDisplayUserId end

    return nil
end

function Common:resolveUserToId(userInput)
    if userInput == nil then return nil end
    if type(userInput) == "number" then return math.floor(userInput) end
    if type(userInput) ~= "string" then return nil end

    local trimmed = userInput:gsub("^%s+",""):gsub("%s+$","")
    if trimmed == "" then return nil end

    local numeric = tonumber(trimmed)
    if numeric then return math.floor(numeric) end

    local username = trimmed:gsub("^@", "")
    if username == "" then return nil end

    local cacheKey = normalizeForLookup(username)
    if cacheKey == "" then return nil end

    local cachedUserId = self:cacheGetTimed(
        self.resolvedUserIdCache,
        self.resolvedUserIdCacheTime,
        cacheKey,
        RESOLVED_USERID_TTL_SECONDS
    )
    if cachedUserId then return cachedUserId end

    local inServer = self:findUserIdInServerByNameOrDisplay(username)
    if inServer then
        return self:cacheSetTimed(
            self.resolvedUserIdCache,
            self.resolvedUserIdCacheTime,
            cacheKey,
            inServer,
            CACHE_MAX_ENTRIES.resolvedUserId
        )
    end

    local ok, uid = pcall(function() return Players:GetUserIdFromNameAsync(username) end)
    if ok and uid then
        return self:cacheSetTimed(
            self.resolvedUserIdCache,
            self.resolvedUserIdCacheTime,
            cacheKey,
            uid,
            CACHE_MAX_ENTRIES.resolvedUserId
        )
    end

    return nil
end

function Common:getCharacterAppearanceModel(userId)
    local entry = self:cacheGetEntry(self.appearanceModelCache, userId, AVATAR_CACHE_TTL_SECONDS, function(expired)
        if expired and expired.model then
            pcall(function() expired.model:Destroy() end)
        end
    end)

    if entry and entry.model then
        local okClone, clone = pcall(function() return entry.model:Clone() end)
        if okClone and clone then return clone end
    end

    if self.pendingAppearanceModel[userId] then
        waitForPending(self.pendingAppearanceModel, userId, FETCH_WAIT_TIMEOUT_SECONDS)
        local waitedEntry = self:cacheGetEntry(self.appearanceModelCache, userId, AVATAR_CACHE_TTL_SECONDS)
        if waitedEntry and waitedEntry.model then
            local okClone, clone = pcall(function() return waitedEntry.model:Clone() end)
            if okClone and clone then return clone end
        end
    end

    self.pendingAppearanceModel[userId] = true

    local ok, model = false, nil
    for attempt = 1, 2 do
        local okAttempt, result = pcall(function() return Players:GetCharacterAppearanceAsync(userId) end)
        if okAttempt and result then
            ok, model = true, result
            break
        end
        if attempt == 1 then task.wait(0.15) end
    end

    self.pendingAppearanceModel[userId] = nil

    if not (ok and model) then
        return nil
    end

    local okClone, stored = pcall(function() return model:Clone() end)
    if okClone and stored then
        local prev = self.appearanceModelCache[userId]
        if prev and prev.model then pcall(function() prev.model:Destroy() end) end

        self:cacheSetEntry(
            self.appearanceModelCache,
            userId,
            { model = stored, timestamp = os.clock() },
            CACHE_MAX_ENTRIES.appearanceModel,
            function(_, oldEntry)
                if oldEntry and oldEntry.model then
                    pcall(function() oldEntry.model:Destroy() end)
                end
            end
        )
    end

    return model
end

function Common:getTargetDescriptionCached(userId)
    local entry = self:cacheGetEntry(self.descriptionCache, userId, AVATAR_CACHE_TTL_SECONDS, function(expired)
        if expired and expired.desc then
            pcall(function() expired.desc:Destroy() end)
        end
    end)

    if entry and entry.desc then
        local okClone, clone = pcall(function() return entry.desc:Clone() end)
        if okClone and clone then return clone end
    end

    if self.pendingDescription[userId] then
        waitForPending(self.pendingDescription, userId, FETCH_WAIT_TIMEOUT_SECONDS)
        local waitedEntry = self:cacheGetEntry(self.descriptionCache, userId, AVATAR_CACHE_TTL_SECONDS)
        if waitedEntry and waitedEntry.desc then
            local okClone, clone = pcall(function() return waitedEntry.desc:Clone() end)
            if okClone and clone then return clone end
        end
    end

    self.pendingDescription[userId] = true

    local okDesc, desc = pcall(function() return Players:GetHumanoidDescriptionFromUserId(userId) end)
    if not okDesc or not desc then
        self.pendingDescription[userId] = nil
        return nil
    end

    local okStore, stored = pcall(function() return desc:Clone() end)
    if okStore and stored then
        local prev = self.descriptionCache[userId]
        if prev and prev.desc then pcall(function() prev.desc:Destroy() end) end

        self:cacheSetEntry(
            self.descriptionCache,
            userId,
            { desc = stored, timestamp = os.clock() },
            CACHE_MAX_ENTRIES.description,
            function(_, oldEntry)
                if oldEntry and oldEntry.desc then
                    pcall(function() oldEntry.desc:Destroy() end)
                end
            end
        )
    end

    local okRet, ret = pcall(function() return desc:Clone() end)
    self.pendingDescription[userId] = nil
    return (okRet and ret) or desc
end

function Common:getCharacterAppearanceInfoCached(userId)
    local entry = self:cacheGetEntry(self.appearanceInfoCache, userId, AVATAR_CACHE_TTL_SECONDS)
    if entry and entry.info then return entry.info end

    if self.pendingAppearanceInfo[userId] then
        waitForPending(self.pendingAppearanceInfo, userId, FETCH_WAIT_TIMEOUT_SECONDS)
        local waitedEntry = self:cacheGetEntry(self.appearanceInfoCache, userId, AVATAR_CACHE_TTL_SECONDS)
        if waitedEntry and waitedEntry.info then
            return waitedEntry.info
        end
    end

    self.pendingAppearanceInfo[userId] = true

    local ok, info = pcall(function() return Players:GetCharacterAppearanceInfoAsync(userId) end)
    if ok and info then
        self:cacheSetEntry(
            self.appearanceInfoCache,
            userId,
            { info = info, timestamp = os.clock() },
            CACHE_MAX_ENTRIES.appearanceInfo
        )
        self.pendingAppearanceInfo[userId] = nil
        return info
    end

    self.pendingAppearanceInfo[userId] = nil

    return nil
end

function Common:resolveFaceFromAssetId(assetId, userId)
    local assetKey = tostring(assetId)
    local cachedByAsset = self:cacheGetTimed(
        self.faceAssetTextureCache,
        self.faceAssetTextureCacheTime,
        assetKey,
        AVATAR_CACHE_TTL_SECONDS
    )
    if cachedByAsset ~= nil then
        return self:cacheSetTimed(
            self.faceTextureCache,
            self.faceTextureCacheTime,
            userId,
            cachedByAsset,
            CACHE_MAX_ENTRIES.faceTexture
        )
    end

    if self.pendingFaceAsset[assetKey] then
        waitForPending(self.pendingFaceAsset, assetKey, FETCH_WAIT_TIMEOUT_SECONDS)
        local waitedByAsset = self:cacheGetTimed(
            self.faceAssetTextureCache,
            self.faceAssetTextureCacheTime,
            assetKey,
            AVATAR_CACHE_TTL_SECONDS
        )
        if waitedByAsset ~= nil then
            return self:cacheSetTimed(
                self.faceTextureCache,
                self.faceTextureCacheTime,
                userId,
                waitedByAsset,
                CACHE_MAX_ENTRIES.faceTexture
            )
        end
    end

    self.pendingFaceAsset[assetKey] = true

    local okAsset, assetModel = pcall(function() return InsertService:LoadAsset(assetId) end)
    if okAsset and assetModel then
        local foundTexture = nil
        for _, inst in ipairs(assetModel:GetDescendants()) do
            if inst:IsA("Decal") and inst.Texture ~= "" then
                foundTexture = inst.Texture
                break
            end
        end
        assetModel:Destroy()
        if foundTexture then
            self:cacheSetTimed(
                self.faceAssetTextureCache,
                self.faceAssetTextureCacheTime,
                assetKey,
                foundTexture,
                CACHE_MAX_ENTRIES.faceAssetTexture
            )
            self.pendingFaceAsset[assetKey] = nil
            return self:cacheSetTimed(
                self.faceTextureCache,
                self.faceTextureCacheTime,
                userId,
                foundTexture,
                CACHE_MAX_ENTRIES.faceTexture
            )
        end
    end

    local fallback = "rbxassetid://" .. tostring(assetId)
    self:cacheSetTimed(
        self.faceAssetTextureCache,
        self.faceAssetTextureCacheTime,
        assetKey,
        fallback,
        CACHE_MAX_ENTRIES.faceAssetTexture
    )
    self.pendingFaceAsset[assetKey] = nil

    return self:cacheSetTimed(
        self.faceTextureCache,
        self.faceTextureCacheTime,
        userId,
        fallback,
        CACHE_MAX_ENTRIES.faceTexture
    )
end

function Common:resolveFaceTexture(userId, appearanceModel, targetDesc)
    local cached = self:cacheGetTimed(self.faceTextureCache, self.faceTextureCacheTime, userId, AVATAR_CACHE_TTL_SECONDS)
    if cached ~= nil then
        if cached == NO_FACE_TOKEN then return nil, "unknown" end
        return cached, "texture"
    end

    local appearanceHead = appearanceModel and appearanceModel:FindFirstChild("Head")

    -- Some avatar loaders attach decals a few frames later. Give it a short
    -- window before concluding there is no direct face texture.
    local direct = nil
    for _ = 1, 4 do
        direct = firstDecalTextureFromHead(appearanceHead)
        if direct then break end
        task.wait(0.05)
    end
    if direct then
        local tex = self:cacheSetTimed(self.faceTextureCache, self.faceTextureCacheTime, userId, direct, CACHE_MAX_ENTRIES.faceTexture)
        return tex, "texture"
    end

    if targetDesc and targetDesc.Face ~= nil then
        if targetDesc.Face == 0 then
            -- Do not cache faceless immediately here. Dynamic heads and some
            -- custom heads may present face visuals without a Face asset id.
            -- We only cache faceless once all probes are exhausted.
        else
            local tex = self:resolveFaceFromAssetId(targetDesc.Face, userId)
            if tex and tex ~= "" then
                return tex, "texture"
            end
        end
    end

    local info = self:getCharacterAppearanceInfoCached(userId)
    if info and info.assets then
        local foundFaceAsset = false
        for _, asset in ipairs(info.assets) do
            if asset.assetType and asset.assetType.id == 18 and asset.id then
                foundFaceAsset = true
                local tex = self:resolveFaceFromAssetId(asset.id, userId)
                if tex and tex ~= "" then
                    return tex, "texture"
                end
            end
        end
        if foundFaceAsset then
            return nil, "unknown"
        end
    end

    -- For modern head-based faces we cannot reliably infer faceless here.
    -- Return unknown and preserve whatever ApplyDescription produced.
    return nil, "unknown"
end

return Common
