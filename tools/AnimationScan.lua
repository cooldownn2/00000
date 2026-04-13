return function(targetInput)
    local env = (getgenv and getgenv()) or _G
    local api = env and env.AvatarSpoofer

    if type(api) ~= "table" or type(api.ScanAnimations) ~= "function" then
        warn("[AnimationScan] AvatarSpoofer.ScanAnimations is unavailable. Load sauce.lua first.")
        return nil
    end

    local target = targetInput
    if target == nil or tostring(target):gsub("^%s+", ""):gsub("%s+$", "") == "" then
        target = "7450926784"
    end

    local report, err = api.ScanAnimations(target)
    if err then
        warn("[AnimationScan] failed: " .. tostring(err))
        return nil
    end
    if type(report) ~= "table" or type(report.slots) ~= "table" then
        warn("[AnimationScan] invalid report payload")
        return nil
    end

    print("[AnimationScan] userId=", tostring(report.userId), " target=", tostring(target))

    local orderedSlots = { "run", "walk", "idle", "jump", "fall", "climb", "swim" }
    for _, slot in ipairs(orderedSlots) do
        local d = report.slots[slot] or {}
        print(
            "[AnimationScan]",
            slot,
            "field=", tostring(d.field),
            "raw=", tostring(d.raw),
            "resolved=", tostring(d.resolved),
            "resolvedNumeric=", tostring(d.resolvedNumeric)
        )
    end

    return report
end
