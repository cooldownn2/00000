local Visuals = {}

local settings, State, Camera, LP, screenGui, ForceHitModule, ESPModule, KNOWN_BODY_PARTS

local mathExp   = math.exp
local mathAbs   = math.abs
local mathFloor = math.floor

-- ═════════════════════════════════════════════════════════════════════════════
--  LAYOUT CONSTANTS  (overridden by cfg in init)
-- ═════════════════════════════════════════════════════════════════════════════
local FONT      = Enum.Font.GothamBold
local CORNER    = 4
local PAD_X     = 6
local CHIP_H    = 15
local HEADER_H  = 18
local ROW_GAP   = 5
local FONT_SIZE = 10
local HDR_SIZE  = 10
local MAX_ROWS  = 3
local TOGGLE_W  = 18
local TOGGLE_H  = 10
local TOGGLE_DOT = 8
local TOGGLE_PAD = 1

-- ═════════════════════════════════════════════════════════════════════════════
--  LIVE COLOUR TABLE
-- ═════════════════════════════════════════════════════════════════════════════
local C = {}

local function lighten(c, t) return Color3.new(c.R+(1-c.R)*t, c.G+(1-c.G)*t, c.B+(1-c.B)*t) end
local function darken(c, t)  return Color3.new(c.R*(1-t), c.G*(1-t), c.B*(1-t)) end
local function lerpC3(a, b, t) return Color3.new(a.R+(b.R-a.R)*t, a.G+(b.G-a.G)*t, a.B+(b.B-a.B)*t) end

local function resolveColors(cfg)
    local co  = cfg["Colors"] or {}
    local bg  = co.Background or Color3.fromRGB(45, 38, 30)
    local hdr = co.Header     or Color3.fromRGB(35, 30, 25)
    local txt = co.Text       or Color3.fromRGB(230, 225, 218)
    local acc = co.Accent     or Color3.fromRGB(45, 100, 220)
    local bdr = co.Border     or Color3.fromRGB(200, 188, 170)
    local tgt = co.Target     or Color3.fromRGB(255, 70, 70)
    local outl = cfg["Outline"] ~= false

    C.HeaderBg       = hdr
    C.HeaderAlpha    = 0.03
    C.ChipBg         = bg
    C.ChipAlpha      = 0.38
    C.StrokeColor    = bdr
    C.StrokeAlpha    = outl and 0.52 or 1
    C.StrokeThick    = outl and 1 or 0
    C.LabelText      = txt
    C.ValueText      = txt
    C.HeaderText     = lighten(txt, 0.05)
    C.HeaderIcon     = lighten(acc, 0.35)
    C.ToggleOnBg     = co.ToggleOn or acc
    C.ToggleOnAlpha  = 0.25
    C.ToggleOffBg    = co.ToggleOff or Color3.fromRGB(70, 68, 80)
    C.ToggleOffAlpha = 0.50
    C.ToggleDot      = Color3.fromRGB(255, 255, 255)
    C.ToggleDotGlow  = lighten(co.ToggleOn or acc, 0.35)
    C.TargetBg       = darken(tgt, 0.78)
    C.TargetAlpha    = 0.35
    C.TargetText     = tgt
    C.GlassBg        = bg
    C.GlassAlpha     = 0.38
    C.GlassEdge      = lighten(bdr, 0.1)
    C.GlassEdgeAlpha = 0.88

    -- Info row colors
    C.InfoLabelText  = darken(txt, 0.25)
    C.InfoValueText  = txt
    C.HPHigh         = Color3.fromRGB(80, 220, 110)
    C.HPMid          = Color3.fromRGB(240, 200, 40)
    C.HPLow          = Color3.fromRGB(225, 55, 55)
    C.HPDead         = Color3.fromRGB(220, 50, 50)
    C.Armor          = Color3.fromRGB(140, 200, 255)
    C.InRange        = Color3.fromRGB(80, 220, 110)
    C.OutRange       = Color3.fromRGB(225, 55, 55)
end

-- ═════════════════════════════════════════════════════════════════════════════
--  HELPERS
-- ═════════════════════════════════════════════════════════════════════════════
local function addGlassGradient(f)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 195, 185)),
    })
    g.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.60),
        NumberSequenceKeypoint.new(0.35, 0.80),
        NumberSequenceKeypoint.new(1, 0.92),
    })
    g.Rotation = 90
    g.Parent = f
    return g
end

local function addCorner(f, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or CORNER)
    c.Parent = f
end

local function applyStroke(f)
    local s = Instance.new("UIStroke")
    s.Color           = C.StrokeColor
    s.Transparency    = C.StrokeAlpha
    s.Thickness       = C.StrokeThick
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent          = f
end

local function newFrame(z)
    local f = Instance.new("Frame")
    f.BackgroundColor3       = C.ChipBg
    f.BackgroundTransparency = C.ChipAlpha
    f.BorderSizePixel        = 0
    f.ZIndex                 = z or 10
    f.Visible                = false
    f.Parent                 = screenGui
    addCorner(f)
    applyStroke(f)
    addGlassGradient(f)
    return f
end

local function newText(parent, color, size, z, xAlign)
    local t = Instance.new("TextLabel")
    t.BackgroundTransparency = 1
    t.TextColor3             = color
    t.Font                   = FONT
    t.TextSize               = size or FONT_SIZE
    t.Text                   = ""
    t.TextXAlignment         = xAlign or Enum.TextXAlignment.Left
    t.TextYAlignment         = Enum.TextYAlignment.Center
    t.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
    t.TextStrokeTransparency = 0.65
    t.ZIndex                 = z or 11
    t.Size                   = UDim2.fromScale(1, 1)
    t.Parent                 = parent
    return t
end

local TxtSvc = game:GetService("TextService")
local function tw(s, sz)
    local ok, bounds = pcall(function()
        return TxtSvc:GetTextSize(tostring(s), sz or FONT_SIZE, FONT, Vector2.new(1000, 100))
    end)
    if ok and bounds then return bounds.X end
    return math.ceil(#tostring(s) * ((sz or FONT_SIZE) >= 12 and 7.0 or 6.4))
end

-- ═════════════════════════════════════════════════════════════════════════════
--  FEATURE DEFINITIONS  (wired to real settings/State)
-- ═════════════════════════════════════════════════════════════════════════════
local featureDefs = {
    {
        label = "Triggerbot",
        getOn = function()
            return State.TriggerbotToggleActive or State.TriggerbotHoldActive
        end,
    },
    {
        label = "Camlock",
        getOn = function()
            return State.CamlockToggleActive or State.CamlockHoldActive
        end,
    },
    {
        label = "Force Shot",
        getOn = function()
            return State.ForceHitActive
        end,
    },
}

MAX_ROWS = #featureDefs

-- ═════════════════════════════════════════════════════════════════════════════
--  INFO ROW DEFINITIONS  (value rows shown when target is locked)
-- ═════════════════════════════════════════════════════════════════════════════
local INFO_ROW_COUNT = 5
local INFO_CHIP_H    = 13
local INFO_GAP       = 3

local function getTargetPlayer()
    local target = State.LockedTarget
    if not target then return nil, nil end
    -- LockedTarget is a Player object
    if target:IsA("Player") then
        local char = target.Character
        if not char then return target, nil end
        return target, char
    end
    -- Fallback: might be a character model
    local char = target
    if not char:FindFirstChildOfClass("Humanoid") then return nil, nil end
    for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
        if p.Character == char then return p, char end
    end
    return nil, char
end

local fdByLabel = {}
for i, fd in ipairs(featureDefs) do
    fdByLabel[fd.label] = { fd = fd, idx = i }
end

-- Pre-compute label widths (updated after cfg FontSize is known)
local labelWidthCache = {}
local maxLabelWCache  = 0
local cachedHdrW      = 0
local cachedTgtName   = ""
local cachedTgtW      = 0

local function rebuildLabelWidths(cfg)
    FONT_SIZE = cfg["FontSize"] or 10
    HDR_SIZE  = FONT_SIZE
    CORNER    = cfg["Roundness"] or 4
    maxLabelWCache = 0
    for _, fd in ipairs(featureDefs) do
        local lw = tw(fd.label, FONT_SIZE) + PAD_X * 2
        labelWidthCache[fd.label] = lw
        if lw > maxLabelWCache then maxLabelWCache = lw end
    end
    cachedHdrW = tw(cfg["Title"] or "Hotkeys", HDR_SIZE) + 20 + PAD_X
end

-- Animation state
local fadeAlphas      = {}
local prevOn          = {}
local rowYSmoothed    = {}
local activationOrder = {}
local FADE_SPEED      = 10

local function resetAnimState()
    fadeAlphas = {}; prevOn = {}; rowYSmoothed = {}; activationOrder = {}
    for _, fd in ipairs(featureDefs) do
        local on = fd.getOn()
        fadeAlphas[fd.label] = on and 1 or 0
        prevOn[fd.label]     = on
        activationOrder[#activationOrder + 1] = fd.label
    end
end

-- Module-level helpers
local function ft(base, fa) return 1 - (1 - base) * fa end
local ROW_STEP = CHIP_H + ROW_GAP
local TG_PAD   = 2
local TG_W     = TOGGLE_W + TG_PAD * 2
local TG_H     = TOGGLE_H + TG_PAD * 2

-- ═════════════════════════════════════════════════════════════════════════════
--  POOL
-- ═════════════════════════════════════════════════════════════════════════════
local pool  = {}
local ready = false

local function destroyPool()
    if pool.backdrop then pcall(function() pool.backdrop:Destroy() end) end
    if pool.hChip then pcall(function() pool.hChip:Destroy() end) end
    if pool.tChip then pcall(function() pool.tChip:Destroy() end) end
    for _, inf in ipairs(pool.info or {}) do
        pcall(function() inf.chip:Destroy() end)
    end
    for _, r in ipairs(pool.rows or {}) do
        pcall(function() r.chip:Destroy() end)
        if r.toggleGlass then pcall(function() r.toggleGlass:Destroy() end) end
    end
    pool  = {}
    ready = false
end

local function buildPool(cfg)
    destroyPool()
    rowYSmoothed = {}

    -- Glass backdrop
    local bd = Instance.new("Frame")
    bd.BackgroundColor3       = C.GlassBg or Color3.fromRGB(60, 52, 45)
    bd.BackgroundTransparency = C.GlassAlpha or 0.45
    bd.BorderSizePixel        = 0
    bd.ZIndex                 = 9
    bd.Visible                = false
    bd.Parent                 = screenGui
    addCorner(bd, 7)
    addGlassGradient(bd)

    local bdEdge = Instance.new("UIStroke")
    bdEdge.Color           = C.GlassEdge or Color3.fromRGB(220, 210, 195)
    bdEdge.Transparency    = C.GlassEdgeAlpha or 0.88
    bdEdge.Thickness       = 1
    bdEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    bdEdge.Parent          = bd

    pool.backdrop = bd
    pool.bdEdge   = bdEdge

    -- Header
    local hc = newFrame(10)
    hc.BackgroundColor3       = C.HeaderBg
    hc.BackgroundTransparency = C.HeaderAlpha
    local hcCorner = hc:FindFirstChildOfClass("UICorner")
    if hcCorner then hcCorner.CornerRadius = UDim.new(0, CORNER + 3) end
    local hi = newText(hc, C.HeaderIcon, 16, 12, Enum.TextXAlignment.Left)
    hi.Text     = (cfg and cfg["Icon"]) or "\226\152\133"
    hi.Size     = UDim2.fromOffset(16, HEADER_H)
    hi.Position = UDim2.fromOffset(4, -1)
    local ht = newText(hc, C.HeaderText, HDR_SIZE, 12, Enum.TextXAlignment.Left)
    ht.Position = UDim2.fromOffset(20, -1)

    pool.hChip   = hc
    pool.hIcon   = hi
    pool.hTitle  = ht
    pool.hStroke = hc:FindFirstChildOfClass("UIStroke")

    -- Target chip
    local tc = newFrame(10)
    tc.BackgroundColor3       = C.TargetBg or C.ChipBg
    tc.BackgroundTransparency = C.TargetAlpha or C.ChipAlpha
    local tt = newText(tc, C.TargetText, FONT_SIZE, 11, Enum.TextXAlignment.Left)
    tt.Position = UDim2.fromOffset(PAD_X, -1)

    pool.tChip   = tc
    pool.tText   = tt
    pool.tStroke = tc:FindFirstChildOfClass("UIStroke")

    -- Info chips (HP, Armor, Dist, Tool, Range)
    pool.info = {}
    for i = 1, INFO_ROW_COUNT do
        local ic = newFrame(10)
        local il = newText(ic, C.InfoLabelText or C.LabelText, FONT_SIZE - 1, 11, Enum.TextXAlignment.Left)
        il.Position = UDim2.fromOffset(PAD_X, -1)
        local iv = newText(ic, C.InfoValueText or C.LabelText, FONT_SIZE - 1, 11, Enum.TextXAlignment.Right)
        iv.Position = UDim2.fromOffset(0, -1)
        pool.info[i] = {
            chip   = ic,
            label  = il,
            value  = iv,
            stroke = ic:FindFirstChildOfClass("UIStroke"),
        }
    end

    -- Row chips
    pool.rows = {}
    for i = 1, MAX_ROWS do
        local chip = newFrame(10)
        local lt   = newText(chip, C.LabelText, FONT_SIZE, 11, Enum.TextXAlignment.Left)
        lt.Position = UDim2.fromOffset(PAD_X, -1)

        local vt = newText(chip, C.ValueText or C.LabelText, FONT_SIZE, 11, Enum.TextXAlignment.Right)
        vt.Position = UDim2.fromOffset(PAD_X, 0)
        vt.Visible  = false

        -- Toggle pill
        local togglePill = Instance.new("Frame")
        togglePill.BackgroundColor3       = C.ToggleOnBg or Color3.fromRGB(55, 120, 255)
        togglePill.BackgroundTransparency = C.ToggleOnAlpha or 0.25
        togglePill.BorderSizePixel        = 0
        togglePill.ZIndex                 = 12
        togglePill.Size                   = UDim2.fromOffset(TOGGLE_W, TOGGLE_H)
        togglePill.Visible                = false
        togglePill.Parent                 = chip
        addCorner(togglePill, TOGGLE_H / 2)
        addGlassGradient(togglePill)

        local pillStroke = Instance.new("UIStroke")
        pillStroke.Color           = Color3.fromRGB(255, 255, 255)
        pillStroke.Transparency    = 0.55
        pillStroke.Thickness       = 1
        pillStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        pillStroke.Parent          = togglePill

        local toggleDot = Instance.new("Frame")
        toggleDot.BackgroundColor3       = C.ToggleDot or Color3.fromRGB(255, 255, 255)
        toggleDot.BackgroundTransparency = 0.05
        toggleDot.BorderSizePixel        = 0
        toggleDot.ZIndex                 = 13
        toggleDot.Size                   = UDim2.fromOffset(TOGGLE_DOT, TOGGLE_DOT)
        toggleDot.Position               = UDim2.fromOffset(TOGGLE_W - TOGGLE_DOT - TOGGLE_PAD, TOGGLE_PAD)
        toggleDot.Parent                 = togglePill
        addCorner(toggleDot, TOGGLE_DOT / 2)
        local dotHL = Instance.new("UIGradient")
        dotHL.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0,    0.00),
            NumberSequenceKeypoint.new(0.40, 0.25),
            NumberSequenceKeypoint.new(1,    0.55),
        })
        dotHL.Rotation = 90
        dotHL.Parent = toggleDot

        -- Glass backing for toggle
        local tGlass = Instance.new("Frame")
        tGlass.BackgroundColor3       = C.GlassBg or Color3.fromRGB(35, 33, 42)
        tGlass.BackgroundTransparency = C.GlassAlpha or 0.75
        tGlass.BorderSizePixel        = 0
        tGlass.ZIndex                 = 10
        tGlass.Visible                = false
        tGlass.Parent                 = screenGui
        addCorner(tGlass, 6)
        applyStroke(tGlass)
        addGlassGradient(tGlass)

        togglePill.Parent = tGlass

        pool.rows[i] = {
            chip        = chip,
            lt          = lt,
            vt          = vt,
            togglePill  = togglePill,
            toggleDot   = toggleDot,
            toggleGlass = tGlass,
            chipStroke  = chip:FindFirstChildOfClass("UIStroke"),
            glassStroke = tGlass:FindFirstChildOfClass("UIStroke"),
            glassCorner = tGlass:FindFirstChildOfClass("UICorner"),
            pillStroke  = togglePill:FindFirstChildOfClass("UIStroke"),
        }
    end

    ready = true
end

-- ═════════════════════════════════════════════════════════════════════════════
--  HIDE ALL
-- ═════════════════════════════════════════════════════════════════════════════
local function hideAll()
    if pool.backdrop then pool.backdrop.Visible = false end
    if pool.hChip then pool.hChip.Visible = false end
    if pool.tChip then pool.tChip.Visible = false end
    for _, r in ipairs(pool.rows or {}) do
        r.chip.Visible = false
        if r.toggleGlass then r.toggleGlass.Visible = false end
    end
    for _, inf in ipairs(pool.info or {}) do
        inf.chip.Visible = false
    end
end

-- ═════════════════════════════════════════════════════════════════════════════
--  RENDER
-- ═════════════════════════════════════════════════════════════════════════════
local function renderHeader(cfg, bx, by, hdrW, titleStr)
    local hc = pool.hChip
    hc.BackgroundColor3       = C.HeaderBg
    hc.BackgroundTransparency = C.HeaderAlpha
    hc.Position               = UDim2.fromOffset(bx, by)
    hc.Size                   = UDim2.fromOffset(hdrW, HEADER_H)
    hc.Visible                = true

    local hs = pool.hStroke
    if hs then
        hs.Color        = C.StrokeColor
        hs.Transparency = C.StrokeAlpha
        hs.Thickness    = C.StrokeThick
    end
    pool.hIcon.Text        = cfg["Icon"] or "\226\152\133"
    pool.hIcon.TextColor3  = C.HeaderIcon
    pool.hTitle.TextColor3 = C.HeaderText
    pool.hTitle.Text       = titleStr
    pool.hTitle.Size       = UDim2.fromOffset(hdrW - 22, HEADER_H)

    -- Glass backdrop
    local glassPad = 1
    local bd = pool.backdrop
    bd.Position = UDim2.fromOffset(bx - glassPad, by - glassPad)
    bd.Size     = UDim2.fromOffset(hdrW + glassPad * 2, HEADER_H + glassPad * 2)
    bd.BackgroundColor3       = C.GlassBg or Color3.fromRGB(60, 52, 45)
    bd.BackgroundTransparency = C.GlassAlpha or 0.45
    bd.Visible                = true
    local edge = pool.bdEdge
    if edge then
        edge.Color        = C.GlassEdge or Color3.fromRGB(220, 210, 195)
        edge.Transparency = C.GlassEdgeAlpha or 0.88
        edge.Thickness    = 1
    end

    return by + HEADER_H + ROW_GAP + 2
end

local function renderTarget(cfg, bx, curY)
    local hasTarget = State.LockedTarget ~= nil and State.LockedTarget.Parent ~= nil
    if hasTarget then
        local tn = State.LockedTarget.DisplayName or State.LockedTarget.Name
        if tn ~= cachedTgtName then
            cachedTgtName = tn
            cachedTgtW    = tw(tn, FONT_SIZE) + PAD_X * 2
        end
        local tc = pool.tChip
        tc.BackgroundColor3       = C.TargetBg or C.ChipBg
        tc.BackgroundTransparency = C.TargetAlpha or C.ChipAlpha
        local inv    = cfg["Inverted"] == true
        local tStyle = cfg["ToggleStyle"] or "pill"
        local tgtX   = bx
        if inv and tStyle == "pill" then tgtX = bx + TG_W + 12
        elseif inv and tStyle == "dot" then tgtX = bx + 6 + 8 end
        tc.Position = UDim2.fromOffset(tgtX, curY)
        tc.Size     = UDim2.fromOffset(cachedTgtW, CHIP_H)
        tc.Visible  = true
        local ts = pool.tStroke
        if ts then ts.Color = C.StrokeColor; ts.Transparency = C.StrokeAlpha; ts.Thickness = C.StrokeThick end
        pool.tText.Text       = tn
        pool.tText.TextColor3 = C.TargetText
        pool.tText.Size       = UDim2.fromOffset(cachedTgtW - PAD_X, CHIP_H)
        return curY + CHIP_H + ROW_GAP
    else
        pool.tChip.Visible = false
        return curY
    end
end

local function renderInfo(cfg, bx, curY)
    local hasTarget = State.LockedTarget ~= nil and State.LockedTarget.Parent ~= nil
    if not hasTarget then
        for _, inf in ipairs(pool.info or {}) do inf.chip.Visible = false end
        return curY
    end

    local player, char = getTargetPlayer()
    if not char then
        for _, inf in ipairs(pool.info or {}) do inf.chip.Visible = false end
        return curY
    end

    -- Gather stats
    local hp, maxHp, arm = 0, 100, 0
    local alive = false
    if ESPModule and player then
        local entry = ESPModule.getEspCharData(player)
        if entry and entry.char == char then
            hp, maxHp, arm = ESPModule.getEspStatsFromCache(entry)
            alive = entry.hum and entry.hum.Health > 0
        end
    else
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hp = mathFloor(hum.Health); maxHp = mathFloor(hum.MaxHealth); alive = hum.Health > 0 end
    end
    local pct = math.clamp(hp / math.max(maxHp, 1), 0, 1)

    -- Distance & range
    local myChar = LP and LP.Character
    local myHrp  = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local tHrp   = char:FindFirstChild("HumanoidRootPart")
    local dist   = (myHrp and tHrp) and mathFloor((tHrp.Position - myHrp.Position).Magnitude) or nil

    local inRange = true
    if ForceHitModule and ForceHitModule.getDistanceInfo then
        local fd, fr = ForceHitModule.getDistanceInfo()
        if fd then dist = fd; inRange = fr end
    end

    local tool     = char:FindFirstChildOfClass("Tool")
    local toolName = tool and tool.Name or "Unarmed"

    -- HP color
    local hpCol
    if not alive then hpCol = C.HPDead
    elseif pct > 0.6 then hpCol = C.HPHigh
    elseif pct > 0.3 then hpCol = C.HPMid
    else hpCol = C.HPLow end

    local inv    = cfg["Inverted"] == true
    local tStyle = cfg["ToggleStyle"] or "pill"
    local chipX  = bx
    if inv and tStyle == "pill" then chipX = bx + TG_W + 12
    elseif inv and tStyle == "dot" then chipX = bx + 6 + 8 end

    -- Build info entries: { label, value, valueColor }
    local infos = {
        { "HP",    alive and tostring(hp) .. "/" .. tostring(maxHp) or "DEAD", hpCol },
        { "Armor", arm > 0 and tostring(arm) or "0",                          C.Armor },
        { "Dist",  dist and (tostring(dist) .. "m") or "--",                  C.InfoValueText },
        { "Tool",  toolName,                                                    C.InfoValueText },
        { "Range", inRange and "In Range" or "Out",                            inRange and C.InRange or C.OutRange },
    }

    local fontSize = (FONT_SIZE - 1)
    for i, info in ipairs(infos) do
        local inf = pool.info[i]
        if not inf then break end

        local labelW = tw(info[1], fontSize) + PAD_X
        local valW   = tw(info[2], fontSize) + PAD_X
        local chipW  = labelW + valW + PAD_X * 2

        inf.chip.BackgroundColor3       = C.ChipBg
        inf.chip.BackgroundTransparency = C.ChipAlpha + 0.08
        inf.chip.Position = UDim2.fromOffset(chipX, curY)
        inf.chip.Size     = UDim2.fromOffset(chipW, INFO_CHIP_H)
        inf.chip.Visible  = true
        if inf.stroke then
            inf.stroke.Color        = C.StrokeColor
            inf.stroke.Transparency = C.StrokeAlpha + 0.1
            inf.stroke.Thickness    = C.StrokeThick
        end

        inf.label.Text       = info[1]
        inf.label.TextColor3 = C.InfoLabelText or C.LabelText
        inf.label.TextSize   = fontSize
        inf.label.Size       = UDim2.fromOffset(labelW, INFO_CHIP_H)

        inf.value.Text       = info[2]
        inf.value.TextColor3 = info[3]
        inf.value.TextSize   = fontSize
        inf.value.Size       = UDim2.fromOffset(chipW - PAD_X, INFO_CHIP_H)

        curY = curY + INFO_CHIP_H + INFO_GAP
    end

    -- Hide unused info slots
    for i = #infos + 1, INFO_ROW_COUNT do
        local inf = pool.info[i]
        if inf then inf.chip.Visible = false end
    end

    return curY + (ROW_GAP - INFO_GAP)
end

local function renderRows(cfg, bx, baseY, dt)
    local maxLabelW = maxLabelWCache
    local runningH  = 0
    local yFactor   = 1 - mathExp(-FADE_SPEED * dt)
    local inv       = cfg["Inverted"] == true

    for _, label in ipairs(activationOrder) do
        local fa      = fadeAlphas[label] or 0
        local targetY = baseY + runningH
        if rowYSmoothed[label] == nil then rowYSmoothed[label] = targetY end
        local sy  = rowYSmoothed[label]
        local nsy = sy + (targetY - sy) * yFactor
        rowYSmoothed[label] = (mathAbs(nsy - targetY) < 0.5) and targetY or nsy
        runningH = runningH + ROW_STEP * fa

        local entry = fdByLabel[label]
        local fd    = entry.fd
        local r     = pool.rows[entry.idx]
        if not r then break end

        if fa < 0.005 then
            r.chip.Visible        = false
            r.toggleGlass.Visible = false
        else
            local smoothY = mathFloor(rowYSmoothed[label])
            local labelW  = labelWidthCache[fd.label]
            local on      = fd.getOn()
            local tStyle  = cfg["ToggleStyle"] or "pill"

            local chipX = bx
            if inv and tStyle == "pill" then chipX = bx + TG_W + 12
            elseif inv and tStyle == "dot" then chipX = bx + 6 + 8 end

            -- Label chip
            r.chip.BackgroundColor3       = C.ChipBg
            r.chip.BackgroundTransparency = ft(C.ChipAlpha, fa)
            if r.chipStroke then r.chipStroke.Color = C.StrokeColor; r.chipStroke.Transparency = ft(C.StrokeAlpha, fa); r.chipStroke.Thickness = C.StrokeThick end
            r.chip.Position = UDim2.fromOffset(chipX, smoothY)
            r.chip.Size     = UDim2.fromOffset(labelW, CHIP_H)
            r.chip.Visible  = true
            r.lt.Text       = fd.label
            r.lt.TextColor3 = C.LabelText
            r.lt.TextTransparency       = ft(0, fa)
            r.lt.TextStrokeTransparency = ft(0.65, fa)
            r.lt.Size = UDim2.fromOffset(labelW - PAD_X * 2, CHIP_H)

            -- Toggle indicator
            if tStyle == "none" then
                r.toggleGlass.Visible = false
                r.togglePill.Visible  = false
            elseif tStyle == "dot" then
                local DOT_SZ = 6
                local dotX = inv and bx or (bx + maxLabelW + 8)
                r.toggleGlass.Position = UDim2.fromOffset(dotX - 1, smoothY + (CHIP_H - DOT_SZ) / 2 - 1)
                r.toggleGlass.Size     = UDim2.fromOffset(DOT_SZ + 2, DOT_SZ + 2)
                local dotCol = on and C.ToggleDotGlow or C.ToggleOffBg
                r.toggleGlass.BackgroundColor3       = dotCol
                r.toggleGlass.BackgroundTransparency = ft(on and 0.55 or 0.85, fa)
                r.toggleGlass.Visible = true
                if r.glassCorner then r.glassCorner.CornerRadius = UDim.new(0, (DOT_SZ + 2) / 2) end
                if r.glassStroke then
                    r.glassStroke.Color        = on and C.ToggleDotGlow or C.StrokeColor
                    r.glassStroke.Transparency = ft(on and 0.15 or C.StrokeAlpha, fa)
                    r.glassStroke.Thickness    = on and 2 or C.StrokeThick
                end
                r.togglePill.Parent   = r.toggleGlass
                r.togglePill.Size     = UDim2.fromOffset(DOT_SZ, DOT_SZ)
                r.togglePill.Position = UDim2.fromOffset(1, 1)
                r.togglePill.BackgroundColor3       = on and C.ToggleDotGlow or C.ToggleOffBg
                r.togglePill.BackgroundTransparency = ft(on and 0.0 or 0.45, fa)
                r.togglePill.Visible  = true
                if r.pillStroke then
                    r.pillStroke.Color        = on and C.ToggleDotGlow or C.ToggleOffBg
                    r.pillStroke.Transparency = ft(on and 0.10 or 0.80, fa)
                    r.pillStroke.Thickness    = on and 1 or 0
                end
                r.toggleDot.Visible = false
            else -- "pill"
                local pillX = inv and bx or (bx + maxLabelW + 12)
                r.toggleGlass.Position = UDim2.fromOffset(pillX, smoothY + (CHIP_H - TG_H) / 2)
                r.toggleGlass.Size     = UDim2.fromOffset(TG_W, TG_H)
                r.toggleGlass.BackgroundColor3       = on and C.ToggleOnBg or C.ToggleOffBg
                r.toggleGlass.BackgroundTransparency = ft(on and 0.72 or 0.90, fa)
                r.toggleGlass.Visible = true
                if r.glassCorner then r.glassCorner.CornerRadius = UDim.new(0, TG_H / 2) end
                if r.glassStroke then
                    r.glassStroke.Color        = on and C.ToggleDotGlow or C.StrokeColor
                    r.glassStroke.Transparency = ft(on and 0.35 or C.StrokeAlpha, fa)
                    r.glassStroke.Thickness    = C.StrokeThick
                end
                r.togglePill.Parent   = r.toggleGlass
                r.togglePill.Position = UDim2.fromOffset(TG_PAD, TG_PAD)
                r.togglePill.Visible  = true
                if on then
                    r.togglePill.BackgroundColor3       = C.ToggleOnBg
                    r.togglePill.BackgroundTransparency = ft(0.05, fa)
                    r.toggleDot.Position = UDim2.fromOffset(TOGGLE_W - TOGGLE_DOT - TOGGLE_PAD, TOGGLE_PAD)
                    r.toggleDot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                else
                    r.togglePill.BackgroundColor3       = C.ToggleOffBg
                    r.togglePill.BackgroundTransparency = ft(0.15, fa)
                    r.toggleDot.Position = UDim2.fromOffset(TOGGLE_PAD, TOGGLE_PAD)
                    r.toggleDot.BackgroundColor3 = Color3.fromRGB(160, 158, 165)
                end
                r.toggleDot.BackgroundTransparency = ft(0.0, fa)
                if r.pillStroke then r.pillStroke.Transparency = ft(0.55, fa) end
            end
            r.vt.Visible = false
        end
    end
end

-- ═════════════════════════════════════════════════════════════════════════════
--  UPDATE
-- ═════════════════════════════════════════════════════════════════════════════
local INFO_UPDATE_RATE = 1 / 60
local infoLastUpdate   = 0

local function update()
    Camera = workspace.CurrentCamera
    local cfg = settings["Hotkeys"]
    if not cfg or cfg["Enabled"] ~= true then hideAll(); return end

    local now = os.clock()
    local dt  = now - infoLastUpdate
    if dt < INFO_UPDATE_RATE then return end
    infoLastUpdate = now

    -- Animate fades
    local fadeFactor = 1 - mathExp(-FADE_SPEED * dt)
    for _, fd in ipairs(featureDefs) do
        local on = fd.getOn()
        if on and not prevOn[fd.label] then
            for j = #activationOrder, 1, -1 do
                if activationOrder[j] == fd.label then
                    table.remove(activationOrder, j)
                    break
                end
            end
            activationOrder[#activationOrder + 1] = fd.label
        end
        prevOn[fd.label] = on
        local target = on and 1 or 0
        local cur = fadeAlphas[fd.label] or 0
        local new = cur + (target - cur) * fadeFactor
        fadeAlphas[fd.label] = (mathAbs(new - target) < 0.005) and target or new
    end

    resolveColors(cfg)
    if not ready then buildPool(cfg) end
    if not ready then return end

    local vp  = Camera and Camera.ViewportSize or Vector2.new(1920, 1080)
    local pos = cfg["Position"] or {}
    local bx  = mathFloor(vp.X * (pos["X"] or 0.0055))
    local by  = mathFloor(vp.Y * (pos["Y"] or 0.60))

    local titleStr = cfg["Title"] or "Hotkeys"
    local curY = renderHeader(cfg, bx, by, cachedHdrW, titleStr)
    curY = renderTarget(cfg, bx, curY)
    curY = renderInfo(cfg, bx, curY)
    renderRows(cfg, bx, curY, dt)
end

-- ═════════════════════════════════════════════════════════════════════════════
--  LIFECYCLE
-- ═════════════════════════════════════════════════════════════════════════════
local function cleanup()
    destroyPool()
    infoLastUpdate = 0
    fadeAlphas = {}; prevOn = {}; rowYSmoothed = {}; activationOrder = {}
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

    local cfg = settings["Hotkeys"] or {}
    resolveColors(cfg)
    rebuildLabelWidths(cfg)
    resetAnimState()
    buildPool(cfg)
end

function Visuals.update()
    update()
end

function Visuals.cleanup()
    cleanup()
end

return Visuals