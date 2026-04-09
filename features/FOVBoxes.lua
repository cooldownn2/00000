local DrawingLib = rawget(_G, "Drawing") or Drawing

local FOVBoxes = {}

local Settings, UIS
local getTriggerbotBoxForPart, getCamlockBoxForPart

local TriggerbotFOVBox = nil
local CamlockFOVBox = nil

local function hideTriggerbotFOVBox()
    if TriggerbotFOVBox then TriggerbotFOVBox.Visible = false end
end

local function ensureTriggerbotFOVBox()
    if TriggerbotFOVBox or not DrawingLib then return end
    local ok, box = pcall(function() return DrawingLib.new("Square") end)
    if not ok or not box then return end
    box.Visible = false
    box.Filled = false
    box.Thickness = 1
    box.Transparency = 1
    box.Color = Color3.fromRGB(255, 255, 255)
    TriggerbotFOVBox = box
end

local function updateTriggerbotFOVBox(part, precomputedBox)
    if not Settings.TriggerbotFOVVisualizeEnabled then hideTriggerbotFOVBox(); return end
    ensureTriggerbotFOVBox()
    if not TriggerbotFOVBox then return end
    if not part then hideTriggerbotFOVBox(); return end

    local box = precomputedBox or getTriggerbotBoxForPart(part)
    if not box then hideTriggerbotFOVBox(); return end

    TriggerbotFOVBox.Size = Vector2.new(box.width, box.height)
    TriggerbotFOVBox.Position = Vector2.new(box.left, box.top)

    local baseColor = Settings.TriggerbotFOVVisualizeColor or Color3.fromRGB(255, 255, 255)
    local hoverEnabled = Settings.TriggerbotFOVVisualizeHover ~= false
    local mousePos = UIS:GetMouseLocation()
    local isHovering = mousePos.X >= box.left and mousePos.X <= (box.left + box.width)
        and mousePos.Y >= box.top and mousePos.Y <= (box.top + box.height)

    TriggerbotFOVBox.Color = (isHovering and hoverEnabled) and (Settings.SelectionColor or baseColor) or baseColor
    TriggerbotFOVBox.Visible = true
end

local function hideCamlockFOVBox()
    if CamlockFOVBox then CamlockFOVBox.Visible = false end
end

local function ensureCamlockFOVBox()
    if CamlockFOVBox or not DrawingLib then return end
    local ok, box = pcall(function() return DrawingLib.new("Square") end)
    if not ok or not box then return end
    box.Visible = false
    box.Filled = false
    box.Thickness = 1
    box.Transparency = 1
    box.Color = Color3.fromRGB(255, 255, 255)
    CamlockFOVBox = box
end

local function updateCamlockFOVBox(part, precomputedBox)
    if not Settings.CamlockFOVVisualizeEnabled then hideCamlockFOVBox(); return end
    ensureCamlockFOVBox()
    if not CamlockFOVBox then return end
    if not part then hideCamlockFOVBox(); return end

    local box = precomputedBox or getCamlockBoxForPart(part)
    if not box then hideCamlockFOVBox(); return end

    CamlockFOVBox.Size = Vector2.new(box.width, box.height)
    CamlockFOVBox.Position = Vector2.new(box.left, box.top)

    local baseColor = Settings.CamlockFOVVisualizeColor or Color3.fromRGB(255, 255, 255)
    local hoverEnabled = Settings.CamlockFOVVisualizeHover == true
    local mousePos = UIS:GetMouseLocation()
    local isHovering = mousePos.X >= box.left and mousePos.X <= (box.left + box.width)
        and mousePos.Y >= box.top and mousePos.Y <= (box.top + box.height)

    CamlockFOVBox.Color = (isHovering and hoverEnabled) and (Settings.SelectionColor or baseColor) or baseColor
    CamlockFOVBox.Visible = true
end

local function cleanupFOVBox()
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
    Settings = deps.Settings
    UIS = deps.UIS
    getTriggerbotBoxForPart = deps.getTriggerbotBoxForPart
    getCamlockBoxForPart = deps.getCamlockBoxForPart
end

FOVBoxes.init = init
FOVBoxes.updateTriggerbotFOVBox = updateTriggerbotFOVBox
FOVBoxes.updateCamlockFOVBox = updateCamlockFOVBox
FOVBoxes.hideTriggerbotFOVBox = hideTriggerbotFOVBox
FOVBoxes.hideCamlockFOVBox = hideCamlockFOVBox
FOVBoxes.cleanupFOVBox = cleanupFOVBox

return FOVBoxes