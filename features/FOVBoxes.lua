local function resolveDrawingLib()
    local env = _G
    local getgenvFn = rawget(_G, "getgenv")
    if type(getgenvFn) == "function" then
        local ok, g = pcall(getgenvFn)
        if ok and type(g) == "table" then
            env = g
        end
    end
    return rawget(env, "Drawing") or rawget(_G, "Drawing")
end

local DrawingLib = resolveDrawingLib()

local FOVBoxes = {}

local Settings

local DEFAULT_WHITE = Color3.fromRGB(255, 255, 255)

-- ── Slot ─────────────────────────────────────────────────────────────────────
local function newSlot()
    return { obj = nil, lx = -1e9, ly = -1e9, lw = -1, lh = -1, lc = false }
end

local TB = newSlot()  -- Triggerbot
local CL = newSlot()  -- Camlock
local SA = newSlot()  -- Silent Aim

local function ensureObj(slot)
    if slot.obj then return end
    if not DrawingLib then DrawingLib = resolveDrawingLib() end
    if not DrawingLib or type(DrawingLib.new) ~= "function" then return end
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

-- Reads a {Left, Right} or single-number config value.
local function readPad(cfg, fallback, firstKey, secondKey)
    if type(cfg) == "table" then
        local a = tonumber(cfg[firstKey]) or tonumber(cfg[1]) or fallback
        local b = tonumber(cfg[secondKey]) or tonumber(cfg[2]) or fallback
        return a, b
    end
    local v = tonumber(cfg) or fallback
    return v, v
end

-- Draws a fixed-pixel FOV box centred on the target's screen position.
-- The box does NOT scale with distance — it is always the configured pixel size.
local function updateSlot(slot, enabledKey, wKey, hKey, colorKey, targetPart)
    if not Settings[enabledKey] then hideSlot(slot); return end
    if not targetPart then hideSlot(slot); return end
    local cam = workspace.CurrentCamera
    if not cam then hideSlot(slot); return end

    local sp, onScreen = cam:WorldToViewportPoint(targetPart.Position)
    if not onScreen or sp.Z <= 0 then hideSlot(slot); return end

    ensureObj(slot)
    local obj = slot.obj
    if not obj then return end

    local padL, padR = readPad(Settings[wKey], 10, "Left", "Right")
    local padU, padD = readPad(Settings[hKey], 10, "Up", "Down")
    local totalW = padL + padR
    local totalH = padU + padD
    local lx = sp.X - padL
    local ly = sp.Y - padU

    if totalW ~= slot.lw or totalH ~= slot.lh then
        obj.Size = Vector2.new(totalW, totalH)
        slot.lw, slot.lh = totalW, totalH
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

local function updateTriggerbotFOVBox(targetPart)
    updateSlot(TB,
        "TriggerbotFOVVisualizeEnabled",
        "TriggerbotFOVWidth", "TriggerbotFOVHeight",
        "TriggerbotFOVVisualizeColor", targetPart)
end

local function updateCamlockFOVBox(targetPart)
    updateSlot(CL,
        "CamlockFOVVisualizeEnabled",
        "CamlockFOVWidth", "CamlockFOVHeight",
        "CamlockFOVVisualizeColor", targetPart)
end

local function updateSilentAimFOVBox(targetPart)
    updateSlot(SA,
        "SilentAimFOVVisualizeEnabled",
        "SilentAimFOVWidth", "SilentAimFOVHeight",
        "SilentAimFOVVisualizeColor", targetPart)
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