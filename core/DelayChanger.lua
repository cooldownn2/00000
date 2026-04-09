
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

local function restore(tool)
	local saved = patched[tool]
	if not saved then return end
	if saved.mode == "config" then
		pcall(function() saved.tbl["Cooldown"] = saved.original end)
	else
		pcall(debug.setupvalue, saved.fn, saved.idx, saved.original)
	end
	patched[tool] = nil
end

local function apply(tool)
	if not tool then return end
	local delay = getDelay(tool.Name)
	if delay == nil then restore(tool); return end
	if patched[tool] then
		if patched[tool].mode == "config" then
			pcall(function() patched[tool].tbl["Cooldown"] = delay end)
		else
			pcall(debug.setupvalue, patched[tool].fn, patched[tool].idx, delay)
		end
		return
	end
	local handle = findCooldownAny(tool)
	if not handle then return end
	patched[tool] = handle
	if handle.mode == "config" then
		handle.tbl["Cooldown"] = delay
	else
		debug.setupvalue(handle.fn, handle.idx, delay)
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
