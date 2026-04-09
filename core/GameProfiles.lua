local GameProfiles = {}

local KNOWN_PROFILES_BY_PLACE_ID = {
    [127163360850090] = {
        Name = "Dashood",
        PlaceId = 127163360850090,
        -- Keep empty for now to avoid behavior regressions on the game that is already tuned.
        -- Add per-game overrides here when onboarding additional experiences.
        Patch = {},
    },
    [99427474123086] = {
        Name    = "NewGame",
        PlaceId = 99427474123086,
        -- Different architecture: no GunHandler, uses MainRemotes.MainRemoteEvent,
        -- fires "GunFired" with a table payload instead of positional ShootGun args.
        Style   = "newgame",
        Patch   = {},
    },
}

local function deepMerge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            local node = dst[k]
            if type(node) ~= "table" then
                node = {}
                dst[k] = node
            end
            deepMerge(node, v)
        else
            dst[k] = v
        end
    end
end

local function resolve(placeId, universeId, overridePlaceId)
    local id = tonumber(overridePlaceId) or tonumber(placeId)
    if id and KNOWN_PROFILES_BY_PLACE_ID[id] then return KNOWN_PROFILES_BY_PLACE_ID[id] end
    -- Also check by universe/game ID so the caller can pass either game.PlaceId
    -- or game.GameId and the correct profile will still be found.
    local uid = tonumber(universeId)
    if uid and KNOWN_PROFILES_BY_PLACE_ID[uid] then return KNOWN_PROFILES_BY_PLACE_ID[uid] end
    return nil
end

local function apply(settings, profile)
    if type(settings) ~= "table" or type(profile) ~= "table" then return false end
    local patch = profile.Patch
    if type(patch) ~= "table" then return false end
    deepMerge(settings, patch)
    return true
end

local function getKnownPlaceIds()
    local out = {}
    for placeId in pairs(KNOWN_PROFILES_BY_PLACE_ID) do
        out[#out + 1] = placeId
    end
    table.sort(out)
    return out
end

GameProfiles.resolve = resolve
GameProfiles.apply = apply
GameProfiles.getKnownPlaceIds = getKnownPlaceIds

return GameProfiles
