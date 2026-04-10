
local LP = game:GetService("Players").LocalPlayer
local clock = os.clock
local VirtualInputManager

pcall(function()
	VirtualInputManager = game:GetService("VirtualInputManager")
end)

local Settings, isUnloaded
local gameStyle
local connections = {}
local patchedDelay = {}
local patchedRange = {}
local patchedAmmo = {}
local ammoConnections = {}

local INFINITE_AMMO_VALUE = 9999
local AUTO_RELOAD_MIN_INTERVAL = 0.85
local DEFAULT_FALLBACK_CLIP = 12
local FALLBACK_CLIPS = {
	["[Revolver]"] = 6,
	["[Double-Barrel SG]"] = 2,
	["[TacticalShotgun]"] = 5,
	["[Shotgun]"] = 5,
	["[Drum-Shotgun]"] = 8,
	["[SMG]"] = 25,
	["[AR]"] = 30,
}

local function getDelay(toolName)
	local delays = Settings.CustomDelays
	if type(delays) ~= "table" or delays["Enabled"] == false then return nil end
	local v = delays[toolName]
	return (type(v) == "number" and v >= 0) and v or nil
end

local function getDesiredRange()
	if Settings.InfiniteRange then
		return 1e9
	end
	return nil
end

local function getDesiredAmmo()
	if gameStyle ~= "zeehood" then return nil end
	if Settings.InfiniteAmmo then
		return INFINITE_AMMO_VALUE
	end
	return nil
end

local function getReloadFlag()
	local char = LP.Character
	local be = char and char:FindFirstChild("BodyEffects")
	if not be then return nil end
	return be:FindFirstChild("Reload") or be:FindFirstChild("Reloading")
end

local function estimateClipSize(toolName, observed)
	local n = tonumber(observed)
	if n and n >= 1 and n <= 200 then
		return math.floor(n + 0.5)
	end
	return FALLBACK_CLIPS[toolName] or DEFAULT_FALLBACK_CLIP
end

local function tryTriggerZeehoodReload(entry)
	if gameStyle ~= "zeehood" then return end
	if not Settings.InfiniteAmmo then return end

	local now = clock()
	if now - (entry.lastReloadAt or 0) < AUTO_RELOAD_MIN_INTERVAL then return end

	local reloadFlag = getReloadFlag()
	if reloadFlag and reloadFlag.Value == true then return end

	entry.lastReloadAt = now
	if not VirtualInputManager or not VirtualInputManager.SendKeyEvent then return end

	pcall(VirtualInputManager.SendKeyEvent, VirtualInputManager, true, Enum.KeyCode.R, false, game)
	task.delay(0.03, function()
		pcall(VirtualInputManager.SendKeyEvent, VirtualInputManager, false, Enum.KeyCode.R, false, game)
	end)
end

local function readUpvalue(fn, i)
	local ok, a, b = pcall(debug.getupvalue, fn, i)
	if not ok then return nil, false end
	return (b ~= nil) and b or a, true
end

local function scanUpvalues(fn, target)
	local bestIdx, bestVal
	for i = 1, 64 do
		local val, ok = readUpvalue(fn, i)
		if not ok then break end
		if type(val) == "number" and math.abs(val - target) < 0.001 then
			bestIdx, bestVal = i, val
		end
	end
	return bestIdx and fn or nil, bestIdx, bestVal
end

local function findViaConnections(tool, cd)
	local ok, conns = pcall(getconnections, tool.Activated)
	if not ok or not conns then return nil, nil, nil end
	for _, conn in ipairs(conns) do
		if conn.Function then
			local f, idx, val = scanUpvalues(conn.Function, cd)
			if f then return f, idx, val end
		end
	end
	return nil, nil, nil
end

local function findViaGC(tool, cd)
	if not getgc then return nil, nil, nil end
	local ok, gc = pcall(getgc)
	if not ok or not gc then return nil, nil, nil end
	for _, obj in ipairs(gc) do
		if type(obj) ~= "function" then continue end
		local refs = false
		for i = 1, 64 do
			local val, valid = readUpvalue(obj, i)
			if not valid then break end
			if val == tool then refs = true; break end
		end
		if refs then
			local f, idx, val = scanUpvalues(obj, cd)
			if f then return f, idx, val end
		end
	end
	return nil, nil, nil
end

local function findViaConfigTable(tool)
	local ok, conns = pcall(getconnections, tool.Activated)
	if not ok or not conns then return nil end
	for _, conn in ipairs(conns) do
		local fn = conn.Function
		if not fn then continue end
		for i = 1, 64 do
			local val, valid = readUpvalue(fn, i)
			if not valid then break end
			if type(val) == "table"
				and type(val["Cooldown"]) == "number"
				and val["Cooldown"] > 0 then
				return val
			end
		end
	end
	return nil
end

local function findViaRangeConfigTable(tool)
	local ok, conns = pcall(getconnections, tool.Activated)
	if not ok or not conns then return nil end
	for _, conn in ipairs(conns) do
		local fn = conn.Function
		if not fn then continue end
		for i = 1, 64 do
			local val, valid = readUpvalue(fn, i)
			if not valid then break end
			if type(val) == "table"
				and type(val["Range"]) == "number"
				and val["Range"] > 0 then
				return val
			end
		end
	end
	return nil
end

-- Returns a mode-tagged handle describing how to get/set the cooldown for a tool.
local function findCooldownAny(tool)
	-- Try ShootingCooldown-value based approach first (Dashood style).
	local cdObj = tool:FindFirstChild("ShootingCooldown")
	if cdObj then
		local cd = cdObj.Value
		local fn, idx, val = findViaConnections(tool, cd)
		if not fn then fn, idx, val = findViaGC(tool, cd) end
		if fn then
			return { mode = "upvalue", fn = fn, idx = idx, original = val }
		end
	end
	-- Fallback: config-table cooldown (zeehood style, e.g. {["Cooldown"]=0.13,...}).
	local configTable = findViaConfigTable(tool)
	if configTable then
		return { mode = "config", tbl = configTable, original = configTable["Cooldown"] }
	end
	return nil
end

local function findRangeAny(tool)
	local rangeObj = tool:FindFirstChild("Range")
	if rangeObj and type(rangeObj.Value) == "number" then
		return { mode = "instance", obj = rangeObj, original = rangeObj.Value }
	end

	local configTable = findViaRangeConfigTable(tool)
	if configTable then
		return { mode = "config", tbl = configTable, original = configTable["Range"] }
	end

	return nil
end

local function restoreDelay(tool)
	local saved = patchedDelay[tool]
	if not saved then return end
	if saved.mode == "config" then
		pcall(function() saved.tbl["Cooldown"] = saved.original end)
	else
		pcall(debug.setupvalue, saved.fn, saved.idx, saved.original)
	end
	patchedDelay[tool] = nil
end

local function restoreRange(tool)
	local saved = patchedRange[tool]
	if not saved then return end

	if saved.mode == "config" then
		pcall(function() saved.tbl["Range"] = saved.original end)
	else
		pcall(function() saved.obj.Value = saved.original end)
	end

	patchedRange[tool] = nil
end

local function disconnectAmmoWatcher(tool)
	local conn = ammoConnections[tool]
	if conn then
		pcall(conn.Disconnect, conn)
		ammoConnections[tool] = nil
	end
end

local function restoreAmmo(tool)
	disconnectAmmoWatcher(tool)
	local saved = patchedAmmo[tool]
	if not saved then return end
	pcall(function()
		if saved.obj and saved.obj.Parent then
			saved.obj.Value = saved.original
		end
	end)
	patchedAmmo[tool] = nil
end

local function applyAmmo(tool)
	local desired = getDesiredAmmo()
	if desired == nil then
		restoreAmmo(tool)
		return
	end

	local ammoObj = tool:FindFirstChild("Ammo")
	if not ammoObj then
		restoreAmmo(tool)
		return
	end

	local saved = patchedAmmo[tool]
	if not saved or saved.obj ~= ammoObj then
		restoreAmmo(tool)
		patchedAmmo[tool] = {
			obj = ammoObj,
			original = ammoObj.Value,
			clipSize = estimateClipSize(tool.Name, ammoObj.Value),
			consumed = 0,
			lastReloadAt = 0,
		}
	end

	pcall(function()
		if ammoObj.Value < desired then
			ammoObj.Value = desired
		end
	end)

	if not ammoConnections[tool] then
		ammoConnections[tool] = ammoObj:GetPropertyChangedSignal("Value"):Connect(function()
			if isUnloaded() then return end
			if gameStyle ~= "zeehood" or not Settings.InfiniteAmmo then return end

			local entry = patchedAmmo[tool]
			if not entry then return end

			local current = tonumber(ammoObj.Value) or 0
			if current < desired then
				entry.consumed = entry.consumed + (desired - current)
				if entry.consumed >= math.max(1, entry.clipSize - 1) then
					entry.consumed = 0
					tryTriggerZeehoodReload(entry)
				end
			end

			pcall(function()
				if ammoObj.Parent and ammoObj.Value < desired then
					ammoObj.Value = desired
				end
			end)
		end)
	end
end

local function apply(tool)
	if not tool then return end

	-- Delay patching
	local delay = getDelay(tool.Name)
	if delay == nil then
		restoreDelay(tool)
	else
		if patchedDelay[tool] then
			if patchedDelay[tool].mode == "config" then
				pcall(function() patchedDelay[tool].tbl["Cooldown"] = delay end)
			else
				pcall(debug.setupvalue, patchedDelay[tool].fn, patchedDelay[tool].idx, delay)
			end
		else
			local handle = findCooldownAny(tool)
			if handle then
				patchedDelay[tool] = handle
				if handle.mode == "config" then
					handle.tbl["Cooldown"] = delay
				else
					debug.setupvalue(handle.fn, handle.idx, delay)
				end
			end
		end
	end

	-- Infinite range patching
	applyAmmo(tool)

	local desiredRange = getDesiredRange()
	if desiredRange == nil then
		restoreRange(tool)
		return
	end

	if patchedRange[tool] then
		if patchedRange[tool].mode == "config" then
			pcall(function() patchedRange[tool].tbl["Range"] = desiredRange end)
		else
			pcall(function() patchedRange[tool].obj.Value = desiredRange end)
		end
		return
	end

	local rangeHandle = findRangeAny(tool)
	if not rangeHandle then return end
	patchedRange[tool] = rangeHandle
	if rangeHandle.mode == "config" then
		rangeHandle.tbl["Range"] = desiredRange
	else
		rangeHandle.obj.Value = desiredRange
	end
end

local function patchAll()
	for _, container in ipairs({LP.Character, LP:FindFirstChild("Backpack")}) do
		if not container then continue end
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") then
				apply(child)
			end
		end
	end
end

local function disconnectAll()
	for _, conn in pairs(connections) do
		pcall(conn.Disconnect, conn)
	end
	connections = {}
end

local function onCharacterAdded(char)
	disconnectAll()
	patchAll()

	connections.equipped = char.ChildAdded:Connect(function(child)
		if isUnloaded() then return end
		if child:IsA("Tool") then
			task.defer(apply, child)
		end
	end)

	local bp = LP:FindFirstChild("Backpack") or LP:WaitForChild("Backpack", 5)
	if bp then
		connections.pickup = bp.ChildAdded:Connect(function(child)
			if isUnloaded() then return end
			if not child:IsA("Tool") then return end
			task.wait(0.5)
			apply(child)
		end)
	end
end

local function cleanup()
	disconnectAll()
	for tool in pairs(patchedDelay) do
		restoreDelay(tool)
	end
	for tool in pairs(patchedRange) do
		restoreRange(tool)
	end
	for tool in pairs(patchedAmmo) do
		restoreAmmo(tool)
	end
	patchedDelay = {}
	patchedRange = {}
	patchedAmmo = {}
end

local function init(deps)
	Settings   = deps.Settings
	isUnloaded = deps.isUnloaded
	gameStyle  = deps.gameStyle

	local char = LP.Character
	if char then onCharacterAdded(char) end

	LP.CharacterAdded:Connect(function(newChar)
		if isUnloaded() then return end
		task.wait(0.5)
		onCharacterAdded(newChar)
	end)
end

return { init = init, cleanup = cleanup }
