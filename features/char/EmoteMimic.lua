local Players = game:GetService("Players")

local EmoteMimic = {}
EmoteMimic.__index = EmoteMimic

local ANIMATION_FIELDS = {
    "RunAnimation",
    "WalkAnimation",
    "IdleAnimation",
    "JumpAnimation",
    "FallAnimation",
    "ClimbAnimation",
    "SwimAnimation",
}


local function hasAnyTableEntries(value)
    return type(value) == "table" and next(value) ~= nil
end

local function hasUsableEmotePayload(emoteData)
    if type(emoteData) ~= "table" then return false end
    return hasAnyTableEntries(emoteData.emotes) or hasAnyTableEntries(emoteData.equipped)
end

local function stableKeySort(a, b)
    local ta, tb = typeof(a), typeof(b)
    if ta ~= tb then
        return ta < tb
    end
    return tostring(a) < tostring(b)
end

local function stableSerialize(value, out)
    out = out or {}
    local valueType = typeof(value)

    if valueType == "table" then
        out[#out + 1] = "{"
        local keys = {}
        for k in pairs(value) do keys[#keys + 1] = k end
        table.sort(keys, stableKeySort)
        for i = 1, #keys do
            local k = keys[i]
            out[#out + 1] = "["
            stableSerialize(k, out)
            out[#out + 1] = "]="
            stableSerialize(value[k], out)
            out[#out + 1] = ";"
        end
        out[#out + 1] = "}"
        return out
    end

    out[#out + 1] = valueType
    out[#out + 1] = ":"
    out[#out + 1] = tostring(value)
    return out
end


function EmoteMimic.new(deps)
    local self = setmetatable({}, EmoteMimic)

    self.shared = deps.shared
    self.localPlayer = deps.localPlayer

    self.active = true
    self.targetInput = nil
    self.currentUserId = nil
    self.applyToken = 0

    self.cacheTtlSeconds = 20
    self.minReapplyIntervalSeconds = 0.35

    self.lastAppliedCharacter = nil
    self.lastAppliedSignature = nil
    self.lastAppliedAt = 0

    return self
end

function EmoteMimic:buildEmoteSignature(emoteData)
    if not emoteData then return nil end
    local payload = {
        emotes = emoteData.emotes or {},
        equipped = emoteData.equipped or {},
    }
    return table.concat(stableSerialize(payload, {}), "")
end

function EmoteMimic:getEmoteDataFromDescription(desc)
    if not desc then return nil end

    local emotes = nil
    local equipped = nil

    if type(desc.GetEmotes) == "function" then
        local ok, value = pcall(function() return desc:GetEmotes() end)
        if ok and type(value) == "table" then emotes = self.shared:deepCopyTable(value) end
    end

    if type(desc.GetEquippedEmotes) == "function" then
        local ok, value = pcall(function() return desc:GetEquippedEmotes() end)
        if ok and type(value) == "table" then equipped = self.shared:deepCopyTable(value) end
    end

    if emotes == nil then
        local ok, value = pcall(function() return desc.Emotes end)
        if ok and type(value) == "table" then emotes = self.shared:deepCopyTable(value) end
    end

    if equipped == nil then
        local ok, value = pcall(function() return desc.EquippedEmotes end)
        if ok and type(value) == "table" then equipped = self.shared:deepCopyTable(value) end
    end

    if type(emotes) ~= "table" then emotes = {} end
    if type(equipped) ~= "table" then equipped = {} end

    return { emotes = emotes, equipped = equipped }
end

function EmoteMimic:getEmoteDataFromLivePlayer(userId)
    local okPlayer, player = pcall(function() return Players:GetPlayerByUserId(userId) end)
    if not okPlayer or not player then return nil end

    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return nil end

    local okDesc, desc = pcall(function() return humanoid:GetAppliedDescription() end)
    if not okDesc or not desc then return nil end

    return self:getEmoteDataFromDescription(desc)
end

function EmoteMimic:getEmoteDataFromUserId(userId)
    local entry = self.shared:cacheGetEntry(self.shared.emoteDataCache, userId, self.cacheTtlSeconds)
    if entry and entry.data then
        return {
            emotes = self.shared:deepCopyTable(entry.data.emotes),
            equipped = self.shared:deepCopyTable(entry.data.equipped),
        }
    end

    local data = self:getEmoteDataFromLivePlayer(userId)
    if not data then
        local desc = self.shared:getTargetDescriptionCached(userId)
        if desc then
            data = self:getEmoteDataFromDescription(desc)
        end
    end

    if not data or not hasUsableEmotePayload(data) then return nil end

    self.shared:cacheSetEntry(
        self.shared.emoteDataCache,
        userId,
        { data = data, timestamp = os.clock() },
        self.shared:getCacheMaxEntries("emoteData")
    )

    return data
end

function EmoteMimic:applyEmotesToHumanoid(humanoid, emoteData)
    if not humanoid or not emoteData then return false end
    if not hasUsableEmotePayload(emoteData) then return false end

    local character = humanoid.Parent
    local colorSnapshot = self.shared:snapshotCharacterColors(character)
    local scaleSnapshot = self.shared:getCurrentScaleValues(humanoid)

    local okDesc, currentDesc = pcall(function() return humanoid:GetAppliedDescription() end)
    if not okDesc or not currentDesc then
        self.shared:destroyColorSnapshot(colorSnapshot)
        return false
    end

    local setAny = false
    if type(currentDesc.SetEmotes) == "function" then
        local ok = pcall(function() currentDesc:SetEmotes(self.shared:deepCopyTable(emoteData.emotes)) end)
        setAny = setAny or ok
    else
        local ok = pcall(function() currentDesc.Emotes = self.shared:deepCopyTable(emoteData.emotes) end)
        setAny = setAny or ok
    end

    if type(currentDesc.SetEquippedEmotes) == "function" then
        local ok = pcall(function() currentDesc:SetEquippedEmotes(self.shared:deepCopyTable(emoteData.equipped)) end)
        setAny = setAny or ok
    else
        local ok = pcall(function() currentDesc.EquippedEmotes = self.shared:deepCopyTable(emoteData.equipped) end)
        setAny = setAny or ok
    end

    if not setAny then
        self.shared:destroyColorSnapshot(colorSnapshot)
        return false
    end

    self.shared:applyScaleValuesToDescription(currentDesc, scaleSnapshot)

    for _, fieldName in ipairs(ANIMATION_FIELDS) do
        currentDesc[fieldName] = 0
    end

    if humanoid.ApplyDescriptionClientServer then
        local okCS = pcall(function() humanoid:ApplyDescriptionClientServer(currentDesc) end)
        if okCS then
            self.shared:restoreCharacterColorsSafely(character, colorSnapshot)
            return true
        end
    end

    local okApply = pcall(function() humanoid:ApplyDescription(currentDesc) end)
    self.shared:restoreCharacterColorsSafely(character, colorSnapshot)
    return okApply
end

function EmoteMimic:mimicFromUserId(userId)
    if not self.active then return false end

    local numericUserId = tonumber(userId)
    if not numericUserId then return false end

    local character = self.localPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end

    self.applyToken = self.applyToken + 1
    local applyToken = self.applyToken

    local emoteData = self:getEmoteDataFromUserId(numericUserId)
    if not emoteData then return false end
    if applyToken ~= self.applyToken or not self.active then return false end

    local signature = self:buildEmoteSignature(emoteData)
    if signature and self.currentUserId == numericUserId and self.lastAppliedCharacter == character then
        local age = os.clock() - (self.lastAppliedAt or 0)
        if self.lastAppliedSignature == signature and age <= self.minReapplyIntervalSeconds then
            return true
        end
    end

    local ok = false
    for attempt = 1, 3 do
        ok = self:applyEmotesToHumanoid(humanoid, emoteData)
        if ok then break end
        if attempt < 3 then task.wait(0.12) end
    end

    if ok then
        self.currentUserId = numericUserId
        self.lastAppliedCharacter = character
        self.lastAppliedSignature = signature
        self.lastAppliedAt = os.clock()
    end

    return ok
end

function EmoteMimic:mimicFromTarget(target)
    if not self.active then return false end

    local userId = self.shared:resolveUserToId(target)
    if not userId then return false end

    self.targetInput = target
    if self.currentUserId and tonumber(self.currentUserId) ~= tonumber(userId) then
        self.currentUserId = nil
    end
    return self:mimicFromUserId(userId)
end

function EmoteMimic:reapply()
    if self.targetInput ~= nil then
        return self:mimicFromTarget(self.targetInput)
    end
    if self.currentUserId then
        return self:mimicFromUserId(self.currentUserId)
    end
    return false
end

function EmoteMimic:onCharacterAdded(char)
    if not self.active then return end

    self.lastAppliedCharacter = nil
    self.lastAppliedSignature = nil
    self.lastAppliedAt = 0

    self.applyToken = self.applyToken + 1
    local respawnToken = self.applyToken

    local hum = char:WaitForChild("Humanoid", 10)
    if not hum or respawnToken ~= self.applyToken or not self.active then return end

    task.spawn(function()
        local delays = { 0.2, 0.45, 0.8 }
        for _, delayTime in ipairs(delays) do
            if not self.active or respawnToken ~= self.applyToken or not char.Parent then return end
            task.wait(delayTime)
            if not self.active or respawnToken ~= self.applyToken or not char.Parent then return end
            if self:reapply() then break end
        end

        task.wait(0.9)
        if not self.active or respawnToken ~= self.applyToken or not char.Parent then return end
        self:reapply()
    end)
end

function EmoteMimic:setEnabled(enabled)
    enabled = enabled == true
    if self.active == enabled then return end

    self.active = enabled
    self.applyToken = self.applyToken + 1

    if not enabled then
        self.currentUserId = nil
        self.targetInput = nil
        self.lastAppliedCharacter = nil
        self.lastAppliedSignature = nil
        self.lastAppliedAt = 0
    end
end

function EmoteMimic:cleanup()
    self.active = false
    self.applyToken = self.applyToken + 1
    self.currentUserId = nil
    self.targetInput = nil
    self.lastAppliedCharacter = nil
    self.lastAppliedSignature = nil
    self.lastAppliedAt = 0
end

return EmoteMimic
