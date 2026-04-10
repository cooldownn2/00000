local settings = {}

local INFINITE_RANGE_PATH = {"Weapon Modifications", "Infinite Range"}
local WALLBANG_PATH      = {"Weapon Modifications", "WallBang"}
local WALLBANG_ALT_PATH  = {"Weapon Modifications", "Wallbang"}

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
    Wallbang                    = {"Weapon Modifications", "WallBang"},
    WallBang                    = {"Weapon Modifications", "WallBang"},

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

local function resolveInfiniteRangeSetting()
    local v = getPathValue(settings, INFINITE_RANGE_PATH)
    if type(v) == "table" then
        if v.Enabled == nil then return false end
        return v.Enabled == true
    end
    return v == true
end

local function resolveWallbangSetting()
    local top = getPathValue(settings, WALLBANG_PATH)
    if type(top) == "boolean" then
        return top
    end

    local alt = getPathValue(settings, WALLBANG_ALT_PATH)
    if type(alt) == "boolean" then
        return alt
    end

    local v = getPathValue(settings, INFINITE_RANGE_PATH)
    if type(v) == "table" then
        if type(v.WallBang) == "boolean" then return v.WallBang end
        if type(v.Wallbang) == "boolean" then return v.Wallbang end
    end

    return false
end

local Settings = setmetatable({}, {
    __index = function(_, key)
        if key == "InfiniteRange" then
            return resolveInfiniteRangeSetting()
        end
        if key == "Wallbang" then
            return resolveWallbangSetting()
        end
        if key == "WallBang" then
            return resolveWallbangSetting()
        end
        local path = SettingPaths[key]
        if path then
            return getPathValue(settings, path)
        end
        return nil
    end,
    __newindex = function(_, key, value)
        if key == "InfiniteRange" then
            local current = getPathValue(settings, INFINITE_RANGE_PATH)
            if type(current) == "table" and type(value) == "boolean" then
                current.Enabled = value
            else
                setPathValue(settings, INFINITE_RANGE_PATH, value)
            end
            return
        end
        if key == "Wallbang" then
            setPathValue(settings, WALLBANG_PATH, value == true)
            return
        end
        if key == "WallBang" then
            setPathValue(settings, WALLBANG_PATH, value == true)
            return
        end
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
