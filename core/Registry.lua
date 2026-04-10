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
    SpreadMod                   = {"Weapon Modifications", "Spread Modifications"},
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
    SpeedVelocityInjection      = {"Character", "Speed Override", "Velocity Injection"},
    SpeedData                   = {"Character", "Speed Override", "Data"},
    AntiTripEnabled             = {"Character", "Anti Trip", "Enabled"},
    PanicGroundEnabled          = {"Character", "Panic Ground", "Enabled"},
    PanicGroundKey              = {"Character", "Panic Ground", "Key"},
    CharacterModelEnabled       = {"Character Model", "Enabled"},
    CharacterModelUserId        = {"Character Model", "User ID"},

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

    HotkeysEnabled              = {"Hotkeys", "Enabled"},
    HotkeysTitle                = {"Hotkeys", "Title"},
    HotkeysX                    = {"Hotkeys", "Position", "X"},
    HotkeysY                    = {"Hotkeys", "Position", "Y"},
    HotkeysIcon                 = {"Hotkeys", "Icon"},
    HotkeysDraggable            = {"Hotkeys", "Draggable"},
    HotkeysInverted             = {"Hotkeys", "Inverted"},
    HotkeysOutline              = {"Hotkeys", "Outline"},
    HotkeysTextToggleOnly       = {"Hotkeys", "TextToggleOnly"},
    HotkeysFontSize             = {"Hotkeys", "FontSize"},
    HotkeysRoundness            = {"Hotkeys", "Roundness"},
    HotkeysToggleStyle          = {"Hotkeys", "ToggleStyle"},

    HotkeysBackground           = {"Hotkeys", "Colors", "Background"},
    HotkeysHeader               = {"Hotkeys", "Colors", "Header"},
    HotkeysText                 = {"Hotkeys", "Colors", "Text"},
    HotkeysAccent               = {"Hotkeys", "Colors", "Accent"},
    HotkeysBorder               = {"Hotkeys", "Colors", "Border"},
    HotkeysTarget               = {"Hotkeys", "Colors", "Target"},
    HotkeysToggleOn             = {"Hotkeys", "Colors", "ToggleOn"},

    ForceHitEnabled             = {"Weapon Modifications", "ForceHit", "Enabled"},
    ForceHitFullDamage          = {"Weapon Modifications", "ForceHit", "Full Damage"},
    ForceHitDistances           = {"Weapon Modifications", "ForceHit", "Weapon Distances"},
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
    settings     = settings,
    Settings     = Settings,
    getPathValue = getPathValue,
}
