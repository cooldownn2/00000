local TargetLine = {}

local Settings
local line
local drawingApi = rawget(_G, "Drawing")

local function ensureLine()
    if line or type(drawingApi) ~= "table" then return end
    line = drawingApi.new("Line")
    line.Visible      = false
    line.Color        = Settings.LineColor or Color3.fromRGB(0, 255, 255)
    line.Thickness    = 1
    line.Transparency = 1
end

local function hide()
    if line then
        pcall(function() line.Visible = false end)
    end
end

local function update(camera, anchorPart, canUseAimPart, mousePos)
    ensureLine()
    if not line then return end
    if not camera or not anchorPart then
        hide()
        return
    end

    local screenPos, onScreen = camera:WorldToViewportPoint(anchorPart.Position)
    if not onScreen or screenPos.Z <= 0 then
        hide()
        return
    end

    if Settings.VisCheck then
        line.Color = canUseAimPart and Settings.LineColorVisible or Settings.LineColorBlocked
    else
        line.Color = Settings.LineColor or Color3.fromRGB(0, 255, 255)
    end

    line.Visible = Settings.LineEnabled ~= false
    line.From    = Vector2.new(mousePos.X, mousePos.Y)
    line.To      = Vector2.new(screenPos.X, screenPos.Y)
end

local function cleanup()
    if line then
        pcall(function()
            line.Visible = false
            line:Remove()
        end)
        line = nil
    end
end

local function init(deps)
    Settings = deps.Settings
    ensureLine()
end

TargetLine.init = init
TargetLine.hide = hide
TargetLine.update = update
TargetLine.cleanup = cleanup

return TargetLine
