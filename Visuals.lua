local Visuals = {}

local settings, State, Camera, LP, screenGui, ForceHitModule, ESPModule, KNOWN_BODY_PARTS

-- ═════════════════════════════════════════════════════════════════════════════
--  LAYOUT CONSTANTS
-- ═════════════════════════════════════════════════════════════════════════════
local FONT      = Enum.Font.GothamBold
local CORNER    = 6
local PAD_X     = 10
local CHIP_H    = 22
local HEADER_H  = 26
local ROW_GAP   = 3
local VAL_PAD   = 8
local FONT_SIZE = 11
local HDR_SIZE  = 12
local TOG_W     = 36
local MAX_ROWS  = 16

-- ═════════════════════════════════════════════════════════════════════════════
--  LIVE COLOUR TABLE
-- ═════════════════════════════════════════════════════════════════════════════
local C = {
    HeaderBg    = Color3.fromRGB(30, 28, 35),
    HeaderAlpha = 0.10,
    ChipBg      = Color3.fromRGB(30, 28, 35),
    ChipAlpha   = 0.10,
    StrokeColor = Color3.fromRGB(255, 255, 255),
    StrokeAlpha = 0.91,
    StrokeThick = 0.6,
    LabelText   = Color3.fromRGB(200, 210, 220),
    ValueText   = Color3.fromRGB(240, 245, 255),
    HeaderText  = Color3.fromRGB(220, 228, 238),
    HeaderIcon  = Color3.fromRGB(120, 160, 190),
    ToggleOnBg     = Color3.fromRGB(46, 168, 126),
    ToggleOnThumb  = Color3.fromRGB(255, 255, 255),
    ToggleOffBg    = Color3.fromRGB(70,  70,  88),
    ToggleOffThumb = Color3.fromRGB(195, 195, 205),
}

local function syncColors(co)
    if not co or type(co) ~= "table" then return end
    for k, v in pairs(co) do C[k] = v end
end

-- ═════════════════════════════════════════════════════════════════════════════
--  HELPERS
-- ═════════════════════════════════════════════════════════════════════════════
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

local function refreshStroke(f)
    local s = f:FindFirstChildOfClass("UIStroke")
    if s then
        s.Color        = C.StrokeColor
        s.Transparency = C.StrokeAlpha
        s.Thickness    = C.StrokeThick
    end
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
    t.TextStrokeTransparency = 0.55
    t.ZIndex                 = z or 11
    t.Size                   = UDim2.fromScale(1, 1)
    t.Parent                 = parent
    return t
end

local function tw(s, sz)
    return math.ceil(#tostring(s) * ((sz or FONT_SIZE) >= 12 and 7.2 or 6.8))
end

local function newTogglePill(parent, z)
    local track = Instance.new("Frame")
    track.BorderSizePixel  = 0
    track.BackgroundColor3 = C.ToggleOffBg
    track.Size             = UDim2.fromOffset(26, 13)
    track.ZIndex           = z or 11
    track.Parent           = parent
    addCorner(track, 99)

    local thumb = Instance.new("Frame")
    thumb.BorderSizePixel  = 0
    thumb.BackgroundColor3 = C.ToggleOffThumb
    thumb.Size             = UDim2.fromOffset(9, 9)
    thumb.Position         = UDim2.fromOffset(2, 2)
    thumb.ZIndex           = (z or 11) + 1
    thumb.Parent           = track
    addCorner(thumb, 99)

    return { track = track, thumb = thumb }
end

local function setPill(pill, on)
    if on then
        pill.track.BackgroundColor3 = C.ToggleOnBg
        pill.thumb.BackgroundColor3 = C.ToggleOnThumb
        pill.thumb.Position         = UDim2.fromOffset(15, 2)
    else
        pill.track.BackgroundColor3 = C.ToggleOffBg
        pill.thumb.BackgroundColor3 = C.ToggleOffThumb
        pill.thumb.Position         = UDim2.fromOffset(2, 2)
    end
end

-- ═════════════════════════════════════════════════════════════════════════════
--  POOL
-- ═════════════════════════════════════════════════════════════════════════════
local pool  = {}
local ready = false

local function destroyPool()
    if pool.hChip then pcall(function() pool.hChip:Destroy() end) end
    for _, r in ipairs(pool.rows or {}) do
        pcall(function() r.lblChip:Destroy() end)
        pcall(function() r.valChip:Destroy() end)
        pcall(function() r.togChip:Destroy() end)
    end
    pool  = {}
    ready = false
end

local function buildPool()
    destroyPool()

    local hc = newFrame(10)
    hc.BackgroundColor3       = C.HeaderBg
    hc.BackgroundTransparency = C.HeaderAlpha
    local hi = newText(hc, C.HeaderIcon, 14, 12, Enum.TextXAlignment.Left)
    hi.Text     = "\226\137\161"
    hi.Size     = UDim2.fromOffset(20, HEADER_H)
    hi.Position = UDim2.fromOffset(6, 0)
    local ht = newText(hc, C.HeaderText, HDR_SIZE, 12, Enum.TextXAlignment.Left)
    ht.Position = UDim2.fromOffset(26, 0)

    pool.hChip  = hc
    pool.hIcon  = hi
    pool.hTitle = ht

    pool.rows = {}
    for i = 1, MAX_ROWS do
        local lc = newFrame(10)
        local lt = newText(lc, C.LabelText, FONT_SIZE, 11, Enum.TextXAlignment.Left)
        lt.Position = UDim2.fromOffset(PAD_X, 0)

        local vc = newFrame(10)
        local vt = newText(vc, C.ValueText, FONT_SIZE, 11, Enum.TextXAlignment.Center)

        local tc   = newFrame(10)
        local pill = newTogglePill(tc, 11)
        pill.track.Position = UDim2.fromOffset(
            math.floor((TOG_W - 26) / 2),
            math.floor((CHIP_H - 13) / 2)
        )

        pool.rows[i] = { lblChip = lc, lt = lt, valChip = vc, vt = vt, togChip = tc, pill = pill }
    end

    ready = true
end

-- ═════════════════════════════════════════════════════════════════════════════
--  DEFAULT BINDS  (structural — not user config)
-- ═════════════════════════════════════════════════════════════════════════════
local DEFAULT_BINDS = {
    { label = "Triggerbot",  type = "bool",   source = "Triggerbot", valueKey = "Enabled" },
    { label = "Camlock",     type = "bool",   source = "Camlock",    valueKey = "Enabled" },
    { label = "Force Shot",  type = "bool",   path = {"Weapon Modifications", "ForceHit", "Enabled"} },
    { label = "Triggerbot",  type = "toggle", stateKey = "TriggerbotToggleActive", parentSource = "Triggerbot" },
    { label = "Camlock",     type = "toggle", stateKey = "CamlockToggleActive",    parentSource = "Camlock" },
}

-- ═════════════════════════════════════════════════════════════════════════════
--  GATHER VISIBLE ROWS  (wired to real settings/State)
-- ═════════════════════════════════════════════════════════════════════════════
local function getCurrentSpreadValue()
    local wm = settings["Weapon Modifications"]
    if type(wm) ~= "table" then return nil end
    local raw = wm["Custom Spread"]
    if type(raw) ~= "table" or raw["Enabled"] == false then return nil end
    local char = LP and LP.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    if not tool then return nil end
    local v = raw[tool.Name]
    return type(v) == "number" and v or nil
end

local function gatherVisible(cfg)
    local out   = {}
    local binds = (cfg and cfg["Binds"]) or DEFAULT_BINDS
    if not binds then return out end

    for _, def in ipairs(binds) do
        local function resolve()
            if def.path then
                local cur = settings
                for _, k in ipairs(def.path) do cur = cur and cur[k] end
                return cur
            end
            if def.resolver then return def.resolver() end
            return settings[def.source] and settings[def.source][def.valueKey]
        end

        local parentOk = true
        if def.parentSource then
            parentOk = settings[def.parentSource]
                and settings[def.parentSource]["Enabled"] == true
        end
        if not parentOk then continue end

        if def.type == "bool" then
            if resolve() == true then
                out[#out + 1] = { label = def.label, type = "bool" }
            end

        elseif def.type == "value" then
            local v = resolve()
            if v ~= nil then
                out[#out + 1] = { label = def.label, type = "value", value = v }
            end

        elseif def.type == "toggle" then
            if State[def.stateKey] == true then
                out[#out + 1] = { label = def.label, type = "toggle" }
            end
        end
    end
    return out
end

-- ═════════════════════════════════════════════════════════════════════════════
--  HIDE ALL
-- ═════════════════════════════════════════════════════════════════════════════
local function hideAll()
    if pool.hChip then pool.hChip.Visible = false end
    for _, r in ipairs(pool.rows or {}) do
        r.lblChip.Visible = false
        r.valChip.Visible = false
        r.togChip.Visible = false
    end
end

-- ═════════════════════════════════════════════════════════════════════════════
--  RENDER
-- ═════════════════════════════════════════════════════════════════════════════
local function render(cfg, visRows)
    local vp  = Camera and Camera.ViewportSize or Vector2.new(1920, 1080)
    local pos = cfg["Position"] or {}
    local bx  = math.floor(vp.X * (pos["X"] or 0.015))
    local by  = math.floor(vp.Y * (pos["Y"] or 0.38))

    local titleStr = cfg["Title"] or cfg["Alias"] or "Hotkeys"

    -- Dynamic header (locked target)
    local dynHead  = cfg["Dynamic Header"] ~= false
    local hasTarget = State.LockedTarget ~= nil and State.LockedTarget.Parent ~= nil
    if dynHead and hasTarget then
        titleStr = State.LockedTarget.DisplayName or State.LockedTarget.Name
    end

    -- Measure widest row → shared column width
    local colW = tw(titleStr, HDR_SIZE) + 20 + PAD_X * 2

    for _, rd in ipairs(visRows) do
        local rowW
        if rd.type == "bool" then
            rowW = tw(rd.label, FONT_SIZE) + PAD_X * 2
        elseif rd.type == "value" then
            local vw = tw(tostring(rd.value), FONT_SIZE) + VAL_PAD * 2
            rowW = vw + ROW_GAP + tw(rd.label, FONT_SIZE) + PAD_X * 2
        elseif rd.type == "toggle" then
            rowW = tw(rd.label, FONT_SIZE) + PAD_X * 2 + ROW_GAP + TOG_W
        end
        if rowW and rowW > colW then colW = rowW end
    end

    -- Header
    local hc = pool.hChip
    hc.BackgroundColor3       = C.HeaderBg
    hc.BackgroundTransparency = C.HeaderAlpha
    hc.Position               = UDim2.fromOffset(bx, by)
    hc.Size                   = UDim2.fromOffset(colW, HEADER_H)
    hc.Visible                = true
    refreshStroke(hc)
    pool.hIcon.TextColor3  = C.HeaderIcon
    pool.hTitle.TextColor3 = (dynHead and hasTarget)
        and (C.TargetText or Color3.fromRGB(255, 80, 80))
        or C.HeaderText
    pool.hTitle.Text = titleStr
    pool.hTitle.Size = UDim2.fromOffset(colW - 28, HEADER_H)

    local curY = by + HEADER_H + ROW_GAP

    for i, rd in ipairs(visRows) do
        local r = pool.rows[i]
        if not r then break end

        local function styleChip(chip)
            chip.BackgroundColor3       = C.ChipBg
            chip.BackgroundTransparency = C.ChipAlpha
            refreshStroke(chip)
        end

        if rd.type == "bool" then
            styleChip(r.lblChip)
            r.lblChip.Position = UDim2.fromOffset(bx, curY)
            r.lblChip.Size     = UDim2.fromOffset(colW, CHIP_H)
            r.lblChip.Visible  = true
            r.lt.Text          = rd.label
            r.lt.TextColor3    = C.LabelText
            r.lt.Size          = UDim2.fromOffset(colW - PAD_X, CHIP_H)
            r.lt.Position      = UDim2.fromOffset(PAD_X, 0)
            r.valChip.Visible  = false
            r.togChip.Visible  = false

        elseif rd.type == "value" then
            local valStr = tostring(rd.value)
            local vw     = tw(valStr, FONT_SIZE) + VAL_PAD * 2
            local lw     = colW - vw - ROW_GAP

            styleChip(r.valChip)
            r.valChip.Position = UDim2.fromOffset(bx, curY)
            r.valChip.Size     = UDim2.fromOffset(vw, CHIP_H)
            r.valChip.Visible  = true
            r.vt.Text          = valStr
            r.vt.TextColor3    = C.ValueText
            r.vt.Size          = UDim2.fromOffset(vw, CHIP_H)
            r.vt.Position      = UDim2.fromOffset(0, 0)

            styleChip(r.lblChip)
            r.lblChip.Position = UDim2.fromOffset(bx + vw + ROW_GAP, curY)
            r.lblChip.Size     = UDim2.fromOffset(lw, CHIP_H)
            r.lblChip.Visible  = true
            r.lt.Text          = rd.label
            r.lt.TextColor3    = C.LabelText
            r.lt.Size          = UDim2.fromOffset(lw - PAD_X, CHIP_H)
            r.lt.Position      = UDim2.fromOffset(PAD_X, 0)
            r.togChip.Visible  = false

        elseif rd.type == "toggle" then
            local lw = colW - TOG_W - ROW_GAP

            styleChip(r.lblChip)
            r.lblChip.Position = UDim2.fromOffset(bx, curY)
            r.lblChip.Size     = UDim2.fromOffset(lw, CHIP_H)
            r.lblChip.Visible  = true
            r.lt.Text          = rd.label
            r.lt.TextColor3    = C.LabelText
            r.lt.Size          = UDim2.fromOffset(lw - PAD_X, CHIP_H)
            r.lt.Position      = UDim2.fromOffset(PAD_X, 0)

            styleChip(r.togChip)
            r.togChip.Position = UDim2.fromOffset(bx + lw + ROW_GAP, curY)
            r.togChip.Size     = UDim2.fromOffset(TOG_W, CHIP_H)
            r.togChip.Visible  = true
            setPill(r.pill, true)
            r.valChip.Visible  = false
        end

        curY = curY + CHIP_H + ROW_GAP
    end

    for i = #visRows + 1, MAX_ROWS do
        local r = pool.rows[i]
        if r then
            r.lblChip.Visible = false
            r.valChip.Visible = false
            r.togChip.Visible = false
        end
    end
end

-- ═════════════════════════════════════════════════════════════════════════════
--  UPDATE
-- ═════════════════════════════════════════════════════════════════════════════
local INFO_UPDATE_RATE = 1 / 50
local infoLastUpdate   = 0

local function update()
    Camera = workspace.CurrentCamera
    local cfg = settings["Hotkeys"]
    if not cfg or cfg["Enabled"] ~= true then hideAll(); return end

    local now = os.clock()
    if (now - infoLastUpdate) < INFO_UPDATE_RATE then return end
    infoLastUpdate = now

    syncColors(cfg["Colors"])
    if not ready then buildPool() end
    if not ready then return end

    local visRows = gatherVisible(cfg)
    hideAll()
    render(cfg, visRows)
end

-- ═════════════════════════════════════════════════════════════════════════════
--  LIFECYCLE
-- ═════════════════════════════════════════════════════════════════════════════
local function cleanup()
    destroyPool()
    infoLastUpdate = 0
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
    buildPool()
end

function Visuals.update()
    update()
end

function Visuals.cleanup()
    cleanup()
end

return Visuals