--[[
AnimationMimicStandaloneInspector.lua
Standalone animation slot inspector for a target Roblox user.

Usage:
1) Paste into your executor.
2) Set TARGET_USER_ID below.
3) Execute and inspect output per slot.
]]

local TARGET_USER_ID = 7450926784

local Players = game:GetService("Players")
local InsertService = game:GetService("InsertService")
local MarketplaceService = game:GetService("MarketplaceService")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local PACKAGE_ID_THRESHOLD = 10000000000

local SLOT_FIELDS = {
    run = "RunAnimation",
    walk = "WalkAnimation",
    idle = "IdleAnimation",
    jump = "JumpAnimation",
    fall = "FallAnimation",
    climb = "ClimbAnimation",
    swim = "SwimAnimation",
}

local SLOT_HINTS = {
    run = { "run" },
    walk = { "walk" },
    idle = { "idle", "animation1", "animation2" },
    jump = { "jump" },
    fall = { "fall" },
    climb = { "climb" },
    swim = { "swim" },
}

local function normalizeAnimationId(raw)
    if raw == nil then return nil end
    local s = tostring(raw)
    local n = tonumber(s:match("(%d+)"))
    if not n or n <= 0 then return nil end
    return "rbxassetid://" .. tostring(math.floor(n))
end

local function numericIdFromContentId(raw)
    if raw == nil then return nil end
    return tonumber(tostring(raw):match("(%d+)"))
end

local function findBestAnimationInAsset(assetModel, slotName)
    if not assetModel then return nil end

    local allAnimations = {}
    for _, inst in ipairs(assetModel:GetDescendants()) do
        if inst:IsA("Animation") then
            allAnimations[#allAnimations + 1] = inst
        end
    end

    if #allAnimations == 0 then return nil end

    local hints = SLOT_HINTS[slotName] or { tostring(slotName or "") }

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

local function getProductInfoSafe(numericId)
    local out = {
        ok = false,
        assetTypeId = nil,
        assetTypeName = nil,
        name = nil,
        creator = nil,
        rawError = nil,
    }

    local ok, info = pcall(function()
        return MarketplaceService:GetProductInfo(numericId)
    end)

    if not ok or type(info) ~= "table" then
        out.rawError = tostring(info)
        return out
    end

    out.ok = true
    out.assetTypeId = tonumber(info.AssetTypeId)
    out.assetTypeName = tostring(info.AssetTypeId)
    out.name = tostring(info.Name)

    if type(info.Creator) == "table" then
        out.creator = tostring(info.Creator.Name)
    end

    return out
end

local function keyframeCheck(contentId)
    local ok, seq = pcall(function()
        return KeyframeSequenceProvider:GetKeyframeSequenceAsync(contentId)
    end)

    local result = {
        ok = ok and seq ~= nil,
        keyframeCount = nil,
        rawError = nil,
    }

    if ok and seq then
        local okKeys, keys = pcall(function()
            return seq:GetKeyframes()
        end)
        if okKeys and type(keys) == "table" then
            result.keyframeCount = #keys
        end
        pcall(function() seq:Destroy() end)
    else
        result.rawError = tostring(seq)
    end

    return result
end

local function loadAssetProbe(numericId, slotName)
    local out = {
        ok = false,
        animationCount = 0,
        pickedAnimationId = nil,
        pickedAnimationName = nil,
        pickedParentName = nil,
        rawError = nil,
    }

    local ok, model = pcall(function()
        return InsertService:LoadAsset(numericId)
    end)

    if not ok or not model then
        out.rawError = tostring(model)
        return out
    end

    out.ok = true

    local allAnimations = {}
    for _, inst in ipairs(model:GetDescendants()) do
        if inst:IsA("Animation") then
            allAnimations[#allAnimations + 1] = inst
        end
    end

    out.animationCount = #allAnimations

    local picked = findBestAnimationInAsset(model, slotName)
    if picked then
        out.pickedAnimationId = normalizeAnimationId(picked.AnimationId)
        out.pickedAnimationName = picked.Name
        out.pickedParentName = picked.Parent and picked.Parent.Name or nil
    end

    pcall(function() model:Destroy() end)
    return out
end

local function resolvePlayableAnimationId(rawId, slotName)
    local cleaned = normalizeAnimationId(rawId)
    local numeric = numericIdFromContentId(cleaned)
    local likelyPackage = numeric and numeric >= PACKAGE_ID_THRESHOLD or false

    local result = {
        raw = rawId,
        cleaned = cleaned,
        numericId = numeric,
        likelyPackage = likelyPackage,
        productInfo = nil,
        keyframe = nil,
        loadAsset = nil,
        resolved = cleaned,
        reason = "cleaned",
    }

    if not cleaned or not numeric then
        result.resolved = nil
        result.reason = "invalid-id"
        return result
    end

    local productInfo = getProductInfoSafe(numeric)
    result.productInfo = productInfo

    local animationTypeValue = Enum.AssetType.Animation.Value
    if productInfo.ok and productInfo.assetTypeId and productInfo.assetTypeId == animationTypeValue then
        result.reason = "marketplace-assettype-animation"
        return result
    end

    local keyframe = keyframeCheck(cleaned)
    result.keyframe = keyframe
    if keyframe.ok then
        result.reason = "keyframe-sequence-valid"
        return result
    end

    local assetProbe = loadAssetProbe(numeric, slotName)
    result.loadAsset = assetProbe

    if assetProbe.ok and assetProbe.pickedAnimationId then
        result.resolved = assetProbe.pickedAnimationId
        result.reason = "resolved-from-loadasset"
        return result
    end

    if likelyPackage then
        result.resolved = nil
        result.reason = "unresolved-package-id"
    else
        result.resolved = cleaned
        result.reason = "fallback-nonpackage"
    end

    return result
end

local function printHeader(title)
    print(string.rep("=", 80))
    print(title)
    print(string.rep("=", 80))
end

local function inspectTarget(userId)
    printHeader("Animation Mimic Standalone Inspector")
    print("Target UserId:", userId)

    local okDesc, desc = pcall(function()
        return Players:GetHumanoidDescriptionFromUserId(userId)
    end)

    if not okDesc or not desc then
        warn("[Inspector] Failed to fetch HumanoidDescription:", desc)
        return
    end

    print("[Inspector] Description fetched successfully.")

    local summary = {
        total = 0,
        resolved = 0,
        unresolvedPackage = 0,
        invalid = 0,
    }

    for slotName, fieldName in pairs(SLOT_FIELDS) do
        summary.total = summary.total + 1
        local raw = desc[fieldName]
        local outcome = resolvePlayableAnimationId(raw, slotName)

        if outcome.resolved then
            summary.resolved = summary.resolved + 1
        elseif outcome.reason == "unresolved-package-id" then
            summary.unresolvedPackage = summary.unresolvedPackage + 1
        else
            summary.invalid = summary.invalid + 1
        end

        print(string.rep("-", 80))
        print("Slot:", slotName, "| Field:", fieldName)
        print("Raw:", tostring(outcome.raw))
        print("Cleaned:", tostring(outcome.cleaned))
        print("NumericId:", tostring(outcome.numericId), "| LikelyPackage:", tostring(outcome.likelyPackage))
        print("Resolved:", tostring(outcome.resolved), "| Reason:", tostring(outcome.reason))

        if outcome.productInfo then
            local p = outcome.productInfo
            print("ProductInfo:", "ok=" .. tostring(p.ok), "assetTypeId=" .. tostring(p.assetTypeId), "name=" .. tostring(p.name), "creator=" .. tostring(p.creator))
            if not p.ok and p.rawError then
                print("ProductInfoError:", tostring(p.rawError))
            end
        end

        if outcome.keyframe then
            local k = outcome.keyframe
            print("KeyframeCheck:", "ok=" .. tostring(k.ok), "count=" .. tostring(k.keyframeCount))
            if not k.ok and k.rawError then
                print("KeyframeError:", tostring(k.rawError))
            end
        end

        if outcome.loadAsset then
            local a = outcome.loadAsset
            print("LoadAsset:", "ok=" .. tostring(a.ok), "animationCount=" .. tostring(a.animationCount))
            print("LoadAssetPick:", "id=" .. tostring(a.pickedAnimationId), "name=" .. tostring(a.pickedAnimationName), "parent=" .. tostring(a.pickedParentName))
            if not a.ok and a.rawError then
                print("LoadAssetError:", tostring(a.rawError))
            end
        end
    end

    print(string.rep("=", 80))
    print("Summary:")
    print("Total Slots:", summary.total)
    print("Resolved:", summary.resolved)
    print("Unresolved Package IDs:", summary.unresolvedPackage)
    print("Invalid/Other Failures:", summary.invalid)
    print(string.rep("=", 80))
end

inspectTarget(TARGET_USER_ID)
