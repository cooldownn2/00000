local OutfitMimic = {}
OutfitMimic.__index = OutfitMimic

local COPY_CLASSES = { "Shirt", "Pants", "ShirtGraphic", "Accessory", "Hat", "BodyColors", "CharacterMesh" }
local COPY_CLASS_SET = {}
for _, cls in ipairs(COPY_CLASSES) do COPY_CLASS_SET[cls] = true end

local SCALE_VALUE_NAMES = {
    "BodyHeightScale", "BodyWidthScale", "BodyDepthScale",
    "HeadScale", "BodyTypeScale", "BodyProportionScale",
}

local SCALE_VALUE_SET = {}
for _, scaleName in ipairs(SCALE_VALUE_NAMES) do
    SCALE_VALUE_SET[scaleName] = true
end

local COPY_ANIMATION_FIELDS = {
    "ClimbAnimation", "FallAnimation", "IdleAnimation",
    "JumpAnimation", "RunAnimation", "SwimAnimation", "WalkAnimation",
}

local BODY_PART_NAMES = {
    "Head",
    "Torso", "UpperTorso", "LowerTorso",
    "LeftArm", "RightArm", "LeftLeg", "RightLeg",
    "LeftUpperArm", "LeftLowerArm", "LeftHand",
    "RightUpperArm", "RightLowerArm", "RightHand",
    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
    "RightUpperLeg", "RightLowerLeg", "RightFoot",
}

local function isCopyClass(className)
    return COPY_CLASS_SET[className] == true
end

local function shouldCloneClass(className)
    return isCopyClass(className) and className ~= "BodyColors"
end

local function isAccessoryClass(className)
    return className == "Accessory" or className == "Hat"
end

local function buildBasePartMap(model)
    local out = {}
    if not model then return out end

    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("BasePart") then
            out[child.Name] = child
        end
    end

    return out
end

local function buildAttachmentCarrierMap(partMap)
    local carrier = {}
    for partName, part in pairs(partMap or {}) do
        for _, child in ipairs(part:GetChildren()) do
            if child:IsA("Attachment") then
                local prev = carrier[child.Name]
                if prev == nil then
                    carrier[child.Name] = partName
                elseif prev ~= partName then
                    carrier[child.Name] = false
                end
            end
        end
    end
    return carrier
end

local function hasAnySourceBodyPart(model)
    for _, partName in ipairs(BODY_PART_NAMES) do
        if model:FindFirstChild(partName) then return true end
    end
    return false
end

local function buildSourcePartSizeMap(srcModel)
    local sizes = {}
    for _, part in ipairs(srcModel:GetChildren()) do
        if part:IsA("BasePart") then sizes[part.Name] = part.Size end
    end
    return sizes
end

local function clearCopyChildren(char)
    for _, inst in ipairs(char:GetChildren()) do
        if isCopyClass(inst.ClassName) then
            pcall(function() inst:Destroy() end)
        end
    end
end

local function applyFaceTexture(char, texture)
    local head = char:FindFirstChild("Head")
    if not head then return end

    for _, child in ipairs(head:GetChildren()) do
        if child:IsA("Decal") and (child.Name == "face" or child.Face == Enum.NormalId.Front) then
            pcall(function() child:Destroy() end)
        end
    end

    if not texture or texture == "" then return end

    local decal = Instance.new("Decal")
    decal.Name = "face"
    decal.Face = Enum.NormalId.Front
    decal.Texture = texture
    decal.Parent = head
end

local function clearHeadFaceDecals(head)
    if not head then return end
    for _, child in ipairs(head:GetChildren()) do
        if child:IsA("Decal") and (child.Name == "face" or child.Face == Enum.NormalId.Front) then
            pcall(function() child:Destroy() end)
        end
    end
end

local function applyHeadVisualFromSource(char, sourceHead, desiredFaceTexture)
    local destHead = char and char:FindFirstChild("Head")
    if not destHead or not sourceHead then
        applyFaceTexture(char, desiredFaceTexture)
        return
    end

    pcall(function()
        if sourceHead:IsA("BasePart") and destHead:IsA("BasePart") then
            destHead.Transparency = sourceHead.Transparency
        end
    end)

    pcall(function()
        if sourceHead:IsA("MeshPart") and destHead:IsA("MeshPart") then
            destHead.MeshId = sourceHead.MeshId
            destHead.TextureID = sourceHead.TextureID
        end
    end)

    local srcMesh = sourceHead:FindFirstChildOfClass("SpecialMesh")
    local dstMesh = destHead:FindFirstChildOfClass("SpecialMesh")
    if srcMesh then
        if not dstMesh then
            dstMesh = srcMesh:Clone()
            dstMesh.Parent = destHead
        else
            dstMesh.MeshId = srcMesh.MeshId
            dstMesh.TextureId = srcMesh.TextureId
            dstMesh.Scale = srcMesh.Scale
            dstMesh.Offset = srcMesh.Offset
        end
    elseif dstMesh then
        pcall(function() dstMesh:Destroy() end)
    end

    -- If the source head is effectively hidden (headless-style), never add face decals.
    if sourceHead.Transparency >= 0.98 then
        clearHeadFaceDecals(destHead)
        return
    end

    applyFaceTexture(char, desiredFaceTexture)
end

local function toColor3(value)
    local kind = typeof(value)
    if kind == "Color3" then return value end
    if kind == "BrickColor" then return value.Color end
    if kind == "number" then
        local ok, brick = pcall(function() return BrickColor.new(value) end)
        if ok and brick then return brick.Color end
    end
    return nil
end

local function applyBodyFromDescription(targetDesc, char)
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or not targetDesc then return false end

    for _, fieldName in ipairs(COPY_ANIMATION_FIELDS) do
        pcall(function() targetDesc[fieldName] = 0 end)
    end

    return pcall(function() hum:ApplyDescription(targetDesc) end)
end

function OutfitMimic.new(deps)
    local self = setmetatable({}, OutfitMimic)

    self.shared = deps.shared
    self.localPlayer = deps.localPlayer

    self.active = true
    self.applySerial = 0
    self.targetUserId = nil
    self.currentUserId = nil

    self.appearanceChildConn = nil
    self.appearanceScaleValueConns = {}

    return self
end

function OutfitMimic:isApplyStillCurrent(applyToken)
    return self.active and applyToken == self.applySerial
end

function OutfitMimic:disconnectAppearanceHooks()
    if self.appearanceChildConn then
        self.appearanceChildConn:Disconnect()
        self.appearanceChildConn = nil
    end

    for i = #self.appearanceScaleValueConns, 1, -1 do
        local conn = self.appearanceScaleValueConns[i]
        if conn and conn.Connected then conn:Disconnect() end
        self.appearanceScaleValueConns[i] = nil
    end
end

function OutfitMimic:enforceSkinColorFromDescription(targetDesc, char, sourceModel, preferredSnapshot)
    if not char then return end

    local bodyColors = char:FindFirstChildOfClass("BodyColors")
    if not bodyColors then
        bodyColors = Instance.new("BodyColors")
        bodyColors.Parent = char
    end

    local preferredBodyColors = preferredSnapshot and preferredSnapshot.bodyColors or nil
    local sourceBodyColors = sourceModel and sourceModel:FindFirstChildOfClass("BodyColors")

    local headColor = (preferredBodyColors and preferredBodyColors.HeadColor3)
        or (targetDesc and toColor3(targetDesc.HeadColor))
        or (sourceBodyColors and sourceBodyColors.HeadColor3)

    local leftArmColor = (preferredBodyColors and preferredBodyColors.LeftArmColor3)
        or (targetDesc and toColor3(targetDesc.LeftArmColor))
        or (sourceBodyColors and sourceBodyColors.LeftArmColor3)

    local rightArmColor = (preferredBodyColors and preferredBodyColors.RightArmColor3)
        or (targetDesc and toColor3(targetDesc.RightArmColor))
        or (sourceBodyColors and sourceBodyColors.RightArmColor3)

    local torsoColor = (preferredBodyColors and preferredBodyColors.TorsoColor3)
        or (targetDesc and toColor3(targetDesc.TorsoColor))
        or (sourceBodyColors and sourceBodyColors.TorsoColor3)

    local leftLegColor = (preferredBodyColors and preferredBodyColors.LeftLegColor3)
        or (targetDesc and toColor3(targetDesc.LeftLegColor))
        or (sourceBodyColors and sourceBodyColors.LeftLegColor3)

    local rightLegColor = (preferredBodyColors and preferredBodyColors.RightLegColor3)
        or (targetDesc and toColor3(targetDesc.RightLegColor))
        or (sourceBodyColors and sourceBodyColors.RightLegColor3)

    local preferredPartColors = preferredSnapshot and preferredSnapshot.partColors or nil
    local function pickPartColor(partName, fallbackColor)
        if preferredPartColors then
            local preferred = toColor3(preferredPartColors[partName])
            if preferred then return preferred end
        end
        return fallbackColor
    end

    if headColor then bodyColors.HeadColor3 = headColor end
    if leftArmColor then bodyColors.LeftArmColor3 = leftArmColor end
    if rightArmColor then bodyColors.RightArmColor3 = rightArmColor end
    if torsoColor then bodyColors.TorsoColor3 = torsoColor end
    if leftLegColor then bodyColors.LeftLegColor3 = leftLegColor end
    if rightLegColor then bodyColors.RightLegColor3 = rightLegColor end

    local partColorMap = {
        Head = pickPartColor("Head", headColor),
        LeftArm = pickPartColor("LeftArm", leftArmColor),
        RightArm = pickPartColor("RightArm", rightArmColor),
        ["Left Arm"] = pickPartColor("Left Arm", leftArmColor),
        ["Right Arm"] = pickPartColor("Right Arm", rightArmColor),
        LeftUpperArm = pickPartColor("LeftUpperArm", leftArmColor),
        LeftLowerArm = pickPartColor("LeftLowerArm", leftArmColor),
        LeftHand = pickPartColor("LeftHand", leftArmColor),
        RightUpperArm = pickPartColor("RightUpperArm", rightArmColor),
        RightLowerArm = pickPartColor("RightLowerArm", rightArmColor),
        RightHand = pickPartColor("RightHand", rightArmColor),
        Torso = pickPartColor("Torso", torsoColor),
        UpperTorso = pickPartColor("UpperTorso", torsoColor),
        LowerTorso = pickPartColor("LowerTorso", torsoColor),
        LeftLeg = pickPartColor("LeftLeg", leftLegColor),
        LeftUpperLeg = pickPartColor("LeftUpperLeg", leftLegColor),
        LeftLowerLeg = pickPartColor("LeftLowerLeg", leftLegColor),
        LeftFoot = pickPartColor("LeftFoot", leftLegColor),
        ["Left Leg"] = pickPartColor("Left Leg", leftLegColor),
        ["Right Leg"] = pickPartColor("Right Leg", rightLegColor),
        RightLeg = pickPartColor("RightLeg", rightLegColor),
        RightUpperLeg = pickPartColor("RightUpperLeg", rightLegColor),
        RightLowerLeg = pickPartColor("RightLowerLeg", rightLegColor),
        RightFoot = pickPartColor("RightFoot", rightLegColor),
    }

    for partName, color3 in pairs(partColorMap) do
        if color3 then
            local part = char:FindFirstChild(partName)
            if part and part:IsA("BasePart") then
                pcall(function() part.Color = color3 end)
            end
        end
    end
end

function OutfitMimic:scaleAccessoryOnce(acc, char, sourcePartSizeMap, charPartMap, attachmentCarrierMap)
    local handle = acc:FindFirstChild("Handle")
    if not handle or not handle:IsA("BasePart") then return end

    local matchedPartName = nil
    for _, hChild in ipairs(handle:GetChildren()) do
        if hChild:IsA("Attachment") then
            local carrier = attachmentCarrierMap and attachmentCarrierMap[hChild.Name] or nil
            if type(carrier) == "string" then
                matchedPartName = carrier
                break
            end
            if carrier == false then
                local scanMap = charPartMap or buildBasePartMap(char)
                for partName, bodyPart in pairs(scanMap) do
                    if bodyPart and bodyPart:IsA("BasePart") and bodyPart:FindFirstChild(hChild.Name) then
                        matchedPartName = partName
                        break
                    end
                end
            end
        end
        if matchedPartName then break end
    end

    if not handle:GetAttribute("_cpBaseSizeX") then
        handle:SetAttribute("_cpBaseSizeX", handle.Size.X)
        handle:SetAttribute("_cpBaseSizeY", handle.Size.Y)
        handle:SetAttribute("_cpBaseSizeZ", handle.Size.Z)

        for _, hChild in ipairs(handle:GetChildren()) do
            if hChild:IsA("Attachment") then
                hChild:SetAttribute("_cpBasePosX", hChild.Position.X)
                hChild:SetAttribute("_cpBasePosY", hChild.Position.Y)
                hChild:SetAttribute("_cpBasePosZ", hChild.Position.Z)
            end
        end

        local sm0 = handle:FindFirstChildOfClass("SpecialMesh")
        if sm0 then
            sm0:SetAttribute("_cpBaseScaleX", sm0.Scale.X)
            sm0:SetAttribute("_cpBaseScaleY", sm0.Scale.Y)
            sm0:SetAttribute("_cpBaseScaleZ", sm0.Scale.Z)
        end
    end

    local scale = nil
    if matchedPartName then
        local srcSize = sourcePartSizeMap[matchedPartName]
        local dstPart = char:FindFirstChild(matchedPartName)
        if srcSize and dstPart and dstPart:IsA("BasePart") then
            local sx = math.max(srcSize.X, 0.001)
            local sy = math.max(srcSize.Y, 0.001)
            local sz = math.max(srcSize.Z, 0.001)
            scale = (dstPart.Size.X / sx + dstPart.Size.Y / sy + dstPart.Size.Z / sz) / 3
        end
    end

    local function applyScale(s)
        local bx = handle:GetAttribute("_cpBaseSizeX")
        local by = handle:GetAttribute("_cpBaseSizeY")
        local bz = handle:GetAttribute("_cpBaseSizeZ")
        if bx and by and bz then
            pcall(function() handle.Size = Vector3.new(bx * s, by * s, bz * s) end)
        end

        for _, hChild in ipairs(handle:GetChildren()) do
            if hChild:IsA("Attachment") then
                local apx = hChild:GetAttribute("_cpBasePosX")
                local apy = hChild:GetAttribute("_cpBasePosY")
                local apz = hChild:GetAttribute("_cpBasePosZ")
                if apx and apy and apz then
                    pcall(function() hChild.Position = Vector3.new(apx * s, apy * s, apz * s) end)
                end
            end
        end

        local sm = handle:FindFirstChildOfClass("SpecialMesh")
        if sm then
            local msx = sm:GetAttribute("_cpBaseScaleX")
            local msy = sm:GetAttribute("_cpBaseScaleY")
            local msz = sm:GetAttribute("_cpBaseScaleZ")
            pcall(function()
                if msx and msy and msz then
                    sm.Scale = Vector3.new(msx * s, msy * s, msz * s)
                else
                    sm.Scale = sm.Scale * s
                end
            end)
        end
    end

    if scale and math.abs(scale - 1) > 0.01 then
        applyScale(scale)
    else
        applyScale(1)
    end
end

function OutfitMimic:scaleAllAccessories(char, sourcePartSizeMap, charPartMap, attachmentCarrierMap)
    for _, child in ipairs(char:GetChildren()) do
        if isAccessoryClass(child.ClassName) then
            self:scaleAccessoryOnce(child, char, sourcePartSizeMap, charPartMap, attachmentCarrierMap)
        end
    end
end

function OutfitMimic:cleanupForSwitch(char)
    self:disconnectAppearanceHooks()
    if not char then return end
    clearCopyChildren(char)
end

function OutfitMimic:applyAppearance(userId, char, applyToken)
    if not self:isApplyStillCurrent(applyToken) then return end

    local model = self.shared:getCharacterAppearanceModel(userId)
    if not model then return end
    if not self:isApplyStillCurrent(applyToken) then model:Destroy(); return end

    clearCopyChildren(char)

    local sourceModel = model
    local humModel = nil
    local bodyModel = nil

    local hasHead = sourceModel:FindFirstChild("Head") ~= nil
    local hasAnyPart = hasAnySourceBodyPart(sourceModel)

    if not hasHead or not hasAnyPart then
        local ok, created = pcall(function() return game:GetService("Players"):CreateHumanoidModelFromUserId(userId) end)
        if ok and created then
            humModel = created
            sourceModel = humModel
        end
    end

    if not self:isApplyStillCurrent(applyToken) then
        if humModel then humModel:Destroy() end
        model:Destroy()
        return
    end

    local targetDesc = self.shared:getTargetDescriptionCached(userId)

    local bodyApplied = applyBodyFromDescription(targetDesc, char)
    task.wait()

    local postDescriptionColorSnapshot = nil
    if bodyApplied then
        postDescriptionColorSnapshot = self.shared:snapshotCharacterColors(char)
    end

    local delayedSkinSnapshot = nil
    if postDescriptionColorSnapshot and postDescriptionColorSnapshot.bodyColors then
        delayedSkinSnapshot = {
            bodyColors = postDescriptionColorSnapshot.bodyColors:Clone(),
            partColors = {},
        }
        for partName, brickColor in pairs(postDescriptionColorSnapshot.partColors or {}) do
            delayedSkinSnapshot.partColors[partName] = brickColor
        end
    end

    if not self:isApplyStillCurrent(applyToken) then
        self.shared:destroyColorSnapshot(postDescriptionColorSnapshot)
        self.shared:destroyColorSnapshot(delayedSkinSnapshot)
        if bodyModel then bodyModel:Destroy() end
        if humModel then humModel:Destroy() end
        model:Destroy()
        return
    end

    if bodyApplied and not bodyModel then
        local okBody, createdBody = pcall(function() return game:GetService("Players"):CreateHumanoidModelFromUserId(userId) end)
        if okBody and createdBody then
            bodyModel = createdBody
        end
    end

    local bodySourceModel = bodyModel or sourceModel
    local sourceHead = bodySourceModel:FindFirstChild("Head") or sourceModel:FindFirstChild("Head")
    local desiredFaceTexture = self.shared:resolveFaceTexture(userId, bodySourceModel, targetDesc)
    local sourcePartSizeMap = buildSourcePartSizeMap(bodySourceModel)
    local charPartMap = buildBasePartMap(char)
    local attachmentCarrierMap = buildAttachmentCarrierMap(charPartMap)

    local function enforceHeadVisualNow()
        applyHeadVisualFromSource(char, sourceHead, desiredFaceTexture)
    end

    for _, partName in ipairs(BODY_PART_NAMES) do
        if bodyApplied then
        else
            local src = bodySourceModel:FindFirstChild(partName) or sourceModel:FindFirstChild(partName)
            local dest = char:FindFirstChild(partName)
            if src and dest then
                dest.Transparency = src.Transparency

                local sm = src:FindFirstChildOfClass("SpecialMesh")
                local dm = dest:FindFirstChildOfClass("SpecialMesh")
                if sm then
                    if not dm then
                        dm = sm:Clone()
                        dm.Parent = dest
                    else
                        dm.MeshId = sm.MeshId
                        dm.TextureId = sm.TextureId
                        dm.Scale = sm.Scale
                        dm.Offset = sm.Offset
                    end
                elseif dm then
                    dm:Destroy()
                end

                pcall(function()
                    if src:IsA("MeshPart") and dest:IsA("MeshPart") then
                        dest.MeshId = src.MeshId
                        dest.TextureID = src.TextureID
                    end
                end)

                for _, att in ipairs(src:GetChildren()) do
                    if att:IsA("Attachment") then
                        local existing = dest:FindFirstChild(att.Name)
                        if existing then
                            existing.Position = att.Position
                            existing.Orientation = att.Orientation
                        else
                            att:Clone().Parent = dest
                        end
                    end
                end

            end
        end
    end

    enforceHeadVisualNow()

    if not self:isApplyStillCurrent(applyToken) then
        self.shared:destroyColorSnapshot(postDescriptionColorSnapshot)
        if bodyModel then bodyModel:Destroy() end
        if humModel then humModel:Destroy() end
        model:Destroy()
        return
    end

    for _, inst in ipairs(sourceModel:GetChildren()) do
        if shouldCloneClass(inst.ClassName) then
            if bodyApplied and inst.ClassName == "CharacterMesh" then
            else
                local clone = inst:Clone()
                clone.Parent = char
                if isAccessoryClass(clone.ClassName) then
                    self:scaleAccessoryOnce(clone, char, sourcePartSizeMap, charPartMap, attachmentCarrierMap)
                end
            end
        end
    end

    local rigRefreshToken = 0
    local function requestRigAndFaceRefresh(delaySeconds)
        rigRefreshToken = rigRefreshToken + 1
        local token = rigRefreshToken
        task.delay(delaySeconds or 0, function()
            if token ~= rigRefreshToken then return end
            if not self:isApplyStillCurrent(applyToken) then return end
            if not char.Parent then return end
            local h = char:FindFirstChildOfClass("Humanoid")
            if h then pcall(function() h:BuildRigFromAttachments() end) end
            enforceHeadVisualNow()
        end)
    end

    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then pcall(function() hum:BuildRigFromAttachments() end) end

    if not self:isApplyStillCurrent(applyToken) then
        self.shared:destroyColorSnapshot(postDescriptionColorSnapshot)
        self.shared:destroyColorSnapshot(delayedSkinSnapshot)
        if bodyModel then bodyModel:Destroy() end
        if humModel then humModel:Destroy() end
        model:Destroy()
        return
    end

    self:enforceSkinColorFromDescription(targetDesc, char, bodySourceModel, postDescriptionColorSnapshot)
    self.shared:destroyColorSnapshot(postDescriptionColorSnapshot)
    enforceHeadVisualNow()

    task.defer(function()
        local retryDelays = { 0.1, 0.28, 0.55 }
        for _, dt in ipairs(retryDelays) do
            task.wait(dt)
            if not self:isApplyStillCurrent(applyToken) then
                self.shared:destroyColorSnapshot(delayedSkinSnapshot)
                return
            end
            if not char.Parent then
                self.shared:destroyColorSnapshot(delayedSkinSnapshot)
                return
            end

            if delayedSkinSnapshot then
                if delayedSkinSnapshot.bodyColors then
                    local okClone, bcClone = pcall(function() return delayedSkinSnapshot.bodyColors:Clone() end)
                    if okClone and bcClone then
                        pcall(function()
                            local currentBC = char:FindFirstChildOfClass("BodyColors")
                            if currentBC then currentBC:Destroy() end
                            bcClone.Parent = char
                        end)
                    end
                end
                for partName, brickColor in pairs(delayedSkinSnapshot.partColors or {}) do
                    local part = char:FindFirstChild(partName)
                    if part and part:IsA("BasePart") and brickColor then
                        pcall(function() part.BrickColor = brickColor end)
                    end
                end
                self:enforceSkinColorFromDescription(nil, char, nil, delayedSkinSnapshot)
            else
                self:enforceSkinColorFromDescription(targetDesc, char, nil, nil)
            end
            enforceHeadVisualNow()
        end

        self.shared:destroyColorSnapshot(delayedSkinSnapshot)
    end)

    self:disconnectAppearanceHooks()
    self.appearanceChildConn = char.ChildAdded:Connect(function(child)
        if isAccessoryClass(child.ClassName) then
            task.defer(function()
                if not self:isApplyStillCurrent(applyToken) then return end
                if not char.Parent then return end
                local livePartMap = buildBasePartMap(char)
                local liveCarrierMap = buildAttachmentCarrierMap(livePartMap)
                self:scaleAccessoryOnce(child, char, sourcePartSizeMap, livePartMap, liveCarrierMap)
                requestRigAndFaceRefresh(0.03)
            end)
        elseif child.Name == "Head" or child:IsA("Decal") then
            requestRigAndFaceRefresh(0.02)
        end
    end)

    local scaleRefreshScheduled = false
    local scaleRefreshQueued = false
    local function scheduleScaleRefresh()
        if scaleRefreshScheduled then
            scaleRefreshQueued = true
            return
        end

        scaleRefreshScheduled = true
        task.delay(0.03, function()
            scaleRefreshScheduled = false
            if not self:isApplyStillCurrent(applyToken) then self:disconnectAppearanceHooks(); return end
            if not char.Parent then self:disconnectAppearanceHooks(); return end
            local livePartMap = buildBasePartMap(char)
            local liveCarrierMap = buildAttachmentCarrierMap(livePartMap)
            self:scaleAllAccessories(char, sourcePartSizeMap, livePartMap, liveCarrierMap)
            requestRigAndFaceRefresh(0.02)
            if scaleRefreshQueued then
                scaleRefreshQueued = false
                scheduleScaleRefresh()
            end
        end)
    end

    local function onScaleValueChanged()
        scheduleScaleRefresh()
    end

    local hScale = char:FindFirstChildOfClass("Humanoid")
    if hScale then
        local function tryBindScaleValue(nv)
            if not nv or not nv:IsA("NumberValue") then return end
            if not SCALE_VALUE_SET[nv.Name] then return end
            local conn = nv:GetPropertyChangedSignal("Value"):Connect(onScaleValueChanged)
            self.appearanceScaleValueConns[#self.appearanceScaleValueConns + 1] = conn
        end

        for _, child in ipairs(hScale:GetChildren()) do
            tryBindScaleValue(child)
        end

        local childAddedConn = hScale.ChildAdded:Connect(function(child)
            tryBindScaleValue(child)
        end)
        self.appearanceScaleValueConns[#self.appearanceScaleValueConns + 1] = childAddedConn
    end

    task.delay(0.2, onScaleValueChanged)

    if bodyModel then bodyModel:Destroy() end
    if humModel then humModel:Destroy() end
    model:Destroy()
end

function OutfitMimic:apply(userId)
    if not self.active then return false end

    local char = self.localPlayer.Character
    if not char then return false end

    self.applySerial = self.applySerial + 1
    local thisApply = self.applySerial

    self.targetUserId = userId
    self.currentUserId = userId

    self:cleanupForSwitch(char)

    task.spawn(function()
        if not self.active then return end
        if thisApply ~= self.applySerial then return end
        self:applyAppearance(userId, char, thisApply)
    end)

    return true
end

function OutfitMimic:setTarget(target)
    local uid = nil
    if type(target) == "number" then
        uid = math.floor(target)
    else
        uid = self.shared:resolveUserToId(target)
    end

    if not uid then return false end
    if uid == self.currentUserId and self.localPlayer.Character and self.localPlayer.Character.Parent then
        return true
    end

    return self:apply(uid)
end

function OutfitMimic:reapply()
    local uid = self.currentUserId or self.targetUserId
    if not uid then return false end
    return self:apply(uid)
end

function OutfitMimic:onCharacterAdded(char)
    if not self.active then return end

    self:disconnectAppearanceHooks()

    local uid = self.currentUserId or self.targetUserId
    if not uid then return end

    local hum = char:WaitForChild("Humanoid", 10)
    if not hum then return end

    task.wait(0.5)
    if not self.active or not char.Parent then return end

    self:apply(uid)
end

function OutfitMimic:setEnabled(enabled)
    enabled = enabled == true
    if self.active == enabled then return end

    self.active = enabled
    if not enabled then
        self.applySerial = self.applySerial + 1
        self:disconnectAppearanceHooks()
        local char = self.localPlayer.Character
        if char then self:cleanupForSwitch(char) end
    else
        self:reapply()
    end
end

function OutfitMimic:cleanup()
    self.active = false
    self.applySerial = self.applySerial + 1
    self.targetUserId = nil
    self.currentUserId = nil
    self:disconnectAppearanceHooks()
end

return OutfitMimic
