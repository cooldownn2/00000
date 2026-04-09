local TweenService = game:GetService("TweenService")
local Debris       = game:GetService("Debris")

local ZeehoodTracer = {}

local TRACER_COLOR      = Color3.fromRGB(255, 139, 38)
local TRACER_THICKNESS  = 0.08
local TRACER_FADE_TIME  = 0.08

local function getTracerParent()
    return workspace:FindFirstChild("Ignored") or workspace
end

local function renderSegment(startPos, endPos)
    if typeof(startPos) ~= "Vector3" or typeof(endPos) ~= "Vector3" then return end

    local delta = endPos - startPos
    local dist  = delta.Magnitude
    if dist <= 0.01 then return end

    local part = Instance.new("Part")
    part.Name = "SauceTracer"
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.CastShadow = false
    part.Material = Enum.Material.Neon
    part.Color = TRACER_COLOR
    part.Transparency = 0.15
    part.Size = Vector3.new(TRACER_THICKNESS, TRACER_THICKNESS, dist)
    part.CFrame = CFrame.lookAt(startPos, endPos) * CFrame.new(0, 0, -dist * 0.5)
    part.Parent = getTracerParent()

    TweenService:Create(part, TweenInfo.new(TRACER_FADE_TIME), {
        Transparency = 1,
    }):Play()
    Debris:AddItem(part, TRACER_FADE_TIME + 0.05)
end

function ZeehoodTracer.renderPayload(startPos, payload)
    if typeof(startPos) ~= "Vector3" or type(payload) ~= "table" then return end

    local pellets = payload.Pellets
    if type(pellets) == "table" then
        for i = 1, #pellets do
            local pellet = pellets[i]
            if type(pellet) == "table" then
                renderSegment(startPos, pellet.HitPosition)
            end
        end
        return
    end

    renderSegment(startPos, payload.HitPosition)
end

return ZeehoodTracer