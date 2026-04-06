
local LP = game:GetService("Players").LocalPlayer

local Settings, isUnloaded
local connections = {}
local patched = {}

local function getDelay(toolName)
	local delays = Settings.CustomDelays
	if type(delays) ~= "table" or delays["Enabled"] == false then return nil end
	local v = delays[toolName]
	return (type(v) == "number" and v >= 0) and v or nil
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

local function findCooldownUpvalue(tool)
	local cdObj = tool:FindFirstChild("ShootingCooldown")
	if not cdObj then return nil, nil, nil end
	local cd = cdObj.Value
	local fn, idx, val = findViaConnections(tool, cd)
	if fn then return fn, idx, val end
	return findViaGC(tool, cd)
end

local function restore(tool)
	local saved = patched[tool]
	if not saved then return end
	pcall(debug.setupvalue, saved.fn, saved.idx, saved.original)
	patched[tool] = nil
end

local function apply(tool)
	if not tool then return end
	local delay = getDelay(tool.Name)
	if delay == nil then restore(tool); return end
	if patched[tool] then
		pcall(debug.setupvalue, patched[tool].fn, patched[tool].idx, delay)
		return
	end
	local fn, idx, original = findCooldownUpvalue(tool)
	if not fn then return end
	patched[tool] = { fn = fn, idx = idx, original = original }
	debug.setupvalue(fn, idx, delay)
end

local function patchAll()
	for _, container in ipairs({LP.Character, LP:FindFirstChild("Backpack")}) do
		if not container then continue end
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and child:FindFirstChild("ShootingCooldown") then
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
		if child:IsA("Tool") and child:FindFirstChild("ShootingCooldown") then
			task.defer(apply, child)
		end
	end)

	local bp = LP:FindFirstChild("Backpack") or LP:WaitForChild("Backpack", 5)
	if bp then
		connections.pickup = bp.ChildAdded:Connect(function(child)
			if isUnloaded() then return end
			if not child:IsA("Tool") then return end
			task.wait(0.5)
			if child:FindFirstChild("ShootingCooldown") then
				apply(child)
			end
		end)
	end
end

local function cleanup()
	disconnectAll()
	for tool in pairs(patched) do
		restore(tool)
	end
	patched = {}
end

local function init(deps)
	Settings   = deps.Settings
	isUnloaded = deps.isUnloaded

	local char = LP.Character
	if char then onCharacterAdded(char) end

	LP.CharacterAdded:Connect(function(newChar)
		if isUnloaded() then return end
		task.wait(0.5)
		onCharacterAdded(newChar)
	end)
end

return { init = init, cleanup = cleanup }
