local State, safeCall
local GH, MainEvent, oldShoot, mt, oldNamecall, oldIndex
local isStoredShootArgsValid
local Taps
local SilentAim
local ForceHit
local Settings
local Players
local LP, UIS, Mouse
local hookedShoot, hookedNamecall, hookedIndex
local gameStyle
local random = math.random
local HUGE = math.huge
local UI_SPOOFER_RESOLVE_TTL = 1
local _uiSpooferLastResolvedAt = 0
local _uiSpooferLastInput = nil
local _uiSpooferLastResolvedUserId = nil
local GETGENV_FN = rawget(_G, "getgenv")
local RUNTIME_ENV = (type(GETGENV_FN) == "function" and GETGENV_FN()) or _G
local SETREADONLY_FN = rawget(RUNTIME_ENV, "setreadonly") or rawget(_G, "setreadonly")
local GETNAMECALLMETHOD_FN = rawget(RUNTIME_ENV, "getnamecallmethod") or rawget(_G, "getnamecallmethod")
local HOOKMETAMETHOD_FN = rawget(RUNTIME_ENV, "hookmetamethod") or rawget(_G, "hookmetamethod")

local MOUSE1 = Enum.UserInputType.MouseButton1
local ASSIST_MIN_INTERVAL = 0.05
local TAP_TIME_STEP = 1 / 120
local TAP_TIME_JITTER = 0.0005
local _lastAssistSendAt = 0
local _assignIndexInstalled = false
local _assignNamecallInstalled = false

local function isFiniteNumber(value)
    return type(value) == "number" and value == value and value > -HUGE and value < HUGE
end

local function isVector3(value)
    return typeof(value) == "Vector3"
end

local function isValidHitInstance(value)
    return typeof(value) == "Instance" and value.Parent ~= nil
end

local function normalizeText(value)
    local text = tostring(value or "")
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

local function getUISpooferTargetInput()
    if not Settings then return "" end

    local target = normalizeText(Settings.UISpooferUser)
    if target ~= "" then return target end

    target = normalizeText(Settings.AvatarSpooferUser)
    if target ~= "" then return target end

    return ""
end

local function resolveUISpooferTargetUserId()
    if not Settings or not Players then return nil end
    if Settings.UISpooferEnabled ~= true then
        _uiSpooferLastInput = nil
        _uiSpooferLastResolvedUserId = nil
        _uiSpooferLastResolvedAt = 0
        return nil
    end

    local input = getUISpooferTargetInput()
    if input == "" then return nil end

    local now = os.clock()
    if input == _uiSpooferLastInput
        and _uiSpooferLastResolvedUserId
        and (now - _uiSpooferLastResolvedAt) < UI_SPOOFER_RESOLVE_TTL then
        return _uiSpooferLastResolvedUserId
    end

    local resolvedUserId = nil
    local numeric = tonumber(input)
    if numeric then
        resolvedUserId = math.floor(numeric)
    else
        local ok, lookedUp = pcall(function()
            return Players:GetUserIdFromNameAsync(input)
        end)
        if ok and type(lookedUp) == "number" then
            resolvedUserId = math.floor(lookedUp)
        end
    end

    _uiSpooferLastInput = input
    _uiSpooferLastResolvedAt = now
    _uiSpooferLastResolvedUserId = resolvedUserId
    return resolvedUserId
end

local function remapUISpooferLocalPlayerIndex(self, key)
    if not LP or not key then return nil end
    if not rawequal(self, LP) then return nil end

    local targetUserId = resolveUISpooferTargetUserId()
    if not targetUserId then return nil end

    -- Safe global fallback: CharacterAppearanceId is inspect/avatar specific.
    if key == "CharacterAppearanceId" then
        return targetUserId
    end

    return nil
end

local function remapUISpooferAvatarMethodArgs(self, method, ...)
    if not Players or not LP or not rawequal(self, Players) then return nil end

    if method ~= "GetCharacterAppearanceInfoAsync"
        and method ~= "GetCharacterAppearanceAsync"
        and method ~= "GetHumanoidDescriptionFromUserId"
        and method ~= "GetNameFromUserIdAsync"
        and method ~= "GetUserThumbnailAsync" then
        return nil
    end

    local targetUserId = resolveUISpooferTargetUserId()
    if not targetUserId then return nil end

    local localUserId = tonumber(LP.UserId)
    if not localUserId then return nil end

    local args = {...}
    local requestedUserId = tonumber(args[1])
    if not requestedUserId then return nil end

    if math.floor(requestedUserId) ~= math.floor(localUserId) then
        return nil
    end

    args[1] = targetUserId
    return args
end

local function rewriteUISpooferUrl(rawUrl, localUserId, targetUserId)
    if type(rawUrl) ~= "string" or rawUrl == "" then return nil end

    local lowerUrl = string.lower(rawUrl)
    local hasIdentityRoute = lowerUrl:find("avatar", 1, true) ~= nil
        or lowerUrl:find("users", 1, true) ~= nil
        or lowerUrl:find("inventory", 1, true) ~= nil
        or lowerUrl:find("catalog", 1, true) ~= nil
    if not hasIdentityRoute then
        return nil
    end

    local localIdText = tostring(localUserId)
    local targetIdText = tostring(targetUserId)
    local rewritten = rawUrl
    local changed = false

    local v1, c1 = rewritten:gsub("([?&][uU][sS][eE][rR][iI][dD]=)" .. localIdText, "%1" .. targetIdText)
    if c1 > 0 then rewritten = v1; changed = true end

    local v2, c2 = rewritten:gsub("([?&][uU][sS][eE][rR][iI][dD][sS]=)" .. localIdText, "%1" .. targetIdText)
    if c2 > 0 then rewritten = v2; changed = true end

    local v3, c3 = rewritten:gsub("([/][uU][sS][eE][rR][sS][/-])" .. localIdText .. "([/?#&])", "%1" .. targetIdText .. "%2")
    if c3 > 0 then rewritten = v3; changed = true end

    local v4, c4 = rewritten:gsub("([/][uU][sS][eE][rR][sS][/-])" .. localIdText .. "$", "%1" .. targetIdText)
    if c4 > 0 then rewritten = v4; changed = true end

    if changed then return rewritten end
    return nil
end

local function remapUISpooferHttpApiArgs(self, method, ...)
    if not LP or not method then return nil end
    if method ~= "GetAsync" and method ~= "PostAsync" and method ~= "RequestAsync" then return nil end

    local className = ""
    pcall(function() className = tostring(self.ClassName or "") end)
    className = string.lower(className)
    if className ~= "httprbxapiservice" then
        return nil
    end

    local targetUserId = resolveUISpooferTargetUserId()
    if not targetUserId then return nil end

    local localUserId = tonumber(LP.UserId)
    if not localUserId or localUserId == targetUserId then return nil end

    local args = {...}
    if method == "RequestAsync" and type(args[1]) == "table" then
        local request = args[1]
        local url = request.Url
        local rewritten = rewriteUISpooferUrl(url, localUserId, targetUserId)
        if rewritten and rewritten ~= url then
            local requestCopy = {}
            for k, v in pairs(request) do requestCopy[k] = v end
            requestCopy.Url = rewritten
            args[1] = requestCopy
            return args
        end
        return nil
    end

    local url = args[1]
    local rewritten = rewriteUISpooferUrl(url, localUserId, targetUserId)
    if rewritten and rewritten ~= url then
        args[1] = rewritten
        return args
    end

    return nil
end

local function cloneArray(arr)
    if table.clone then return table.clone(arr) end
    local out = {}
    for i = 1, #arr do
        out[i] = arr[i]
    end
    return out
end

local function clonePayload(payload)
    local copy = {}
    for k, v in pairs(payload) do
        if k == "Pellets" and type(v) == "table" then
            local pellets = table.create and table.create(#v) or {}
            for i = 1, #v do
                local p = v[i]
                if type(p) == "table" then
                    pellets[i] = {
                        HitPosition = p.HitPosition,
                        HitInstance = p.HitInstance,
                    }
                else
                    pellets[i] = p
                end
            end
            copy[k] = pellets
        else
            copy[k] = v
        end
    end
    return copy
end

local function getFreshTimestamp(burstIndex)
    local ok, serverNow = pcall(workspace.GetServerTimeNow, workspace)
    local base = (ok and type(serverNow) == "number") and serverNow or os.clock()
    local idx = tonumber(burstIndex) or 0
    return base + (idx * TAP_TIME_STEP) + ((random() - 0.5) * TAP_TIME_JITTER)
end

local function normalizeZeehoodPayload(payload, burstIndex, forceFreshTimestamp)
    if type(payload) ~= "table" then return nil end
    if type(payload.ToolName) ~= "string" or payload.ToolName == "" then return nil end

    local out = clonePayload(payload)
    local fallbackPos = isVector3(out.HitPosition) and out.HitPosition or nil
    local fallbackHit = isValidHitInstance(out.HitInstance) and out.HitInstance or nil

    if type(out.Pellets) == "table" then
        local foundPelletPos = nil
        local foundPelletHit = nil
        for i, pellet in ipairs(out.Pellets) do
            if type(pellet) == "table" then
                local hitPos = isVector3(pellet.HitPosition) and pellet.HitPosition or fallbackPos
                local hitInst = isValidHitInstance(pellet.HitInstance) and pellet.HitInstance or fallbackHit
                if hitPos then
                    pellet.HitPosition = hitPos
                    pellet.HitInstance = hitInst
                    if not foundPelletPos then foundPelletPos = hitPos end
                    if not foundPelletHit and hitInst then foundPelletHit = hitInst end
                elseif foundPelletPos then
                    pellet.HitPosition = foundPelletPos
                    pellet.HitInstance = foundPelletHit
                else
                    return nil
                end
            end
        end
        if not fallbackPos then fallbackPos = foundPelletPos end
        if not fallbackHit then fallbackHit = foundPelletHit end
        if not isVector3(out.HitPosition) then out.HitPosition = fallbackPos end
        if out.HitInstance ~= nil and not isValidHitInstance(out.HitInstance) then
            out.HitInstance = fallbackHit
        elseif out.HitInstance == nil then
            out.HitInstance = fallbackHit
        end
    else
        if not fallbackPos then return nil end
        out.HitPosition = fallbackPos
        if out.HitInstance ~= nil and not isValidHitInstance(out.HitInstance) then
            out.HitInstance = fallbackHit
        end
    end

    if not isVector3(out.StartPoint) then
        out.StartPoint = out.HitPosition
    end
    if not isVector3(out.StartPoint) then
        return nil
    end

    if forceFreshTimestamp or not isFiniteNumber(out.Timestamp) then
        out.Timestamp = getFreshTimestamp(burstIndex)
    end

    return out
end

local function buildZeehoodSendArgs(args, burstIndex, forceFreshTimestamp)
    if type(args) ~= "table" then return nil end
    local payload = args[2]
    local normalized = normalizeZeehoodPayload(payload, burstIndex, forceFreshTimestamp)
    if not normalized then return nil end

    local out = cloneArray(args)
    out[2] = normalized
    return out
end

local function setReadOnlySafe(value)
    if type(SETREADONLY_FN) == "function" then
        pcall(SETREADONLY_FN, mt, value)
    end
end

local function tryAssignMetamethod(fieldName, hookFn)
    local ok = false
    setReadOnlySafe(false)
    ok = pcall(function()
        if mt[fieldName] ~= hookFn then
            mt[fieldName] = hookFn
        end
    end)
    setReadOnlySafe(true)
    return ok
end

local function trySendZeehoodWallbangAssist()
    if gameStyle ~= "zeehood" then return end
    if not Settings or Settings.VisCheck == true then return end
    if not ForceHit or not ForceHit.sendAssistShot then return end

    local blocked = false
    pcall(function()
        if SilentAim.shouldUseZeehoodAssistShot then
            blocked = (SilentAim.shouldUseZeehoodAssistShot() == true)
        end
    end)
    if not blocked then return end

    local now = os.clock()
    if now - _lastAssistSendAt < ASSIST_MIN_INTERVAL then return end
    _lastAssistSendAt = now

    -- Defer so native gun local flow finishes first.
    task.defer(function()
        pcall(ForceHit.sendAssistShot)
    end)
end

local function buildHooks()
    hookedShoot = function(data)
        if State.Unloaded then return oldShoot(data) end
        local shootData = data
        if type(data) == "table" then
            shootData = SilentAim.prepareShootData(data)
        end
        return oldShoot(shootData)
    end

    hookedIndex = function(self, key)
        if State.Unloaded then return oldIndex(self, key) end

        if gameStyle == "zeehood" and Mouse and rawequal(self, Mouse) and key == "Hit" then
            local firing = UIS and UIS:IsMouseButtonPressed(MOUSE1)
            if firing then
                local ok, aimPos = pcall(function()
                    if SilentAim.getCurrentMouseHitPosition then
                        return SilentAim.getCurrentMouseHitPosition()
                    end
                    if SilentAim.getCurrentAimPosition then
                        return SilentAim.getCurrentAimPosition()
                    end
                    return nil
                end)
                if ok and typeof(aimPos) == "Vector3" then
                    local cOk, aimedCf = pcall(CFrame.new, aimPos)
                    if cOk and aimedCf then
                        return aimedCf
                    end
                end
            end
        end

        local remappedIdentity = remapUISpooferLocalPlayerIndex(self, key)
        if remappedIdentity ~= nil then
            return remappedIdentity
        end

        return oldIndex(self, key)
    end

    hookedNamecall = function(self, ...)
        if State.Unloaded then return oldNamecall(self, ...) end

        local method = nil
        if type(GETNAMECALLMETHOD_FN) == "function" then
            local okMethod, resolvedMethod = pcall(GETNAMECALLMETHOD_FN)
            if okMethod and type(resolvedMethod) == "string" then
                method = resolvedMethod
            end
        end
        if not method then
            return oldNamecall(self, ...)
        end

        local remappedHttpArgs = remapUISpooferHttpApiArgs(self, method, ...)
        if remappedHttpArgs then
            return oldNamecall(self, table.unpack(remappedHttpArgs))
        end

        local remappedAvatarArgs = remapUISpooferAvatarMethodArgs(self, method, ...)
        if remappedAvatarArgs then
            return oldNamecall(self, table.unpack(remappedAvatarArgs))
        end

        if method ~= "FireServer" or not rawequal(self, MainEvent) then
            return oldNamecall(self, ...)
        end

        local args = {...}

        if gameStyle == "zeehood" then
            -- Zeehood stability: strict native passthrough for manual shooting.
            if isStoredShootArgsValid(args) then
                local tapCount = 1
                pcall(function()
                    SilentAim.recordShootArgs(args)
                    tapCount = Taps.getTapCount(args)
                end)

                local baseArgs = buildZeehoodSendArgs(args, 0, false) or args
                local result = oldNamecall(self, table.unpack(baseArgs))
                for burstIndex = 1, tapCount - 1 do
                    local tapArgs = buildZeehoodSendArgs(args, burstIndex, true) or baseArgs
                    oldNamecall(self, table.unpack(tapArgs))
                end

                trySendZeehoodWallbangAssist()
                return result
            end
            return oldNamecall(self, ...)
        end

        -- Dashood / positional-args style.
        SilentAim.recordShootArgs(args)
        if SilentAim.shouldRedirectFireServer(args) then
            SilentAim.applyFireServerRedirect(args)
            local result = oldNamecall(self, table.unpack(args))
            local extra = Taps.getTapCount(args) - 1
            for _ = 1, extra do
                oldNamecall(self, table.unpack(args))
            end
            return result
        end

        if isStoredShootArgsValid(args) then
            local result = oldNamecall(self, ...)
            local extra = Taps.getTapCount(args) - 1
            for _ = 1, extra do
                oldNamecall(self, table.unpack(args))
            end
            return result
        end

        return oldNamecall(self, ...)
    end
end

local function install()
    if GH then
        pcall(function()
            if GH.shoot ~= hookedShoot then GH.shoot = hookedShoot end
        end)
    end

    local indexOk = tryAssignMetamethod("__index", hookedIndex)
    local namecallOk = tryAssignMetamethod("__namecall", hookedNamecall)

    _assignIndexInstalled = indexOk
    _assignNamecallInstalled = namecallOk

    if not indexOk and type(HOOKMETAMETHOD_FN) == "function" then
        indexOk = pcall(function()
            HOOKMETAMETHOD_FN(game, "__index", hookedIndex)
        end)
    end

    if not namecallOk and type(HOOKMETAMETHOD_FN) == "function" then
        namecallOk = pcall(function()
            HOOKMETAMETHOD_FN(game, "__namecall", hookedNamecall)
        end)
    end

    if not indexOk or not namecallOk then
        warn("[Hooks] partial install: __index=" .. tostring(indexOk) .. " __namecall=" .. tostring(namecallOk))
    end
end

local function uninstall()
    if GH then
        pcall(function()
            if GH.shoot == hookedShoot then GH.shoot = oldShoot end
        end)
    end
    safeCall(function()
        if _assignIndexInstalled or _assignNamecallInstalled then
            setReadOnlySafe(false)
            if _assignIndexInstalled and mt.__index == hookedIndex then mt.__index = oldIndex end
            if _assignNamecallInstalled and mt.__namecall == hookedNamecall then mt.__namecall = oldNamecall end
            setReadOnlySafe(true)
        end
        _assignIndexInstalled = false
        _assignNamecallInstalled = false
    end, "CleanupFails")
end

local function init(deps)
    State                  = deps.State
    safeCall               = deps.safeCall
    GH                     = deps.GH
    MainEvent              = deps.MainEvent
    oldShoot               = deps.oldShoot
    mt                     = deps.mt
    oldNamecall            = deps.oldNamecall
    oldIndex               = deps.oldIndex
    isStoredShootArgsValid = deps.isStoredShootArgsValid
    Taps                   = deps.Taps
    SilentAim              = deps.SilentAim
    ForceHit               = deps.ForceHit
    Settings               = deps.Settings
    Players                = deps.Players
    LP                     = deps.LP
    UIS                    = deps.UIS
    Mouse                  = LP and LP:GetMouse() or nil
    gameStyle              = deps.gameStyle
    SilentAim.init(deps)
    buildHooks()
end

return {
    init      = init,
    install   = install,
    uninstall = uninstall,
}
