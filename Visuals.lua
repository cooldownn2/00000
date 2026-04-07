local Visuals = {}

local settings, State, Camera, LP, screenGui, ForceHitModule, ESPModule, KNOWN_BODY_PARTS

-- UI references
local container
local headerPill, headerIcon, headerText
local rowPills     = {}
local cachedColors = {}

local infoLastUpdate   = 0
local INFO_UPDATE_RATE = 1 / 50
local overlayReady     = false

-- Layout
local VISUALS_FONT = Enum.Font.GothamBold
local PILL_W    = 182
local PILL_H    = 28
local HEADER_H  = 30
local PILL_GAP  = 4
local PAD_H     = 10
local CORNER_R  = 10
local BADGE_R   = 6
local BADGE_H   = 20
local BADGE_W   = 74

local ICON_CHAR = "\226\137\161"   -- U+2261 IDENTICAL TO (≡)

-- Default colours
local defaults = {
    Active  = Color3.fromRGB(74, 222, 128),
    Idle    = Color3.fromRGB(80, 88, 102),
    Ghost   = Color3.fromRGB(62, 66, 78),
    Label   = Color3.fromRGB(200, 200, 220),
    Text    = Color3.fromRGB(195, 200, 210),
    Accent  = Color3.fromRGB(90, 110, 255),
    Header  = Color3.fromRGB(255, 255, 255),
    PillBG  = Color3.fromRGB(15, 17, 25),
    BadgeBG = Color3.fromRGB(30, 34, 48),
}
local C = {}
for k, v in pairs(defaults) do C[k] = v end

local PILL_TRANS  = 0.18
local BADGE_TRANS = 0.35

local ROW_COUNT = 4

-- ── helpers ──────────────────────────────────────────────

local function syncColors(colors)
    if type(colors) ~= "table" then return end
    local dirty = false
    for k, v in pairs(colors) do
        if cachedColors[k] ~= v then cachedColors[k] = v; dirty = true end
    end
    if not dirty then return end
    for k, def in pairs(defaults) do
        C[k] = cachedColors[k] or def
    end
end

local function makeLabel(parent, props)
    local t = Instance.new("TextLabel")
    t.Name                   = props.Name or "Lbl"
    t.BackgroundTransparency = 1
    t.Font                   = VISUALS_FONT
    t.TextSize               = props.TextSize or 11
    t.TextColor3             = props.TextColor3 or C.Text
    t.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
    t.TextStrokeTransparency = props.Outline and 0.15 or 1
    t.TextXAlignment         = props.XAlign or Enum.TextXAlignment.Left
    t.TextYAlignment         = Enum.TextYAlignment.Center
    t.RichText               = false
    t.Text                   = props.Text or ""
    t.Size                   = props.Size or UDim2.new(1, 0, 1, 0)
    t.Position               = props.Position or UDim2.fromOffset(0, 0)
    t.ZIndex                 = 12
    t.Visible                = true
    t.Parent                 = parent
    return t
end

local function makePill(parent, name, w, h, yOff)
    local pill = Instance.new("Frame")
    pill.Name                   = name
    pill.BackgroundColor3       = C.PillBG
    pill.BackgroundTransparency = PILL_TRANS
    pill.BorderSizePixel        = 0
    pill.Size                   = UDim2.fromOffset(w, h)
    pill.Position               = UDim2.fromOffset(0, yOff)
    pill.ZIndex                 = 10
    pill.Visible                = true
    pill.Parent                 = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, CORNER_R)
    corner.Parent = pill

    return pill
end

local function makeBadge(parent, sz, outline)
    local badge = Instance.new("Frame")
    badge.Name                   = "Badge"
    badge.BackgroundColor3       = C.BadgeBG
    badge.BackgroundTransparency = BADGE_TRANS
    badge.BorderSizePixel        = 0
    badge.Size                   = UDim2.fromOffset(BADGE_W, BADGE_H)
    badge.AnchorPoint            = Vector2.new(1, 0.5)
    badge.Position               = UDim2.new(1, -6, 0.5, 0)
    badge.ZIndex                 = 11
    badge.Parent                 = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, BADGE_R)
    corner.Parent = badge

    local label = makeLabel(badge, {
        Name = "Txt", TextSize = sz, TextColor3 = C.Text,
        Outline = outline, XAlign = Enum.TextXAlignment.Center,
        Size = UDim2.new(1, 0, 1, 0),
        Position = UDim2.fromOffset(0, 0),
    })
    label.TextXAlignment = Enum.TextXAlignment.Center

    return badge, label
end

-- ── build ────────────────────────────────────────────────

local function buildCard()
    if container then pcall(function() container:Destroy() end) end
    container = nil; headerPill = nil; headerIcon = nil; headerText = nil
    rowPills = {}

    local cfg     = settings["Visuals"]["Info"]
    local sz      = cfg["Position"]["Size"] or 11
    local outline = cfg["Outline"] ~= false

    -- invisible wrapper
    container = Instance.new("Frame")
    container.Name                   = "VisualsContainer"
    container.BackgroundTransparency = 1
    container.BorderSizePixel        = 0
    container.ZIndex                 = 9
    container.Visible                = false
    container.Parent                 = screenGui

    local y = 0

    -- header pill
    headerPill = makePill(container, "Header", PILL_W, HEADER_H, y)
    local iconW = sz + 4

    headerIcon = makeLabel(headerPill, {
        Name = "Icon", Text = ICON_CHAR, TextColor3 = C.Accent,
        TextSize = sz + 2, Outline = outline,
        Size = UDim2.fromOffset(iconW, HEADER_H),
        Position = UDim2.fromOffset(PAD_H, 0),
    })

    headerText = makeLabel(headerPill, {
        Name = "Title", Text = cfg["Alias"] or "sauce", TextColor3 = C.Header,
        TextSize = sz, Outline = outline,
        Size = UDim2.new(1, -(PAD_H * 2 + iconW + 4), 0, HEADER_H),
        Position = UDim2.fromOffset(PAD_H + iconW + 4, 0),
    })

    y = y + HEADER_H + PILL_GAP

    -- row pills
    for i = 1, ROW_COUNT do
        local pill = makePill(container, "Row" .. i, PILL_W, PILL_H, y)

        local leftLabel = makeLabel(pill, {
            Name = "Left", TextColor3 = C.Label, TextSize = sz,
            Outline = outline,
            Size = UDim2.new(0.5, -PAD_H, 1, 0),
            Position = UDim2.fromOffset(PAD_H, 0),
        })

        local badge, badgeLabel = makeBadge(pill, sz, outline)

        rowPills[i] = {
            pill       = pill,
            leftLabel  = leftLabel,
            badge      = badge,
            badgeLabel = badgeLabel,
        }

        y = y + PILL_H + PILL_GAP
    end

    container.Size = UDim2.fromOffset(PILL_W, y - PILL_GAP)
    overlayReady = true
end

-- ── per-frame ────────────────────────────────────────────

local function statusColor(enabled, active)
    if not enabled then return C.Ghost end
    if active     then return C.Active end
    return C.Idle
end

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

local function setRow(i, label, badgeText, badgeColor)
    local row = rowPills[i]
    if not row then return end
    row.leftLabel.Text       = label
    row.leftLabel.TextColor3 = C.Label
    row.badgeLabel.Text       = badgeText
    row.badgeLabel.TextColor3 = badgeColor
end

local function update()
    Camera = workspace.CurrentCamera
    local cfg = settings["Visuals"] and settings["Visuals"]["Info"]
    if not cfg or not cfg["Enabled"] then
        if container and container.Visible then container.Visible = false end
        return
    end

    if not overlayReady then buildCard() end

    local now = os.clock()
    if (now - infoLastUpdate) < INFO_UPDATE_RATE then return end
    infoLastUpdate = now

    syncColors(cfg["Colors"])

    local align   = string.lower(cfg["Align"] or "left")
    local dynHead = cfg["Dynamic Header"] ~= false
    local pos     = cfg["Position"]
    local vp      = Camera and Camera.ViewportSize or Vector2.new(1920, 1080)
    local xPct    = pos["X"] or 0.0055
    local yPct    = pos["Y"] or 0.65

    local cardX
    if align == "right" then
        cardX = math.floor(vp.X * (1 - xPct)) - PILL_W
    else
        cardX = math.floor(vp.X * xPct)
    end
    local cardY = math.floor(vp.Y * yPct)

    container.Position = UDim2.fromOffset(cardX, cardY)
    container.Visible  = true

    -- header
    local hasTarget = State.LockedTarget ~= nil and State.LockedTarget.Parent ~= nil
    if dynHead and hasTarget then
        headerText.Text       = State.LockedTarget.DisplayName or State.LockedTarget.Name
        headerText.TextColor3 = cachedColors["Target"] or Color3.fromRGB(255, 80, 80)
    else
        headerText.Text       = cfg["Alias"] or "sauce"
        headerText.TextColor3 = C.Header
    end
    headerIcon.TextColor3 = C.Accent

    -- Row 1 – Triggerbot
    local tbEnabled   = settings["Triggerbot"] and settings["Triggerbot"]["Enabled"]
    local tbClickType = tostring((settings["Triggerbot"] and settings["Triggerbot"]["Click Type"]) or "Hold")
    local tbArmed     = tbEnabled and (
        (string.lower(tbClickType) == "toggle" and State.TriggerbotToggleActive) or
        (string.lower(tbClickType) ~= "toggle" and State.TriggerbotHoldActive)
    )
    setRow(1, "Triggerbot", tbEnabled and tbClickType or "Off", statusColor(tbEnabled, tbArmed))

    -- Row 2 – Camlock
    local camEnabled   = settings["Camlock"] and settings["Camlock"]["Enabled"]
    local camClickType = tostring((settings["Camlock"] and settings["Camlock"]["Click Type"]) or "Hold")
    local camArmed     = camEnabled and (
        (string.lower(camClickType) == "toggle" and State.CamlockToggleActive) or
        (string.lower(camClickType) ~= "toggle" and State.CamlockHoldActive)
    )
    setRow(2, "Camlock", camEnabled and camClickType or "Off", statusColor(camEnabled, camArmed))

    -- Row 3 – ForceHit
    local fhEnabled = settings["Weapon Modifications"]
        and settings["Weapon Modifications"]["ForceHit"]
        and settings["Weapon Modifications"]["ForceHit"]["Enabled"]
    local fhActive = ForceHitModule and ForceHitModule.isActive and ForceHitModule.isActive() or false
    setRow(3, "ForceHit", fhEnabled and (fhActive and "Active" or "Enabled") or "Off", statusColor(fhEnabled, fhActive))

    -- Row 4 – Spread
    local sv = getCurrentSpreadValue()
    local spreadStr = sv and tostring(math.floor(sv)) or "--"
    setRow(4, "Spread", spreadStr, sv and C.Text or C.Ghost)
end

-- ── lifecycle ────────────────────────────────────────────

local function cleanup()
    if container then pcall(function() container:Destroy() end) end
    container    = nil
    headerPill   = nil
    headerIcon   = nil
    headerText   = nil
    rowPills     = {}
    cachedColors = {}
    overlayReady = false
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
    buildCard()
end

function Visuals.update()
    update()
end

function Visuals.cleanup()
    cleanup()
end

return Visuals