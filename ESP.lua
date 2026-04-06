local Players   = game:GetService("Players")
local LP        = Players.LocalPlayer

local ESPNameColor  = Color3.fromRGB(255, 255, 255)
local FEET_OFFSET   = Vector3.new(0, 3, 0)
local UPDATE_RATE   = 1 / 70
local ESP_FONT      = Enum.Font.GothamBold

local Camera, Settings, State, isUnloaded, screenGui

local espObjects      = {}
local espPlayerConns  = {}
local espCharCache    = {}
local espLastUpdate   = 0
local espShownLastFrame = false

local cachedNameSize   = 15
local cachedLockedTarget = nil

local function newEspLabel()
    local lbl = Instance.new("TextLabel")
    lbl.Name                   = "ESP_Name"
    lbl.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Size                   = UDim2.fromOffset(200, 30)
    lbl.AnchorPoint            = Vector2.new(0.5, 0.5)
    lbl.Font                   = ESP_FONT
    lbl.TextSize               = cachedNameSize
    lbl.TextColor3             = ESPNameColor
    lbl.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
    lbl.TextStrokeTransparency = 0
    lbl.TextXAlignment         = Enum.TextXAlignment.Center
    lbl.TextYAlignment         = Enum.TextYAlignment.Center
    lbl.ZIndex                 = 5
    lbl.Visible                = false
    lbl.Parent                 = screenGui
    return lbl
end

local function getEspCharData(player)
    local char = player and player.Character
    if not char then espCharCache[player] = nil; return nil end
    local entry = espCharCache[player]
    if not entry or entry.char ~= char then
        entry = { char = char, hum = nil, root = nil }
        espCharCache[player] = entry
    end
    if not entry.hum  or entry.hum.Parent  ~= char then entry.hum  = char:FindFirstChildOfClass("Humanoid") end
    if not entry.root or entry.root.Parent ~= char then entry.root = char:FindFirstChild("HumanoidRootPart") end
    return entry
end

local function getEspStatsFromCache(entry)
    if not entry or not entry.hum then return 0, 100, 0 end
    local hum = entry.hum
    local hp = math.floor(hum.Health)
    local maxHp = math.floor(hum.MaxHealth)
    local arm = 0
    local be = entry.char and entry.char:FindFirstChild("BodyEffects")
    if be then
        for _, child in ipairs(be:GetChildren()) do
            if child:IsA("ValueBase") then
                local ln = string.lower(child.Name)
                if ln == "armor" or ln == "arm" or ln == "shield" or ln == "armour" then
                    local ok, v = pcall(function() return child.Value end)
                    if ok and type(v) == "number" then arm = math.floor(v) break end
                end
            end
        end
    end
    return hp, maxHp, arm
end

local function removePlayerEsp(player)
    if espPlayerConns[player] then
        pcall(function() espPlayerConns[player]:Disconnect() end)
        espPlayerConns[player] = nil
    end
    if espObjects[player] then
        pcall(function() espObjects[player].label:Destroy() end)
        espObjects[player] = nil
    end
    espCharCache[player] = nil
end

local function createPlayerEsp(player)
    removePlayerEsp(player)
    if Settings.ESPAllowed == false or not State.ESPEnabled then return end
    espObjects[player] = {
        label = newEspLabel(),
        meta = {
            visible = false,
            x = nil,
            y = nil,
            name = nil,
            size = nil,
            color = nil,
        }
    }
end

local function watchEspPlayer(player)
    if espPlayerConns[player] then
        pcall(function() espPlayerConns[player]:Disconnect() end)
        espPlayerConns[player] = nil
    end
    espPlayerConns[player] = player.CharacterAdded:Connect(function(char)
        if Settings.ESPAllowed == false or not State.ESPEnabled then return end
        espCharCache[player] = nil
        char:WaitForChild("HumanoidRootPart", 5)
        createPlayerEsp(player)
    end)
end

local function hideAllEsp()
    for _, rec in pairs(espObjects) do
        if rec.meta.visible then
            rec.label.Visible = false
            rec.meta.visible = false
        end
    end
    espShownLastFrame = false
end

local function updateEsp()
    if isUnloaded() then return end
    Camera = workspace.CurrentCamera
    if Settings.ESPAllowed == false then
        if State.ESPEnabled then State.ESPEnabled = false; hideAllEsp() end
        return
    end
    local now = os.clock()
    local updateRate = tonumber(Settings.ESPUpdateRate) or UPDATE_RATE
    if (now - espLastUpdate) < updateRate then return end
    espLastUpdate = now
    if not State.ESPEnabled then
        if espShownLastFrame then hideAllEsp() end
        return
    end
    if next(espObjects) == nil then espShownLastFrame = false; return end

    cachedNameSize    = tonumber(Settings.ESPNameSize) or 15
    cachedLockedTarget = State.LockedTarget

    local drewAny = false
    for player, rec in pairs(espObjects) do
        local lbl = rec.label
        local meta = rec.meta
        local data    = getEspCharData(player)
        local hum     = data and data.hum
        local root    = data and data.root
        local canDraw = root and hum and hum.Health > 0
        if canDraw then
            local screenPos, onScreen = Camera:WorldToViewportPoint(root.Position - FEET_OFFSET)
            if onScreen and screenPos.Z > 0 then
                local color = (cachedLockedTarget == player) and Settings.SelectionColor or ESPNameColor
                local sx = math.floor(screenPos.X)
                local sy = math.floor(screenPos.Y)
                local name = player.DisplayName
                if meta.color ~= color then
                    lbl.TextColor3 = color
                    meta.color = color
                end
                if meta.name ~= name then
                    lbl.Text = name
                    meta.name = name
                end
                if meta.size ~= cachedNameSize then
                    lbl.TextSize = cachedNameSize
                    meta.size = cachedNameSize
                end
                if meta.x ~= sx or meta.y ~= sy then
                    lbl.Position = UDim2.fromOffset(sx, sy)
                    meta.x, meta.y = sx, sy
                end
                if not meta.visible then
                    lbl.Visible = true
                    meta.visible = true
                end
                drewAny = true
            else
                if meta.visible then
                    lbl.Visible = false
                    meta.visible = false
                end
            end
        else
            if meta.visible then
                lbl.Visible = false
                meta.visible = false
            end
        end
    end
    espShownLastFrame = drewAny
end

local function cleanupEsp()
    for player in pairs(espObjects) do removePlayerEsp(player) end
    espObjects    = {}
    for player, conn in pairs(espPlayerConns) do
        pcall(function() conn:Disconnect() end)
        espPlayerConns[player] = nil
    end
    espCharCache      = {}
    cachedLockedTarget = nil
    espLastUpdate     = 0
    espShownLastFrame = false
end

local function init(deps)
    Camera     = deps.Camera
    Settings   = deps.Settings
    State      = deps.State
    isUnloaded = deps.isUnloaded
    screenGui  = deps.screenGui
end

return {
    init            = init,
    updateEsp       = updateEsp,
    cleanupEsp      = cleanupEsp,
    createPlayerEsp = createPlayerEsp,
    watchEspPlayer  = watchEspPlayer,
    removePlayerEsp = removePlayerEsp,
    hideAllEsp      = hideAllEsp,
    getEspCharData  = getEspCharData,
    getEspStatsFromCache = getEspStatsFromCache,
}
