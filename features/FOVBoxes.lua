local DrawingLib = rawget(_G, "Drawing") or Drawing

local FOVBoxes = {}

local Settings, UIS
local getTriggerbotBoxForPart, getCamlockBoxForPart

local TriggerbotFOVBox = nil
local CamlockFOVBox    = nil

-- Lerp state: persists between frames so the box moves smoothly.
-- Set to nil when the feature is toggled off so the next enable snaps cleanly.
local _tbPrev = nil
local _cbPrev = nil

-- Blend factor per RenderStepped frame (assumed ~60 fps).
-- 0.5 → ~97 % of the way to the target position within 5 frames (~83 ms).
local LERP_ALPHA = 0.5

local function lerpBox(prev, target)
    if not prev then return target end
    local a = LERP_ALPHA
    return {
        left    = prev.left    + (target.left    - prev.left)    * a,
        top     = prev.top     + (target.top     - prev.top)     * a,
        width   = prev.width   + (target.width   - prev.width)   * a,
        height  = prev.height  + (target.height  - prev.height)  * a,
        centerX = prev.centerX + (target.centerX - prev.centerX) * a,
        centerY = prev.centerY + (target.centerY - prev.centerY) * a,
    }
end

-- When no target is in range, keep the box at screen-centre using the
-- last known pixel dimensions so the activation zone is always visible.
local function makeScreenCenterBox(refBox)
    if not refBox then return nil end
    local cam = workspace.CurrentCamera
    if not cam then return nil end
    local vp = cam.ViewportSize
    local cx = vp.X * 0.5
    local cy = vp.Y * 0.5
    local hw = refBox.width  * 0.5
    local hh = refBox.height * 0.5
    return {
        left    = cx - hw,
        top     = cy - hh,
        width   = refBox.width,
        height  = refBox.height,
        centerX = cx,
        centerY = cy,
    }
end

local function hideTriggerbotFOVBox()
    if TriggerbotFOVBox then TriggerbotFOVBox.Visible = false end
end

local function ensureTriggerbotFOVBox()
    if TriggerbotFOVBox or not DrawingLib then return end
    local ok, box = pcall(function() return DrawingLib.new("Square") end)
    if not ok or not box then return end
    box.Visible      = false
    box.Filled       = false
    box.Thickness    = 1
    box.Transparency = 1
    box.Color        = Color3.fromRGB(255, 255, 255)
    TriggerbotFOVBox = box
end

local function updateTriggerbotFOVBox(part, precomputedBox)
    if not Settings.TriggerbotFOVVisualizeEnabled then
        _tbPrev = nil
        hideTriggerbotFOVBox()
        return
    end
    ensureTriggerbotFOVBox()
    if not TriggerbotFOVBox then return end

    local rawBox = precomputedBox or (part and getTriggerbotBoxForPart(part))
    if not rawBox then
        -- No target in range: keep the box visible at screen-centre.
        rawBox = makeScreenCenterBox(_tbPrev)
    end
    if not rawBox then
        hideTriggerbotFOVBox()
        return
    end

    local smoothed = lerpBox(_tbPrev, rawBox)
    _tbPrev = smoothed

    TriggerbotFOVBox.Size     = Vector2.new(smoothed.width, smoothed.height)
    TriggerbotFOVBox.Position = Vector2.new(smoothed.left,  smoothed.top)

    local baseColor    = Settings.TriggerbotFOVVisualizeColor or Color3.fromRGB(255, 255, 255)
    local hoverEnabled = Settings.TriggerbotFOVVisualizeHover == true
    if hoverEnabled then
        local mp    = UIS:GetMouseLocation()
        local isHov = mp.X >= smoothed.left and mp.X <= (smoothed.left + smoothed.width)
                   and mp.Y >= smoothed.top  and mp.Y <= (smoothed.top  + smoothed.height)
        TriggerbotFOVBox.Color = isHov and (Settings.SelectionColor or baseColor) or baseColor
    else
        TriggerbotFOVBox.Color = baseColor
    end
    TriggerbotFOVBox.Visible = true
end

local function hideCamlockFOVBox()
    if CamlockFOVBox then CamlockFOVBox.Visible = false end
end

local function ensureCamlockFOVBox()
    if CamlockFOVBox or not DrawingLib then return end
    local ok, box = pcall(function() return DrawingLib.new("Square") end)
    if not ok or not box then return end
    box.Visible      = false
    box.Filled       = false
    box.Thickness    = 1
    box.Transparency = 1
    box.Color        = Color3.fromRGB(255, 255, 255)
    CamlockFOVBox = box
end

local function updateCamlockFOVBox(part, precomputedBox)
    if not Settings.CamlockFOVVisualizeEnabled then
        _cbPrev = nil
        hideCamlockFOVBox()
        return
    end
    ensureCamlockFOVBox()
    if not CamlockFOVBox then return end

    local rawBox = precomputedBox or (part and getCamlockBoxForPart(part))
    if not rawBox then
        rawBox = makeScreenCenterBox(_cbPrev)
    end
    if not rawBox then
        hideCamlockFOVBox()
        return
    end

    local smoothed = lerpBox(_cbPrev, rawBox)
    _cbPrev = smoothed

    CamlockFOVBox.Size     = Vector2.new(smoothed.width, smoothed.height)
    CamlockFOVBox.Position = Vector2.new(smoothed.left,  smoothed.top)

    local baseColor    = Settings.CamlockFOVVisualizeColor or Color3.fromRGB(255, 255, 255)
    local hoverEnabled = Settings.CamlockFOVVisualizeHover == true
    if hoverEnabled then
        local mp    = UIS:GetMouseLocation()
        local isHov = mp.X >= smoothed.left and mp.X <= (smoothed.left + smoothed.width)
                   and mp.Y >= smoothed.top  and mp.Y <= (smoothed.top  + smoothed.height)
        CamlockFOVBox.Color = isHov and (Settings.SelectionColor or baseColor) or baseColor
    else
        CamlockFOVBox.Color = baseColor
    end
    CamlockFOVBox.Visible = true
end

local function cleanupFOVBox()
    _tbPrev = nil
    _cbPrev = nil
    if TriggerbotFOVBox then
        pcall(function()
            TriggerbotFOVBox.Visible = false
            TriggerbotFOVBox:Remove()
        end)
        TriggerbotFOVBox = nil
    end
    if CamlockFOVBox then
        pcall(function()
            CamlockFOVBox.Visible = false
            CamlockFOVBox:Remove()
        end)
        CamlockFOVBox = nil
    end
end

local function init(deps)
    Settings                = deps.Settings
    UIS                     = deps.UIS
    getTriggerbotBoxForPart = deps.getTriggerbotBoxForPart
    getCamlockBoxForPart    = deps.getCamlockBoxForPart
end

FOVBoxes.init                   = init
FOVBoxes.updateTriggerbotFOVBox = updateTriggerbotFOVBox
FOVBoxes.updateCamlockFOVBox    = updateCamlockFOVBox
FOVBoxes.hideTriggerbotFOVBox   = hideTriggerbotFOVBox
FOVBoxes.hideCamlockFOVBox      = hideCamlockFOVBox
FOVBoxes.cleanupFOVBox          = cleanupFOVBox

return FOVBoxes