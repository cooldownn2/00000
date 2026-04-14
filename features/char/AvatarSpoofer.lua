local Players = game:GetService("Players")

local AvatarSpoofer = {}
AvatarSpoofer.__index = AvatarSpoofer

local DESC_TTL_SECONDS = 60
local RESPAWN_RETRY_DELAYS = { 0.2, 0.45, 0.8 }

local SCALE_FIELDS = {
    "HeightScale", "WidthScale", "DepthScale",
    "HeadScale", "BodyTypeScale", "ProportionScale",
}

local STRIP_CLASS_SET = {
    Accessory = true,
    Hat = true,
    Shirt = true,
    Pants = true,
    ShirtGraphic = true,
    BodyColors = true,
    CharacterMesh = true,
}

local STRIP_NESTED_CLASS_SET = {
    Accessory = true,
    Hat = true,
    SpecialMesh = true,
    SurfaceAppearance = true,
    Decal = true,
}

local function cloneDescription(desc)
    if not desc then return nil end
    local ok, clone = pcall(function() return desc:Clone() end)
    return ok and clone or nil
end

local function trimTarget(raw)
    if raw == nil then return "" end
    return tostring(raw):gsub("^%s+", ""):gsub("%s+$", "")
end

local function stripAppearance(character)
    if not character then return end

    for _, inst in ipairs(character:GetChildren()) do
        if STRIP_CLASS_SET[inst.ClassName] then
            pcall(function() inst:Destroy() end)
        elseif inst:IsA("BasePart") then
            for _, child in ipairs(inst:GetChildren()) do
                if STRIP_NESTED_CLASS_SET[child.ClassName] then
                    pcall(function() child:Destroy() end)
                end
            end
        end
    end
end

local function applyDesc(humanoid, desc)
    if not humanoid or not desc then return false end

    if humanoid.ApplyDescriptionClientServer then
        local ok = pcall(function() humanoid:ApplyDescriptionClientServer(desc) end)
        if ok then return true end
    end

    return pcall(function() humanoid:ApplyDescription(desc) end)
end

function AvatarSpoofer.new(deps)
    local self = setmetatable({}, AvatarSpoofer)

    self.shared = deps.shared
    self.localPlayer = deps.localPlayer

    self.active = true
    self.applySerial = 0

    self.targetInput = nil
    self.targetUserId = nil
    self.currentUserId = nil
    self.lastAppliedCharacter = nil
    self.lastAppliedAt = 0

    self.descCache = {}
    self.originalDescByCharacter = setmetatable({}, { __mode = "k" })

    return self
end

function AvatarSpoofer:isApplyStillCurrent(applyToken)
    return self.active and applyToken == self.applySerial
end

function AvatarSpoofer:cleanupDescCache()
    local now = os.clock()
    local count = 0

    for key, entry in pairs(self.descCache) do
        count = count + 1
        if type(entry) ~= "table" or (now - (entry.timestamp or 0)) > DESC_TTL_SECONDS then
            self.descCache[key] = nil
            count = count - 1
        end
    end

    if count <= 64 then return end

    while count > 64 do
        local oldestKey, oldestTs = nil, math.huge
        for key, entry in pairs(self.descCache) do
            local ts = (type(entry) == "table" and entry.timestamp) or 0
            if ts < oldestTs then
                oldestTs = ts
                oldestKey = key
            end
        end
        if not oldestKey then break end
        self.descCache[oldestKey] = nil
        count = count - 1
    end
end

function AvatarSpoofer:getDescription(userId)
    local cacheKey = tostring(userId)
    local cached = self.descCache[cacheKey]
    if cached and (os.clock() - (cached.timestamp or 0)) <= DESC_TTL_SECONDS then
        local clone = cloneDescription(cached.desc)
        if clone then return clone end
    end

    local desc = nil
    if self.shared and type(self.shared.getTargetDescriptionCached) == "function" then
        desc = self.shared:getTargetDescriptionCached(userId)
    end

    if not desc then
        local ok, fetched = pcall(Players.GetHumanoidDescriptionFromUserIdAsync, Players, userId)
        if ok and fetched then desc = fetched end
    end

    if not desc then return nil end

    local stored = cloneDescription(desc) or desc
    self.descCache[cacheKey] = {
        desc = stored,
        timestamp = os.clock(),
    }
    self:cleanupDescCache()

    return cloneDescription(stored) or desc
end

function AvatarSpoofer:captureOriginalDescription(character)
    if not character or self.originalDescByCharacter[character] then return end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    local ok, desc = pcall(function() return humanoid:GetAppliedDescription() end)
    if not ok or not desc then return end

    local clone = cloneDescription(desc)
    if clone then
        self.originalDescByCharacter[character] = clone
    end
end

function AvatarSpoofer:restoreOriginalDescription(character)
    if not character then return false end

    local snap = self.originalDescByCharacter[character]
    if not snap then return false end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end

    local desc = cloneDescription(snap) or snap
    local ok = applyDesc(humanoid, desc)
    self.originalDescByCharacter[character] = nil
    return ok
end

function AvatarSpoofer:buildApplyDescription(humanoid, targetDesc)
    local nextDesc = cloneDescription(targetDesc) or targetDesc

    local okCurrent, currentDesc = pcall(function() return humanoid:GetAppliedDescription() end)
    if okCurrent and currentDesc then
        for _, scaleField in ipairs(SCALE_FIELDS) do
            nextDesc[scaleField] = currentDesc[scaleField]
        end
    end

    return nextDesc
end

function AvatarSpoofer:applyAppearance(userId, char, applyToken)
    if not self:isApplyStillCurrent(applyToken) then return false end
    if not char or not char.Parent then return false end

    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end

    self:captureOriginalDescription(char)

    local targetDesc = self:getDescription(userId)
    if not targetDesc then return false end

    local applyDescNow = self:buildApplyDescription(humanoid, targetDesc)

    stripAppearance(char)

    local applied = applyDesc(humanoid, applyDescNow)
    applyDesc(humanoid, applyDescNow)

    task.delay(0.12, function()
        if not self:isApplyStillCurrent(applyToken) then return end
        if not char.Parent then return end

        local hum2 = char:FindFirstChildOfClass("Humanoid")
        if not hum2 then return end

        local desc2 = self:buildApplyDescription(hum2, targetDesc)
        applyDesc(hum2, desc2)
    end)

    if applied then
        self.currentUserId = userId
        self.targetUserId = userId
        self.lastAppliedCharacter = char
        self.lastAppliedAt = os.clock()
    end

    return applied
end

function AvatarSpoofer:apply(userId)
    if not self.active then return false end

    local uid = tonumber(userId)
    if not uid then return false end

    local char = self.localPlayer and self.localPlayer.Character
    if not char then return false end

    self.applySerial = self.applySerial + 1
    local applyToken = self.applySerial

    self.targetUserId = uid
    self.currentUserId = uid

    task.spawn(function()
        self:applyAppearance(uid, char, applyToken)
    end)

    return true
end

function AvatarSpoofer:setTarget(target)
    self.targetInput = target

    local uid = nil
    if type(target) == "number" then
        uid = math.floor(target)
    else
        local text = trimTarget(target)
        uid = tonumber(text)
        if not uid and self.shared and type(self.shared.resolveUserToId) == "function" then
            uid = self.shared:resolveUserToId(text)
        end
    end

    if not uid then return false end

    if self.currentUserId and uid ~= self.currentUserId then
        self.currentUserId = nil
    end

    return self:apply(uid)
end

function AvatarSpoofer:reapply()
    local uid = nil
    if self.targetInput ~= nil then
        if type(self.targetInput) == "number" then
            uid = math.floor(self.targetInput)
        else
            local text = trimTarget(self.targetInput)
            uid = tonumber(text)
            if not uid and self.shared and type(self.shared.resolveUserToId) == "function" then
                uid = self.shared:resolveUserToId(text)
            end
        end
    end

    uid = uid or self.currentUserId or self.targetUserId
    if not uid then return false end

    return self:apply(uid)
end

function AvatarSpoofer:onCharacterAdded(char)
    if not self.active then return end

    self.applySerial = self.applySerial + 1
    local applyToken = self.applySerial

    self.lastAppliedCharacter = nil

    local uid = nil
    if self.targetInput ~= nil then
        if type(self.targetInput) == "number" then
            uid = math.floor(self.targetInput)
        else
            local text = trimTarget(self.targetInput)
            uid = tonumber(text)
            if not uid and self.shared and type(self.shared.resolveUserToId) == "function" then
                uid = self.shared:resolveUserToId(text)
            end
        end
    end
    uid = uid or self.currentUserId or self.targetUserId
    if not uid then return end

    task.spawn(function()
        local hum = char:WaitForChild("Humanoid", 10)
        if not hum then return end

        for _, delayTime in ipairs(RESPAWN_RETRY_DELAYS) do
            if not self:isApplyStillCurrent(applyToken) then return end
            if not char.Parent then return end

            task.wait(delayTime)

            if not self:isApplyStillCurrent(applyToken) then return end
            if not char.Parent then return end

            if self:applyAppearance(uid, char, applyToken) then
                break
            end
        end
    end)
end

function AvatarSpoofer:setEnabled(enabled)
    enabled = enabled == true
    if self.active == enabled then return end

    self.active = enabled
    self.applySerial = self.applySerial + 1

    local char = self.localPlayer and self.localPlayer.Character

    if not enabled then
        self:restoreOriginalDescription(char)
        self.lastAppliedCharacter = nil
        return
    end

    if char and char.Parent then
        task.defer(function()
            if self.active then
                self:reapply()
            end
        end)
    end
end

function AvatarSpoofer:cleanup()
    self.active = false
    self.applySerial = self.applySerial + 1

    local char = self.localPlayer and self.localPlayer.Character
    self:restoreOriginalDescription(char)

    self.targetInput = nil
    self.targetUserId = nil
    self.currentUserId = nil
    self.lastAppliedCharacter = nil
    self.lastAppliedAt = 0

    for key in pairs(self.descCache) do
        self.descCache[key] = nil
    end
    for character in pairs(self.originalDescByCharacter) do
        self.originalDescByCharacter[character] = nil
    end
end

return AvatarSpoofer
