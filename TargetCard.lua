local TweenService  = game:GetService("TweenService")
local TextService   = game:GetService("TextService")
local Players       = game:GetService("Players")
local LP            = Players.LocalPlayer

local FADE_TIME          = 0.1
local NOTIF_W            = 252
local NOTIF_H            = 66
local ICON_SIZE          = 44
local CARD_BOTTOM_OFFSET = 105
local CARD_RX            = ICON_SIZE + 20
local HEADER_GAP         = 7
local WEAPON_MIN_W       = 52
local WEAPON_MAX_W       = 94
local NAME_MIN_W         = 88
local DIST_LERP_ALPHA    = 0.22
local WEAPON_DIM_AFTER   = 2.4
local WEAPON_DIM_SPAN    = 1.6
local WEAPON_DIM_MAX     = 0.6

local C_BG         = Color3.fromRGB(15, 15, 19)
local C_TEXT       = Color3.fromRGB(255, 255, 255)
local C_SUBTEXT    = Color3.fromRGB(110, 110, 128)
local C_HP_HIGH    = Color3.fromRGB(80, 220, 110)
local C_HP_MID     = Color3.fromRGB(240, 200, 40)
local C_HP_LOW     = Color3.fromRGB(225, 55, 55)
local C_ARM        = Color3.fromRGB(140, 200, 255)
local C_DEAD       = Color3.fromRGB(220, 50, 50)
local C_TRACK      = Color3.fromRGB(28, 28, 36)
local C_ACCENT_MID  = Color3.fromRGB(236, 172, 62)
local C_ACCENT_SAFE = Color3.fromRGB(215, 62, 62)

local Settings, State, isUnloaded, screenGui, ESP

local toggleId = 0

local card, iconLabel, nameLabel, hpLabel, armLabel, distLabel, hpBarFill, lockDot
local cardStroke, avatarRingFrame, weaponLabelRef, armBarFill

local cardTweenState = {
    hpPct = -1, armPct = -1, hpColor = nil, accentColor = nil,
    weaponColor = nil, weaponText = nil, weaponChangedAt = 0,
    distDisplay = nil, lastDistText = nil,
}
local cardTweens = {}

local function tweenCard(key, instance, props, duration)
    if not instance then return end
    local existing = cardTweens[key]
    if existing then pcall(function() existing:Cancel() end); cardTweens[key] = nil end
    local ok, tween = pcall(function()
        return TweenService:Create(instance, TweenInfo.new(duration or 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
    end)
    if ok and tween then cardTweens[key] = tween; tween:Play(); return end
    for prop, value in pairs(props) do pcall(function() instance[prop] = value end) end
end

local function colorChanged(a, b, threshold)
    if not a or not b then return true end
    local t = threshold or 0.03
    return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) > t
end

local function getCardAccent(hpPct, alive)
    if not alive then return C_DEAD end
    if hpPct <= 0.3 then return C_HP_LOW end
    if hpPct <= 0.6 then return C_ACCENT_MID end
    return C_ACCENT_SAFE
end

local function applyCardAccent(accent)
    if colorChanged(cardTweenState.accentColor, accent, 0.015) then
        tweenCard("strokeColor", cardStroke,       { Color            = accent }, 0.14)
        tweenCard("ringColor",   avatarRingFrame,   { BackgroundColor3 = accent }, 0.14)
        tweenCard("dotColor",    lockDot,           { BackgroundColor3 = accent }, 0.12)
        cardTweenState.accentColor = accent
    end
end

local function pulseLockDot()
    if not lockDot then return end
    tweenCard("dotPulseGrow", lockDot, { Size = UDim2.new(0, 10, 0, 10), Position = UDim2.new(0, CARD_RX - 3, 0, 54) }, 0.09)
    task.delay(0.09, function()
        if isUnloaded() or not lockDot then return end
        tweenCard("dotPulseShrink", lockDot, { Size = UDim2.new(0, 6, 0, 6), Position = UDim2.new(0, CARD_RX - 1, 0, 56) }, 0.12)
    end)
end

local function layoutCardHeader(displayName, weaponText)
    if not nameLabel or not weaponLabelRef then return end
    local totalHeaderW = NOTIF_W - CARD_RX - 8
    local labelText = weaponText ~= "" and weaponText or "UNARMED"
    local measured
    local ok, sizeOrErr = pcall(function()
        return TextService:GetTextSize(labelText, weaponLabelRef.TextSize, weaponLabelRef.Font, Vector2.new(300, 20))
    end)
    if ok and sizeOrErr then
        measured = sizeOrErr.X
    else
        measured = math.max(#labelText * (weaponLabelRef.TextSize * 0.55), WEAPON_MIN_W - 8)
    end
    local weaponW  = math.clamp(math.floor(measured + 8), WEAPON_MIN_W, WEAPON_MAX_W)
    local maxNameW = totalHeaderW - weaponW - HEADER_GAP
    local nameW    = math.max(NAME_MIN_W, maxNameW)
    if nameW + weaponW + HEADER_GAP > totalHeaderW then nameW = totalHeaderW - weaponW - HEADER_GAP end
    if nameW < 64 then nameW = 64; weaponW = math.max(WEAPON_MIN_W, totalHeaderW - nameW - HEADER_GAP) end
    nameLabel.Size     = UDim2.new(0, nameW, 0, 16)
    nameLabel.Position = UDim2.new(0, CARD_RX, 0, 7)
    nameLabel.Text     = displayName or ""
    weaponLabelRef.Size     = UDim2.new(0, weaponW, 0, 11)
    weaponLabelRef.Position = UDim2.new(0, CARD_RX + nameW + HEADER_GAP, 0, 9)
end

local function makeCorner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = parent
    return c
end

local function makeLabel(parent, props)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.ZIndex = 4
    for k, v in pairs(props) do l[k] = v end
    l.Parent = parent
    return l
end

local function destroyCard()
    if card then pcall(function() card:Destroy() end); card = nil end
    iconLabel, nameLabel, hpLabel, armLabel, distLabel, hpBarFill, lockDot = nil,nil,nil,nil,nil,nil,nil
    cardStroke, avatarRingFrame, weaponLabelRef, armBarFill = nil, nil, nil, nil
    for key, tween in pairs(cardTweens) do pcall(function() tween:Cancel() end); cardTweens[key] = nil end
    cardTweenState.hpPct = -1; cardTweenState.armPct = -1; cardTweenState.hpColor = nil
    cardTweenState.accentColor = nil; cardTweenState.weaponColor = nil; cardTweenState.weaponText = nil
    cardTweenState.weaponChangedAt = 0; cardTweenState.distDisplay = nil; cardTweenState.lastDistText = nil
end

local function buildCard()
    destroyCard()
    card = Instance.new("Frame")
    card.Name = "TargetCard"; card.Size = UDim2.new(0, NOTIF_W, 0, NOTIF_H)
    card.AnchorPoint = Vector2.new(0.5, 1); card.Position = UDim2.new(0.5, 0, 1, -CARD_BOTTOM_OFFSET)
    card.BackgroundColor3 = C_BG; card.BackgroundTransparency = 0
    card.BorderSizePixel = 0; card.ZIndex = 2; card.ClipsDescendants = true
    card.Parent = screenGui
    makeCorner(card, 8)

    cardStroke = Instance.new("UIStroke")
    cardStroke.Color = C_ACCENT_SAFE; cardStroke.Thickness = 1
    cardStroke.Transparency = 0.72; cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    cardStroke.Parent = card

    local grad = Instance.new("UIGradient")
    grad.Rotation = 90
    grad.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 30, 38)), ColorSequenceKeypoint.new(1, Color3.fromRGB(13, 13, 17)) })
    grad.Parent = card

    avatarRingFrame = Instance.new("Frame")
    avatarRingFrame.Size = UDim2.new(0, ICON_SIZE + 4, 0, ICON_SIZE + 4)
    avatarRingFrame.Position = UDim2.new(0, 9, 0.5, -(ICON_SIZE + 4) / 2)
    avatarRingFrame.BackgroundColor3 = C_ACCENT_SAFE; avatarRingFrame.BorderSizePixel = 0
    avatarRingFrame.ZIndex = 3; avatarRingFrame.Parent = card
    makeCorner(avatarRingFrame, 8)

    local ringGrad = Instance.new("UIGradient")
    ringGrad.Rotation = 90
    ringGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0,   Color3.fromRGB(255, 65, 65)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(210, 30, 30)),
        ColorSequenceKeypoint.new(1,   Color3.fromRGB(210, 30, 30)),
    })
    ringGrad.Parent = avatarRingFrame

    local avatarBg = Instance.new("Frame")
    avatarBg.Size = UDim2.new(0, ICON_SIZE, 0, ICON_SIZE)
    avatarBg.Position = UDim2.new(0, 2, 0.5, -ICON_SIZE / 2)
    avatarBg.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
    avatarBg.BorderSizePixel = 0; avatarBg.ZIndex = 4; avatarBg.Parent = avatarRingFrame
    makeCorner(avatarBg, 6)

    iconLabel = Instance.new("ImageLabel")
    iconLabel.Size = UDim2.new(1, 0, 1, 0); iconLabel.BackgroundTransparency = 1
    iconLabel.Image = ""; iconLabel.ScaleType = Enum.ScaleType.Crop
    iconLabel.ZIndex = 5; iconLabel.Parent = avatarBg
    makeCorner(iconLabel, 6)

    local RX = CARD_RX
    nameLabel = makeLabel(card, { Size = UDim2.new(0, NOTIF_W - RX - 96, 0, 16), Position = UDim2.new(0, RX, 0, 7), Text = "", TextColor3 = Color3.fromRGB(255, 255, 255), TextSize = 14, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4 })
    weaponLabelRef = makeLabel(card, { Name = "WeaponLabel", Size = UDim2.new(0, 90, 0, 11), Position = UDim2.new(1, -94, 0, 9), Text = "", TextColor3 = C_SUBTEXT, TextSize = 9, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4 })

    local divider = Instance.new("Frame")
    divider.Size = UDim2.new(0, NOTIF_W - RX - 8, 0, 1); divider.Position = UDim2.new(0, RX, 0, 24)
    divider.BackgroundColor3 = Color3.fromRGB(40, 40, 54); divider.BorderSizePixel = 0; divider.ZIndex = 4; divider.Parent = card

    hpLabel  = makeLabel(card, { Size = UDim2.new(0, 54, 0, 11), Position = UDim2.new(0, RX, 0, 27), Text = "HP 100", TextColor3 = C_HP_HIGH, TextSize = 9, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4 })
    armLabel = makeLabel(card, { Size = UDim2.new(0, 68, 0, 11), Position = UDim2.new(0, RX + 56, 0, 27), Text = "", TextColor3 = C_ARM, TextSize = 9, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 })

    local hpTrack = Instance.new("Frame")
    hpTrack.Size = UDim2.new(0, NOTIF_W - RX - 10, 0, 4); hpTrack.Position = UDim2.new(0, RX, 0, 40)
    hpTrack.BackgroundColor3 = C_TRACK; hpTrack.BorderSizePixel = 0; hpTrack.ZIndex = 3; hpTrack.Parent = card
    makeCorner(hpTrack, 2)

    hpBarFill = Instance.new("Frame")
    hpBarFill.Size = UDim2.new(1, 0, 1, 0); hpBarFill.BackgroundColor3 = C_HP_HIGH
    hpBarFill.BorderSizePixel = 0; hpBarFill.ZIndex = 4; hpBarFill.Parent = hpTrack
    makeCorner(hpBarFill, 2)

    local barGloss = Instance.new("Frame")
    barGloss.Size = UDim2.new(1, 0, 0.5, 0); barGloss.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    barGloss.BackgroundTransparency = 0.78; barGloss.BorderSizePixel = 0; barGloss.ZIndex = 5; barGloss.Parent = hpBarFill
    makeCorner(barGloss, 2)

    local armTrack = Instance.new("Frame")
    armTrack.Size = UDim2.new(0, NOTIF_W - RX - 10, 0, 4); armTrack.Position = UDim2.new(0, RX, 0, 47)
    armTrack.BackgroundColor3 = Color3.fromRGB(25, 40, 65); armTrack.BorderSizePixel = 0; armTrack.ZIndex = 3; armTrack.Parent = card
    makeCorner(armTrack, 2)

    armBarFill = Instance.new("Frame")
    armBarFill.Name = "ArmFill"; armBarFill.Size = UDim2.new(0, 0, 1, 0)
    armBarFill.BackgroundColor3 = Color3.fromRGB(100, 180, 255); armBarFill.BorderSizePixel = 0
    armBarFill.ZIndex = 4; armBarFill.Parent = armTrack
    makeCorner(armBarFill, 2)

    lockDot = Instance.new("Frame")
    lockDot.Size = UDim2.new(0, 6, 0, 6); lockDot.Position = UDim2.new(0, RX - 1, 0, 56)
    lockDot.BackgroundColor3 = C_HP_HIGH; lockDot.BorderSizePixel = 0; lockDot.ZIndex = 5; lockDot.Parent = card
    makeCorner(lockDot, 3)

    makeLabel(card, { Size = UDim2.new(0, 80, 0, 11), Position = UDim2.new(0, RX + 8, 0, 53), Text = "LOCKED ON", TextColor3 = Color3.fromRGB(200, 200, 220), TextSize = 8, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
    distLabel = makeLabel(card, { Size = UDim2.new(0, 80, 0, 11), Position = UDim2.new(1, -86, 0, 53), Text = "", TextColor3 = Color3.fromRGB(134, 134, 141), TextSize = 9, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4 })
end

local function resetCardTweenState()
    cardTweenState.hpPct = -1; cardTweenState.armPct = -1; cardTweenState.hpColor = nil
    cardTweenState.accentColor = nil; cardTweenState.weaponColor = nil; cardTweenState.weaponText = nil
    cardTweenState.weaponChangedAt = 0; cardTweenState.distDisplay = nil; cardTweenState.lastDistText = nil
end

local function showCardForTarget(player)
    if State.Unloaded then return end
    if not card then buildCard() end
    if player then
        iconLabel.Image = "rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=48&h=48"
        local char = player.Character
        local tool = char and char:FindFirstChildOfClass("Tool")
        layoutCardHeader(player.DisplayName, tool and tool.Name or "UNARMED")
    end
    card.BackgroundTransparency = 1
    resetCardTweenState()
    local showOk, showTween = pcall(function()
        return TweenService:Create(card, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { BackgroundTransparency = 0 })
    end)
    if showOk and showTween then showTween:Play() else card.BackgroundTransparency = 0 end
    pulseLockDot()
end

local function hideCard()
    if State.Unloaded or not card then return end
    local hideOk, hideTween = pcall(function()
        return TweenService:Create(card, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { BackgroundTransparency = 1 })
    end)
    if hideOk and hideTween then hideTween:Play() else card.BackgroundTransparency = 1 end
end

local function updateCardStats(player)
    if isUnloaded() or State.CardCapabilityBlocked then return end
    local ok, err = pcall(function()
        if not card or not player then return end
        local tchar = player.Character
        local hp, maxHp, arm = 0, 100, 0
        local alive = false
        if tchar then
            local entry = ESP.getEspCharData(player)
            if entry and entry.char == tchar then
                hp, maxHp, arm = ESP.getEspStatsFromCache(entry)
                alive = entry.hum and entry.hum.Health > 0
            end
        end
        local myChar = LP.Character
        local myHrp  = myChar and myChar:FindFirstChild("HumanoidRootPart")
        local tHrp   = tchar and tchar:FindFirstChild("HumanoidRootPart")
        local dist   = (myHrp and tHrp) and math.floor((tHrp.Position - myHrp.Position).Magnitude) or 0
        local pct    = math.clamp(hp / math.max(maxHp, 1), 0, 1)
        local hpCol
        if not alive then hpCol = C_DEAD
        elseif pct > 0.6 then hpCol = C_HP_HIGH
        elseif pct > 0.3 then hpCol = C_HP_MID
        else hpCol = C_HP_LOW end
        local targetHpPct = alive and pct or 0
        if hpBarFill then
            if math.abs((cardTweenState.hpPct or -1) - targetHpPct) > 0.015 then
                tweenCard("hpSize", hpBarFill, { Size = UDim2.new(targetHpPct, 0, 1, 0) }, 0.1)
                cardTweenState.hpPct = targetHpPct
            end
            if colorChanged(cardTweenState.hpColor, hpCol, 0.02) then
                tweenCard("hpColor", hpBarFill, { BackgroundColor3 = hpCol }, 0.1)
                cardTweenState.hpColor = hpCol
            end
        end
        if hpLabel then
            if alive then hpLabel.Text = "HP " .. hp; hpLabel.TextColor3 = hpCol
            else hpLabel.Text = "DEAD"; hpLabel.TextColor3 = C_DEAD end
        end
        local armPct = math.clamp(arm / 200, 0, 1)
        if armBarFill and math.abs((cardTweenState.armPct or -1) - armPct) > 0.015 then
            tweenCard("armSize", armBarFill, { Size = UDim2.new(armPct, 0, 1, 0) }, 0.12)
            cardTweenState.armPct = armPct
        end
        if armLabel then armLabel.Text = arm > 0 and ("ARM " .. arm) or "" end
        if not tchar then cardTweenState.distDisplay = nil end
        if cardTweenState.distDisplay == nil then cardTweenState.distDisplay = dist
        else cardTweenState.distDisplay = cardTweenState.distDisplay + (dist - cardTweenState.distDisplay) * DIST_LERP_ALPHA end
        if distLabel then
            local shownDist = math.floor((cardTweenState.distDisplay or dist) + 0.5)
            local distText  = (tchar and myHrp) and (shownDist .. "m") or "—"
            if cardTweenState.lastDistText ~= distText then distLabel.Text = distText; cardTweenState.lastDistText = distText end
        end
        local tool       = tchar and tchar:FindFirstChildOfClass("Tool")
        local weaponText = not tchar and "—" or (tool and tool.Name or "UNARMED")
        local accent = getCardAccent(pct, alive)
        if weaponLabelRef then
            weaponLabelRef.Text = weaponText
            local now = os.clock()
            if cardTweenState.weaponText ~= weaponText then
                cardTweenState.weaponText = weaponText; cardTweenState.weaponChangedAt = now
            elseif cardTweenState.weaponChangedAt == 0 then cardTweenState.weaponChangedAt = now end
            local targetWeaponColor = tool and C_TEXT:Lerp(accent, 0.15) or C_SUBTEXT
            if tool then
                local idle = now - (cardTweenState.weaponChangedAt or now)
                local dimT = math.clamp((idle - WEAPON_DIM_AFTER) / WEAPON_DIM_SPAN, 0, WEAPON_DIM_MAX)
                targetWeaponColor = targetWeaponColor:Lerp(C_SUBTEXT, dimT)
            end
            if colorChanged(cardTweenState.weaponColor, targetWeaponColor, 0.02) then
                tweenCard("weaponColor", weaponLabelRef, { TextColor3 = targetWeaponColor }, 0.12)
                cardTweenState.weaponColor = targetWeaponColor
            end
        end
        layoutCardHeader(player.DisplayName, weaponText)
        applyCardAccent(accent)
    end)
    if not ok and type(err) == "string" and string.find(err, "lacking capability Plugin", 1, true) then
        State.CardCapabilityBlocked = true
        pcall(function() hideCard(); destroyCard() end)
    end
end

local function getToggleId()  return toggleId  end
local function bumpToggleId() toggleId = toggleId + 1 end

local function init(deps)
    Settings   = deps.Settings
    State      = deps.State
    isUnloaded = deps.isUnloaded
    screenGui  = deps.screenGui
    ESP        = deps.ESP
end

return {
    init             = init,
    showCardForTarget = showCardForTarget,
    hideCard         = hideCard,
    updateCardStats  = updateCardStats,
    destroyCard      = destroyCard,
    getToggleId      = getToggleId,
    bumpToggleId     = bumpToggleId,
}
