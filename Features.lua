local Features = {}

local Movement
local AimAssist
local FOVBoxes

local function init(deps)
    Movement = deps.Movement
    AimAssist = deps.AimAssist
    FOVBoxes = deps.FOVBoxes

    if not Movement or not AimAssist or not FOVBoxes then
        error("Features.init missing modular dependencies", 2)
    end

    Movement.init(deps)

    AimAssist.init({
        Settings = deps.Settings,
        State = deps.State,
        safeCall = deps.safeCall,
        Camera = deps.Camera,
        getCamlockAimPosition = deps.getCamlockAimPosition,
        Movement = Movement,
    })

    FOVBoxes.init({
        Settings = deps.Settings,
    })
end

Features.init = init

Features.applySpeedModification = function(tool, deltaTime)
    return Movement.applySpeedModification(tool, deltaTime)
end

Features.resetSpeedModification = function()
    return Movement.resetSpeedModification()
end

Features.panicGround = function()
    return Movement.panicGround()
end

Features.runTriggerbot = function(part)
    return AimAssist.runTriggerbot(part)
end

Features.runCamlock = function(part)
    return AimAssist.runCamlock(part)
end

Features.updateTriggerbotFOVBox = function(targetPart)
    return FOVBoxes.updateTriggerbotFOVBox(targetPart)
end

Features.updateCamlockFOVBox = function(targetPart)
    return FOVBoxes.updateCamlockFOVBox(targetPart)
end

Features.updateSilentAimFOVBox = function(targetPart)
    return FOVBoxes.updateSilentAimFOVBox(targetPart)
end

Features.hideTriggerbotFOVBox = function()
    return FOVBoxes.hideTriggerbotFOVBox()
end

Features.hideCamlockFOVBox = function()
    return FOVBoxes.hideCamlockFOVBox()
end

Features.hideSilentAimFOVBox = function()
    return FOVBoxes.hideSilentAimFOVBox()
end

Features.cleanupFOVBox = function()
    return FOVBoxes.cleanupFOVBox()
end

Features.isPartInsideSilentAimFOV = function(part)
    return AimAssist.isPartInsideSilentAimFOV(part)
end

Features.isPartInTriggerDistance = function(part)
    return AimAssist.isPartInTriggerDistance(part)
end

Features.isPartInCamlockDistance = function(part)
    return AimAssist.isPartInCamlockDistance(part)
end

Features.getEquippedTool = function()
    return Movement.getEquippedTool()
end

Features.isKnifeTool = function(tool)
    return Movement.isKnifeTool(tool)
end

Features.getReloadingFlag = function(char)
    return Movement.getReloadingFlag(char)
end

return Features