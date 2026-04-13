local Players = game:GetService("Players")
local InsertService = game:GetService("InsertService")

local TARGET_INPUT = "7450926784"
local PACKAGE_THRESHOLD = 10000000000

local SLOT_FIELDS = {
    { slot = "run", field = "RunAnimation" },
    { slot = "walk", field = "WalkAnimation" },
    { slot = "idle", field = "IdleAnimation" },
    { slot = "jump", field = "JumpAnimation" },
    { slot = "fall", field = "FallAnimation" },
    { slot = "climb", field = "ClimbAnimation" },
    { slot = "swim", field = "SwimAnimation" },
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
    local numeric = tostring(raw):match("%d+")
    if not numeric then return nil end
    if (tonumber(numeric) or 0) <= 0 then return nil end
    return "rbxassetid://" .. numeric
end

local function numericFromId(raw)
    if raw == nil then return nil end
    local numeric = tostring(raw):match("%d+")
    return numeric and tonumber(numeric) or nil
end

local function resolveUserId(input)
    if type(input) == "number" then
        return math.floor(input)
    end

    local text = tostring(input or "")
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    if text == "" then return nil end

    local n = tonumber(text)
    if n then return math.floor(n) end

    text = text:gsub("^@", "")
    local ok, uid = pcall(function()
        return Players:GetUserIdFromNameAsync(text)
    end)
    if ok and uid then return uid end
    return nil
end

local function matchesHint(name, slot)
    local lower = string.lower(name or "")
    local hints = SLOT_HINTS[slot] or {}
    for _, hint in ipairs(hints) do
        if hint ~= "" and lower:find(hint, 1, true) then
            return true
        end
    end
    return false
end

local function extractAnimationFromLoadedAsset(assetModel, slot)
    if not assetModel then return nil end

    local allAnimations = {}
    for _, inst in ipairs(assetModel:GetDescendants()) do
        if inst:IsA("Animation") then
            allAnimations[#allAnimations + 1] = inst
        end
    end

    if #allAnimations == 0 then return nil end

    for _, anim in ipairs(allAnimations) do
        if matchesHint(anim.Name, slot) then
            return anim
        end
    end

    for _, anim in ipairs(allAnimations) do
        local parentName = anim.Parent and anim.Parent.Name or ""
        if matchesHint(parentName, slot) then
            return anim
        end
    end

    return allAnimations[1]
end

local function resolvePlayableAnimation(rawId, slot)
    local cleaned = normalizeAnimationId(rawId)
    if not cleaned then
        return nil, "invalid-input"
    end

    local numeric = numericFromId(cleaned)
    if not numeric then
        return nil, "missing-numeric"
    end

    local likelyPackage = numeric >= PACKAGE_THRESHOLD

    local okAsset, assetModel = pcall(function()
        return InsertService:LoadAsset(numeric)
    end)

    if okAsset and assetModel then
        local picked = extractAnimationFromLoadedAsset(assetModel, slot)
        local resolved = picked and normalizeAnimationId(picked.AnimationId) or nil
        local pickedName = picked and picked.Name or nil
        local pickedParent = picked and picked.Parent and picked.Parent.Name or nil
        pcall(function() assetModel:Destroy() end)

        if resolved then
            return resolved, "resolved-from-asset", pickedName, pickedParent
        end

        if likelyPackage then
            return nil, "package-without-animation"
        end

        return cleaned, "kept-original-no-animation"
    end

    if likelyPackage then
        return nil, "package-load-failed"
    end

    return cleaned, "kept-original-load-failed"
end

local function run()
    local userId = resolveUserId(TARGET_INPUT)
    if not userId then
        warn("[StandaloneAnimationInspector] failed to resolve target: " .. tostring(TARGET_INPUT))
        return
    end

    local okDesc, desc = pcall(function()
        return Players:GetHumanoidDescriptionFromUserId(userId)
    end)
    if not okDesc or not desc then
        warn("[StandaloneAnimationInspector] failed to fetch HumanoidDescription for userId " .. tostring(userId))
        return
    end

    print("[StandaloneAnimationInspector] userId=" .. tostring(userId))

    for _, map in ipairs(SLOT_FIELDS) do
        local raw = desc[map.field]
        local rawNumeric = numericFromId(raw)
        local resolved, reason, pickedName, pickedParent = resolvePlayableAnimation(raw, map.slot)
        local resolvedNumeric = numericFromId(resolved)

        print(
            "[StandaloneAnimationInspector]",
            map.slot,
            "field=" .. map.field,
            "raw=" .. tostring(raw),
            "rawNumeric=" .. tostring(rawNumeric),
            "resolved=" .. tostring(resolved),
            "resolvedNumeric=" .. tostring(resolvedNumeric),
            "reason=" .. tostring(reason),
            "pickedName=" .. tostring(pickedName),
            "pickedParent=" .. tostring(pickedParent)
        )
    end
end

run()
