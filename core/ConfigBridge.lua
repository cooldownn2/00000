local ConfigBridge = {}

local function applyUserConfig(settings, userConfig)
    if type(settings) ~= "table" or type(userConfig) ~= "table" then return end

    local function resolve(root, path)
        local cur = root
        for i = 1, #path do
            if type(cur) ~= "table" then return nil end
            cur = cur[path[i]]
        end
        return cur
    end

    local function apply(value, path)
        if value == nil then return end
        local cur = settings
        for i = 1, #path - 1 do
            if type(cur[path[i]]) ~= "table" then cur[path[i]] = {} end
            cur = cur[path[i]]
        end
        cur[path[#path]] = value
    end

    local configMap = {
        -- Silent Aim
        { {"Silent Aim","Enabled"},                        {"Main","Enabled"} },
        { {"Silent Aim","Target Part"},                    {"Main","Target Part"} },
        { {"Silent Aim","Scale"},                          {"Main","Closest Point Scale"} },
        { {"Silent Aim","Selection"},                      {"Main","Selection System"} },
        { {"Silent Aim","Selection Color"},                {"Main","Selection Color"} },
        { {"Main","Keybinds","Target"},                  {"Main","Keybinds","Target"} },
        { {"Silent Aim","Checks","Visible"},             {"Main","Checks","Target","Visible Check"} },
        { {"Silent Aim","Checks","Persist Lock On Death"}, {"Main","Checks","Target","Persist Lock On Death"} },
        { {"Silent Aim","Checks","Death Check"},         {"Main","Checks","Target","Death Check"} },

        -- Camlock
        { {"Camlock","Enabled"},                             {"Camlock","Enabled"} },
        { {"Camlock","Distance"},                            {"Camlock","Distance"} },
        { {"Camlock","Smoothness"},                          {"Camlock","Smoothness"} },
        { {"Camlock","Click Type"},                          {"Camlock","Click Type"} },
        { {"Camlock","Easing Style"},                        {"Camlock","Easing Style"} },
        { {"Camlock","Easing Direction"},                    {"Camlock","Easing Direction"} },
        { {"Camlock","FOV","Type"},                        {"Camlock","FOV","Type"} },
        { {"Camlock","FOV","Width"},                       {"Camlock","Width"} },
        { {"Camlock","Height"},                              {"Camlock","Height"} },
        { {"Camlock","FOV","Height"},                      {"Camlock","Height"} },
        { {"Camlock","Visualize","Enabled"},               {"Camlock","Visualize","Enabled"} },
        { {"Camlock","Visualize","Color"},                 {"Camlock","Visualize","Color"} },
        { {"Camlock","Visualize","Change Color On Hover"}, {"Camlock","Visualize","Change Color On Hover"} },
        { {"Camlock","Visualize","Hover Color"},           {"Camlock","Visualize","Change Color On Hover"} },
        { {"Camlock","FOV","Visualize","Enabled"},       {"Camlock","Visualize","Enabled"} },
        { {"Camlock","FOV","Visualize","Color"},         {"Camlock","Visualize","Color"} },
        { {"Camlock","FOV","Visualize","Hover Color"},   {"Camlock","Visualize","Change Color On Hover"} },
        { {"Camlock","FOV","Visualize","Change Color On Hover"}, {"Camlock","Visualize","Change Color On Hover"} },
        { {"Camlock","Keybind"},                             {"Main","Keybinds","Camlock"} },
        { {"Main","Keybinds","Camlock"},                   {"Main","Keybinds","Camlock"} },

        -- Triggerbot
        { {"Triggerbot","Enabled"},                          {"Triggerbot","Enabled"} },
        { {"Triggerbot","Visible"},                          {"Triggerbot","VisCheck"} },
        { {"Triggerbot","Distance"},                         {"Triggerbot","Distance"} },
        { {"Triggerbot","Delay"},                            {"Triggerbot","Delay"} },
        { {"Triggerbot","Click Type"},                       {"Triggerbot","Click Type"} },
        { {"Triggerbot","FOV","Type"},                     {"Triggerbot","FOV","Type"} },
        { {"Triggerbot","FOV","Width"},                    {"Main","FOV","Triggerbot","Width"} },
        { {"Triggerbot","FOV","Height"},                   {"Main","FOV","Triggerbot","Height"} },
        { {"Triggerbot","FOV","Visualize","Enabled"},    {"Main","FOV","Triggerbot","Visualize","Enabled"} },
        { {"Triggerbot","FOV","Visualize","Color"},      {"Main","FOV","Triggerbot","Visualize","Color"} },
        { {"Triggerbot","FOV","Visualize","Hover Color"},{"Main","FOV","Triggerbot","Visualize","Change Color On Hover"} },
        { {"Main","Keybinds","Triggerbot"},                {"Main","Keybinds","Triggerbot"} },

        -- ESP
        { {"ESP","Enabled"},                                 {"ESP","Enabled"} },
        { {"ESP","Name Size"},                               {"ESP","Name Size"} },
        { {"Main","Keybinds","ESP"},                       {"Main","Keybinds","ESP"} },
        { {"ESP","Line","Enabled"},                        {"ESP","Line","Enabled"} },
        { {"ESP","Line","Visible Color"},                  {"ESP","Line","Visible Color"} },
        { {"ESP","Line","Blocked Color"},                  {"ESP","Line","Blocked Color"} },
        { {"ESP","Line","Line Color"},                     {"ESP","Line","Line Color"} },

        -- Weapon Modifications
        { {"Weapon Modifications","Infinite Range"},         {"Weapon Modifications","Infinite Range"} },
        { {"Weapon Modifications","Spread Modifications"},   {"Weapon Modifications","Spread Modifications"} },
        { {"Weapon Modifications","Custom Delays"},          {"Weapon Modifications","Custom Delays"} },
        { {"Weapon Modifications","Taps"},                   {"Weapon Modifications","Taps"} },

        -- ForceHit
        { {"Weapon Modifications","ForceHit","Enabled"},   {"Weapon Modifications","ForceHit","Enabled"} },
        { {"Weapon Modifications","ForceHit","Full Damage"}, {"Weapon Modifications","ForceHit","Full Damage"} },
        { {"Weapon Modifications","ForceHit","Weapon Distances"}, {"Weapon Modifications","ForceHit","Weapon Distances"} },

        -- Speed
        { {"Speed Modification","Enabled"},                  {"Character","Speed Override","Enabled"} },
        { {"Speed Modification","Velocity Injection"},        {"Character","Speed Override","Velocity Injection"} },
        { {"Main","Keybinds","Speed"},                     {"Main","Keybinds","Speed"} },
        { {"Speed Modification","Anti Trip"},                {"Character","Anti Trip","Enabled"} },
        { {"Speed Modification","Data"},                     {"Character","Speed Override","Data"} },
        { {"Speed Modification","Panic Ground","Enabled"}, {"Character","Panic Ground","Enabled"} },
        { {"Speed Modification","Panic Ground","Keybind"}, {"Character","Panic Ground","Key"} },

        -- Character Model (legacy)
        { {"Character Model","Enabled"},                     {"Character Model","Enabled"} },
        { {"Character Model","Apply Respawn"},               {"Character Model","Apply Respawn"} },
        { {"Character Model","User ID"},                     {"Character Model","User ID"} },

        -- Avatar Spoofer (preferred)
        { {"Avatar Spoofer","Enabled"},                      {"Avatar Spoofer","Enabled"} },
        { {"Avatar Spoofer","Apply Respawn"},                {"Avatar Spoofer","Apply Respawn"} },
        { {"Avatar Spoofer","User"},                         {"Avatar Spoofer","User"} },
        
        -- Hotkeys
        { {"Hotkeys","Enabled"},                             {"Hotkeys","Enabled"} },
        { {"Hotkeys","Title"},                               {"Hotkeys","Title"} },
        { {"Hotkeys","Position","X"},                      {"Hotkeys","Position","X"} },
        { {"Hotkeys","Position","Y"},                      {"Hotkeys","Position","Y"} },
        { {"Hotkeys","Icon"},                                {"Hotkeys","Icon"} },
        { {"Hotkeys","Draggable"},                           {"Hotkeys","Draggable"} },
        { {"Hotkeys","Inverted"},                            {"Hotkeys","Inverted"} },
        { {"Hotkeys","Outline"},                             {"Hotkeys","Outline"} },
        { {"Hotkeys","TextToggleOnly"},                      {"Hotkeys","TextToggleOnly"} },
        { {"Hotkeys","FontSize"},                            {"Hotkeys","FontSize"} },
        { {"Hotkeys","Roundness"},                           {"Hotkeys","Roundness"} },
        { {"Hotkeys","ToggleStyle"},                         {"Hotkeys","ToggleStyle"} },
        { {"Hotkeys","Colors","Background"},               {"Hotkeys","Colors","Background"} },
        { {"Hotkeys","Colors","Header"},                   {"Hotkeys","Colors","Header"} },
        { {"Hotkeys","Colors","Text"},                     {"Hotkeys","Colors","Text"} },
        { {"Hotkeys","Colors","Accent"},                   {"Hotkeys","Colors","Accent"} },
        { {"Hotkeys","Colors","Border"},                   {"Hotkeys","Colors","Border"} },
        { {"Hotkeys","Colors","Target"},                   {"Hotkeys","Colors","Target"} },
        { {"Hotkeys","Colors","ToggleOn"},                 {"Hotkeys","Colors","ToggleOn"} },

        -- Visuals
        { {"Visuals","Target Card"},                         {"Main","Target Card"} },
    }

    for _, entry in ipairs(configMap) do
        apply(resolve(userConfig, entry[1]), entry[2])
    end
end

local function validateSettings(Settings)
    local function vWarn(msg)
        warn("[SauceConfig] " .. msg)
    end

    local function expectType(path, value, expected)
        if value == nil then return end
        if type(value) ~= expected then
            vWarn(path .. " expected " .. expected .. ", got " .. type(value))
        end
    end

    local function expectEnum(path, value, valid)
        if value == nil then return end
        local lower = string.lower(tostring(value))
        for _, v in ipairs(valid) do
            if string.lower(v) == lower then return end
        end
        vWarn(path .. ' invalid value "' .. tostring(value) .. '", expected one of: ' .. table.concat(valid, ", "))
    end

    local function expectRange(path, value, lo, hi)
        if value == nil then return end
        local n = tonumber(value)
        if not n then
            vWarn(path .. " expected number, got " .. type(value))
            return
        end
        if n < lo or n > hi then
            vWarn(path .. " = " .. tostring(n) .. " out of range [" .. lo .. ", " .. hi .. "]")
        end
    end

    local function expectKey(path, value)
        if value == nil then return end
        if typeof(value) == "EnumItem" then return end
        if type(value) ~= "string" then
            vWarn(path .. " expected string or KeyCode, got " .. type(value))
            return
        end
        local ok = pcall(function() return Enum.KeyCode[string.upper(value)] end)
        if not ok then vWarn(path .. ' invalid key "' .. tostring(value) .. '"') end
    end

    local S = Settings
    expectType("Main.Enabled", S.Enabled, "boolean")
    expectEnum("Main.Target Part", S.TargetPart, {"Head","HumanoidRootPart","Torso","UpperTorso","LowerTorso","Closest Point"})
    expectRange("Main.Closest Point Scale", S.ClosestPointScale, 0, 1)
    expectEnum("Main.Selection System", S.SelectionSystem, {"Target","Auto"})
    expectType("Main.Checks.Visible Check", S.VisCheck, "boolean")
    expectType("Main.Checks.Persist Lock On Death", S.PersistLockOnDeath, "boolean")
    expectType("Main.Checks.Death Check", S.DeathCheck, "boolean")
    expectKey("Keybinds.Target", S.ToggleKey)
    expectKey("Keybinds.Camlock", S.CamlockKey)
    expectKey("Keybinds.Speed", S.SpeedKey)
    expectKey("Keybinds.ESP", S.ESPKey)
    expectKey("Keybinds.Triggerbot", S.TriggerbotKey)
    expectType("Camlock.Enabled", S.CamlockEnabled, "boolean")
    expectRange("Camlock.Smoothness", S.CamlockSmoothness, 0, 1)
    expectEnum("Camlock.Click Type", S.CamlockClickType, {"Hold","Toggle"})
    expectEnum("Camlock.Easing Style", S.CamlockEasingStyle, {"Linear","Quad","Quart","Sine","Cubic","Back","Bounce","Elastic","Exponential","Circular"})
    expectEnum("Camlock.Easing Direction", S.CamlockEasingDirection, {"In","Out","InOut"})
    expectType("Triggerbot.Enabled", S.TriggerbotEnabled, "boolean")
    expectRange("Triggerbot.Distance", S.TriggerbotDistance, 0, 10000)
    expectRange("Triggerbot.Delay", S.TriggerbotDelay, 0, 10)
    expectEnum("Triggerbot.Click Type", S.TriggerbotClickType, {"Hold","Toggle"})
    expectType("Weapon Modifications.Infinite Range", S.InfiniteRange, "boolean")
    expectType("ForceHit.Enabled", S.ForceHitEnabled, "boolean")
    expectType("ForceHit.Full Damage", S.ForceHitFullDamage, "boolean")
    expectType("Avatar Spoofer.Enabled", S.AvatarSpooferEnabled, "boolean")
    expectType("Avatar Spoofer.Apply Respawn", S.AvatarSpooferApplyRespawn, "boolean")
    expectType("Character Model.Enabled", S.CharacterModelEnabled, "boolean")
    expectType("Character Model.Apply Respawn", S.CharacterModelApplyRespawn, "boolean")
    expectType("ESP.Enabled", S.ESPAllowed, "boolean")
    expectType("Hotkeys.Enabled", S.HotkeysEnabled, "boolean")
    expectEnum("Hotkeys.ToggleStyle", S.HotkeysToggleStyle, {"pill","dot","none"})
    expectEnum("Triggerbot.FOV.Type", S.TriggerbotFOVType, {"Box","Direct"})
    expectEnum("Camlock.FOV.Type", S.CamlockFOVType, {"Box","Direct"})

    if S.AvatarSpooferUser ~= nil then
        local t = type(S.AvatarSpooferUser)
        if t ~= "string" and t ~= "number" then
            vWarn("Avatar Spoofer.User expected string or number, got " .. t)
        end
    end

    if S.CharacterModelUserId ~= nil then
        local t = type(S.CharacterModelUserId)
        if t ~= "string" and t ~= "number" then
            vWarn("Character Model.User ID expected string or number, got " .. t)
        end
    end

    if type(S.Taps) == "table" then
        for weaponName, entry in pairs(S.Taps) do
            if type(entry) == "table" and entry["Enabled"] then
                local value = entry["Value"]
                expectRange("Weapon Modifications.Taps." .. tostring(weaponName), value, 1, 50)
            end
        end
    end
end

ConfigBridge.applyUserConfig = applyUserConfig
ConfigBridge.validateSettings = validateSettings

return ConfigBridge
