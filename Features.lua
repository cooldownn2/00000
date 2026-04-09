local Features = {}

local Movement, AimAssist, FOVBoxes

local function init(deps)
    Movement  = deps.Movement
    AimAssist = deps.AimAssist
    FOVBoxes  = deps.FOVBoxes
    if not Movement or not AimAssist or not FOVBoxes then
        error("Features.init missing modular dependencies", 2)
    end
    Movement.init(deps)
    AimAssist.init({
        Settings              = deps.Settings,
        State                 = deps.State,
        safeCall              = deps.safeCall,
        Camera                = deps.Camera,
        getCamlockAimPosition = deps.getCamlockAimPosition,
        Movement              = Movement,
    })
    FOVBoxes.init({
        Settings                = deps.Settings,
        UIS                     = deps.UIS,
        getTriggerbotBoxForPart = AimAssist.getTriggerbotBoxForPart,
        getCamlockBoxForPart    = AimAssist.getCamlockBoxForPart,
    })
end

Features.init = init

Features.applySpeedModification  = function(tool, deltaTime) return Movement.applySpeedModification(tool, deltaTime) end
Features.resetSpeedModification  = function()                return Movement.resetSpeedModification() end
Features.panicGround             = function()                return Movement.panicGround() end

Features.runTriggerbot           = function(part)            return AimAssist.runTriggerbot(part) end
Features.runCamlock              = function(part)            return AimAssist.runCamlock(part) end
Features.isPartInTriggerDistance = function(part)            return AimAssist.isPartInTriggerDistance(part) end
Features.isPartInCamlockDistance = function(part)            return AimAssist.isPartInCamlockDistance(part) end

Features.updateTriggerbotFOVBox  = function(part, box)       return FOVBoxes.updateTriggerbotFOVBox(part, box) end
Features.updateCamlockFOVBox     = function(part, box)       return FOVBoxes.updateCamlockFOVBox(part, box) end
Features.hideTriggerbotFOVBox    = function()                return FOVBoxes.hideTriggerbotFOVBox() end
Features.hideCamlockFOVBox       = function()                return FOVBoxes.hideCamlockFOVBox() end
Features.cleanupFOVBox           = function()                return FOVBoxes.cleanupFOVBox() end

Features.getEquippedTool         = function()                return Movement.getEquippedTool() end
Features.isKnifeTool             = function(tool)            return Movement.isKnifeTool(tool) end
Features.getReloadingFlag        = function()                return Movement.getReloadingFlag() end