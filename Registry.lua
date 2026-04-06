local settings = {}

local SettingPaths = {
    TargetAllowed               = {"Main", "Enabled"},
    TargetCardEnabled           = {"Main", "Target Card"},
    ESPAllowed                  = {"ESP", "Enabled"},
    ToggleKey                   = {"Main", "Keybinds", "Target"},
    ESPKey                      = {"Main", "Keybinds", "ESP"},
    SpeedKey                    = {"Main", "Keybinds", "Speed"},
    TriggerbotKey               = {"Main", "Keybinds", "Triggerbot"},
    CamlockKey                  = {"Main", "Keybinds", "Camlock"},
    SelectionColor              = {"Main", "Selection Color"},
    TargetPart                  = {"Main", "Target Part"},
    ClosestPointScale           = {"Main", "Closest Point Scale"},
    CustomSpread                = {"Weapon Modifications", "Custom Spread"},
    CustomDelays                = {"Weapon Modifications", "Custom Delays"},
    Taps                        = {"Weapon Modifications", "Taps"},
    InfiniteRange               = {"Weapon Modifications", "Infinite Range"},

    PersistLockOnDeath          = {"Main", "Checks", "Target", "Persist Lock On Death"},
    RetargetInterval            = {"Main", "Retarget Interval"},
    VisCheck                    = {"Main", "Checks", "Target", "Visible Check"},
    DeathCheck                  = {"Main", "Checks", "Target", "Death Check"},

    ESPNameSize                 = {"ESP", "Name Size"},
    ESPUpdateRate               = {"ESP", "Update Rate"},

    LineEnabled                 = {"ESP", "Line", "Enabled"},
    LineColorVisible            = {"ESP", "Line", "Visible Color"},
    LineColorBlocked            = {"ESP", "Line", "Blocked Color"},
    LineColor                   = {"ESP", "Line", "Line Color"},

    SpeedEnabled                = {"Character", "Speed Override", "Enabled"},
    SpeedData                   = {"Character", "Speed Override", "Data"},
    AntiTripEnabled             = {"Character", "Anti Trip", "Enabled"},
    PanicGroundEnabled          = {"Character", "Panic Ground", "Enabled"},
    PanicGroundKey              = {"Character", "Panic Ground", "Key"},

    TriggerbotEnabled           = {"Triggerbot", "Enabled"},
    TriggerbotVisCheck          = {"Triggerbot", "VisCheck"},
    TriggerbotDistance          = {"Triggerbot", "Distance"},
    TriggerbotDelay             = {"Triggerbot", "Delay"},
    TriggerbotFOVType           = {"Triggerbot", "FOV", "Type"},
    TriggerbotClickType         = {"Triggerbot", "Click Type"},
    TriggerbotFOVWidth          = {"Main", "FOV", "Triggerbot", "Width"},
    TriggerbotFOVHeight         = {"Main", "FOV", "Triggerbot", "Height"},
    TriggerbotFOVVisualizeEnabled = {"Main", "FOV", "Triggerbot", "Visualize", "Enabled"},
    TriggerbotFOVVisualizeColor   = {"Main", "FOV", "Triggerbot", "Visualize", "Color"},
    TriggerbotFOVVisualizeHover   = {"Main", "FOV", "Triggerbot", "Visualize", "Change Color On Hover"},

    CamlockEnabled              = {"Camlock", "Enabled"},
    CamlockDistance             = {"Camlock", "Distance"},
    CamlockSmoothness           = {"Camlock", "Smoothness"},
    CamlockClickType            = {"Camlock", "Click Type"},
    CamlockEasingStyle          = {"Camlock", "Easing Style"},
    CamlockEasingDirection      = {"Camlock", "Easing Direction"},
    CamlockFOVType              = {"Camlock", "FOV", "Type"},
    CamlockFOVWidth             = {"Camlock", "Width"},
    CamlockFOVHeight            = {"Camlock", "Height"},
    CamlockFOVVisualizeEnabled  = {"Camlock", "Visualize", "Enabled"},
    CamlockFOVVisualizeColor    = {"Camlock", "Visualize", "Color"},
    CamlockFOVVisualizeHover    = {"Camlock", "Visualize", "Change Color On Hover"},

    VisualsEnabled              = {"Visuals", "Info", "Enabled"},
    VisualsAlias                = {"Visuals", "Info", "Alias"},
    VisualsOutline              = {"Visuals", "Info", "Outline"},
    VisualsSize                 = {"Visuals", "Info", "Position", "Size"},
    VisualsX                    = {"Visuals", "Info", "Position", "X"},
    VisualsY                    = {"Visuals", "Info", "Position", "Y"},

    VisualsHeaderColor          = {"Visuals", "Info", "Colors", "Header"},          -- alias text
    VisualsAccentColor          = {"Visuals", "Info", "Colors", "Accent"},           -- left bar & border stroke
    VisualsTextColor            = {"Visuals", "Info", "Colors", "Text"},             -- distance numbers
    VisualsTargetColor          = {"Visuals", "Info", "Colors", "Target"},           -- locked target name
    VisualsActiveColor          = {"Visuals", "Info", "Colors", "Active"},           -- active ▎bar & status text
    VisualsIdleColor            = {"Visuals", "Info", "Colors", "Idle"},             -- idle/off status text
    VisualsBarIdleColor         = {"Visuals", "Info", "Colors", "Bar Idle"},         -- ▎bar when idle
    VisualsInRangeColor         = {"Visuals", "Info", "Colors", "In Range"},         -- "in" indicator
    VisualsOutRangeColor        = {"Visuals", "Info", "Colors", "Out Range"},        -- "out"/"wall" indicator
    VisualsFeatureLabelColor    = {"Visuals", "Info", "Colors", "Feature Label"},    -- Triggerbot/Camlock/ForceHit text
    VisualsStatLabelColor       = {"Visuals", "Info", "Colors", "Stat Label"},       -- "hp" & "armor" label text
    VisualsArmorValueColor      = {"Visuals", "Info", "Colors", "Armor Value"},      -- armor number at full/high value
    VisualsGhostColor           = {"Visuals", "Info", "Colors", "Ghost"},            -- no-target placeholder text

    ForceHitEnabled             = {"Weapon Modifications", "ForceHit", "Enabled"},
    ForceHitFullDamage          = {"Weapon Modifications", "ForceHit", "Full Damage"},
    ForceHitDistances           = {"Weapon Modifications", "ForceHit", "Weapon Distances"},
    ShotgunPellets              = {"Weapon Modifications", "ForceHit", "Shotgun Pellets"},
    FullDamageShotgun           = {"Weapon Modifications", "ForceHit", "Full Damage Shots", "Shotgun"},
    FullDamageDefault           = {"Weapon Modifications", "ForceHit", "Full Damage Shots", "Default"},
}

local function getPathValue(root, path)
    local current = root
    for i = 1, #path do
        if type(current) ~= "table" then return nil end
        current = current[path[i]]
    end
    return current
end

local function setPathValue(root, path, value)
    local current = root
    for i = 1, #path - 1 do
        local key = path[i]
        if type(current[key]) ~= "table" then
            current[key] = {}
        end
        current = current[key]
    end
    current[path[#path]] = value
end

local Settings = setmetatable({}, {
    __index = function(_, key)
        local path = SettingPaths[key]
        if path then
            return getPathValue(settings, path)
        end
        return nil
    end,
    __newindex = function(_, key, value)
        local path = SettingPaths[key]
        if path then
            setPathValue(settings, path, value)
            return
        end
        warn("[Registry] Unknown setting key: '" .. tostring(key) .. "' — value was not applied.")
    end,
})

return {
    settings = settings,
    Settings = Settings,
    getPathValue = getPathValue,
}