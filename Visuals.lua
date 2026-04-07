local Visuals = {}

local settings, State, Camera, LP, screenGui, ForceHitModule, ESPModule, KNOWN_BODY_PARTS

local card, headerIcon, headerText, headerDiv
local rowObjs    = {}
local cardStroke = nil

local infoLastUpdate   = 0
local INFO_UPDATE_RATE = 1 / 50

local VISUALS_FONT = Enum.Font.GothamBold
local CARD_W   = 178
local PAD_H    = 12
local PAD_V    = 8
local CORNER_R = 6

local DOT       = "\226\151\143"   -- U+25CF BLACK CIRCLE
local ICON_CHAR = "\226\137\161"   -- U+2261 IDENTICAL TO

local C_BG       = Color3.fromRGB(18, 20, 28)
local C_DIV      = Color3.fromRGB(40, 44, 55)
local C_HEADER   = Color3.fromRGB(255, 255, 255)
local C_ACTIVE   = Color3.fromRGB(74, 222, 128)
local C_IDLE     = Color3.fromRGB(80, 88, 102)
local C_GHOST    = Color3.fromRGB(62, 66, 78)
local C_LABEL    = Color3.fromRGB(200, 200, 255)
local C_TEXT     = Color3.fromRGB(195, 200, 210)
local C_ACCENT   = Color3.fromRGB(180, 120, 255)
local C_BAR_IDLE = Color3.fromRGB(55, 62, 78)

local overlayReady = false
local cachedColors = {}

local ROW_COUNT = 4

local function syncColors(colors)
    if type(colors) ~= "table" then return end
    local dirty = false
    for k, v in pairs(colors) do
        if cachedColors[k] ~= v then cachedColors[k] = v; dirty = true end
    end
    if not dirty then return end
    C_ACTIVE   = cachedColors["Active"]        or C_ACTIVE
    C_IDLE     = cachedColors["Idle"]          or C_IDLE
    C_GHOST    = cachedColors["Ghost"]         or C_GHOST
    C_LABEL    = cachedColors["Feature Label"] or C_LABEL
    C_TEXT     = cachedColors["Text"]          or C_TEXT
    C_ACCENT   = cachedColors["Accent"]        or C_ACCENT
    C_BAR_IDLE = cachedColors["Bar Idle"]      or C_BAR_IDLE
    C_HEADER   = cachedColors["Header"]        or C_HEADER
    if cardStroke then cardStroke.Color = C_ACCENT end
end

local function makeLabel(parent, props)
    local t = Instance.new("TextLabel")
    t.Name                   = props.Name or "Lbl"
    t.BackgroundTransparency = 1
    t.Font                   = VISUALS_FONT
    t.TextSize               = props.TextSize or 11
    t.TextColor3             = props.TextColor3 or C_TEXT
    t.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
    t.TextStrokeTransparency = props.Outline and 0.2 or 1
    t.TextXAlignment         = props.XAlign or Enum.TextXAlignment.Left
    t.TextYAlignment         = Enum.TextYAlignment.Center
    t.RichText               = false
    t.Text                   = props.Text or ""
    t.Size                   = props.Size or UDim2.fromOffset(80, 22)
    t.Position               = props.Position or UDim2.fromOffset(0, 0)
    t.ZIndex                 = 11
    t.Visible                = true
    t.Parent                 = parent
    return t
end

local function makeDivider(parent, yPos)
    local d = Instance.new("Frame")
    d.Name                   = "Div"
    d.BackgroundColor3       = C_DIV
    d.BackgroundTransparency = 0.25
    d.BorderSizePixel        = 0
    d.Size                   = UDim2.new(1, -(PAD_H * 2), 0, 1)
    d.Position               = UDim2.fromOffset(PAD_H, yPos)
    d.ZIndex                 = 11
    d.Parent                 = parent
    return d
end

local function buildCard()
    if card then pcall(function() card:Destroy() end) end
    card = nil; rowObjs = {}; cardStroke = nil
    headerIcon = nil; headerText = nil; headerDiv = nil

    local cfg     = settings["Visuals"]["Info"]
    local sz      = cfg["Position"]["Size"] or 11
    local outline = cfg["Outline"] ~= false
    local rowH    = sz + 10
    local headH   = sz + 12

    card = Instance.new("Frame")
    card.Name                   = "VisualsCard"
    card.BackgroundColor3       = C_BG
    card.BackgroundTransparency = 0.15
    card.BorderSizePixel        = 0
    card.ZIndex                 = 9
    card.Visible                = false
    card.Parent                 = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, CORNER_R)
    corner.Parent = card

    cardStroke = Instance.new("UIStroke")
    cardStroke.Color        = C_ACCENT
    cardStroke.Transparency = 0.6
    cardStroke.Thickness    = 1.2
    cardStroke.Parent       = card

    local iconW = sz + 4
    headerIcon = makeLabel(card, {
        Name = "Icon", Text = ICON_CHAR, TextColor3 = C_ACCENT,
        TextSize = sz + 2, Outline = outline,
        Size = UDim2.fromOffset(iconW, headH),
        Position = UDim2.fromOffset(PAD_H, PAD_V),
    })

    headerText = makeLabel(card, {
        Name = "Header", Text = cfg["Alias"] or "sauce", TextColor3 = C_HEADER,
        TextSize = sz, Outline = outline,
        Size = UDim2.new(1, -(PAD_H * 2 + iconW + 4), 0, headH),
        Position = UDim2.fromOffset(PAD_H + iconW + 4, PAD_V),
    })

    local divY = PAD_V + headH
    headerDiv = makeDivider(card, divY)

    local y = divY + 1
    for i = 1, ROW_COUNT do
        local ry = y + (i - 1) * (rowH + 1)

        local left = makeLabel(card, {
            Name = "R" .. i .. "L", TextColor3 = C_LABEL, TextSize = sz,
            Outline = outline,
            Size = UDim2.new(0.6, 0, 0, rowH),
            Position = UDim2.fromOffset(PAD_H, ry),
        })

        local right = makeLabel(card, {
            Name = "R" .. i .. "R", TextColor3 = C_TEXT, TextSize = sz,
            Outline = outline,
            Size = UDim2.new(0.4, -PAD_H, 0, rowH),
            Position = UDim2.new(0.6, 0, 0, ry),
            XAlign = Enum.TextXAlignment.Right,
        })

        local div = nil
        if i < ROW_COUNT then
            div = makeDivider(card, ry + rowH)
        end

        rowObjs[i] = { left = left, right = right, div = div }
    end

    local totalH = PAD_V + headH + 1 + ROW_COUNT * rowH + (ROW_COUNT - 1) + PAD_V
    card.Size = UDim2.fromOffset(CARD_W, totalH)

    overlayReady = true
end

local function getDotColor(enabled, active)
    if not enabled then return C_GHOST end
    if active then return C_ACTIVE end
    return C_BAR_IDLE
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

local function setRow(i, labelText, valueText, labelColor, valueColor, isInverted)
    local row = rowObjs[i]
    if not row then return end
    if isInverted then
        row.left.Text            = valueText
        row.left.TextColor3      = valueColor
        row.left.TextXAlignment  = Enum.TextXAlignment.Left
        row.right.Text           = labelText
        row.right.TextColor3     = labelColor
        row.right.TextXAlignment = Enum.TextXAlignment.Right
    else
        row.left.Text            = labelText
        row.left.TextColor3      = labelColor
        row.left.TextXAlignment  = Enum.TextXAlignment.Left
        row.right.Text           = valueText
        row.right.TextColor3     = valueColor
        row.right.TextXAlignment = Enum.TextXAlignment.Right
    end
end

local function update()
    Camera = workspace.CurrentCamera
    local cfg = settings["Visuals"] and settings["Visuals"]["Info"]
    if not cfg or not cfg["Enabled"] then
        if card and card.Visible then card.Visible = false end
        return
    end

    if not overlayReady then buildCard() end

    local now = os.clock()
    if (now - infoLastUpdate) < INFO_UPDATE_RATE then return end
    infoLastUpdate = now

    syncColors(cfg["Colors"])

    local style   = string.lower(cfg["Style"] or "normal")
    local align   = string.lower(cfg["Align"] or "left")
    local dynHead = cfg["Dynamic Header"] ~= false
    local pos     = cfg["Position"]
    local vp      = Camera and Camera.ViewportSize or Vector2.new(1920, 1080)
    local xPct    = pos["X"] or 0.0055
    local yPct    = pos["Y"] or 0.65

    local cardX
    if align == "right" then
        cardX = math.floor(vp.X * (1 - xPct)) - CARD_W
    else
        cardX = math.floor(vp.X * xPct)
    end
    local cardY = math.floor(vp.Y * yPct)

    card.Position = UDim2.fromOffset(cardX, cardY)
    card.Visible  = true

    local hasTarget = State.LockedTarget ~= nil and State.LockedTarget.Parent ~= nil
    if dynHead and hasTarget then
        headerText.Text       = State.LockedTarget.DisplayName or State.LockedTarget.Name
        headerText.TextColor3 = cachedColors["Target"] or Color3.fromRGB(255, 80, 80)
    else
        headerText.Text       = cfg["Alias"] or "sauce"
        headerText.TextColor3 = C_HEADER
    end
    headerIcon.TextColor3 = C_ACCENT

    local isInv = style == "inverted"

    -- Triggerbot
    local tbEnabled   = settings["Triggerbot"] and settings["Triggerbot"]["Enabled"]
    local tbClickType = string.lower(tostring((settings["Triggerbot"] and settings["Triggerbot"]["Click Type"]) or "Hold"))
    local tbArmed     = tbEnabled and (
        (tbClickType == "toggle" and State.TriggerbotToggleActive) or
        (tbClickType ~= "toggle" and State.TriggerbotHoldActive)
    )
    setRow(1, "Triggerbot", DOT, C_LABEL, getDotColor(tbEnabled, tbArmed), isInv)

    -- Camlock
    local camEnabled   = settings["Camlock"] and settings["Camlock"]["Enabled"]
    local camClickType = string.lower(tostring((settings["Camlock"] and settings["Camlock"]["Click Type"]) or "Hold"))
    local camArmed     = camEnabled and (
        (camClickType == "toggle" and State.CamlockToggleActive) or
        (camClickType ~= "toggle" and State.CamlockHoldActive)
    )
    setRow(2, "Camlock", DOT, C_LABEL, getDotColor(camEnabled, camArmed), isInv)

    -- ForceHit
    local fhEnabled = settings["Weapon Modifications"]
        and settings["Weapon Modifications"]["ForceHit"]
        and settings["Weapon Modifications"]["ForceHit"]["Enabled"]
    local fhActive  = ForceHitModule and ForceHitModule.isActive and ForceHitModule.isActive() or false
    setRow(3, "ForceHit", DOT, C_LABEL, getDotColor(fhEnabled, fhActive), isInv)

    -- Spread
    local sv = getCurrentSpreadValue()
    local spreadStr = sv and tostring(math.floor(sv)) or "--"
    setRow(4, "Spread", spreadStr, C_LABEL, sv and C_TEXT or C_GHOST, isInv)
end

local function cleanup()
    if card then pcall(function() card:Destroy() end) end
    card         = nil
    headerIcon   = nil
    headerText   = nil
    headerDiv    = nil
    rowObjs      = {}
    cardStroke   = nil
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