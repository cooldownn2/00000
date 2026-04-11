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
local IDENTITY_CONTEXT_KEYWORDS = {
    "inspect",
    "profile",
    "hover",
    "target",
    "avatar",
    "card",
    "identity",
    "viewer",
    "subject",
}
local PEOPLE_CONTEXT_KEYWORDS = {
    "people",
    "playerlist",
    "ingamemenu",
    "social",
}

local function normalizeLower(raw)
    return string.lower(tostring(raw or ""))
end

local function isGenericIdentityKey(rawKey)
    local key = normalizeLower(rawKey)
    return key == "id"
        or key == "name"
        or key == "display"
        or key == "displayname"
end

local function isLikelyIdentityContext(instance)
    local cursor = instance
    local depth = 0

    while cursor and depth < 12 do
        local nodeName = normalizeLower(cursor.Name)
        if nodeName ~= "" and nodeName ~= "playergui" then
            for i = 1, #IDENTITY_CONTEXT_KEYWORDS do
                if nodeName:find(IDENTITY_CONTEXT_KEYWORDS[i], 1, true) then
                    return true
                end
            end
        end

        cursor = cursor.Parent
        depth = depth + 1
    end

    return false
end

local function isLikelyPeopleContext(instance)
    local cursor = instance
    local depth = 0

    while cursor and depth < 12 do
        local nodeName = normalizeLower(cursor.Name)
        if nodeName ~= "" and nodeName ~= "playergui" then
            for i = 1, #PEOPLE_CONTEXT_KEYWORDS do
                if nodeName:find(PEOPLE_CONTEXT_KEYWORDS[i], 1, true) then
                    return true
                end
            end
        end

        cursor = cursor.Parent
        depth = depth + 1
    end

    return false
end

local function scorePeopleRowCandidate(row)
    if not row or not row:IsA("GuiObject") then return nil end

    local score = 0
    local parent = row.Parent
    if parent and parent:FindFirstChildOfClass("UIListLayout") then
        score = score + 90
    end

    local hasButton = row:IsA("GuiButton") or row:FindFirstChildWhichIsA("GuiButton", true) ~= nil
    local hasText = row:FindFirstChildWhichIsA("TextLabel", true) ~= nil
        or row:FindFirstChildWhichIsA("TextButton", true) ~= nil
    local hasImage = row:FindFirstChildWhichIsA("ImageLabel", true) ~= nil
        or row:FindFirstChildWhichIsA("ImageButton", true) ~= nil

    if hasButton then score = score + 45 end
    if hasText then score = score + 35 end
    if hasImage then score = score + 25 end

    local size = row.AbsoluteSize
    if size.X >= 220 then score = score + 20 end
    if size.Y >= 36 then score = score + 10 end

    if score <= 0 then return nil end
    return score
end

local function findPeopleRowFromTaggedText(textInstance)
    local cursor = textInstance
    local depth = 0
    local best = nil
    local bestScore = nil

    while cursor and depth < 10 do
        if cursor:IsA("GuiObject") then
            local score = scorePeopleRowCandidate(cursor)
            if score and (bestScore == nil or score > bestScore) then
                best = cursor
                bestScore = score
            end

            if score and score >= 150 then
                return cursor
            end
        end

        cursor = cursor.Parent
        depth = depth + 1
    end

    if best then return best end

    if textInstance.Parent and textInstance.Parent:IsA("GuiObject") then
        return textInstance.Parent
    end
    return nil
end

local function isLocalPeopleText(rawText, localName, localDisplay)
    if type(rawText) ~= "string" or rawText == "" then return false end

    local text = normalizeLower(rawText:gsub("^%s+", ""):gsub("%s+$", ""))
    local localNameText = normalizeLower(localName)
    local localDisplayText = normalizeLower(localDisplay)
    if text == "" then return false end

    if text == localNameText or text == localDisplayText then
        return true
    end

    if text == ("@" .. localNameText) or text == ("@" .. localDisplayText) then
        return true
    end

    if localNameText ~= "" and text:find(localNameText, 1, true) then return true end
    if localDisplayText ~= "" and text:find(localDisplayText, 1, true) then return true end

    return false
end

local function isAvatarThumbnailImage(rawImage)
    local image = normalizeLower(rawImage)
    if image == "" then return false end

    if image:find("rbxthumb://", 1, true) then
        return image:find("type=avatar", 1, true) ~= nil
            or image:find("type=headshot", 1, true) ~= nil
            or image:find("type=avatarheadshot", 1, true) ~= nil
            or image:find("type=avatarbust", 1, true) ~= nil
    end

    local hasThumbHost = image:find("thumbnails.roblox.com", 1, true) ~= nil
        or image:find("thumbs.roblox.com", 1, true) ~= nil
        or image:find("avatar-thumbnail", 1, true) ~= nil
        or image:find("avatar-headshot", 1, true) ~= nil
    if not hasThumbHost then
        return false
    end

    local hasUserHint = image:find("userid=", 1, true) ~= nil
        or image:find("userids=", 1, true) ~= nil
        or image:find("/users/", 1, true) ~= nil
    local hasAvatarHint = image:find("avatar", 1, true) ~= nil
        or image:find("headshot", 1, true) ~= nil
        or image:find("bust", 1, true) ~= nil

    return hasUserHint and hasAvatarHint
end

local function isLikelyUserIdKey(rawKey)
    local key = normalizeLower(rawKey)
    if key == "" then return false end

    if key == "userid" or key == "playeruserid" or key == "playerid"
        or key == "targetuserid" or key == "inspectuserid"
        or key == "selecteduserid" or key == "profileuserid"
        or key == "subjectuserid" or key == "owneruserid"
        or key == "hoveruserid" then
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

    if key == "username" or key == "displayname" or key == "playername" or key == "targetname"
        or key == "inspectname" or key == "hovername" or key == "profilename" then
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
    if key == "player" or key == "selectedplayer" or key == "targetplayer" or key == "subjectplayer"
        or key == "hoveredplayer" or key == "inspectedplayer" then
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
    self.targetAvatarThumb = nil
    self.localUserId = self.localPlayer and self.localPlayer.UserId or nil

    self.connections = {}
    self.observedRoots = {}
    self.watchedByInstance = setmetatable({}, { __mode = "k" })
    self.originalByInstance = setmetatable({}, { __mode = "k" })
    self.syntheticPeopleBySource = setmetatable({}, { __mode = "k" })
    self.syntheticSyncScheduled = false

    -- Remove stale rows left by previous runs that may not have cleaned up.
    local ok, descendants = pcall(function() return CoreGui:GetDescendants() end)
    if ok and descendants then
        for _, inst in ipairs(descendants) do
            if inst.Name == "UISpooferSyntheticRow" and inst:IsA("GuiObject") then
                pcall(function() inst:Destroy() end)
            end
        end
    end

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
    self.syntheticSyncScheduled = false
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
    if not isAvatarThumbnailImage(rawImage) then return nil end

    local targetId = tostring(self.targetUserId)
    local rewritten = rawImage
    local changed = false

    local v1, c1 = rewritten:gsub("([?&][uU][sS][eE][rR][iI][dD]=)%d+", "%1" .. targetId)
    if c1 > 0 then rewritten = v1; changed = true end

    local v2, c2 = rewritten:gsub("([?&][uU][sS][eE][rR][iI][dD][sS]=)%d+[,%d]*", "%1" .. targetId)
    if c2 > 0 then rewritten = v2; changed = true end

    if normalizeLower(rawImage):find("rbxthumb://", 1, true) then
        local v3, c3 = rewritten:gsub("([?&][iI][dD]=)%d+", "%1" .. targetId)
        if c3 > 0 then rewritten = v3; changed = true end
    end

    if changed then
        return rewritten
    end

    local lowerImage = normalizeLower(rawImage)
    local isHeadshot = lowerImage:find("headshot", 1, true) ~= nil
        or lowerImage:find("avatarheadshot", 1, true) ~= nil
    if isHeadshot and self.targetHeadshot then
        return self.targetHeadshot
    end

    local isFullAvatar = lowerImage:find("type=avatar", 1, true) ~= nil
        or lowerImage:find("avatar-thumbnail", 1, true) ~= nil
        or lowerImage:find("avatarbust", 1, true) ~= nil
    if isFullAvatar and self.targetAvatarThumb then
        return self.targetAvatarThumb
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

function UISpoofer:findRightmostPeopleButton(row)
    if not row then return nil end

    local best = nil
    local bestScore = nil

    local function scoreButton(button)
        local pos = button.AbsolutePosition
        local size = button.AbsoluteSize
        return (pos.X * 10000) + pos.Y - (math.abs(size.X - size.Y) * 10) - size.X
    end

    if row:IsA("GuiButton") and row.Visible then
        best = row
        bestScore = scoreButton(row)
    end

    local ok, descendants = pcall(function() return row:GetDescendants() end)
    if ok and descendants then
        for _, inst in ipairs(descendants) do
            if inst:IsA("GuiButton") and inst.Visible then
                local score = scoreButton(inst)
                if bestScore == nil or score > bestScore then
                    best = inst
                    bestScore = score
                end
            end
        end
    end

    return best
end

function UISpoofer:tryClonePeopleRow(sourceRow)
    if not sourceRow then return nil end

    local archivableSnapshot = {}
    local function markArchivable(inst)
        if not inst then return end
        pcall(function()
            archivableSnapshot[inst] = inst.Archivable
            inst.Archivable = true
        end)
    end

    markArchivable(sourceRow)
    local okDesc, descendants = pcall(function() return sourceRow:GetDescendants() end)
    if okDesc and descendants then
        for _, inst in ipairs(descendants) do
            markArchivable(inst)
        end
    end

    local okClone, cloned = pcall(function() return sourceRow:Clone() end)

    for inst, oldValue in pairs(archivableSnapshot) do
        pcall(function() inst.Archivable = oldValue end)
    end

    if okClone and cloned then return cloned end
    return nil
end

function UISpoofer:createFallbackPeopleRow(sourceRow)
    if not sourceRow then return nil end

    local localName = self.localPlayer and self.localPlayer.Name or ""
    local localDisplay = self.localPlayer and self.localPlayer.DisplayName or localName
    local sourceButton = self:findRightmostPeopleButton(sourceRow)

    local row = Instance.new("Frame")
    row.Name = "UISpooferSyntheticRow"
    row.BackgroundColor3 = sourceRow.BackgroundColor3
    row.BackgroundTransparency = sourceRow.BackgroundTransparency
    row.BorderSizePixel = 0
    row.Size = sourceRow.Size
    row.LayoutOrder = (tonumber(sourceRow.LayoutOrder) or 0) - 1
    row.ClipsDescendants = false

    local okCorner, sourceCorner = pcall(function() return sourceRow:FindFirstChildOfClass("UICorner") end)
    if okCorner and sourceCorner then
        local clonedCorner = sourceCorner:Clone()
        clonedCorner.Parent = row
    else
        local fallbackCorner = Instance.new("UICorner")
        fallbackCorner.CornerRadius = UDim.new(0, 8)
        fallbackCorner.Parent = row
    end

    local avatar = Instance.new("ImageLabel")
    avatar.Name = "Avatar"
    avatar.BackgroundTransparency = 1
    avatar.Size = UDim2.fromOffset(34, 34)
    avatar.Position = UDim2.new(0, 10, 0.5, -17)
    avatar.Image = self.targetHeadshot or ""
    avatar.Parent = row

    local avatarCorner = Instance.new("UICorner")
    avatarCorner.CornerRadius = UDim.new(0, 6)
    avatarCorner.Parent = avatar

    local displayNameLabel = Instance.new("TextLabel")
    displayNameLabel.Name = "DisplayName"
    displayNameLabel.BackgroundTransparency = 1
    displayNameLabel.TextXAlignment = Enum.TextXAlignment.Left
    displayNameLabel.TextYAlignment = Enum.TextYAlignment.Center
    displayNameLabel.Font = Enum.Font.GothamSemibold
    displayNameLabel.TextSize = 23
    displayNameLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
    displayNameLabel.Text = localDisplay
    displayNameLabel.Position = UDim2.new(0, 56, 0, 6)
    displayNameLabel.Size = UDim2.new(1, -130, 0, 20)
    displayNameLabel.Parent = row

    local usernameLabel = Instance.new("TextLabel")
    usernameLabel.Name = "Username"
    usernameLabel.BackgroundTransparency = 1
    usernameLabel.TextXAlignment = Enum.TextXAlignment.Left
    usernameLabel.TextYAlignment = Enum.TextYAlignment.Center
    usernameLabel.Font = Enum.Font.Gotham
    usernameLabel.TextSize = 20
    usernameLabel.TextColor3 = Color3.fromRGB(166, 170, 178)
    usernameLabel.Text = "@" .. localName
    usernameLabel.Position = UDim2.new(0, 56, 0, 24)
    usernameLabel.Size = UDim2.new(1, -130, 0, 18)
    usernameLabel.Parent = row

    local inspectButton = Instance.new("ImageButton")
    inspectButton.Name = "InspectButton"
    inspectButton.AnchorPoint = Vector2.new(1, 0.5)
    inspectButton.Position = UDim2.new(1, -12, 0.5, 0)
    inspectButton.Size = UDim2.fromOffset(32, 32)
    inspectButton.BackgroundTransparency = 1
    inspectButton.AutoButtonColor = true
    if sourceButton and sourceButton:IsA("ImageButton") and sourceButton.Image and sourceButton.Image ~= "" then
        inspectButton.Image = sourceButton.Image
    end
    inspectButton.Parent = row

    return row
end

function UISpoofer:applySyntheticPeopleRowVisuals(row)
    if not row then return end

    local localName = self.localPlayer and self.localPlayer.Name or ""
    local localDisplay = self.localPlayer and self.localPlayer.DisplayName or localName
    local targetName = self.targetName or tostring(self.targetUserId or "")
    local targetDisplay = self.targetDisplayName or targetName

    local function applyText(instance)
        if not instance or not TEXT_CLASS_SET[instance.ClassName] then return end

        local current = instance.Text
        local rewritten = self:rewriteText(current)
        if not rewritten then
            local trimmed = tostring(current or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if trimmed == localName or trimmed == localDisplay then
                rewritten = targetDisplay
            elseif trimmed == ("@" .. localName) or trimmed == ("@" .. localDisplay) then
                rewritten = "@" .. targetName
            end
        end

        if rewritten and rewritten ~= current then
            pcall(function() instance.Text = rewritten end)
        end
    end

    local function applyImage(instance)
        if not instance or not IMAGE_CLASS_SET[instance.ClassName] then return end

        local current = instance.Image
        local rewritten = self:rewriteImage(current)
        if rewritten and rewritten ~= current then
            pcall(function() instance.Image = rewritten end)
        end
    end

    applyText(row)
    applyImage(row)

    local leftMostAvatarImage = nil
    local leftMostX = nil

    local ok, descendants = pcall(function() return row:GetDescendants() end)
    if ok and descendants then
        for _, inst in ipairs(descendants) do
            applyText(inst)
            applyImage(inst)

            if IMAGE_CLASS_SET[inst.ClassName] then
                local pos = inst.AbsolutePosition
                local size = inst.AbsoluteSize
                if size.X >= 20 and size.Y >= 20 then
                    if leftMostX == nil or pos.X < leftMostX then
                        leftMostX = pos.X
                        leftMostAvatarImage = inst
                    end
                end
            end
        end
    end

    if leftMostAvatarImage and self.targetHeadshot and leftMostAvatarImage.Image ~= self.targetHeadshot then
        pcall(function() leftMostAvatarImage.Image = self.targetHeadshot end)
    end
end

function UISpoofer:clearSyntheticPeopleRows()
    for sourceRow, syntheticRow in pairs(self.syntheticPeopleBySource) do
        if syntheticRow and syntheticRow.Parent then
            pcall(function() syntheticRow:Destroy() end)
        end
        self.syntheticPeopleBySource[sourceRow] = nil
    end

    self.syntheticPeopleBySource = setmetatable({}, { __mode = "k" })
    self.syntheticSyncScheduled = false
end

function UISpoofer:syncSyntheticPeopleRows()
    if not self.active or not self.targetUserId then
        self:clearSyntheticPeopleRows()
        return
    end

    local localName = self.localPlayer and self.localPlayer.Name or ""
    local localDisplay = self.localPlayer and self.localPlayer.DisplayName or localName
    if localName == "" then return end

    local sourceRows = {}

    local ok, descendants = pcall(function() return CoreGui:GetDescendants() end)
    if not ok or not descendants then return end

    for _, inst in ipairs(descendants) do
        if TEXT_CLASS_SET[inst.ClassName]
            and isLikelyPeopleContext(inst)
            and isLocalPeopleText(inst.Text, localName, localDisplay) then
            local sourceRow = findPeopleRowFromTaggedText(inst)
            if sourceRow and sourceRow.Parent and sourceRow.Name ~= "UISpooferSyntheticRow" then
                sourceRows[sourceRow] = true
            end
        end
    end

    for sourceRow, syntheticRow in pairs(self.syntheticPeopleBySource) do
        if not sourceRows[sourceRow] or not sourceRow or not sourceRow.Parent then
            if syntheticRow and syntheticRow.Parent then
                pcall(function() syntheticRow:Destroy() end)
            end
            self.syntheticPeopleBySource[sourceRow] = nil
        end
    end

    for sourceRow in pairs(sourceRows) do
        local syntheticRow = self.syntheticPeopleBySource[sourceRow]

        if not syntheticRow or not syntheticRow.Parent then
            local cloned = self:tryClonePeopleRow(sourceRow)
            if not cloned then
                cloned = self:createFallbackPeopleRow(sourceRow)
            end

            if cloned then
                syntheticRow = cloned
                syntheticRow.Name = "UISpooferSyntheticRow"
                syntheticRow.Visible = true

                local okCloneDesc, cloneDesc = pcall(function() return syntheticRow:GetDescendants() end)
                if okCloneDesc and cloneDesc then
                    for _, inst in ipairs(cloneDesc) do
                        if inst:IsA("LocalScript") or inst:IsA("Script") or inst:IsA("ModuleScript") then
                            pcall(function() inst:Destroy() end)
                        end
                    end
                end

                pcall(function() syntheticRow.Parent = sourceRow.Parent end)
                self.syntheticPeopleBySource[sourceRow] = syntheticRow

                local sourceButton = self:findRightmostPeopleButton(sourceRow)
                local syntheticButton = self:findRightmostPeopleButton(syntheticRow)
                if sourceButton and syntheticButton then
                    local okConn, conn = pcall(function()
                        return syntheticButton.Activated:Connect(function()
                            if not self.active then return end
                            pcall(function() sourceButton:Activate() end)
                        end)
                    end)
                    if okConn and conn then
                        self.connections[#self.connections + 1] = conn
                    end
                end
            end
        end

        if syntheticRow and syntheticRow.Parent then
            pcall(function()
                syntheticRow.LayoutOrder = (tonumber(sourceRow.LayoutOrder) or 0) - 1
            end)
            self:applySyntheticPeopleRowVisuals(syntheticRow)
        end
    end
end

function UISpoofer:requestSyntheticPeopleSync()
    if self.syntheticSyncScheduled then return end
    self.syntheticSyncScheduled = true

    task.defer(function()
        self.syntheticSyncScheduled = false
        if not self.active or not self.targetUserId then
            self:clearSyntheticPeopleRows()
            return
        end
        self:syncSyntheticPeopleRows()
    end)
end

function UISpoofer:registerInstanceObservers(instance, watchAttributes)
    if not instance or self.watchedByInstance[instance] then return end

    local className = instance.ClassName
    local watchImage = IMAGE_CLASS_SET[className] == true
    local watchText = TEXT_CLASS_SET[className] == true
    local watchValue = NUMERIC_VALUE_CLASS_SET[className] == true
        or STRING_VALUE_CLASS_SET[className] == true
        or className == "ObjectValue"
    local identityContext = isLikelyIdentityContext(instance)

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
                if identityContext then
                    scheduleReapply()
                    return
                end

                if isLikelyUserIdKey(attrName)
                    or isLikelyNameKey(attrName)
                    or isGenericIdentityKey(attrName) then
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
    local identityContext = isLikelyIdentityContext(instance)
    local instanceName = normalizeLower(instance.Name)
    local isUserIdCarrier = isLikelyUserIdKey(instance.Name)
        or (identityContext and instanceName == "id")
    local isNameCarrier = isLikelyNameKey(instance.Name)
        or (identityContext and (instanceName == "name" or instanceName == "display" or instanceName == "displayname"))
    local watchAttributes = identityContext
    local localUserId = tonumber(self.localUserId)
    local targetUserIdText = tostring(self.targetUserId)

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
        if not rewritten and identityContext and localUserId then
            local localUserIdText = tostring(localUserId)
            local replaced, changed = replacePlain(currentText, localUserIdText, targetUserIdText)
            if changed then
                rewritten = replaced
            end
        end
        if rewritten and rewritten ~= currentText then
            self:rememberOriginal(instance, "Text", currentText)
            pcall(function() instance.Text = rewritten end)
        end
    end

    if NUMERIC_VALUE_CLASS_SET[className] then
        local currentNumeric = tonumber(instance.Value)
        local currentId = currentNumeric and math.floor(currentNumeric) or nil
        local shouldRewrite = false

        if currentId then
            if isUserIdCarrier and currentId ~= self.targetUserId then
                shouldRewrite = true
            elseif identityContext and localUserId and currentId == localUserId and currentId ~= self.targetUserId then
                shouldRewrite = true
            end
        end

        if shouldRewrite then
            self:rememberOriginal(instance, "Value", instance.Value)
            pcall(function() instance.Value = self.targetUserId end)
        end
    end

    if STRING_VALUE_CLASS_SET[className] then
        local currentString = tostring(instance.Value or "")
        local currentNumeric = tonumber(currentString)
        local currentId = currentNumeric and math.floor(currentNumeric) or nil
        local isContextLocalId = identityContext and localUserId and currentId == localUserId

        if isUserIdCarrier or isContextLocalId then
            if currentId and currentId ~= self.targetUserId then
                self:rememberOriginal(instance, "Value", instance.Value)
                pcall(function() instance.Value = targetUserIdText end)
            end
        elseif isNameCarrier then
            local rewritten = self:rewriteText(currentString)
            if not rewritten and currentString ~= (self.targetDisplayName or "") and currentString ~= (self.targetName or "") then
                rewritten = self.targetDisplayName or self.targetName
            end
            if rewritten and rewritten ~= currentString then
                self:rememberOriginal(instance, "Value", instance.Value)
                pcall(function() instance.Value = rewritten end)
            end
        end
    end

    if className == "ObjectValue" then
        local shouldRewritePlayerObject = isLikelyPlayerObjectKey(instance.Name)
            or (identityContext and instance.Value == self.localPlayer)

        local targetPlayer = self:getTargetPlayerInstance()
        if shouldRewritePlayerObject and targetPlayer and targetPlayer ~= instance.Value then
            self:rememberOriginal(instance, "Value", instance.Value)
            pcall(function() instance.Value = targetPlayer end)
        end
    end

    local okAttrs, attrs = pcall(function() return instance:GetAttributes() end)
    if okAttrs and type(attrs) == "table" then
        for attrName, attrValue in pairs(attrs) do
            local attrKey = normalizeLower(attrName)
            local attrIsUserIdCarrier = isLikelyUserIdKey(attrName)
                or (identityContext and attrKey == "id")
            local attrIsNameCarrier = isLikelyNameKey(attrName)
                or (identityContext and (attrKey == "name" or attrKey == "display" or attrKey == "displayname"))

            if attrIsUserIdCarrier then
                watchAttributes = true

                if type(attrValue) == "number" and math.floor(attrValue) ~= self.targetUserId then
                    self:rememberOriginalAttribute(instance, attrName, attrValue)
                    pcall(function() instance:SetAttribute(attrName, self.targetUserId) end)
                elseif type(attrValue) == "string" then
                    local attrNumeric = tonumber(attrValue)
                    if attrNumeric and math.floor(attrNumeric) ~= self.targetUserId then
                        self:rememberOriginalAttribute(instance, attrName, attrValue)
                        pcall(function() instance:SetAttribute(attrName, targetUserIdText) end)
                    end
                end
            elseif attrIsNameCarrier then
                watchAttributes = true
                if type(attrValue) == "string" then
                    local rewritten = self:rewriteText(attrValue)
                    if not rewritten and attrValue ~= (self.targetDisplayName or "") and attrValue ~= (self.targetName or "") then
                        rewritten = self.targetDisplayName or self.targetName
                    end
                    if rewritten and rewritten ~= attrValue then
                        self:rememberOriginalAttribute(instance, attrName, attrValue)
                        pcall(function() instance:SetAttribute(attrName, rewritten) end)
                    end
                end
            elseif identityContext then
                if type(attrValue) == "number" then
                    local attrNumeric = math.floor(attrValue)
                    if localUserId and attrNumeric == localUserId and attrNumeric ~= self.targetUserId then
                        watchAttributes = true
                        self:rememberOriginalAttribute(instance, attrName, attrValue)
                        pcall(function() instance:SetAttribute(attrName, self.targetUserId) end)
                    end
                elseif type(attrValue) == "string" then
                    local attrNumeric = tonumber(attrValue)
                    if localUserId and attrNumeric and math.floor(attrNumeric) == localUserId and math.floor(attrNumeric) ~= self.targetUserId then
                        watchAttributes = true
                        self:rememberOriginalAttribute(instance, attrName, attrValue)
                        pcall(function() instance:SetAttribute(attrName, targetUserIdText) end)
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
                self:requestSyntheticPeopleSync()
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

    self:requestSyntheticPeopleSync()
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

    local avatarThumb = nil
    local okAvatarThumb, avatarContent = pcall(function()
        return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.AvatarThumbnail, Enum.ThumbnailSize.Size420x420)
    end)
    if okAvatarThumb and type(avatarContent) == "string" and avatarContent ~= "" then
        avatarThumb = avatarContent
    end

    self.targetName = targetName
    self.targetDisplayName = targetDisplayName
    self.targetHeadshot = headshot
    self.targetAvatarThumb = avatarThumb
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
            self:clearSyntheticPeopleRows()
        end

        self:startObserving()
        self:scanRoot(CoreGui)

        local playerGui = self.localPlayer and self.localPlayer:FindFirstChildOfClass("PlayerGui")
        if playerGui then
            self:scanRoot(playerGui)
        end

        self:requestSyntheticPeopleSync()

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

    self:scanRoot(CoreGui)

    local playerGui = self.localPlayer and self.localPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui then
        self:scanRoot(playerGui)
    end

    self:requestSyntheticPeopleSync()

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
        self:clearSyntheticPeopleRows()
        return
    end

    if self.targetUserId then
        self:startObserving()
        self:reapply()
        self:requestSyntheticPeopleSync()
    end
end

function UISpoofer:cleanup()
    self.active = false
    self.targetInput = nil
    self.targetUserId = nil
    self.targetName = nil
    self.targetDisplayName = nil
    self.targetHeadshot = nil
    self.targetAvatarThumb = nil

    self:disconnectAll()
    self:restoreAll()
    self:clearSyntheticPeopleRows()
end

return UISpoofer
