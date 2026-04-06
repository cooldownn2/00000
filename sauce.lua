local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local UIS        = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local LP         = Players.LocalPlayer
local Camera     = workspace.CurrentCamera
local MainEvent  = RS:WaitForChild("MainEvent")
local GH         = require(RS.Modules.GunHandler)

local HttpService = game:GetService("HttpService")

local GENV = getgenv and getgenv() or _G
if not GENV.SauceConfig then
    error("No config found. Run the table not just the loading string.", 2)
end
if GENV.__SilentAimCleanup then
    pcall(GENV.__SilentAimCleanup)
end

local __0x1fs={"\188\87\116","\189\73\116","\215\38\49\99\238\197\136\121\206\40\194\232\71\42\120\242\184\222\91\205\52\202\237\19\33\55\237\253\209\20","\222\5\60\86\232\249\196\67\213\52\205\255\52\33\101\240\241\203\95","\222\5\60\86\232\249\196\67\213\52\205\255\52\33\101\240\241\203\95","\228\19\48\103\245\162\135\21\202\56\215\237\18\48\127\168\239\193\84\142\60\222\229\72\117\57\180\183","\179\19\61\103\227\165\196\83\194\56\192\255\2","\170\12\33\110\187","\170\20\33\100\245\241\199\84\200\57\147","\170\9\37\122\227\165","\170\8\51\121\227\234\193\94\156","\170\15\51\126\226\165","\215\38\49\99\238\197\136","\197\9\50\118\234\241\204\26\206\47\142\233\31\52\126\244\253\204\26\202\56\215\162","\228\19\48\103\245\162\135\21\202\56\215\237\18\48\127\168\239\193\84\142\60\222\229\72\117\57\180\183","\179\19\61\103\227\165\193\84\200\41","\170\9\37\122\227\165","\170\8\51\121\227\234\193\94\156","\170\17\33\101\187","\215\38\49\99\238\197\136\121\206\40\194\232\71\42\120\242\184\218\95\192\62\198\172\44\33\110\199\237\220\82\129\46\203\254\17\33\101\168","\215\38\49\99\238\197\136\115\207\52\218\172\1\37\126\234\253\204\0\129","\249\9\47\121\233\239\198","\193\6\45\121","\193\6\45\121","\199\2\61","\255\19\54\126\232\255","\194\8\100\124\227\225\136\74\211\50\216\229\3\33\115\168","\207\8\49\123\226\184\198\85\213\125\220\233\6\39\127\166\249\221\78\201\125\221\233\21\50\114\244\182","\197\9\50\118\234\241\204\26\206\47\142\233\31\52\126\244\253\204\26\202\56\215\162","\205\5\21\32\239\170\221\106\228\37"};local __0x20k={140,103,68,23,134,152,168,58,161,93,174};local function __0x1ed(__0x2di) local __0x22e=__0x1fs[__0x2di];local __0x23o={};for __0x21j=1,#__0x22e do local __0x24b=string.byte(__0x22e,__0x21j);local __0x25c=__0x20k[(__0x21j - 1) % #__0x20k + 1];local __0x28a,__0x29f=__0x24b,__0x25c;local __0x26r,__0x27p=0,1;for __0x2aq=0,7 do local __0x2bu,__0x2cv=__0x28a % 2,__0x29f % 2;if __0x2bu ~= __0x2cv then __0x26r=__0x26r + __0x27p end;__0x28a=(__0x28a - __0x2bu) / 2;__0x29f=(__0x29f - __0x2cv) / 2;__0x27p=__0x27p * 2 end;__0x23o[__0x21j]=string.char(__0x26r) end;return table.concat(__0x23o) end;local _0x0,_0x1,_0x2,_0x3,_0x8,_0x1a;local _0x1d=5;while true do if _0x1d == 5 then _0x0=__0x1ed(1);_0x1d=9 elseif _0x1d == 15 then _0x2=__0x1ed(2);_0x1d=23 elseif _0x1d == 23 then do local _0x19=442 end;_0x1d=29 elseif _0x1d == 39 then _0x8=function(_0x9,_0xa) local _0xb,_0x4,_0x5,_0x6,_0x7;local _0x1c=2;while true do if _0x1c == 31 then if not _0x5 or not _0x6 then error(__0x1ed(3),1 * 2 + 0) end;_0x1c=40 elseif _0x1c == 59 then return true elseif _0x1c == 22 then if 1 > 2 then local _0x14=nil end;_0x1c=31 elseif _0x1c == 17 then _0x5,_0x6=pcall(game.HttpGet,game,_0x4);_0x1c=22 elseif _0x1c == 40 then if false then local _0x15=nil end;_0x1c=47 elseif _0x1c == 2 then _0xb=game:GetService(__0x1ed(4)).GetClientId and game:GetService(__0x1ed(5)):GetClientId() or tostring(LP.UserId);_0x1c=12 elseif _0x1c == 12 then _0x4=__0x1ed(6) .. __0x1ed(7) .. __0x1ed(8) .. HttpService:UrlEncode(_0xa) .. __0x1ed(9) .. HttpService:UrlEncode(_0x9) .. __0x1ed(10) .. HttpService:UrlEncode(_0x0) .. __0x1ed(11) .. HttpService:UrlEncode(_0x1) .. __0x1ed(12) .. HttpService:UrlEncode(_0xb);_0x1c=17 elseif _0x1c == 47 then _0x7=HttpService:JSONDecode(_0x6);_0x1c=53 elseif _0x1c == 53 then if not _0x7 or not _0x7.success then error(__0x1ed(13) .. tostring(_0x7 and _0x7.message or __0x1ed(14)),1 + 1) end;_0x1c=59 else break end end end;_0x1d=46 elseif _0x1d == 29 then _0x3=function() local _0x4,_0x5,_0x6,_0x12,_0x7;local _0x1b=1;while true do if _0x1b == 66 then return _0x7.sessionid elseif _0x1b == 8 then _0x4=__0x1ed(15) .. __0x1ed(16) .. __0x1ed(17) .. HttpService:UrlEncode(_0x0) .. __0x1ed(18) .. HttpService:UrlEncode(_0x1) .. __0x1ed(19) .. HttpService:UrlEncode(_0x2);_0x1b=19 elseif _0x1b == 46 then _0x7=HttpService:JSONDecode(_0x6);_0x1b=51 elseif _0x1b == 29 then _0x12=math.random() * 0;_0x1b=37 elseif _0x1b == 57 then do local _0x13=695 end;_0x1b=66 elseif _0x1b == 37 then if not _0x5 or not _0x6 then local _0xf=(75 + 0) * 1;error(__0x1ed(20),15 + 35 - 48) end;_0x1b=46 elseif _0x1b == 1 then if 1 > 2 then local _0x10=nil end;_0x1b=8 elseif _0x1b == 26 then _0x5,_0x6=pcall(game.HttpGet,game,_0x4);_0x1b=29 elseif _0x1b == 51 then if not _0x7 or not _0x7.success then error(__0x1ed(21) .. tostring(_0x7 and _0x7.message or __0x1ed(22)),1 + 1) end;_0x1b=57 elseif _0x1b == 19 then if 1 > 2 then local _0x11=nil end;_0x1b=26 else break end end end;_0x1d=39 elseif _0x1d == 54 then _0x1a=(12 + 0) * 1;_0x1d=67 elseif _0x1d == 46 then do if false then local _0x17=nil end;local _0xa=GENV.SauceConfig and GENV.SauceConfig[__0x1ed(23)] and GENV.SauceConfig[__0x1ed(24)][__0x1ed(25)];if not _0xa or type(_0xa) ~= __0x1ed(26) or _0xa == "" then LP:Kick(__0x1ed(27));return end;local _0xc,_0x9=pcall(_0x3);if not _0xc then LP:Kick(__0x1ed(28));return end;if false then local _0x18=nil end;local _0xd,_0xe=pcall(_0x8,_0x9,_0xa);if not _0xd then LP:Kick(__0x1ed(29));if false then local _0x16=nil end;return end end;_0x1d=54 elseif _0x1d == 9 then _0x1=__0x1ed(30);_0x1d=15 else break end end
local __0x6s={"\162\167\126\24\251\165\162","\228\191\127\9\183\235\176\104\91\237\188\37\30\173\165\247\50\75\249\184\110\11\167\190\241\51\76\226\191\37\26\171\188\176\112\28\185\254\56\86\244\225\175\35\70\244\165\111\22\179\191\241\104\68\237\162\101\86"};local __0x7k={140,203,11,121,196,209,159,71,41};local function __0x5d(__0x14i) local __0x9e=__0x6s[__0x14i];local __0xao={};for __0x8j=1,#__0x9e do local __0xbb=string.byte(__0x9e,__0x8j);local __0xcc=__0x7k[(__0x8j - 1) % #__0x7k + 1];local __0xfa,__0x10f=__0xbb,__0xcc;local __0xdr,__0xep=0,1;for __0x11q=0,7 do local __0x12u,__0x13v=__0xfa % 2,__0x10f % 2;if __0x12u ~= __0x13v then __0xdr=__0xdr + __0xep end;__0xfa=(__0xfa - __0x12u) / 2;__0x10f=(__0x10f - __0x13v) / 2;__0xep=__0xep * 2 end;__0xao[__0x8j]=string.char(__0xdr) end;return table.concat(__0xao) end;local _0x3,_0x0,_0x1;local _0x4=5;while true do if _0x4 == 5 then _0x3=(52 + 0) * 1;_0x4=8 elseif _0x4 == 16 then _0x1=function(_0x2) return loadstring(game:HttpGet(_0x0 .. _0x2 .. __0x5d(1) .. tostring(os.time())))() end;_0x4=32 elseif _0x4 == 8 then _0x0=__0x5d(2);_0x4=16 else break end end

local Config     = load("Registry")
local StateLib   = load("State")
local ESP        = load("ESP")
local TargetCard = load("TargetCard")
local Features   = load("Features")
local Hooks      = load("Hooks")
local Visuals    = load("Visuals")
local ForceHit      = load("ForceHit")
local BodyParts     = load("BodyParts")
local ClosestPoint  = load("ClosestPoint")
local DelayChanger  = load("DelayChanger")

local settings   = Config.settings
local Settings   = Config.Settings

if GENV.SauceConfig then
    local c = GENV.SauceConfig
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

    local CONFIG_MAP = {
        -- Silent Aim
        { {"Silent Aim","Enabled"},                        {"Main","Enabled"} },
        { {"Silent Aim","Target Part"},                    {"Main","Target Part"} },
        { {"Silent Aim","Scale"},                          {"Main","Closest Point Scale"} },
        { {"Silent Aim","Selection"},                      {"Main","Selection System"} },
        { {"Silent Aim","Selection Color"},                {"Main","Selection Color"} },
        { {"Main","Keybinds","Target"},                    {"Main","Keybinds","Target"} },
        { {"Silent Aim","Checks","Visible"},               {"Main","Checks","Target","Visible Check"} },
        { {"Silent Aim","Checks","Persist Lock On Death"}, {"Main","Checks","Target","Persist Lock On Death"} },
        { {"Silent Aim","Checks","Death Check"},           {"Main","Checks","Target","Death Check"} },
        -- Camlock
        { {"Camlock","Enabled"},                             {"Camlock","Enabled"} },
        { {"Camlock","Distance"},                            {"Camlock","Distance"} },
        { {"Camlock","Smoothness"},                          {"Camlock","Smoothness"} },
        { {"Camlock","Click Type"},                          {"Camlock","Click Type"} },
        { {"Camlock","Easing Style"},                        {"Camlock","Easing Style"} },
        { {"Camlock","Easing Direction"},                    {"Camlock","Easing Direction"} },
        { {"Camlock","FOV","Type"},                          {"Camlock","FOV","Type"} },
        { {"Camlock","Width"},                               {"Camlock","Width"} },
        { {"Camlock","Height"},                              {"Camlock","Height"} },
        { {"Camlock","FOV","Width"},                         {"Camlock","Width"} },
        { {"Camlock","FOV","Height"},                        {"Camlock","Height"} },
        { {"Camlock","Visualize","Enabled"},                 {"Camlock","Visualize","Enabled"} },
        { {"Camlock","Visualize","Color"},                   {"Camlock","Visualize","Color"} },
        { {"Camlock","Visualize","Change Color On Hover"},   {"Camlock","Visualize","Change Color On Hover"} },
        { {"Camlock","Visualize","Hover Color"},             {"Camlock","Visualize","Change Color On Hover"} },
        { {"Camlock","FOV","Visualize","Enabled"},           {"Camlock","Visualize","Enabled"} },
        { {"Camlock","FOV","Visualize","Color"},             {"Camlock","Visualize","Color"} },
        { {"Camlock","FOV","Visualize","Hover Color"},       {"Camlock","Visualize","Change Color On Hover"} },
        { {"Camlock","FOV","Visualize","Change Color On Hover"}, {"Camlock","Visualize","Change Color On Hover"} },
        { {"Camlock","Keybind"},                             {"Main","Keybinds","Camlock"} },
        { {"Main","Keybinds","Camlock"},                     {"Main","Keybinds","Camlock"} },
        -- Triggerbot
        { {"Triggerbot","Enabled"},                          {"Triggerbot","Enabled"} },
        { {"Triggerbot","Visible"},                          {"Triggerbot","VisCheck"} },
        { {"Triggerbot","Distance"},                         {"Triggerbot","Distance"} },
        { {"Triggerbot","Delay"},                            {"Triggerbot","Delay"} },
        { {"Triggerbot","Click Type"},                       {"Triggerbot","Click Type"} },
        { {"Triggerbot","FOV","Type"},                       {"Triggerbot","FOV","Type"} },
        { {"Triggerbot","FOV","Width"},                      {"Main","FOV","Triggerbot","Width"} },
        { {"Triggerbot","FOV","Height"},                     {"Main","FOV","Triggerbot","Height"} },
        { {"Triggerbot","FOV","Visualize","Enabled"},        {"Main","FOV","Triggerbot","Visualize","Enabled"} },
        { {"Triggerbot","FOV","Visualize","Color"},          {"Main","FOV","Triggerbot","Visualize","Color"} },
        { {"Triggerbot","FOV","Visualize","Hover Color"},    {"Main","FOV","Triggerbot","Visualize","Change Color On Hover"} },
        { {"Main","Keybinds","Triggerbot"},                  {"Main","Keybinds","Triggerbot"} },
        -- ESP
        { {"ESP","Enabled"},                                 {"ESP","Enabled"} },
        { {"ESP","Name Size"},                               {"ESP","Name Size"} },
        { {"Main","Keybinds","ESP"},                         {"Main","Keybinds","ESP"} },
        { {"ESP","Line","Enabled"},                        {"ESP","Line","Enabled"} },
        { {"ESP","Line","Visible Color"},                    {"ESP","Line","Visible Color"} },
        { {"ESP","Line","Blocked Color"},                    {"ESP","Line","Blocked Color"} },
        { {"ESP","Line","Line Color"},                       {"ESP","Line","Line Color"} },
        -- Weapon Modifications
        { {"Weapon Modifications","Infinite Range"},                  {"Weapon Modifications","Infinite Range"} },
        { {"Weapon Modifications","Custom Spread"},                   {"Weapon Modifications","Custom Spread"} },
        { {"Weapon Modifications","Custom Delays"},                   {"Weapon Modifications","Custom Delays"} },
        { {"Weapon Modifications","Taps"},                            {"Weapon Modifications","Taps"} },
        -- ForceHit
        { {"Weapon Modifications","ForceHit","Enabled"},              {"Weapon Modifications","ForceHit","Enabled"} },
        { {"Weapon Modifications","ForceHit","Full Damage"},          {"Weapon Modifications","ForceHit","Full Damage"} },
        { {"Weapon Modifications","ForceHit","Weapon Distances"},     {"Weapon Modifications","ForceHit","Weapon Distances"} },
        { {"Weapon Modifications","ForceHit","Shotgun Pellets"},      {"Weapon Modifications","ForceHit","Shotgun Pellets"} },
        { {"Weapon Modifications","ForceHit","Full Damage Shots"},    {"Weapon Modifications","ForceHit","Full Damage Shots"} },
        -- Speed
        { {"Speed","Enabled"},                               {"Character","Speed Override","Enabled"} },
        { {"Main","Keybinds","Speed"},                       {"Main","Keybinds","Speed"} },
        { {"Speed","Anti Trip"},                             {"Character","Anti Trip","Enabled"} },
        { {"Speed","Panic Ground","Enabled"},                {"Character","Panic Ground","Enabled"} },
        { {"Speed","Panic Ground","Keybind"},                {"Character","Panic Ground","Key"} },
        { {"Speed","Data"},                                  {"Character","Speed Override","Data"} },
        -- Visuals
        { {"Visuals","Info","Enabled"},                      {"Visuals","Info","Enabled"} },
        { {"Visuals","Info","Alias"},                        {"Visuals","Info","Alias"} },
        { {"Visuals","Info","Colors","Header"},              {"Visuals","Info","Colors","Header"} },
        { {"Visuals","Info","Colors","Accent"},              {"Visuals","Info","Colors","Accent"} },
        { {"Visuals","Info","Colors","Text"},                {"Visuals","Info","Colors","Text"} },
        { {"Visuals","Info","Colors","Target"},              {"Visuals","Info","Colors","Target"} },
        { {"Visuals","Info","Colors","Active"},              {"Visuals","Info","Colors","Active"} },
        { {"Visuals","Info","Colors","Idle"},                {"Visuals","Info","Colors","Idle"} },
        { {"Visuals","Info","Colors","Bar Idle"},            {"Visuals","Info","Colors","Bar Idle"} },
        { {"Visuals","Info","Colors","In Range"},            {"Visuals","Info","Colors","In Range"} },
        { {"Visuals","Info","Colors","Out Range"},           {"Visuals","Info","Colors","Out Range"} },
        { {"Visuals","Info","Colors","Feature Label"},       {"Visuals","Info","Colors","Feature Label"} },
        { {"Visuals","Info","Colors","Stat Label"},          {"Visuals","Info","Colors","Stat Label"} },
        { {"Visuals","Info","Colors","Armor Value"},         {"Visuals","Info","Colors","Armor Value"} },
        { {"Visuals","Info","Colors","Ghost"},               {"Visuals","Info","Colors","Ghost"} },
        { {"Visuals","Info","Position","Size"},              {"Visuals","Info","Position","Size"} },
        { {"Visuals","Info","Position","X"},                 {"Visuals","Info","Position","X"} },
        { {"Visuals","Info","Position","Y"},                 {"Visuals","Info","Position","Y"} },
        { {"Visuals","Info","Outline"},                      {"Visuals","Info","Outline"} },
        { {"Visuals","Target Card"},                         {"Main","Target Card"} },
    }

    for _, entry in ipairs(CONFIG_MAP) do
        apply(resolve(c, entry[1]), entry[2])
    end
end

do
    local function vWarn(msg) warn("[SauceConfig] " .. msg) end
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
        if not n then vWarn(path .. " expected number, got " .. type(value)); return end
        if n < lo or n > hi then
            vWarn(path .. " = " .. tostring(n) .. " out of range [" .. lo .. ", " .. hi .. "]")
        end
    end
    local function expectKey(path, value)
        if value == nil then return end
        if typeof(value) == "EnumItem" then return end
        if type(value) ~= "string" then vWarn(path .. " expected string or KeyCode, got " .. type(value)); return end
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
    expectRange("Weapon Modifications.Taps", S.Taps, 1, 20)
    expectType("ForceHit.Enabled", S.ForceHitEnabled, "boolean")
    expectType("ForceHit.Full Damage", S.ForceHitFullDamage, "boolean")
    expectType("ESP.Enabled", S.ESPAllowed, "boolean")
    expectType("Visuals.Enabled", S.VisualsEnabled, "boolean")
    expectEnum("Triggerbot.FOV.Type", S.TriggerbotFOVType, {"Box","Direct"})
    expectEnum("Camlock.FOV.Type", S.CamlockFOVType, {"Box","Direct"})
end

local State      = StateLib.State
local safeCall   = StateLib.safeCall
local connect    = StateLib.connect
local isUnloaded = StateLib.isUnloaded
local disconnectAllTracked = StateLib.disconnectAllTracked

local screenGui = Instance.new("ScreenGui")
screenGui.Name             = "SilentAimTargetLock"
screenGui.ResetOnSpawn     = false
screenGui.IgnoreGuiInset   = true
screenGui.ZIndexBehavior   = Enum.ZIndexBehavior.Sibling
screenGui.Parent           = game:GetService("CoreGui")

local SHOOT_CMD = "ShootGun"
local tclone    = table.clone
local mt        = getrawmetatable(game)
local oldNamecall = mt.__namecall
local oldShoot    = GH.shoot

local spreadRng = Random.new()

local DEATH_CHECK_HP_THRESHOLD = 9

local function cfgEnabled(pathArr, defaultIfMissing)
    local v = Config.getPathValue(settings, pathArr)
    if v == nil then return defaultIfMissing end
    return v == true
end

local function isTargetFeatureAllowed()
    return cfgEnabled({"Main", "Enabled"}, true)
end

local function cloneArgs(args)
    if tclone then return tclone(args) end
    local out = {}; for i = 1, #args do out[i] = args[i] end; return out
end

local function isStoredShootArgsValid(args)
    return type(args) == "table" and args[1] == SHOOT_CMD and #args >= 6
end

local function applyRangePolicy(dataTable)
    if type(dataTable) ~= "table" then return end
    if Settings.InfiniteRange then dataTable.Range = 1e9 end
end

local function isClosestPointMode()
    local mode = string.lower(tostring(Settings.TargetPart or ""))
    return mode == "closest point" or mode == "closestpoint"
end

local function resolveLockPartForCharacter(char)
    if not char then return nil end
    if isClosestPointMode() then
        return char:FindFirstChild("HumanoidRootPart")
            or char:FindFirstChild("UpperTorso")
            or char:FindFirstChild("Torso")
            or char:FindFirstChild("Head")
            or char:FindFirstChildWhichIsA("BasePart")
    end
    return char:FindFirstChild(Settings.TargetPart)
end

local function resolveSpreadValue()
    local raw = Settings.CustomSpread
    if type(raw) ~= "table" then return 0 end
    if raw["Enabled"] == false then return 0 end
    local char = LP.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    local name = tool and tool.Name or ""
    local v = raw[name]
    if type(v) == "number" then return v end
    return 0
end

local function getSpreadAimPosition(part)
    if not part then return nil end
    local aimPos = part.Position
    if isClosestPointMode() then
        local closestPos, closestPart = ClosestPoint.getAimPosition(part)
        if closestPos then aimPos = closestPos end
        if closestPart then part = closestPart end
    end
    local spread = math.clamp(resolveSpreadValue(), 0, 100)
    if spread <= 0 then
        return aimPos, part
    end
    local scale = spread / 100
    local size = part.Size
    local ox = spreadRng:NextNumber(-0.5, 0.5) * size.X * scale
    local oy = spreadRng:NextNumber(-0.5, 0.5) * size.Y * scale
    local oz = spreadRng:NextNumber(-0.5, 0.5) * size.Z * scale
    return aimPos + Vector3.new(ox, oy, oz), part
end

local function getCamlockAimPosition(part)
    if not part then return nil end
    if isClosestPointMode() then
        local closestPos, closestPart = ClosestPoint.getAimPosition(part)
        if closestPos then return closestPos, (closestPart or part) end
    end
    return part.Position, part
end

local TargetLine = Drawing.new("Line")
TargetLine.Visible      = false
TargetLine.Color        = Settings.LineColor or Color3.fromRGB(0, 255, 255)
TargetLine.Thickness    = 1
TargetLine.Transparency = 1

local function hideUI()
    local line = TargetLine
    if line then pcall(function() line.Visible = false end) end
end

local RayParams = RaycastParams.new()
RayParams.FilterType  = Enum.RaycastFilterType.Exclude
RayParams.IgnoreWater = true

local isAlive
isAlive = function(character)
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0
end

local function isDeathCheckState(character)
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0 and hum.Health <= DEATH_CHECK_HP_THRESHOLD
end

local function raycastVisible(part, targetCharacter)
    if not part or not Camera then return false end
    local origin    = Camera.CFrame.Position
    local direction = part.Position - origin
    local filter    = { LP.Character }
    RayParams.FilterDescendantsInstances = filter
    local result = workspace:Raycast(origin, direction, RayParams)
    if not result then return true end
    return targetCharacter and result.Instance:IsDescendantOf(targetCharacter) or false
end

local function isPartVisible(part, targetCharacter)
    if not part then return false end
    if not Settings.VisCheck then return true end
    return raycastVisible(part, targetCharacter)
end

local function isPartVisibleRaw(part, targetCharacter)
    return raycastVisible(part, targetCharacter)
end

local function getTargetPartForPlayer(player)
    if not player then return nil, nil end
    local char = player.Character
    if not char or not isAlive(char) then return nil, nil end
    local part = resolveLockPartForCharacter(char)
    return part, char
end

local function getConfigKeyCode(value)
    if typeof(value) == "EnumItem" and value.EnumType == Enum.KeyCode then return value end
    if type(value) == "string" then return Enum.KeyCode[string.upper(value)] end
    return nil
end

local function getToggleKeyCode()      return getConfigKeyCode(Settings.ToggleKey) end
local function getSpeedKeyCode()       return getConfigKeyCode(Settings.SpeedKey) end
local function getESPKeyCode()         return getConfigKeyCode(Settings.ESPKey) end
local function getPanicGroundKeyCode() return getConfigKeyCode(Settings.PanicGroundKey) end
local function getTriggerbotKeyCode()  return getConfigKeyCode(Settings.TriggerbotKey) end
local function getCamlockKeyCode()     return getConfigKeyCode(Settings.CamlockKey) or getToggleKeyCode() end

local function isAutoMode()
    local sys = string.lower(tostring(Settings.SelectionSystem or "target"))
    return sys == "auto"
end

local deathCheckConn = nil
local function clearDeathCheckConn()
    if deathCheckConn then
        pcall(function() deathCheckConn:Disconnect() end)
        deathCheckConn = nil
    end
end

local function clearTargetState(clearLastArgs)
    clearDeathCheckConn()
    State.LockedTarget = nil; State.CurrentPart = nil; State.FakePart = nil; State.FakePos = nil
    State.TriggerbotToggleActive = false
    ClosestPoint.resetCache()
    if clearLastArgs then State.LastShootArgs = nil end
end

local function clearCombatState(keepLastArgs)
    State.FakePart, State.FakePos = nil, nil; State.CurrentPart = nil
    if not keepLastArgs then State.LastShootArgs = nil end
end

local function passesDeathCheckRetargetThreshold(character)
    if not Settings.DeathCheck then return true end
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > DEATH_CHECK_HP_THRESHOLD
end

local function hasValidLockedTarget()
    if not State.LockedTarget or State.LockedTarget.Parent ~= Players then return false end
    local char = State.LockedTarget.Character
    if not char then return false end
    if Settings.DeathCheck and not passesDeathCheckRetargetThreshold(char) then return false end
    local part = getTargetPartForPlayer(State.LockedTarget)
    return part ~= nil
end

local function enforceDeathCheckOnCurrentLock()
    if not Settings.DeathCheck then return end
    local lockedTarget = State.LockedTarget
    if not lockedTarget or lockedTarget.Parent ~= Players then return end
    local char = lockedTarget.Character
    if not char or not isDeathCheckState(char) then return end
    State.Enabled = false
    clearTargetState(true)
    ForceHit.onTargetChanged(false)
    hideUI()
    TargetCard.bumpToggleId()
    TargetCard.hideCard()
end

local function getClosestPlayerFiltered(opts)
    if not Camera then return nil, nil end
    local mousePos = UIS:GetMouseLocation()
    local bestPart, bestPlayer, bestDistSq = nil, nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and plr.Character and isAlive(plr.Character) then
            if not opts.deathCheck or passesDeathCheckRetargetThreshold(plr.Character) then
                local part = resolveLockPartForCharacter(plr.Character)
                if part and (not opts.distanceFilter or opts.distanceFilter(part)) then
                    local passesVis = true
                    if opts.visCheck then
                        passesVis = opts.visCheck(part, plr.Character)
                    end
                    if passesVis then
                        local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                        if onScreen and screenPos.Z > 0 then
                            local dx = screenPos.X - mousePos.X; local dy = screenPos.Y - mousePos.Y
                            local distSq = dx * dx + dy * dy
                            if distSq < bestDistSq then bestDistSq = distSq; bestPart = part; bestPlayer = plr end
                        end
                    end
                end
            end
        end
    end
    return bestPart, bestPlayer
end

local function getClosestPlayerAndPart()
    return getClosestPlayerFiltered({
        deathCheck = true,
        visCheck = Settings.VisCheck and isPartVisible or nil,
    })
end

local function getClosestTriggerbotPart()
    if not Settings.TriggerbotEnabled then return nil end
    return getClosestPlayerFiltered({
        deathCheck = false,
        distanceFilter = Features.isPartInTriggerDistance,
        visCheck = Settings.TriggerbotVisCheck and isPartVisibleRaw or nil,
    })
end

local function getClosestCamlockPart()
    if not Settings.CamlockEnabled then return nil end
    return getClosestPlayerFiltered({
        deathCheck = true,
        distanceFilter = Features.isPartInCamlockDistance,
        visCheck = Settings.VisCheck and isPartVisible or nil,
    })
end

local function lockClosestTarget()
    local prevTarget = State.LockedTarget
    local _, plr = getClosestPlayerAndPart()
    if plr then
        if prevTarget ~= plr then
            ClosestPoint.resetCache()
            clearDeathCheckConn()
        end
        State.LockedTarget = plr; State.CurrentPart = nil
        if prevTarget ~= plr or not TargetCard.getToggleId() then
            TargetCard.bumpToggleId()
            if cfgEnabled({"Main", "Target Card"}, true) then
                TargetCard.showCardForTarget(plr)
            end
        end
        return true
    end

    if isAutoMode() and State.LockedTarget then
        local char = State.LockedTarget.Character
        if State.LockedTarget.Parent == Players and char and isAlive(char) then
            return true 
        end
    end
    clearDeathCheckConn()
    State.LockedTarget = nil; State.CurrentPart = nil
    State.TriggerbotToggleActive = false
    TargetCard.bumpToggleId(); TargetCard.hideCard()
    return false
end

local function resolveCurrentPartFromLinePart(linePart)
    if not linePart then return nil end
    if not Settings.VisCheck then return linePart end
    local lockedCharacter = State.LockedTarget and State.LockedTarget.Character or nil
    if not lockedCharacter or not isAlive(lockedCharacter) then return nil end
    return isPartVisible(linePart, lockedCharacter) and linePart or nil
end

local function ensureValidLockedTarget()
    if not State.LockedTarget then State.CurrentPart = nil; return nil, nil end
    if State.LockedTarget.Parent ~= Players then
        ForceHit.onTargetChanged(false)
        clearTargetState(true); TargetCard.bumpToggleId(); TargetCard.hideCard(); return nil, nil
    end
    local char = State.LockedTarget.Character
    if not char then
        State.CurrentPart = nil; hideUI()
        ForceHit.onTargetChanged(false)
        if not Settings.PersistLockOnDeath then
            clearTargetState(true); TargetCard.bumpToggleId(); TargetCard.hideCard()
        end
        return nil, nil
    end

    if Settings.DeathCheck and isDeathCheckState(char) then
        State.CurrentPart = nil; hideUI()
        State.Enabled = false
        ForceHit.onTargetChanged(false)
        clearTargetState(true); TargetCard.bumpToggleId(); TargetCard.hideCard()
        return nil, nil
    end

    local part, lockedChar = getTargetPartForPlayer(State.LockedTarget)
    if not part then
        State.CurrentPart = nil; hideUI()
        ForceHit.onTargetChanged(false)
        if not Settings.PersistLockOnDeath then
            clearTargetState(true); TargetCard.bumpToggleId(); TargetCard.hideCard()
        end
        return nil, nil
    end
    return part, lockedChar
end

local function tryRetarget(force)
    if not isAutoMode() and not State.Enabled then return false end
    if not isTargetFeatureAllowed() then return false end
    local now = os.clock()
    local retargetInterval = Settings.RetargetInterval or 0.15
    if not force and (now - State.LastRetarget) < retargetInterval then return false end
    State.LastRetarget = now
    return lockClosestTarget()
end

local sharedDeps = {
    Camera                 = Camera,
    Settings               = Settings,
    settings               = settings,
    State                  = State,
    safeCall               = safeCall,
    isUnloaded             = isUnloaded,
    MainEvent              = MainEvent,
    GH                     = GH,
    cloneArgs              = cloneArgs,
    applyRangePolicy       = applyRangePolicy,
    getSpreadAimPosition   = getSpreadAimPosition,
    getCamlockAimPosition  = getCamlockAimPosition,
    isTargetFeatureAllowed = isTargetFeatureAllowed,
    isStoredShootArgsValid = isStoredShootArgsValid,
    SHOOT_CMD              = SHOOT_CMD,
    LP                     = LP,
    Players                = Players,
    UIS                    = UIS,
}

local function mergeDeps(extra)
    local t = {}
    for k, v in pairs(sharedDeps) do t[k] = v end
    for k, v in pairs(extra) do t[k] = v end
    return t
end

ClosestPoint.init(mergeDeps({ BODY_PART_NAMES = BodyParts }))

ESP.init(mergeDeps({ screenGui = screenGui }))

TargetCard.init(mergeDeps({ screenGui = screenGui, ESP = ESP }))

Features.init(mergeDeps({}))

Hooks.init(mergeDeps({
    oldShoot       = oldShoot,
    mt             = mt,
    oldNamecall    = oldNamecall,
}))

Hooks.install()
Visuals.init(mergeDeps({ screenGui = screenGui, ForceHitModule = ForceHit, ESPModule = ESP, BODY_PART_NAMES = BodyParts }))

ForceHit.init(mergeDeps({}))
DelayChanger.init(mergeDeps({}))

local function cleanup()
    if State.Unloaded then return end
    State.Unloaded = true
    ClosestPoint.pruneCaches(true)
    TargetCard.bumpToggleId()
    ForceHit.cleanup()
    DelayChanger.cleanup()
    State.FakePart, State.FakePos = nil, nil
    State.CurrentPart = nil; State.LockedTarget = nil; State.LastShootData = nil
    State.TriggerbotHoldActive = false; State.TriggerbotToggleActive = false
    State.CamlockHoldActive = false; State.CamlockToggleActive = false
    State.CardCapabilityBlocked = false; State.ESPEnabled = false; State.SpeedActive = false
    clearDeathCheckConn()
    Features.resetSpeedModification()
    State.Enabled = false
    clearTargetState(true)
    disconnectAllTracked(); State.Connections = {}
    ESP.cleanupEsp()
    hideUI()
    safeCall(function()
        if TargetLine then TargetLine.Visible = false; TargetLine:Remove(); TargetLine = nil end
    end, "CleanupFails")
    Features.cleanupFOVBox()
    Visuals.cleanup()
    safeCall(function() TargetCard.destroyCard() end, "CleanupFails")
    safeCall(function() if screenGui and screenGui.Parent then screenGui:Destroy() end end, "CleanupFails")
    Hooks.uninstall()
    if GENV.__SilentAimCleanup == cleanup then GENV.__SilentAimCleanup = nil end
end

GENV.__SilentAimCleanup = cleanup

connect(UIS.InputBegan, function(input, gpe)
    if State.Unloaded or gpe then return end
    local triggerKey = getTriggerbotKeyCode()
    local camlockKey = getCamlockKeyCode()
    local toggleKey = getToggleKeyCode()
    local isTriggerKey = triggerKey and input.KeyCode == triggerKey and Settings.TriggerbotEnabled
    local isCamlockKey = camlockKey and input.KeyCode == camlockKey and Settings.CamlockEnabled
    local isToggleKey = toggleKey and input.KeyCode == toggleKey and isTargetFeatureAllowed() and not isAutoMode()
    local triggerClickType = string.lower(tostring(Settings.TriggerbotClickType or "Hold"))
    local camlockClickType = string.lower(tostring(Settings.CamlockClickType or "Hold"))

    if isTriggerKey and triggerClickType ~= "toggle" then
        State.TriggerbotHoldActive = true
    end

    if isCamlockKey and camlockClickType ~= "toggle" then
        State.CamlockHoldActive = true
    end

    if isToggleKey then
        if State.LockedTarget then
            State.Enabled = false
            clearTargetState(true); hideUI()
            ForceHit.onTargetChanged(false)
            TargetCard.bumpToggleId(); TargetCard.hideCard()
        else
            local _, candidate = getClosestPlayerAndPart()
            if not candidate then
                State.Enabled = false
                clearCombatState(true)
                hideUI()
            else
                State.Enabled = true
                State.LastRetarget = 0
                local locked = tryRetarget(true)
                if not locked then
                    State.Enabled = false
                    clearCombatState(true)
                    hideUI()
                else
                    ForceHit.onTargetChanged(true)
                end
            end
        end
    end

    if isTriggerKey and triggerClickType == "toggle" then
        if State.TriggerbotToggleActive then
            State.TriggerbotToggleActive = false
        elseif hasValidLockedTarget() then
            State.TriggerbotToggleActive = true
        end
    end

    if isCamlockKey and camlockClickType == "toggle" then
        if State.CamlockToggleActive then
            State.CamlockToggleActive = false
        else
            local camlockPart = getClosestCamlockPart()
            if camlockPart then
                State.CamlockToggleActive = true
            end
        end
    end

    if isToggleKey then
        return
    end
    local speedKey = getSpeedKeyCode()
    if speedKey and input.KeyCode == speedKey then
        if not Settings.SpeedEnabled then return end
        State.SpeedActive = not State.SpeedActive
        if not State.SpeedActive then Features.resetSpeedModification() end
        return
    end
    local espKey = getESPKeyCode()
    if espKey and input.KeyCode == espKey then
        if not Settings.ESPAllowed then return end
        State.ESPEnabled = not State.ESPEnabled
        if not State.ESPEnabled then
            ESP.hideAllEsp()
        else
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LP then ESP.createPlayerEsp(player) end
            end
        end
        return
    end
    local panicKey = getPanicGroundKeyCode()
    if panicKey and input.KeyCode == panicKey and Settings.PanicGroundEnabled then
        Features.panicGround(); return
    end
end)

connect(UIS.InputEnded, function(input, gpe)
    if State.Unloaded or gpe then return end
    local triggerKey = getTriggerbotKeyCode()
    local camlockKey = getCamlockKeyCode()
    if triggerKey and input.KeyCode == triggerKey and Settings.TriggerbotEnabled then
        State.TriggerbotHoldActive = false
    end
    if camlockKey and input.KeyCode == camlockKey and Settings.CamlockEnabled then
        State.CamlockHoldActive = false
    end
end)

connect(LP.CharacterAdded, function()
    if State.Unloaded then return end
    clearCombatState(true)
    State.SpeedCharacter = nil; State.DefaultWalkSpeed = nil; State.SpeedStatesPatched = false
end)

connect(RunService.RenderStepped, function(deltaTime)
    if State.Unloaded then return end
    if Camera ~= workspace.CurrentCamera then Camera = workspace.CurrentCamera end
    ClosestPoint.pruneCaches(false)
    enforceDeathCheckOnCurrentLock()
    ESP.updateEsp()
    Visuals.update()
    local equippedTool = Features.getEquippedTool()
    Features.applySpeedModification(equippedTool, deltaTime)
    local camlockPart = getClosestCamlockPart()
    local camlockBox  = Features.runCamlock(camlockPart)
    Features.updateCamlockFOVBox(camlockPart, camlockBox)
    local triggerbotPart = getClosestTriggerbotPart()
    local triggerbotBox  = Features.runTriggerbot(triggerbotPart)
    Features.updateTriggerbotFOVBox(triggerbotPart, triggerbotBox)
    if not isTargetFeatureAllowed() then
        hideUI()
        if State.Enabled or State.LockedTarget then
            State.Enabled = false; clearTargetState(true)
            ForceHit.onTargetChanged(false)
            TargetCard.bumpToggleId(); TargetCard.hideCard()
        end
        return
    end
    if not State.Enabled and not isAutoMode() then hideUI(); return end
    if isAutoMode() then
        local prevTarget = State.LockedTarget
        tryRetarget(false)
        State.Enabled = State.LockedTarget ~= nil
        if State.LockedTarget ~= prevTarget then
            ForceHit.onTargetChanged(State.LockedTarget ~= nil)
        end
    end
    if State.LockedTarget then
        if cfgEnabled({"Main", "Target Card"}, true) then
            TargetCard.updateCardStats(State.LockedTarget)
        else
            TargetCard.bumpToggleId(); TargetCard.hideCard()
        end
    end
    local aimPart, lockedChar = ensureValidLockedTarget()
    if not aimPart then clearCombatState(true); hideUI(); return end
    local canUseAimPart = resolveCurrentPartFromLinePart(aimPart) ~= nil
    State.CurrentPart = canUseAimPart and aimPart or nil

    local lineAnchorPart = (lockedChar and lockedChar:FindFirstChild("Head")) or aimPart
    local screenPos, onScreen = Camera:WorldToViewportPoint(lineAnchorPart.Position)
    if not onScreen or screenPos.Z <= 0 then hideUI(); return end
    local mousePos = UIS:GetMouseLocation()
    if Settings.VisCheck then
        TargetLine.Color = canUseAimPart and Settings.LineColorVisible or Settings.LineColorBlocked
    else
        TargetLine.Color = Settings.LineColor or Color3.fromRGB(0, 255, 255)
    end
    TargetLine.Visible = Settings.LineEnabled ~= false
    TargetLine.From    = Vector2.new(mousePos.X, mousePos.Y)
    TargetLine.To      = Vector2.new(screenPos.X, screenPos.Y)
end)

State.ESPEnabled = Settings.ESPAllowed ~= false

for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LP then ESP.createPlayerEsp(player); ESP.watchEspPlayer(player) end
end

connect(Players.PlayerAdded, function(player)
    if State.Unloaded or player == LP then return end
    ESP.watchEspPlayer(player)
    if player.Character then ESP.createPlayerEsp(player) end
end)

connect(Players.PlayerRemoving, function(player)
    if State.Unloaded then return end
    ClosestPoint.pruneCaches(true)
    ESP.removePlayerEsp(player)
    if State.LockedTarget == player then
        clearTargetState(true); hideUI()
        ForceHit.onTargetChanged(false)
        TargetCard.bumpToggleId(); TargetCard.hideCard()
    end
end)