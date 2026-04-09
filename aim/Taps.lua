local Settings

local function getTapCount(args)
    local taps = Settings.Taps
    if type(taps) ~= "table" then return 1 end
    -- Zeehood style: args[2] is the payload table with a ToolName key.
    -- Dashood style: args[2] is the Handle instance whose Parent is the Tool.
    local toolName
    if type(args[2]) == "table" then
        toolName = args[2].ToolName
    else
        local handle = args[2]
        if not handle or not handle.Parent then return 1 end
        toolName = handle.Parent.Name
    end
    if not toolName then return 1 end
    local entry = taps[toolName]
    if type(entry) ~= "table" then return 1 end
    if not entry["Enabled"] then return 1 end
    local value = tonumber(entry["Value"])
    if not value or value < 2 then return 1 end
    return math.floor(value)
end

local function init(deps)
    Settings = deps.Settings
end

return {
    init         = init,
    getTapCount  = getTapCount,
}
