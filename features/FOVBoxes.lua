local DrawingLib = rawget(_G, "Drawing") or Drawing

-- Localize frequently called globals — avoids _ENV table lookup every frame
local exp   = math.exp
local min   = math.min
local clock = os.clock
local V2    = Vector2.new
local C3    = Color3.fromRGB

local FOVBoxes = {}

local Settings, UIS
local getTriggerbotBoxForPart, getCamlockBoxForPart

-- Exponential decay speed (1/second). Frame-rate independent.
-- At speed=30: ~63% of the way in 33 ms, ~95% in ~100 ms.
local LERP_SPEED = 30
local WHITE      = C3(255, 255, 255)

local TriggerbotFOVBox = nil
local CamlockFOVBox    = nil

-- Lerp state tables. Mutated in-place each frame — zero per-frame GC allocation
-- after the first frame. Reset to nil when the feature is toggled off so the
-- next enable snaps cleanly.
local _tbState    = nil  -- { left, top, width, height }
local _cbState    = nil
local _tbLastTime = nil
local _cbLastTime = nil

-- Creates a Square Drawing object if one doesn't exist yet.
local function ensureBox(existing)
    if existing or not DrawingLib then return existing end
    local ok, box = pcall(function() return DrawingLib.new("Square") end)
    if not ok or not box then return nil end
    box.Visible      = false
    box.Filled       = false
    box.Thickness    = 1
    box.Transparency = 1
    box.Color        = WHITE
    return box
end

-- Lerps state toward target, mutating state in-place to avoid GC pressure.
-- Allocates once on first call (when state is nil), then reuses the table.
local function lerpInPlace(state, target, dt)
    if not state then
        return { left = target.left, top = target.top, width = target.width, height = target.height }
    end
    local a = 1 - exp(-LERP_SPEED * dt)
    state.left   = state.left   + (target.left   - state.left)   * a
    state.top    = state.top    + (target.top    - state.top)    * a
    state.width  = state.width  + (target.width  - state.width)  * a
    state.height = state.height + (target.height - state.height) * a
    return state
end

-- Shared update logic used by both triggerbot and camlock.
-- Returns updated state and current timestamp for the caller to store.
local function applyUpdate(drawBox, state, lastTime, rawBox, baseColor, hoverKey)
    local now = clock()
    local dt  = lastTime and min(now - lastTime, 0.1) or (1 / 60)
    local s   = lerpInPlace(state, rawBox, dt)

    drawBox.Size     = V2(s.width, s.height)
    drawBox.Position = V2(s.left,  s.top)

    if UIS and Settings[hoverKey] == true then
        local mp    = UIS:GetMouseLocation()
        local isHov = mp.X >= s.left and mp.X <= (s.left + s.width)
                   and mp.Y >= s.top  and mp.Y <= (s.top  + s.height)
        drawBox.Color = isHov and (Settings.SelectionColor or baseColor) or baseColor
    else
        drawBox.Color = baseColor
    end
    drawBox.Visible = true
    return s, now
end

local function hideTriggerbotFOVBox()
    _tbState    = nil
    _tbLastTime = nil
    if TriggerbotFOVBox then TriggerbotFOVBox.Visible = false end
end

local function hideCamlockFOVBox()
    _cbState    = nil
    _cbLastTime = nil
    if CamlockFOVBox then CamlockFOVBox.Visible = false end
end

local function updateTriggerbotFOVBox(part, precomputedBox)
    if not Settings.TriggerbotFOVVisualizeEnabled then
        hideTriggerbotFOVBox()
        return
    end
    TriggerbotFOVBox = ensureBox(TriggerbotFOVBox)
    if not TriggerbotFOVBox then return end

    local rawBox = precomputedBox or (part and getTriggerbotBoxForPart(part))
    if not rawBox then
        hideTriggerbotFOVBox()
        return
    end

    local color = Settings.TriggerbotFOVVisualizeColor or WHITE
    _tbState, _tbLastTime = applyUpdate(TriggerbotFOVBox, _tbState, _tbLastTime, rawBox, color, "TriggerbotFOVVisualizeHover")
end

local function updateCamlockFOVBox(part, precomputedBox)
    if not Settings.CamlockFOVVisualizeEnabled then
        hideCamlockFOVBox()
        return
    end
    CamlockFOVBox = ensureBox(CamlockFOVBox)
    if not CamlockFOVBox then return end

    local rawBox = precomputedBox or (part and getCamlockBoxForPart(part))
    if not rawBox then
        hideCamlockFOVBox()
        return
    end

    local color = Settings.CamlockFOVVisualizeColor or WHITE
    _cbState, _cbLastTime = applyUpdate(CamlockFOVBox, _cbState, _cbLastTime, rawBox, color, "CamlockFOVVisualizeHover")
end

local function cleanupFOVBox()
    _tbState    = nil
    _cbState    = nil
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