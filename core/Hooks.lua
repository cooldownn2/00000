local State, safeCall
local GH, MainEvent, oldShoot, mt, oldNamecall, oldIndex
local isStoredShootArgsValid
local Taps
local SilentAim
local Settings
local LP
local hookedShoot, hookedNamecall, hookedIndex
local gameStyle

local function setReadOnlySafe(value)
    if setreadonly then setreadonly(mt, value) end
end

local function buildHooks()
    hookedShoot = function(data)
        if State.Unloaded then return oldShoot(data) end
        local shootData = data
        if type(data) == "table" then
            shootData = SilentAim.prepareShootData(data)
        end
        return oldShoot(shootData)
    end

    hookedIndex = function(self, key)
        if State.Unloaded then return oldIndex(self, key) end

        return oldIndex(self, key)
    end

    hookedNamecall = function(self, ...)
        if State.Unloaded then return oldNamecall(self, ...) end
        if getnamecallmethod() ~= "FireServer" or not rawequal(self, MainEvent) then
            return oldNamecall(self, ...)
        end
        local args = {...}

        if gameStyle == "zeehood" then
            -- Zeehood: redirect the payload in-place (keeps StartPoint at muzzle
            -- so server validates properly) then send a single modified shot.
            if isStoredShootArgsValid(args) then
                pcall(SilentAim.recordShootArgs, args)

                -- Redirect HitPosition/Pellets/HitInstance to locked target.
                pcall(function()
                    if SilentAim.redirectZeehoodPayload then
                        SilentAim.redirectZeehoodPayload(args[2])
                    end
                end)

                local tapCount = 1
                pcall(function() tapCount = Taps.getTapCount(args) end)

                oldNamecall(self, table.unpack(args))
                for _ = 2, tapCount do
                    oldNamecall(self, table.unpack(args))
                end
                return nil
            end
            oldNamecall(self, ...)
            return nil
        end

        -- Dashood / positional-args style.
        SilentAim.recordShootArgs(args)
        if SilentAim.shouldRedirectFireServer(args) then
            SilentAim.applyFireServerRedirect(args)
            oldNamecall(self, table.unpack(args))
            -- Tap extra shots: call oldNamecall directly (bypasses hook) so
            -- SkipNextFireServer is never needed and can't be left dirty.
            local extra = Taps.getTapCount(args) - 1
            for _ = 1, extra do
                oldNamecall(self, table.unpack(args))
            end
            return nil
        end
        if isStoredShootArgsValid(args) then
            oldNamecall(self, ...)
            local extra = Taps.getTapCount(args) - 1
            for _ = 1, extra do
                oldNamecall(self, table.unpack(args))
            end
            return nil
        end
        oldNamecall(self, ...)
        return nil
    end
end

local function install()
    -- Hooks are built once in init; install just wires them in.
    if GH.shoot ~= hookedShoot then GH.shoot = hookedShoot end
    setReadOnlySafe(false)
    if mt.__index ~= hookedIndex then mt.__index = hookedIndex end
    if mt.__namecall ~= hookedNamecall then mt.__namecall = hookedNamecall end
    setReadOnlySafe(true)
end

local function uninstall()
    if GH.shoot == hookedShoot then GH.shoot = oldShoot end
    safeCall(function()
        setReadOnlySafe(false)
        if mt.__index == hookedIndex then mt.__index = oldIndex end
        if mt.__namecall == hookedNamecall then mt.__namecall = oldNamecall end
        setReadOnlySafe(true)
    end, "CleanupFails")
end

local function init(deps)
    State                  = deps.State
    safeCall               = deps.safeCall
    GH                     = deps.GH
    MainEvent              = deps.MainEvent
    oldShoot               = deps.oldShoot
    mt                     = deps.mt
    oldNamecall            = deps.oldNamecall
    oldIndex               = deps.oldIndex
    isStoredShootArgsValid = deps.isStoredShootArgsValid
    Taps                   = deps.Taps
    SilentAim              = deps.SilentAim
    Settings               = deps.Settings
    LP                     = deps.LP
    gameStyle              = deps.gameStyle
    SilentAim.init(deps)
    -- Build closures once here so install() just wires them in without re-allocating.
    buildHooks()
end

return {
    init      = init,
    install   = install,
    uninstall = uninstall,
}
