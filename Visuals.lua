local Visuals = {}

local settings, State, Camera, LP, screenGui
local ForceHitModule, ESPModule, KNOWN_BODY_PARTS

local wallRayParams = RaycastParams.new()
wallRayParams.FilterType  = Enum.RaycastFilterType.Exclude
wallRayParams.IgnoreWater = true

local infoLines        = {}
local infoHeaderLabel  = nil
local infoBg           = nil
local infoAccentBar    = nil
local infoBorderStroke = nil
local infoDivider      = nil
local overlayReady     = false

local INFO_UPDATE_RATE        = 1 / 50
local INFO_METRIC_UPDATE_RATE = 1 / 15
local WALL_UPDATE_RATE        = 1 / 15
local infoLastUpdate          = 0
local infoMetricLastUpdate    = 0
local infoWallLastUpdate      = 0

local VISUALS_FONT = Enum.Font.GothamBold
local LINE_COUNT   = 6
local TARGET_GAP   = 6

local LINES = {
    TRIGGERBOT = 1,
    CAMLOCK    = 2,
    FORCEHIT   = 3,
    TARGET     = 4,
    HP         = 5,
    TOOL       = 6,
}

local C_HP_HI  = Color3.fromRGB(74, 222, 128)
local C_HP_MID = Color3.fromRGB(250, 200, 40)
local C_HP_LO  = Color3.fromRGB(220, 65, 65)

local C_ACTIVE     = Color3.fromRGB(74, 222, 128)
local C_IDLE       = Color3.fromRGB(80, 88, 102)
local C_IN         = Color3.fromRGB(74, 222, 128)
local C_OUT        = Color3.fromRGB(220, 65, 65)
local C_TEXT       = Color3.fromRGB(195, 200, 210)
local C_ARMOR      = Color3.fromRGB(140, 200, 255)
local C_LABEL      = Color3.fromRGB(200, 200, 255)
local C_STAT_LABEL = Color3.fromRGB(200, 200, 255)
local C_GHOST      = Color3.fromRGB(62, 66, 78)
local C_BAR_IDLE   = Color3.fromRGB(55, 62, 78)
local C_ACCENT     = Color3.fromRGB(180, 120, 255)

local S_SEP        = "rgb(255,255,255)"
local S_ACTIVE, S_IDLE, S_IN, S_OUT, S_TEXT   = "", "", "", "", ""
local S_LABEL, S_ARMOR, S_STAT_LABEL           = "", "", ""
local S_GHOST, S_BAR_IDLE                      = "", ""

local metricState = {
    tbDist  = nil, tbInRange  = nil,
    camDist = nil, camInRange = nil,
    fhDist  = nil, fhInRange  = nil,
}

local cachedWallVisible = true
local cachedWallText    = "vis"
local cachedWallColorS  = ""

local renderCtx = {
    size    = 11,
    outline = true,
    baseX   = 0,
    baseY   = 0,
    lineH   = 15,
    style   = "Normal",
}

local cachedColors = {}

local function c3s(c)
    return string.format("rgb(%d,%d,%d)",
        math.floor(c.R * 255 + 0.5),
        math.floor(c.G * 255 + 0.5),
        math.floor(c.B * 255 + 0.5))
end

local function syncColors(colors)
    if not colors then return end
    local dirty = false
    for k, v in pairs(colors) do
        if cachedColors[k] ~= v then cachedColors[k] = v; dirty = true end
    end
    if not dirty then return end

    C_ACTIVE     = cachedColors["Active"]        or C_ACTIVE
    C_IDLE       = cachedColors["Idle"]          or C_IDLE
    C_IN         = cachedColors["In Range"]      or C_IN
    C_OUT        = cachedColors["Out Range"]     or C_OUT
    C_TEXT       = cachedColors["Text"]          or C_TEXT
    C_ACCENT     = cachedColors["Accent"]        or C_ACCENT
    C_LABEL      = cachedColors["Feature Label"] or C_LABEL
    C_STAT_LABEL = cachedColors["Stat Label"]    or C_STAT_LABEL
    C_ARMOR      = cachedColors["Armor Value"]   or C_ARMOR
    C_GHOST      = cachedColors["Ghost"]         or C_GHOST
    C_BAR_IDLE   = cachedColors["Bar Idle"]      or C_BAR_IDLE

    local sepC = cachedColors["Separator"]
    S_SEP = sepC and c3s(sepC) or "rgb(255,255,255)"

    S_ACTIVE     = c3s(C_ACTIVE)
    S_IDLE       = c3s(C_IDLE)
    S_IN         = c3s(C_IN)
    S_OUT        = c3s(C_OUT)
    S_TEXT       = c3s(C_TEXT)
    S_LABEL      = c3s(C_LABEL)
    S_ARMOR      = c3s(C_ARMOR)
    S_STAT_LABEL = c3s(C_STAT_LABEL)
    S_GHOST      = c3s(C_GHOST)
    S_BAR_IDLE   = c3s(C_BAR_IDLE)

    if infoAccentBar    then infoAccentBar.BackgroundColor3 = C_ACCENT end
    if infoBorderStroke then infoBorderStroke.Color         = C_ACCENT end

    cachedWallColorS = cachedWallVisible and S_ACTIVE or S_OUT
end

local function resolveStyle(raw)
    local s = string.lower(tostring(raw or "normal"))
    if s == "inverted" then return "Inverted"
    elseif s == "right" then return "Right"
    elseif s == "dynamic" then return "Dynamic"
    end
    return "Normal"
end

local function styleXAlign(style)
    if style == "Right" then return Enum.TextXAlignment.Right end
    return Enum.TextXAlignment.Left
end

local function newBg(style)
    local f = Instance.new("Frame")
    f.Name                   = "VisualsBg"
    f.BackgroundTransparency = 0.3
    f.BorderSizePixel        = 0
    f.ZIndex                 = 9
    f.Visible                = false
    f.Parent                 = screenGui

    if style == "Inverted" then
        f.BackgroundColor3 = Color3.fromRGB(230, 230, 240)
    else
        f.BackgroundColor3 = Color3.fromRGB(6, 8, 12)
    end

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = f

    local stroke = Instance.new("UIStroke")
    stroke.Color        = C_ACCENT
    stroke.Transparency = 0.55
    stroke.Thickness    = 1.5
    stroke.Parent       = f

    local accentPos = (style == "Right")
        and UDim2.new(1, -2, 0, 6)
        or  UDim2.new(0, 0, 0, 6)

    local accent = Instance.new("Frame")
    accent.Name             = "AccentBar"
    accent.BackgroundColor3 = C_ACCENT
    accent.BorderSizePixel  = 0
    accent.Size             = UDim2.new(0, 2, 1, -12)
    accent.Position         = accentPos
    accent.ZIndex           = 11
    accent.Parent           = f
    local ac = Instance.new("UICorner")
    ac.CornerRadius = UDim.new(0, 2)
    ac.Parent = accent

    local div = Instance.new("Frame")
    div.Name                   = "VisualsDivider"
    div.BackgroundColor3       = Color3.fromRGB(60, 65, 80)
    div.BackgroundTransparency = 0.2
    div.BorderSizePixel        = 0
    div.Size                   = UDim2.new(1, -24, 0, 1)
    div.Position               = UDim2.fromOffset(12, 0)
    div.ZIndex                 = 11
    div.Parent                 = f

    return { bg = f, accentBar = accent, stroke = stroke, divider = div }
end

local function newInfoText(size, outline, xAlign)
    local t = Instance.new("TextLabel")
    t.Name                   = "VisualsInfoLine"
    t.BackgroundTransparency = 1
    t.Size                   = UDim2.fromOffset(340, size + 6)
    t.Font                   = VISUALS_FONT
    t.TextSize               = size
    t.TextColor3             = Color3.fromRGB(255, 255, 255)
    t.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
    t.TextStrokeTransparency = outline ~= false and 0.2 or 1
    t.TextXAlignment         = xAlign or Enum.TextXAlignment.Left
    t.TextYAlignment         = Enum.TextYAlignment.Top
    t.RichText               = true
    t.ZIndex                 = 10
    t.Visible                = false
    t.Parent                 = screenGui
    return t
end

local function initOverlay()
    for _, t in ipairs(infoLines) do pcall(function() t:Destroy() end) end
    infoLines = {}
    if infoHeaderLabel then pcall(function() infoHeaderLabel:Destroy() end); infoHeaderLabel = nil end
    if infoBg          then pcall(function() infoBg:Destroy()          end); infoBg          = nil end
    infoAccentBar    = nil
    infoBorderStroke = nil
    infoDivider      = nil

    local cfg     = settings["Visuals"]["Info"]
    local size    = cfg["Position"]["Size"] or 11
    local outline = cfg["Outline"] ~= false
    local style   = resolveStyle(cfg["Style"])
    local xAlign  = styleXAlign(style)

    metricState.tbDist,  metricState.tbInRange  = nil, nil
    metricState.camDist, metricState.camInRange  = nil, nil
    metricState.fhDist,  metricState.fhInRange   = nil, nil
    cachedColors = {}

    local bgObj      = newBg(style)
    infoBg           = bgObj.bg
    infoAccentBar    = bgObj.accentBar
    infoBorderStroke = bgObj.stroke
    infoDivider      = bgObj.divider

    local header = Instance.new("TextLabel")
    header.Name                   = "VisualsAlias"
    header.BackgroundTransparency = 1
    header.Size                   = UDim2.fromOffset(340, size + 6)
    header.Text                   = cfg["Alias"] or "sauce"
    header.TextColor3             = cfg["Colors"]["Header"] or Color3.fromRGB(180, 100, 255)
    header.TextSize               = size
    header.Font                   = VISUALS_FONT
    header.TextXAlignment         = xAlign
    header.TextYAlignment         = Enum.TextYAlignment.Top
    header.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
    header.TextStrokeTransparency = outline and 0.2 or 1
    header.RichText               = true
    header.ZIndex                 = 10
    header.Visible                = false
    header.Parent                 = screenGui
    infoHeaderLabel = header

    for i = 1, LINE_COUNT do
        infoLines[i] = newInfoText(size, outline, xAlign)
    end

    overlayReady = true
end

local function setLine(i, text, color, yOffset)
    local t = infoLines[i]
    if not t then return end
    t.Text                   = text
    t.TextColor3             = color or C_TEXT
    t.TextStrokeTransparency = renderCtx.outline and 0.2 or 1
    t.Position               = UDim2.fromOffset(renderCtx.baseX, yOffset)
    t.Visible                = true
end

local function fmtFeatureNormal(name, enabled, isActive, dist, inRange)
    local barColor  = not enabled and S_GHOST   or (isActive and S_ACTIVE or S_BAR_IDLE)
    local statColor = not enabled and S_IDLE    or (isActive and S_ACTIVE or S_IDLE)
    local statTxt   = not enabled and "off"     or (isActive and "active" or "idle")

    local line = '<font color="' .. barColor  .. '">\226\150\142</font>  '
        .. '<font color="' .. S_LABEL   .. '">' .. name    .. '</font>'
        .. '<font color="' .. S_SEP     .. '">  \194\183  </font>'
        .. '<font color="' .. statColor .. '">' .. statTxt .. '</font>'

    if dist then
        local rangeStr = inRange and S_IN or S_OUT
        line = line
            .. '<font color="' .. S_SEP    .. '">  \194\183  </font>'
            .. '<font color="' .. S_TEXT   .. '">' .. dist .. 'm</font>'
            .. '  <font color="' .. rangeStr .. '">' .. (inRange and "in" or "out") .. '</font>'
    end
    return line
end

local function fmtFeatureInverted(name, enabled, isActive, dist, inRange)
    local barColor  = not enabled and S_GHOST   or (isActive and S_ACTIVE or S_BAR_IDLE)
    local statColor = not enabled and S_IDLE    or (isActive and S_ACTIVE or S_IDLE)
    local statTxt   = not enabled and "off"     or (isActive and "active" or "idle")

    local line = '<font color="' .. statColor .. '">' .. statTxt .. '</font>'
        .. '<font color="' .. S_SEP     .. '">  \194\183  </font>'
        .. '<font color="' .. S_LABEL   .. '">' .. name    .. '</font>'
        .. '  <font color="' .. barColor .. '">\226\150\142</font>'

    if dist then
        local rangeStr = inRange and S_IN or S_OUT
        line = '<font color="' .. rangeStr .. '">' .. (inRange and "in" or "out") .. '</font>'
            .. '  <font color="' .. S_TEXT .. '">' .. dist .. 'm</font>'
            .. '<font color="' .. S_SEP   .. '">  \194\183  </font>'
            .. line
    end
    return line
end

local function buildStatusLine(name, enabled, isActive, dist, inRange)
    local s = renderCtx.style
    if s == "Inverted" or s == "Right" then
        return fmtFeatureInverted(name, enabled, isActive, dist, inRange)
    end
    return fmtFeatureNormal(name, enabled, isActive, dist, inRange)
end

local function checkWall(tChar)
    if not tChar or not Camera then return true, "vis" end
    local part = tChar:FindFirstChild("Head") or tChar:FindFirstChild("HumanoidRootPart")
    if not part then return true, "vis" end
    local filter = {}
    if LP and LP.Character then filter[1] = LP.Character end
    wallRayParams.FilterDescendantsInstances = filter
    local origin    = Camera.CFrame.Position
    local direction = part.Position - origin
    local result    = workspace:Raycast(origin, direction, wallRayParams)
    if not result then return true, "vis" end
    local vis = result.Instance:IsDescendantOf(tChar)
    return vis, vis and "vis" or "wall"
end

local function getPlayerDistance(tChar)
    local myChar = LP and LP.Character
    local myHrp  = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local tHrp   = tChar  and tChar:FindFirstChild("HumanoidRootPart")
    if myHrp and tHrp then
        return math.floor((tHrp.Position - myHrp.Position).Magnitude)
    end
    return nil
end

local function smoothMetric(prev, target, alpha)
    if prev == nil then return target end
    return prev + (target - prev) * alpha
end

local function buildFeatureLine(name, enabled, isActive, armedAndHasTarget, tChar, maxDist, distKey, rangeKey, refreshMetrics)
    local text = buildStatusLine(name, enabled, isActive, nil, nil)
    if armedAndHasTarget and tChar then
        local distRaw = getPlayerDistance(tChar)
        if distRaw then
            local inRangeRaw = distRaw <= maxDist
            if refreshMetrics then
                metricState[distKey]  = smoothMetric(metricState[distKey], distRaw, 0.35)
                metricState[rangeKey] = inRangeRaw
            end
            local shownDist = metricState[distKey] and math.floor(metricState[distKey] + 0.5) or distRaw
            local inRange   = metricState[rangeKey]
            if inRange == nil then inRange = inRangeRaw end
            text = buildStatusLine(name, enabled, isActive, shownDist, inRange)
        end
    else
        if refreshMetrics then
            metricState[distKey]  = nil
            metricState[rangeKey] = nil
        end
    end
    return text
end

local function buildForceHitLine(fhEnabled, fhActive, hasTarget, tChar, refreshMetrics)
    local text = buildStatusLine("ForceHit", fhEnabled, fhActive, nil, nil)
    if fhActive and hasTarget and tChar and ForceHitModule and ForceHitModule.getDistanceInfo then
        local distRaw, inRangeRaw = ForceHitModule.getDistanceInfo()
        if distRaw then
            if refreshMetrics then
                metricState.fhDist    = smoothMetric(metricState.fhDist, distRaw, 0.35)
                metricState.fhInRange = inRangeRaw
            end
            local shownDist = metricState.fhDist and math.floor(metricState.fhDist + 0.5) or distRaw
            local inRange   = metricState.fhInRange
            if inRange == nil then inRange = inRangeRaw end
            text = buildStatusLine("ForceHit", fhEnabled, fhActive, shownDist, inRange)
        end
    else
        if refreshMetrics then
            metricState.fhDist    = nil
            metricState.fhInRange = nil
        end
    end
    return text
end

local function getHpColor(pct)
    if pct > 0.6  then return C_HP_HI  end
    if pct > 0.25 then return C_HP_MID end
    return C_HP_LO
end

local function getArmorColor(arm)
    if arm > 75 then return C_ARMOR  end
    if arm > 25 then return C_HP_MID end
    if arm > 0  then return C_HP_LO  end
    return C_GHOST
end

local function buildHealthLine(hasTarget, tChar)
    if not hasTarget or not tChar then
        return '<font color="' .. S_GHOST .. '">-- hp</font>'
            .. '<font color="' .. S_SEP   .. '">  \194\183  </font>'
            .. '<font color="' .. S_GHOST .. '">-- armor</font>'
    end

    local hp, maxHp, arm = 0, 100, 0

    if ESPModule and ESPModule.getEspCharData and State.LockedTarget then
        local entry = ESPModule.getEspCharData(State.LockedTarget)
        if entry and entry.char == tChar and ESPModule.getEspStatsFromCache then
            hp, maxHp, arm = ESPModule.getEspStatsFromCache(entry)
        end
    else
        local hum = tChar:FindFirstChildOfClass("Humanoid")
        hp    = hum and math.floor(hum.Health)    or 0
        maxHp = hum and math.floor(hum.MaxHealth) or 100
    end

    hp  = math.min(math.max(math.floor(hp  or 0), 0), 9999)
    arm = math.min(math.max(math.floor(arm or 0), 0), 9999)

    local pct      = maxHp > 0 and (hp / maxHp) or 0
    local hpColor  = c3s(getHpColor(pct))
    local armColor = c3s(getArmorColor(arm))

    local s = renderCtx.style
    if s == "Inverted" or s == "Right" then
        return '<font color="' .. S_STAT_LABEL .. '">armor </font>'
            .. '<font color="' .. armColor     .. '">' .. arm .. '</font>'
            .. '<font color="' .. S_SEP        .. '">  \194\183  </font>'
            .. '<font color="' .. S_STAT_LABEL .. '">hp </font>'
            .. '<font color="' .. hpColor      .. '">' .. hp  .. '</font>'
    end

    return '<font color="' .. hpColor      .. '">' .. hp  .. '</font>'
        .. '<font color="' .. S_STAT_LABEL .. '"> hp</font>'
        .. '<font color="' .. S_SEP        .. '">  \194\183  </font>'
        .. '<font color="' .. armColor     .. '">' .. arm .. '</font>'
        .. '<font color="' .. S_STAT_LABEL .. '"> armor</font>'
end

local function buildToolLine(hasTarget, tChar)
    if not hasTarget or not tChar then
        return '<font color="' .. S_GHOST .. '">unarmed</font>'
    end
    local tool = tChar:FindFirstChildOfClass("Tool")
    if tool then
        return '<font color="' .. S_SEP  .. '">[</font>'
            .. '<font color="' .. S_TEXT .. '">' .. tool.Name .. '</font>'
            .. '<font color="' .. S_SEP  .. '">]</font>'
    end
    for _, child in ipairs(tChar:GetChildren()) do
        if (child:IsA("Tool") or child:IsA("Model")) and not KNOWN_BODY_PARTS[child.Name] then
            return '<font color="' .. S_SEP  .. '">[</font>'
                .. '<font color="' .. S_TEXT .. '">' .. child.Name .. '</font>'
                .. '<font color="' .. S_SEP  .. '">]</font>'
        end
    end
    return '<font color="' .. S_GHOST .. '">unarmed</font>'
end

local function buildTargetLine(hasTarget, S_TARGET)
    if not hasTarget then
        return '<font color="' .. S_GHOST .. '">no target</font>'
    end
    local name = State.LockedTarget.DisplayName or State.LockedTarget.Name
    local s = renderCtx.style
    if s == "Inverted" or s == "Right" then
        return '<font color="' .. cachedWallColorS .. '">' .. cachedWallText .. '</font>'
            .. '<font color="' .. S_SEP            .. '">  \194\183  </font>'
            .. '<font color="' .. S_TARGET         .. '">' .. name .. '</font>'
    end
    return '<font color="' .. S_TARGET       .. '">' .. name .. '</font>'
        .. '<font color="' .. S_SEP          .. '">  \194\183  </font>'
        .. '<font color="' .. cachedWallColorS .. '">' .. cachedWallText .. '</font>'
end

local function buildDynamicHeader(hasTarget, tbEnabled, tbArmed, camEnabled, camArmed, fhEnabled)
    if hasTarget then
        local name     = State.LockedTarget.DisplayName or State.LockedTarget.Name
        local S_TARGET = c3s(cachedColors["Target"] or Color3.fromRGB(255, 80, 80))
        return '<font color="' .. S_TARGET       .. '">' .. name            .. '</font>'
            .. '<font color="' .. S_SEP          .. '">  \194\183  </font>'
            .. '<font color="' .. cachedWallColorS .. '">' .. cachedWallText .. '</font>'
    end
    local parts = {}
    if tbEnabled  then parts[#parts+1] = '<font color="' .. (tbArmed  and S_ACTIVE or S_IDLE) .. '">TB</font>'  end
    if camEnabled then parts[#parts+1] = '<font color="' .. (camArmed and S_ACTIVE or S_IDLE) .. '">CAM</font>' end
    if fhEnabled  then parts[#parts+1] = '<font color="' .. S_IDLE .. '">FH</font>'                             end
    if #parts == 0 then
        return '<font color="' .. S_GHOST .. '">idle</font>'
    end
    return table.concat(parts, '<font color="' .. S_SEP .. '">  \194\183  </font>')
end

local function update()
    Camera = workspace.CurrentCamera

    local cfg = settings["Visuals"] and settings["Visuals"]["Info"]
    if not cfg or not cfg["Enabled"] then
        for _, t in ipairs(infoLines) do
            if t.Visible then t.Visible = false end
        end
        if infoHeaderLabel and infoHeaderLabel.Visible then infoHeaderLabel.Visible = false end
        if infoBg          and infoBg.Visible          then infoBg.Visible          = false end
        return
    end

    if not overlayReady then initOverlay() end
    if not overlayReady then return end

    local now = os.clock()
    if (now - infoLastUpdate) < INFO_UPDATE_RATE then return end
    infoLastUpdate = now

    local refreshMetrics = (now - infoMetricLastUpdate) >= INFO_METRIC_UPDATE_RATE
    if refreshMetrics then infoMetricLastUpdate = now end

    local refreshWall = (now - infoWallLastUpdate) >= WALL_UPDATE_RATE
    if refreshWall then infoWallLastUpdate = now end

    local vp    = Camera and Camera.ViewportSize or Vector2.new(1920, 1080)
    local pos   = cfg["Position"]
    local size  = pos["Size"] or 11
    local style = resolveStyle(cfg["Style"])
    local lineH = size + 4

    local baseX
    if style == "Right" then
        baseX = math.floor(vp.X * (1 - (pos["X"] or 0.0055))) - 230
    else
        baseX = math.floor(vp.X * (pos["X"] or 0.0055))
    end
    local baseY = math.floor(vp.Y * (pos["Y"] or 0.65))

    syncColors(cfg["Colors"])

    renderCtx.size    = size
    renderCtx.outline = cfg["Outline"] ~= false
    renderCtx.baseX   = baseX
    renderCtx.baseY   = baseY
    renderCtx.lineH   = lineH
    renderCtx.style   = style

    local S_TARGET  = c3s(cachedColors["Target"] or Color3.fromRGB(255, 80, 80))
    local hasTarget = State.LockedTarget ~= nil and State.LockedTarget.Parent ~= nil
    local tChar     = hasTarget and State.LockedTarget.Character or nil

    if refreshWall and hasTarget then
        cachedWallVisible, cachedWallText = checkWall(tChar)
        cachedWallColorS = cachedWallVisible and S_ACTIVE or S_OUT
    end

    local tbEnabled = settings["Triggerbot"] and settings["Triggerbot"]["Enabled"]
    local tbClick   = string.lower(tostring((settings["Triggerbot"] and settings["Triggerbot"]["Click Type"]) or "Hold"))
    local tbArmed   = tbEnabled and (
        (tbClick == "toggle" and State.TriggerbotToggleActive) or
        (tbClick ~= "toggle" and State.TriggerbotHoldActive)
    )
    local tbMaxDist = tonumber(settings["Triggerbot"] and settings["Triggerbot"]["Distance"]) or 215

    local camEnabled = settings["Camlock"] and settings["Camlock"]["Enabled"]
    local camClick   = string.lower(tostring((settings["Camlock"] and settings["Camlock"]["Click Type"]) or "Hold"))
    local camArmed   = camEnabled and (
        (camClick == "toggle" and State.CamlockToggleActive) or
        (camClick ~= "toggle" and State.CamlockHoldActive)
    )
    local camMaxDist = tonumber(settings["Camlock"] and settings["Camlock"]["Distance"]) or 300

    local fhEnabled = settings["Weapon Modifications"]
        and settings["Weapon Modifications"]["ForceHit"]
        and settings["Weapon Modifications"]["ForceHit"]["Enabled"]
    local fhActive  = ForceHitModule and ForceHitModule.isActive and ForceHitModule.isActive() or false

    local y = baseY

    if infoHeaderLabel then
        local headerText
        if style == "Dynamic" then
            headerText = buildDynamicHeader(hasTarget, tbEnabled, tbArmed, camEnabled, camArmed, fhEnabled)
        else
            headerText = cfg["Alias"] or "sauce"
        end
        infoHeaderLabel.Text                   = headerText
        infoHeaderLabel.TextColor3             = cachedColors["Header"] or Color3.fromRGB(180, 100, 255)
        infoHeaderLabel.TextSize               = size
        infoHeaderLabel.TextXAlignment         = styleXAlign(style)
        infoHeaderLabel.TextStrokeTransparency = renderCtx.outline and 0.2 or 1
        infoHeaderLabel.Position               = UDim2.fromOffset(baseX, y - lineH - 1)
        infoHeaderLabel.Visible                = true
    end

    local tbText = buildFeatureLine("Triggerbot", tbEnabled, tbArmed,
        tbArmed and hasTarget, tChar, tbMaxDist, "tbDist", "tbInRange", refreshMetrics)
    setLine(LINES.TRIGGERBOT, tbText, C_TEXT, y)
    y = y + lineH

    local camText = buildFeatureLine("Camlock", camEnabled, camArmed,
        camArmed and hasTarget, tChar, camMaxDist, "camDist", "camInRange", refreshMetrics)
    setLine(LINES.CAMLOCK, camText, C_TEXT, y)
    y = y + lineH

    local fhText = buildForceHitLine(fhEnabled, fhActive, hasTarget, tChar, refreshMetrics)
    setLine(LINES.FORCEHIT, fhText, C_TEXT, y)
    y = y + lineH

    if infoDivider then
        infoDivider.Position = UDim2.fromOffset(12, math.floor(lineH * 3 + 6))
    end

    y = y + TARGET_GAP

    if style ~= "Dynamic" then
        setLine(LINES.TARGET, buildTargetLine(hasTarget, S_TARGET), hasTarget and C_TEXT or C_GHOST, y)
        y = y + lineH
    else
        if infoLines[LINES.TARGET] then infoLines[LINES.TARGET].Visible = false end
    end

    setLine(LINES.HP, buildHealthLine(hasTarget, tChar), C_TEXT, y)
    y = y + lineH

    setLine(LINES.TOOL, buildToolLine(hasTarget, tChar), C_TEXT, y)
    y = y + lineH

    if infoBg then
        local PAD_X = 10
        local PAD_T = lineH + 5
        local PAD_B = 9
        infoBg.Position = UDim2.fromOffset(baseX - PAD_X, baseY - PAD_T)
        infoBg.Size     = UDim2.fromOffset(230, (y - baseY) + PAD_B + PAD_T)
        infoBg.Visible  = true
    end
end

local function cleanup()
    for _, t in ipairs(infoLines) do pcall(function() t:Destroy() end) end
    infoLines = {}
    if infoHeaderLabel then pcall(function() infoHeaderLabel:Destroy() end); infoHeaderLabel = nil end
    if infoBg          then pcall(function() infoBg:Destroy()          end); infoBg          = nil end
    infoAccentBar    = nil
    infoBorderStroke = nil
    infoDivider      = nil

    metricState.tbDist,  metricState.tbInRange  = nil, nil
    metricState.camDist, metricState.camInRange  = nil, nil
    metricState.fhDist,  metricState.fhInRange   = nil, nil

    cachedWallVisible = true
    cachedWallText    = "vis"
    cachedWallColorS  = ""

    infoLastUpdate       = 0
    infoMetricLastUpdate = 0
    infoWallLastUpdate   = 0
    cachedColors         = {}
    overlayReady         = false

    renderCtx.size, renderCtx.outline, renderCtx.baseX, renderCtx.baseY, renderCtx.lineH, renderCtx.style
        = 11, true, 0, 0, 15, "Normal"
end

function Visuals.init(deps)
    settings         = deps.settings
    State            = deps.State
    Camera           = deps.Camera
    LP               = deps.LP
    screenGui        = deps.screenGui
    ForceHitModule   = deps.ForceHitModule
    ESPModule        = deps.ESPModule
    KNOWN_BODY_PARTS = deps.BODY_PART_NAMES or {}
    initOverlay()
end

function Visuals.update()
    update()
end

function Visuals.cleanup()
    cleanup()
end

return Visuals