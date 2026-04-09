local DrawingLib = rawget(_G, "Drawing") or Drawing

local FOVBoxes = {}

local Settings, UIS
local getTriggerbotBoxForPart, getCamlockBoxForPart

local TriggerbotFOVBox = nil
local CamlockFOVBox    = nil

-- Lerp state: persists between frames so the box moves smoothly.
-- Set to nil when the feature is toggled off so the next enable snaps cleanly.
local _tbPrev     = nil
local _cbPrev     = nil
local _tbLastTime = nil
local _cbLastTime = nil

-- Exponential decay speed (1/second). Frame-rate independent — compensates
-- automatically for 30 fps, 60 fps, 144 fps, etc.
-- At speed=30: ~63 % of the way in 33 ms, ~95 % in ~100 ms.
local LERP_SPEED = 30

local function lerpBox(prev, target, dt)
    if not prev then return target end
    local a = 1 - math.exp(-LERP_SPEED * dt)
    return {
        left   = prev.left   + (target.left   - prev.left)   * a,
        top    = prev.top    + (target.top    - prev.top)    * a,
        width  = prev.width  + (target.width  - prev.width)  * a,
        height = prev.height + (target.height - prev.height) * a,
    }
end

local function hideTriggerbotFOVBox()
    _tbPrev     = nil
    _tbLastTime = nil
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
        _tbPrev = nil
        hideTriggerbotFOVBox()
        return
    end

    local now = os.clock()
    local dt  = _tbLastTime and math.min(now - _tbLastTime, 0.1) or (1 / 60)
    _tbLastTime = now
    local smoothed = lerpBox(_tbPrev, rawBox, dt)
    _tbPrev = smoothed

    TriggerbotFOVBox.Size     = Vector2.new(smoothed.width, smoothed.height)
    TriggerbotFOVBox.Position = Vector2.new(smoothed.left,  smoothed.top)

    local baseColor    = Settings.TriggerbotFOVVisualizeColor or Color3.fromRGB(255, 255, 255)
    local hoverEnabled = Settings.TriggerbotFOVVisualizeHover == true
    if UIS and hoverEnabled then
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
    _cbPrev     = nil
    _cbLastTime = nil
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
        _cbPrev = nil
        hideCamlockFOVBox()
        return
    end

    local now = os.clock()
    local dt  = _cbLastTime and math.min(now - _cbLastTime, 0.1) or (1 / 60)
    _cbLastTime = now
    local smoothed = lerpBox(_cbPrev, rawBox, dt)
    _cbPrev = smoothed

    CamlockFOVBox.Size     = Vector2.new(smoothed.width, smoothed.height)
    CamlockFOVBox.Position = Vector2.new(smoothed.left,  smoothed.top)

    local baseColor    = Settings.CamlockFOVVisualizeColor or Color3.fromRGB(255, 255, 255)
    local hoverEnabled = Settings.CamlockFOVVisualizeHover == true
    if UIS and hoverEnabled then
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
    _tbPrev     = nil
    _cbPrev     = nil
    _tbLastTime = nil
    _cbLastTime = nil
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