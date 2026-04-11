local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")

local UISpoofer = {}
UISpoofer.__index = UISpoofer

local IMAGE_CLASS_SET = {
    ImageLabel = true,
    ImageButton = true,
}

local TEXT_CLASS_SET = {
    TextLabel = true,
    TextButton = true,
    TextBox = true,
}

local NUMERIC_VALUE_CLASS_SET = {
    IntValue = true,
    NumberValue = true,
}

local STRING_VALUE_CLASS_SET = {
    StringValue = true,
}

local NIL_SENTINEL = {}

local function normalizeLower(raw)
    return string.lower(tostring(raw or ""))
end

local function isLikelyUserIdKey(rawKey)
    local key = normalizeLower(rawKey)
    if key == "" then return false end

    if key == "userid" or key == "playeruserid" or key == "playerid"
        or key == "targetuserid" or key == "inspectuserid" then
        return true
    end

    if key:find("user", 1, true) and key:find("id", 1, true) and not key:find("asset", 1, true) then
        return true
    end

    if key:find("player", 1, true) and key:find("id", 1, true) then
        return true
    end

    return false
end

local function isLikelyNameKey(rawKey)
    local key = normalizeLower(rawKey)
    if key == "" then return false end

    if key == "username" or key == "displayname" or key == "playername" or key == "targetname" then
        return true
    end

    if key:find("user", 1, true) and key:find("name", 1, true) then
        return true
    end

    if key:find("player", 1, true) and key:find("name", 1, true) then
        return true
    end

    if key:find("display", 1, true) and key:find("name", 1, true) then
        return true
    end

    return false
end

local function isLikelyPlayerObjectKey(rawKey)
    local key = normalizeLower(rawKey)
    if key == "player" or key == "selectedplayer" or key == "targetplayer" or key == "subjectplayer" then
        return true
    end
    return key:find("player", 1, true) ~= nil and not key:find("template", 1, true)
end

local function normalizeTargetText(raw)
    if raw == nil then return "" end
    local text = tostring(raw)
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

local function replacePlain(text, fromText, toText)
    if type(text) ~= "string" then return text, false end
    if type(fromText) ~= "string" or fromText == "" then return text, false end
    if type(toText) ~= "string" then toText = tostring(toText or "") end

    local cursor = 1
    local changed = false
    local out = {}

    while true do
        local i, j = string.find(text, fromText, cursor, true)
        if not i then
            out[#out + 1] = string.sub(text, cursor)
            break
        end

        changed = true
        out[#out + 1] = string.sub(text, cursor, i - 1)
        out[#out + 1] = toText
        cursor = j + 1
    end

    if not changed then return text, false end
    return table.concat(out), true
end

function UISpoofer.new(deps)
    local self = setmetatable({}, UISpoofer)

    self.shared = deps.shared
    self.localPlayer = deps.localPlayer

    self.active = false
    self.targetInput = nil
    self.targetUserId = nil
    self.targetName = nil
    self.targetDisplayName = nil
    self.targetHeadshot = nil
    self.localUserId = self.localPlayer and self.localPlayer.UserId or nil

    self.connections = {}
    self.observedRoots = {}
    self.watchedByInstance = setmetatable({}, { __mode = "k" })
    self.originalByInstance = setmetatable({}, { __mode = "k" })

    return self
end

function UISpoofer:disconnectAll()
    for i = #self.connections, 1, -1 do
        local conn = self.connections[i]
        if conn and conn.Connected then
            conn:Disconnect()
        end
        self.connections[i] = nil
    end
    self.observedRoots = {}
    self.watchedByInstance = setmetatable({}, { __mode = "k" })
end

function UISpoofer:rememberOriginal(instance, key, value)
    if not instance then return end

    local rec = self.originalByInstance[instance]
    if not rec then
        rec = {}
        self.originalByInstance[instance] = rec
    end

    if rec[key] == nil then
        rec[key] = (value == nil) and NIL_SENTINEL or value
    end
end

function UISpoofer:rememberOriginalAttribute(instance, attrName, value)
    if not instance or type(attrName) ~= "string" then return end

    local rec = self.originalByInstance[instance]
    if not rec then
        rec = {}
        self.originalByInstance[instance] = rec
    end

    if type(rec.Attributes) ~= "table" then
        rec.Attributes = {}
    end

    if rec.Attributes[attrName] == nil then
        rec.Attributes[attrName] = value
    end
end

function UISpoofer:restoreAll()
    for instance, rec in pairs(self.originalByInstance) do
        if instance and instance.Parent and rec then
            local className = instance.ClassName
            if rec.Image ~= nil and IMAGE_CLASS_SET[className] then
                local value = (rec.Image == NIL_SENTINEL) and nil or rec.Image
                pcall(function() instance.Image = value end)
            end
            if rec.Text ~= nil and TEXT_CLASS_SET[className] then
                local value = (rec.Text == NIL_SENTINEL) and nil or rec.Text
                pcall(function() instance.Text = value end)
            end
            if rec.Value ~= nil and (NUMERIC_VALUE_CLASS_SET[className] or STRING_VALUE_CLASS_SET[className] or className == "ObjectValue") then
                local value = (rec.Value == NIL_SENTINEL) and nil or rec.Value
                pcall(function() instance.Value = value end)
            end
            if type(rec.Attributes) == "table" then
                for attrName, originalValue in pairs(rec.Attributes) do
                    pcall(function() instance:SetAttribute(attrName, originalValue) end)
                end
            end
        end
    end

    self.originalByInstance = setmetatable({}, { __mode = "k" })
end

function UISpoofer:rewriteImage(rawImage)
    if type(rawImage) ~= "string" or rawImage == "" then return nil end
    if not self.targetUserId then return nil end

    local targetId = tostring(self.targetUserId)
    local rewritten = rawImage
    local changed = false

    local v1, c1 = rewritten:gsub("([?&][iI][dD]=)%d+", "%1" .. targetId)
    if c1 > 0 then
        rewritten = v1
        changed = true
    end

    local v2, c2 = rewritten:gsub("([?&][uU][sS][eE][rR][iI][dD]=)%d+", "%1" .. targetId)
    if c2 > 0 then
        rewritten = v2
        changed = true
    end

    if changed then
        return rewritten
    end

    if rawImage:find("rbxthumb://", 1, true) and rawImage:lower():find("avatar", 1, true) then
        return self.targetHeadshot
    end

    return nil
end

function UISpoofer:rewriteText(rawText)
    if type(rawText) ~= "string" or rawText == "" then return nil end

    local localName = self.localPlayer and self.localPlayer.Name or ""
    local localDisplay = self.localPlayer and self.localPlayer.DisplayName or localName
    local targetName = self.targetName or tostring(self.targetUserId or "")
    local targetDisplay = self.targetDisplayName or targetName

    if targetName == "" then return nil end

    local text = rawText
    local changed = false

    local function apply(fromText, toText)
        local updated, didChange = replacePlain(text, fromText, toText)
        if didChange then
            text = updated
            changed = true
        end
    end

    apply("@" .. localName, "@" .. targetName)
    apply(localDisplay, targetDisplay)
    apply(localName, targetName)

    if not changed then return nil end
    return text
end

function UISpoofer:getTargetPlayerInstance()
    if not self.targetUserId then return nil end
    local ok, player = pcall(function()
        return Players:GetPlayerByUserId(self.targetUserId)
    end)
    if ok then return player end
    return nil
end

function UISpoofer:registerInstanceObservers(instance, watchAttributes)
    if not instance or self.watchedByInstance[instance] then return end

    local className = instance.ClassName
    local watchImage = IMAGE_CLASS_SET[className] == true
    local watchText = TEXT_CLASS_SET[className] == true
    local watchValue = NUMERIC_VALUE_CLASS_SET[className] == true
        or STRING_VALUE_CLASS_SET[className] == true
        or className == "ObjectValue"

    if not watchImage and not watchText and not watchValue and not watchAttributes then
        return
    end

    self.watchedByInstance[instance] = true

    local function scheduleReapply()
        if not self.active then return end
        if not instance.Parent then return end

        task.defer(function()
            if not self.active or not instance.Parent then return end
            self:applyToInstance(instance)
        end)
    end

    if watchImage then
        local ok, conn = pcall(function()
            return instance:GetPropertyChangedSignal("Image"):Connect(scheduleReapply)
        end)
        if ok and conn then
            self.connections[#self.connections + 1] = conn
        end
    end

    if watchText then
        local ok, conn = pcall(function()
            return instance:GetPropertyChangedSignal("Text"):Connect(scheduleReapply)
        end)
        if ok and conn then
            self.connections[#self.connections + 1] = conn
        end
    end

    if watchValue then
        local ok, conn = pcall(function()
            return instance:GetPropertyChangedSignal("Value"):Connect(scheduleReapply)
        end)
        if ok and conn then
            self.connections[#self.connections + 1] = conn
        end
    end

    if watchAttributes then
        local ok, conn = pcall(function()
            return instance.AttributeChanged:Connect(function(attrName)
                if isLikelyUserIdKey(attrName) or isLikelyNameKey(attrName) then
                    scheduleReapply()
                end
            end)
        end)
        if ok and conn then
            self.connections[#self.connections + 1] = conn
        end
    end
end

function UISpoofer:applyToInstance(instance)
    if not self.active or not self.targetUserId then return end
    if not instance or not instance.Parent then return end

    local className = instance.ClassName
    local localUserId = self.localUserId
    local watchAttributes = false

    if IMAGE_CLASS_SET[className] then
        local currentImage = instance.Image
        local rewritten = self:rewriteImage(currentImage)
        if rewritten and rewritten ~= currentImage then
            self:rememberOriginal(instance, "Image", currentImage)
            pcall(function() instance.Image = rewritten end)
        end
    end

    if TEXT_CLASS_SET[className] then
        local currentText = instance.Text
        local rewritten = self:rewriteText(currentText)
        if rewritten and rewritten ~= currentText then
            self:rememberOriginal(instance, "Text", currentText)
            pcall(function() instance.Text = rewritten end)
        end
    end

    if localUserId and NUMERIC_VALUE_CLASS_SET[className] and isLikelyUserIdKey(instance.Name) then
        local currentNumeric = tonumber(instance.Value)
        if currentNumeric and math.floor(currentNumeric) == localUserId and currentNumeric ~= self.targetUserId then
            self:rememberOriginal(instance, "Value", instance.Value)
            pcall(function() instance.Value = self.targetUserId end)
        end
    end

    if STRING_VALUE_CLASS_SET[className] then
        local currentString = tostring(instance.Value or "")

        if localUserId and isLikelyUserIdKey(instance.Name) then
            local localUserIdText = tostring(localUserId)
            local targetUserIdText = tostring(self.targetUserId)
            if currentString == localUserIdText and currentString ~= targetUserIdText then
                self:rememberOriginal(instance, "Value", instance.Value)
                pcall(function() instance.Value = targetUserIdText end)
            end
        elseif isLikelyNameKey(instance.Name) then
            local rewritten = self:rewriteText(currentString)
            if rewritten and rewritten ~= currentString then
                self:rememberOriginal(instance, "Value", instance.Value)
                pcall(function() instance.Value = rewritten end)
            end
        end
    end

    if className == "ObjectValue" and isLikelyPlayerObjectKey(instance.Name) and instance.Value == self.localPlayer then
        local targetPlayer = self:getTargetPlayerInstance()
        if targetPlayer and targetPlayer ~= instance.Value then
            self:rememberOriginal(instance, "Value", instance.Value)
            pcall(function() instance.Value = targetPlayer end)
        end
    end

    local okAttrs, attrs = pcall(function() return instance:GetAttributes() end)
    if okAttrs and type(attrs) == "table" then
        for attrName, attrValue in pairs(attrs) do
            if isLikelyUserIdKey(attrName) then
                watchAttributes = true

                if type(attrValue) == "number" and localUserId and math.floor(attrValue) == localUserId and attrValue ~= self.targetUserId then
                    self:rememberOriginalAttribute(instance, attrName, attrValue)
                    pcall(function() instance:SetAttribute(attrName, self.targetUserId) end)
                elseif type(attrValue) == "string" and localUserId then
                    local localUserIdText = tostring(localUserId)
                    local targetUserIdText = tostring(self.targetUserId)
                    if attrValue == localUserIdText and attrValue ~= targetUserIdText then
                        self:rememberOriginalAttribute(instance, attrName, attrValue)
                        pcall(function() instance:SetAttribute(attrName, targetUserIdText) end)
                    end
                end
            elseif isLikelyNameKey(attrName) then
                watchAttributes = true
                if type(attrValue) == "string" then
                    local rewritten = self:rewriteText(attrValue)
                    if rewritten and rewritten ~= attrValue then
                        self:rememberOriginalAttribute(instance, attrName, attrValue)
                        pcall(function() instance:SetAttribute(attrName, rewritten) end)
                    end
                end
            end
        end
    end

    self:registerInstanceObservers(instance, watchAttributes)
end

function UISpoofer:scanRoot(root)
    if not root then return end

    self:applyToInstance(root)

    local ok, descendants = pcall(function() return root:GetDescendants() end)
    if not ok or not descendants then return end

    for _, inst in ipairs(descendants) do
        self:applyToInstance(inst)
    end
end

function UISpoofer:observeRoot(root)
    if not root then return end
    if self.observedRoots[root] then return end

    self.observedRoots[root] = true
    self:scanRoot(root)

    local ok, conn = pcall(function()
        return root.DescendantAdded:Connect(function(inst)
            if not self.active then return end
            task.defer(function()
                if not self.active then return end
                self:applyToInstance(inst)
            end)
        end)
    end)

    if ok and conn then
        self.connections[#self.connections + 1] = conn
    end
end

function UISpoofer:startObserving()
    self:disconnectAll()

    self:observeRoot(CoreGui)

    local playerGui = self.localPlayer and self.localPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui then
        self:observeRoot(playerGui)
    end

    if self.localPlayer then
        local ok, conn = pcall(function()
            return self.localPlayer.ChildAdded:Connect(function(child)
                if not child:IsA("PlayerGui") then return end
                if not self.active then return end

                task.defer(function()
                    if not self.active then return end
                    self:observeRoot(child)
                end)
            end)
        end)

        if ok and conn then
            self.connections[#self.connections + 1] = conn
        end
    end
end

function UISpoofer:refreshTargetProfile(userId)
    local targetName = tostring(userId)
    local okName, lookedUpName = pcall(function()
        return Players:GetNameFromUserIdAsync(userId)
    end)
    if okName and lookedUpName and lookedUpName ~= "" then
        targetName = lookedUpName
    end

    local targetDisplayName = targetName
    local okPlayer, player = pcall(function()
        return Players:GetPlayerByUserId(userId)
    end)
    if okPlayer and player and player.DisplayName and player.DisplayName ~= "" then
        targetDisplayName = player.DisplayName
    end

    local headshot = nil
    local okThumb, content = pcall(function()
        return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
    end)
    if okThumb and type(content) == "string" and content ~= "" then
        headshot = content
    end

    self.targetName = targetName
    self.targetDisplayName = targetDisplayName
    self.targetHeadshot = headshot
end

function UISpoofer:setTarget(target)
    local normalized = normalizeTargetText(target)
    if normalized == "" then return false end

    local userId = nil
    if type(target) == "number" then
        userId = math.floor(target)
    else
        userId = self.shared:resolveUserToId(normalized)
    end

    if not userId then return false end

    self.targetInput = target
    local previousTargetUserId = self.targetUserId
    self.targetUserId = userId
    self:refreshTargetProfile(userId)

    if self.active then
        if previousTargetUserId and previousTargetUserId ~= userId then
            self:restoreAll()
        end

        self:startObserving()
        self:scanRoot(CoreGui)

        local playerGui = self.localPlayer and self.localPlayer:FindFirstChildOfClass("PlayerGui")
        if playerGui then
            self:scanRoot(playerGui)
        end

        task.defer(function()
            task.wait(0.15)
            if self.active and self.targetUserId == userId then
                self:reapply()
            end
        end)

        task.defer(function()
            task.wait(0.45)
            if self.active and self.targetUserId == userId then
                self:reapply()
            end
        end)
    end

    return true
end

function UISpoofer:mimicFromTarget(target)
    return self:setTarget(target)
end

function UISpoofer:reapply()
    if not self.active then return false end
    if not self.targetUserId then return false end

    self:startObserving()
    self:scanRoot(CoreGui)

    local playerGui = self.localPlayer and self.localPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui then
        self:scanRoot(playerGui)
    end

    return true
end

function UISpoofer:onCharacterAdded(_char)
    if not self.active then return end
    if not self.targetUserId then return end

    task.defer(function()
        if self.active then
            self:reapply()
        end
    end)
end

function UISpoofer:setEnabled(enabled)
    enabled = enabled == true
    if self.active == enabled then return end

    self.active = enabled

    if not enabled then
        self:disconnectAll()
        self:restoreAll()
        return
    end

    if self.targetUserId then
        self:startObserving()
        self:reapply()
    end
end

function UISpoofer:cleanup()
    self.active = false
    self.targetInput = nil
    self.targetUserId = nil
    self.targetName = nil
    self.targetDisplayName = nil
    self.targetHeadshot = nil

    self:disconnectAll()
    self:restoreAll()
end

return UISpoofer
