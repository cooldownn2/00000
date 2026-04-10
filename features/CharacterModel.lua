local Players = game:GetService("Players")

local clock = os.clock
local floor = math.floor

local CharacterModel = {}

local Settings
local LP
local isUnloaded

local RETRY_DELAY_SECONDS = 2

local _cachedQuery = nil
local _cachedUserId = nil
local _cachedDescription = nil

local _appliedCharacter = nil
local _appliedQuery = ""
local _nextRetryAt = 0
local _resolveInFlight = false

local function normalizeQuery(raw)
    if raw == nil then return "" end

    if type(raw) == "number" then
        if raw <= 0 then return "" end
        return tostring(floor(raw + 0.5))
    end

    local text = tostring(raw)
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

local function resolveOnlineUserId(query)
    local lower = string.lower(query)
    local partialMatch = nil

    for _, plr in ipairs(Players:GetPlayers()) do
        local userIdStr = tostring(plr.UserId)
        if userIdStr == query then
            return plr.UserId
        end

        local nameLower = string.lower(plr.Name)
        local displayLower = string.lower(plr.DisplayName)

        if nameLower == lower or displayLower == lower then
            return plr.UserId
        end

        if not partialMatch then
            if string.find(nameLower, lower, 1, true) or string.find(displayLower, lower, 1, true) then
                partialMatch = plr.UserId
            end
        end
    end

    return partialMatch
end

local function resolveUserId(query)
    local n = tonumber(query)
    if n and n > 0 then
        return floor(n + 0.5)
    end

    local onlineUserId = resolveOnlineUserId(query)
    if onlineUserId then
        return onlineUserId
    end

    local ok, userId = pcall(Players.GetUserIdFromNameAsync, Players, query)
    if ok and type(userId) == "number" and userId > 0 then
        return userId
    end

    return nil
end

local function getDescriptionForQuery(query)
    if query == _cachedQuery and _cachedDescription and _cachedUserId then
        return _cachedDescription, _cachedUserId
    end

    local userId = resolveUserId(query)
    if not userId then return nil, nil end

    if userId == _cachedUserId and _cachedDescription then
        _cachedQuery = query
        return _cachedDescription, userId
    end

    local ok, description = pcall(Players.GetHumanoidDescriptionFromUserId, Players, userId)
    if not ok or typeof(description) ~= "Instance" or not description:IsA("HumanoidDescription") then
        return nil, userId
    end

    if _cachedDescription and _cachedDescription ~= description then
        pcall(function() _cachedDescription:Destroy() end)
    end

    _cachedQuery = query
    _cachedUserId = userId
    _cachedDescription = description

    return description, userId
end

local function applyDescription(humanoid, description)
    if not humanoid or not description then return false end

    local clone = description:Clone()
    local ok = pcall(function()
        if humanoid.ApplyDescriptionReset then
            humanoid:ApplyDescriptionReset(clone)
        else
            humanoid:ApplyDescription(clone)
        end
    end)
    clone:Destroy()

    return ok
end

local function shouldRun()
    return Settings.CharacterModelEnabled == true
end

local function requestApply(char, query)
    if _resolveInFlight then return end
    _resolveInFlight = true

    task.spawn(function()
        local ok = false
        local now = clock()

        repeat
            if isUnloaded and isUnloaded() then break end
            if not shouldRun() then break end

            local currentQuery = normalizeQuery(Settings.CharacterModelUserId)
            if currentQuery == "" or currentQuery ~= query then break end

            local currentChar = LP and LP.Character
            if not currentChar or currentChar ~= char then break end

            local hum = currentChar:FindFirstChildOfClass("Humanoid")
            if not hum then break end

            local description = getDescriptionForQuery(query)
            if not description then break end

            ok = applyDescription(hum, description)
        until true

        if ok then
            _appliedCharacter = char
            _appliedQuery = query
            _nextRetryAt = 0
        else
            _nextRetryAt = now + RETRY_DELAY_SECONDS
        end

        _resolveInFlight = false
    end)
end

local function applyCurrent()
    if isUnloaded and isUnloaded() then return end
    if not shouldRun() then return end

    local query = normalizeQuery(Settings.CharacterModelUserId)
    if query == "" then return end

    local char = LP and LP.Character
    if not char then return end

    if char == _appliedCharacter and query == _appliedQuery then
        return
    end

    local now = clock()
    if now < _nextRetryAt then
        return
    end

    requestApply(char, query)
end

local function onCharacterAdded()
    _appliedCharacter = nil
    _nextRetryAt = 0
    task.defer(applyCurrent)
end

local function cleanup()
    _appliedCharacter = nil
    _appliedQuery = ""
    _nextRetryAt = 0
    _resolveInFlight = false

    _cachedQuery = nil
    _cachedUserId = nil
    if _cachedDescription then
        pcall(function() _cachedDescription:Destroy() end)
        _cachedDescription = nil
    end
end

local function init(deps)
    Settings = deps.Settings
    LP = deps.LP or Players.LocalPlayer
    isUnloaded = deps.isUnloaded
end

CharacterModel.init = init
CharacterModel.update = applyCurrent
CharacterModel.onCharacterAdded = onCharacterAdded
CharacterModel.cleanup = cleanup

return CharacterModel