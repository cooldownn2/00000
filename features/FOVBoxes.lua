local DrawingLib = rawget(_G, "Drawing")

local FOVBoxes = {}

local Settings, Camera, UIS

-- Module-level constant — avoids allocating a new Color3 every frame.
local DEFAULT_WHITE = Color3.fromRGB(255, 255, 255)

-- ── Slot ─────────────────────────────────────────────────────────────────────
-- One slot per feature. Caches the last written property values so we skip
-- redundant engine property writes on frames where nothing changed.
local function newSlot()
    return { obj = nil, lx = -1e9, ly = -1e9, lw = -1, lh = -1, lc = false }
end

local TB = newSlot()  -- Triggerbot
local CL = newSlot()  -- Camlock
local SA = newSlot()  -- Silent Aim

local function ensureObj(slot)
    if slot.obj or not DrawingLib then return end
    local ok, b = pcall(DrawingLib.new, "Square")
    if not ok or not b then return end
    b.Visible      = false
    b.Filled       = false
    b.Thickness    = 1
    b.Transparency = 1
    b.Color        = DEFAULT_WHITE
    slot.obj = b
end

local function hideSlot(slot)
    local b = slot.obj
    if b and b.Visible then b.Visible = false end
end

-- Draws a fixed-pixel FOV box centered at the current mouse position.
-- The box size DOES NOT scale with target distance — it is always the
-- configured pixel size. All three feature slots share this one body.
local function updateSlot(slot, enabledKey, wKey, hKey, colorKey)
    if not Settings[enabledKey] then hideSlot(slot); return end
    if not Camera or not UIS then hideSlot(slot); return end
    ensureObj(slot)
    local obj = slot.obj
    if not obj then return end

    local w  = tonumber(Settings[wKey]) or 200
    local h  = tonumber(Settings[hKey]) or 200
    local mp = UIS:GetMouseLocation()
    local lx = mp.X - w * 0.5
    local ly = mp.Y - h * 0.5

    -- Gate property writes: only assign when the value has actually changed.
    if w ~= slot.lw or h ~= slot.lh then
        obj.Size     = Vector2.new(w, h)
        slot.lw, slot.lh = w, h
    end
    if lx ~= slot.lx or ly ~= slot.ly then
        obj.Position = Vector2.new(lx, ly)
        slot.lx, slot.ly = lx, ly
    end

    local c = Settings[colorKey] or DEFAULT_WHITE
    if c ~= slot.lc then
        obj.Color = c
        slot.lc   = c
    end

    obj.Visible = true
end

-- ── Public API ────────────────────────────────────────────────────────────────

local function updateTriggerbotFOVBox()
    updateSlot(TB,
        "TriggerbotFOVVisualizeEnabled",
        "TriggerbotFOVWidth", "TriggerbotFOVHeight",
        "TriggerbotFOVVisualizeColor")
end

local function updateCamlockFOVBox()
    updateSlot(CL,
        "CamlockFOVVisualizeEnabled",
        "CamlockFOVWidth", "CamlockFOVHeight",
        "CamlockFOVVisualizeColor")
end

local function updateSilentAimFOVBox()
    updateSlot(SA,
        "SilentAimFOVVisualizeEnabled",
        "SilentAimFOVWidth", "SilentAimFOVHeight",
        "SilentAimFOVVisualizeColor")
end

local function hideTriggerbotFOVBox() hideSlot(TB) end
local function hideCamlockFOVBox()    hideSlot(CL) end
local function hideSilentAimFOVBox()  hideSlot(SA) end

local function cleanupFOVBox()
    for _, slot in ipairs({ TB, CL, SA }) do
        if slot.obj then
            pcall(function()
                slot.obj.Visible = false
                slot.obj:Remove()
            end)
            slot.obj = nil
        end
    end
end

local function init(deps)
    Settings = deps.Settings
    Camera   = deps.Camera
    UIS      = deps.UIS
end

FOVBoxes.init                   = init
FOVBoxes.updateTriggerbotFOVBox = updateTriggerbotFOVBox
FOVBoxes.updateCamlockFOVBox    = updateCamlockFOVBox
FOVBoxes.updateSilentAimFOVBox  = updateSilentAimFOVBox
FOVBoxes.hideTriggerbotFOVBox   = hideTriggerbotFOVBox
FOVBoxes.hideCamlockFOVBox      = hideCamlockFOVBox
FOVBoxes.hideSilentAimFOVBox    = hideSilentAimFOVBox
FOVBoxes.cleanupFOVBox          = cleanupFOVBox

return FOVBoxes