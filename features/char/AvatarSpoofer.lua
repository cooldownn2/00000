local Players = game:GetService("Players")

local AvatarSpoofer = {}
AvatarSpoofer.__index = AvatarSpoofer

local DESC_TTL_SECONDS = 60
local INITIAL_APPLY_DELAY = 0.50

local SCALE_FIELDS = {
    "HeightScale", "WidthScale", "DepthScale",
    "HeadScale", "BodyTypeScale", "ProportionScale",
}

local STRIP_CLASSES = {
    Accessory = true,
    Shirt = true,
    Pants = true,
    ShirtGraphic = true,
    BodyColors = true,
    SpecialMesh = true,
    CharacterMesh = true,
}

local function trimTarget(raw)
    if raw == nil then return "" end
    return tostring(raw):gsub("^%s+", ""):gsub("%s+$", "")
end

local function cloneDescription(desc)
    if not desc then return nil end
    local ok, clone = pcall(function() return desc:Clone() end)
    return ok and clone or nil
end

local function stripAppearance(character)
    if not character then return end

    for _, inst in ipairs(character:GetChildren()) do
        if STRIP_CLASSES[inst.ClassName] then
            pcall(function() inst:Destroy() end)
        elseif inst:IsA("BasePart") then
            for _, child in ipairs(inst:GetChildren()) do
                if child:IsA("Accessory") or child:IsA("SpecialMesh") then
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

    self.localPlayer = deps.localPlayer or Players.LocalPlayer

    self.active = true

    self.targetInput = nil
    self.targetUserId = nil
    self.currentUserId = nil
    self.lastAppliedCharacter = nil
    self.lastAppliedAt = 0

    self.descCache = {}
    self.snapshots = setmetatable({}, { __mode = "k" })

    return self
end

function AvatarSpoofer:fetchDesc(userId)
    local key = tostring(userId)
    local entry = self.descCache[key]
    if entry and (os.clock() - (entry.t or 0)) < DESC_TTL_SECONDS then
        return entry.v
    end

    local ok, desc = pcall(Players.GetHumanoidDescriptionFromUserIdAsync, Players, userId)
    if ok and desc then
        self.descCache[key] = { v = desc, t = os.clock() }
        return desc
    end

    return nil
end

function AvatarSpoofer:resolveUserToId(userInput)
    if userInput == nil then return nil end
    if type(userInput) == "number" then return math.floor(userInput) end

    local text = trimTarget(userInput)
    if text == "" then return nil end

    local numeric = tonumber(text)
    if numeric then return math.floor(numeric) end

    local username = text:gsub("^@", "")
    if username == "" then return nil end
    local usernameLower = string.lower(username)

    for _, player in ipairs(Players:GetPlayers()) do
        if string.lower(player.Name) == usernameLower then
            return player.UserId
        end
    end

    local ok, uid = pcall(function()
        return Players:GetUserIdFromNameAsync(username)
    end)
    if ok and type(uid) == "number" then
        return math.floor(uid)
    end

    return nil
end

function AvatarSpoofer:captureSnapshot(character)
    if not character or self.snapshots[character] then return end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    local ok, desc = pcall(function() return humanoid:GetAppliedDescription() end)
    if not ok or not desc then return end

    self.snapshots[character] = cloneDescription(desc) or desc
end

function AvatarSpoofer:restoreOriginalDescription(character)
    if not character then return false end

    local snapshot = self.snapshots[character]
    if not snapshot then return false end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end

    local desc = cloneDescription(snapshot) or snapshot
    local ok = applyDesc(humanoid, desc)
    self.snapshots[character] = nil
    return ok
end

function AvatarSpoofer:applyAppearance(userId, character)
    if not character or not character.Parent then return false end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end

    self:captureSnapshot(character)

    local fetched = self:fetchDesc(userId)
    if not fetched then return false end

    local desc = cloneDescription(fetched)
    if not desc then return false end

    local okCurrent, current = pcall(function() return humanoid:GetAppliedDescription() end)
    if okCurrent and current then
        for _, field in ipairs(SCALE_FIELDS) do
            desc[field] = current[field]
        end
    end

    stripAppearance(character)

    local applied = applyDesc(humanoid, desc)

    task.delay(0.12, function()
        if not self.active then return end
        if not character.Parent then return end

        local hum2 = character:FindFirstChildOfClass("Humanoid")
        if hum2 then
            applyDesc(hum2, desc)
        end
    end)

    if applied then
        self.currentUserId = userId
        self.targetUserId = userId
        self.lastAppliedCharacter = character
        self.lastAppliedAt = os.clock()
    end

    return applied
end

function AvatarSpoofer:apply(userId)
    if not self.active then return false end

    local uid = tonumber(userId)
    if not uid then return false end

    self.targetUserId = uid
    self.currentUserId = uid

    task.spawn(function()
        self:fetchDesc(uid)
        local char = self.localPlayer and self.localPlayer.Character
        if not char then return end
        if not self.active then return end
        if self.targetUserId ~= uid then return end
        self:applyAppearance(uid, char)
    end)

    return true
end

function AvatarSpoofer:setTarget(target)
    self.targetInput = target

    local uid = self:resolveUserToId(target)
    if not uid then return false end

    return self:apply(uid)
end

function AvatarSpoofer:reapply()
    local uid = nil
    if self.targetInput ~= nil then
        uid = self:resolveUserToId(self.targetInput)
    end
    uid = uid or self.currentUserId or self.targetUserId
    if not uid then return false end

    return self:apply(uid)
end

function AvatarSpoofer:onCharacterAdded(character)
    if not self.active then return end

    local uid = nil
    if self.targetInput ~= nil then
        uid = self:resolveUserToId(self.targetInput)
    end
    uid = uid or self.currentUserId or self.targetUserId
    if not uid then return end

    self.lastAppliedCharacter = nil

    task.spawn(function()
        local hum = character:WaitForChild("Humanoid", 10)
        if not hum then return end

        self:fetchDesc(uid)
        task.wait(INITIAL_APPLY_DELAY)

        if not self.active then return end
        if not character.Parent then return end
        if self.targetUserId ~= uid then return end
        self:applyAppearance(uid, character)
    end)
end

function AvatarSpoofer:setEnabled(enabled)
    enabled = enabled == true
    if self.active == enabled then return end

    self.active = enabled

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
    for character in pairs(self.snapshots) do
        self.snapshots[character] = nil
    end
end

return AvatarSpoofer
