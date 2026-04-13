local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local UserService = game:GetService("UserService")
local GuiService = game:GetService("GuiService")

local UISpoofer = {}
UISpoofer.__index = UISpoofer

local TEXT_CLASS_SET = { TextLabel = true, TextButton = true, TextBox = true }
local IMAGE_CLASS_SET = { ImageLabel = true, ImageButton = true }

local SYNC_INTERVAL = 2.00
local FAST_SYNC_INTERVAL = 0.25
local MENU_FAST_SYNC_DURATION = 0.80
local FAST_SYNC_DESC_KICK_COOLDOWN = 0.20
local IDENTITY_SPOOF_REAPPLY_INTERVAL = 1.50
local HOVER_ELIGIBILITY_CACHE_TTL = 2.00

local PEOPLE_CONTEXT_KEYWORDS = {
	"people", "playerlist", "ingamemenu", "social",
	"players", "playerlabel", "playerentry", "playerrow",
	"gamemenu", "coremenu", "menu", "list",
}

local LEADERBOARD_CONTEXT_KEYWORDS = {
	"leaderboard", "leaderstats", "scoreboard",
}

local ESCAPE_MENU_CONTEXT_KEYWORDS = {
	"ingamemenu", "playermenuscreen", "social", "people", "playermenu",
}

local GETGENV_FN = rawget(_G, "getgenv")

local function getExploitFunction(name)
	if type(name) ~= "string" or name == "" then return nil end
	local fn = rawget(_G, name)
	if type(fn) == "function" then return fn end
	if type(GETGENV_FN) == "function" then
		local ok, env = pcall(function() return GETGENV_FN() end)
		if ok and type(env) == "table" then
			local envFn = rawget(env, name)
			if type(envFn) == "function" then return envFn end
		end
	end
	return nil
end

local function trimString(raw)
	return tostring(raw or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalizeLower(raw)
	return string.lower(tostring(raw or ""))
end

local function normalizeTarget(raw)
	local t = tostring(raw or "")
	t = t:gsub("^@", ""):gsub("^rbx://users/", "")
	t = t:gsub("^https?://www%.roblox%.com/users/", "")
	t = t:gsub("/profile.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
	return t
end

local function looksUnresolvedName(name, userId)
	return tostring(name or "") == tostring(userId or "")
end

local function isLikelyPeopleContext(inst)
	local cur, depth = inst, 0
	while cur and depth < 25 do
		local n = normalizeLower(cur.Name)
		if n ~= "" and n ~= "playergui" then
			for _, kw in ipairs(PEOPLE_CONTEXT_KEYWORDS) do
				if n:find(kw, 1, true) then return true end
			end
		end
		cur = cur.Parent
		depth = depth + 1
	end
	return false
end

local function isLikelyLeaderboardContext(inst)
	local cur, depth = inst, 0
	local boardHit, escapeHit = false, false
	while cur and depth < 30 do
		local n = normalizeLower(cur.Name)
		if n ~= "" and n ~= "playergui" then
			for _, kw in ipairs(LEADERBOARD_CONTEXT_KEYWORDS) do
				if n:find(kw, 1, true) then boardHit = true break end
			end
			for _, kw in ipairs(ESCAPE_MENU_CONTEXT_KEYWORDS) do
				if n:find(kw, 1, true) then escapeHit = true break end
			end
		end
		cur = cur.Parent
		depth = depth + 1
	end
	return boardHit and not escapeHit
end

local function rowHasInspectActionMenu(row)
	if not row then return false end
	local ok, descs = pcall(function() return row:GetDescendants() end)
	if not ok or not descs then return false end
	local scanned = 0
	for _, inst in ipairs(descs) do
		scanned = scanned + 1
		if scanned > 500 then break end
		local n = normalizeLower(inst.Name)
		if n:find("examine", 1, true) or n:find("avatar", 1, true)
			or n:find("friend", 1, true) or n:find("block", 1, true) or n:find("report", 1, true) then
			if inst:IsA("GuiButton") or inst:IsA("Frame") then return true end
		end
		if TEXT_CLASS_SET[inst.ClassName] and inst.Visible then
			local t = normalizeLower(trimString(inst.Text))
			if t:find("examine", 1, true) or t:find("avatar", 1, true)
				or t:find("friend", 1, true) or t:find("block", 1, true) or t:find("report", 1, true) then
				return true
			end
		end
	end
	return false
end

local function isLeaderboardHoverEligible(row)
	if not row or not row:IsA("GuiObject") then return false end
	if not isLikelyLeaderboardContext(row) then return false end
	if row.AbsoluteSize.Y > 72 then return false end
	if rowHasInspectActionMenu(row) then return false end
	return true
end

local function scoreRow(row)
	if not row or not row:IsA("GuiObject") or not row.Visible then return nil end
	local sz = row.AbsoluteSize
	if sz.X <= 0 or sz.Y <= 0 or sz.X < 120 or sz.Y < 20 or sz.Y > 200 then return nil end
	if sz.X * sz.Y > 600000 then return nil end
	local s = 0
	local parent = row.Parent
	if parent and parent:FindFirstChildOfClass("UIListLayout") then s = s + 90 end
	if row:IsA("GuiButton") or row:FindFirstChildWhichIsA("GuiButton", true) then s = s + 45 end
	if row:FindFirstChildWhichIsA("TextLabel", true) or row:FindFirstChildWhichIsA("TextButton", true) then s = s + 35 end
	if row:FindFirstChildWhichIsA("ImageLabel", true) or row:FindFirstChildWhichIsA("ImageButton", true) then s = s + 25 end
	if sz.X >= 220 then s = s + 20 end
	if sz.Y >= 36 then s = s + 10 end
	return s > 0 and s or nil
end

local function rowFromText(textInst)
	local cur, depth, best, bestScore = textInst, 0, nil, nil
	while cur and depth < 10 do
		if cur:IsA("GuiObject") then
			local s = scoreRow(cur)
			if s and (not bestScore or s > bestScore) then
				best = cur
				bestScore = s
			end
			if s and s >= 150 then return cur end
		end
		cur = cur.Parent
		depth = depth + 1
	end
	if best then return best end
	if textInst and textInst.Parent and textInst.Parent:IsA("GuiObject") then return textInst.Parent end
	return nil
end

local function findNameLabels(row)
	if not row then return nil, nil end
	local labels = {}
	local ok, descs = pcall(function() return row:GetDescendants() end)
	if ok and descs then
		for _, inst in ipairs(descs) do
			if (inst:IsA("TextLabel") or inst:IsA("TextButton"))
				and inst.Visible and inst.AbsoluteSize.Y >= 12 and inst.AbsoluteSize.X >= 40 then
				local lowerText = normalizeLower(trimString(inst.Text))
				local ownerBtn = inst:FindFirstAncestorWhichIsA("GuiButton")
				local isAction = lowerText:find("examine", 1, true) or lowerText:find("avatar", 1, true)
					or lowerText:find("friend", 1, true) or lowerText:find("follow", 1, true)
					or lowerText:find("report", 1, true) or lowerText:find("block", 1, true)
				if (not ownerBtn or ownerBtn == row) and not isAction then
					labels[#labels + 1] = inst
				end
			end
		end
	end
	table.sort(labels, function(a, b)
		local ay, by = a.AbsolutePosition.Y, b.AbsolutePosition.Y
		if math.abs(ay - by) > 2 then return ay < by end
		return a.AbsolutePosition.X < b.AbsolutePosition.X
	end)
	local dn, un = nil, nil
	for _, lbl in ipairs(labels) do
		local n = normalizeLower(lbl.Name)
		local t = tostring(lbl.Text or "")
		if not un and (n:find("username", 1, true) or t:sub(1, 1) == "@") then un = lbl
		elseif not dn and (n:find("display", 1, true) or t:sub(1, 1) ~= "@") then dn = lbl end
	end
	return dn or labels[1], un or labels[2]
end

local function isAvatarThumb(img)
	local lower = normalizeLower(img)
	if lower == "" then return false end
	if lower:find("rbxthumb://", 1, true) then
		return lower:find("type=avatar", 1, true) ~= nil
			or lower:find("type=headshot", 1, true) ~= nil
			or lower:find("type=avatarheadshot", 1, true) ~= nil
			or lower:find("type=avatarbust", 1, true) ~= nil
	end
	local hasHost = lower:find("thumbnails.roblox.com", 1, true)
		or lower:find("thumbs.roblox.com", 1, true)
		or lower:find("avatar-thumbnail", 1, true)
		or lower:find("avatar-headshot", 1, true)
	if not hasHost then return false end
	local hasUser = lower:find("userid=", 1, true) or lower:find("userids=", 1, true) or lower:find("/users/", 1, true)
	local hasAvatar = lower:find("avatar", 1, true) or lower:find("headshot", 1, true) or lower:find("bust", 1, true)
	return hasUser and hasAvatar
end

function UISpoofer.new(deps)
	local self = setmetatable({}, UISpoofer)

	self.localPlayer = (deps and deps.localPlayer) or Players.LocalPlayer
	self.enabled = false

	self.localIdentitySeedName = nil
	self.localIdentitySeedDisplayName = nil
	local lp = self.localPlayer
	if lp then
		self.localIdentitySeedName = tostring(lp.Name or "")
		self.localIdentitySeedDisplayName = tostring(lp.DisplayName or "")
	end

	self.targetUserId = nil
	self.targetName = nil
	self.targetDisplayName = nil
	self.targetHeadshot = nil
	self.targetAvatarThumb = nil

	self.identitySpoofOriginalCaptured = false
	self.identitySpoofOriginalUserId = nil
	self.identitySpoofOriginalAppearanceId = nil
	self.identitySpoofOriginalName = nil
	self.identitySpoofOriginalDisplayName = nil

	self.identitySpoofApplied = false
	self.identitySpoofNameApplied = false
	self.identitySpoofDisplayNameApplied = false
	self.identitySpoofTargetUserId = nil
	self.nextIdentitySpoofReapplyAt = 0

	self.connections = {}
	self.rowHoverConnections = {}

	self.rowPrimaryLabelByRow = setmetatable({}, { __mode = "k" })
	self.rowHoverHookedByRow = setmetatable({}, { __mode = "k" })
	self.rowHoverStateByRow = setmetatable({}, { __mode = "k" })
	self.rowHoverEligibilityCache = setmetatable({}, { __mode = "k" })
	self.cachedSourceRows = setmetatable({}, { __mode = "k" })

	self.originalTextByLabel = {}
	self.originalImageByImage = {}

	self.syncPending = false
	self.syncRunning = false
	self.syncRerun = false
	self.lastSyncAt = 0
	self.fastSyncUntil = 0
	self.nextFastSyncKickAt = 0
	self.dirty = false

	self.debugSyncStats = nil
	self.profileFetchToken = 0

	return self
end

function UISpoofer:lp()
	local p = self.localPlayer
	if p and p.Parent then return p end
	p = Players.LocalPlayer
	if p then self.localPlayer = p end
	return p
end

function UISpoofer:getUiSearchRoots()
	local roots = { CoreGui }
	local lp = self:lp()
	local pg = lp and lp:FindFirstChildOfClass("PlayerGui") or nil
	if pg then roots[#roots + 1] = pg end
	return roots
end

function UISpoofer:captureLabelOriginal(lbl)
	if not lbl or not TEXT_CLASS_SET[lbl.ClassName] then return end
	if self.originalTextByLabel[lbl] ~= nil then return end
	local ok, current = pcall(function() return lbl.Text end)
	if ok then self.originalTextByLabel[lbl] = tostring(current or "") end
end

function UISpoofer:captureImageOriginal(img)
	if not img or not IMAGE_CLASS_SET[img.ClassName] then return end
	if self.originalImageByImage[img] ~= nil then return end
	local ok, current = pcall(function() return img.Image end)
	if ok then self.originalImageByImage[img] = tostring(current or "") end
end

function UISpoofer:restorePatchedRows()
	for lbl, original in pairs(self.originalTextByLabel) do
		if lbl and TEXT_CLASS_SET[lbl.ClassName] then pcall(function() lbl.Text = original end) end
	end
	for img, original in pairs(self.originalImageByImage) do
		if img and IMAGE_CLASS_SET[img.ClassName] then pcall(function() img.Image = original end) end
	end
	self.originalTextByLabel = {}
	self.originalImageByImage = {}
end

function UISpoofer:disconnectRowHoverConnections()
	for i = #self.rowHoverConnections, 1, -1 do
		local c = self.rowHoverConnections[i]
		if c and c.Connected then c:Disconnect() end
		self.rowHoverConnections[i] = nil
	end
end

function UISpoofer:isLeaderboardHoverEligibleCached(row)
	if not row or not row:IsA("GuiObject") then return false end
	local now = os.clock()
	local cached = self.rowHoverEligibilityCache[row]
	if cached and (now - cached.at) <= HOVER_ELIGIBILITY_CACHE_TTL then
		return cached.value == true
	end
	local value = isLeaderboardHoverEligible(row)
	self.rowHoverEligibilityCache[row] = { value = value == true, at = now }
	return value
end

function UISpoofer:getCachedSourceRows()
	local rows, count = {}, 0
	for row in pairs(self.cachedSourceRows) do
		if row and row.Parent and row:IsA("GuiObject") and row.Visible then
			local s = scoreRow(row)
			if s and s >= 70 then
				rows[row] = true
				count = count + 1
			end
		end
	end
	return count > 0 and rows or nil, count
end

function UISpoofer:getPropertyCompat(inst, prop)
	if not inst or type(prop) ~= "string" then return nil, false end
	local getHidden = getExploitFunction("gethiddenproperty")
	if getHidden then
		local ok, value = pcall(function() return getHidden(inst, prop) end)
		if ok then return value, true end
	end
	local ok, value = pcall(function() return inst[prop] end)
	return value, ok
end

function UISpoofer:setPropertyCompat(inst, prop, value)
	if not inst or type(prop) ~= "string" then return false end
	local setHidden = getExploitFunction("sethiddenproperty")
	if setHidden then
		local ok = pcall(function() setHidden(inst, prop, value) end)
		if ok then return true end
	end
	local setScriptable = getExploitFunction("setscriptable")
	if setScriptable then
		local toggled, prevScriptable = false, nil
		pcall(function()
			prevScriptable = setScriptable(inst, prop, true)
			toggled = true
		end)
		local okSet = pcall(function() inst[prop] = value end)
		if toggled then pcall(function() setScriptable(inst, prop, prevScriptable) end) end
		if okSet then return true end
	end
	local ok = pcall(function() inst[prop] = value end)
	return ok
end

function UISpoofer:ensureLocalIdentitySpoof()
	if not self.enabled or not self.targetUserId then return false end
	local lp = self:lp()
	local targetUid = tonumber(self.targetUserId)
	local targetUsername = tostring(self.targetName or targetUid or "")
	local targetDisplayName = tostring(self.targetDisplayName or targetUsername)
	if not lp or not targetUid then return false end

	if not self.identitySpoofOriginalCaptured then
		local oid, okId = self:getPropertyCompat(lp, "UserId")
		if okId then self.identitySpoofOriginalUserId = oid end
		local oap, okAp = self:getPropertyCompat(lp, "CharacterAppearanceId")
		if okAp then self.identitySpoofOriginalAppearanceId = oap end
		local on, okN = self:getPropertyCompat(lp, "Name")
		if okN then self.identitySpoofOriginalName = tostring(on or "") end
		local odn, okDN = self:getPropertyCompat(lp, "DisplayName")
		if okDN then self.identitySpoofOriginalDisplayName = tostring(odn or "") end
		if (not self.localIdentitySeedName or self.localIdentitySeedName == "") and okN then
			self.localIdentitySeedName = tostring(on or "")
		end
		if (not self.localIdentitySeedDisplayName or self.localIdentitySeedDisplayName == "") and okDN then
			self.localIdentitySeedDisplayName = tostring(odn or "")
		end
		self.identitySpoofOriginalCaptured = true
	end

	local dnWritten = self:setPropertyCompat(lp, "DisplayName", targetDisplayName)
	local nWritten = self:setPropertyCompat(lp, "Name", targetUsername)
	local apWritten = self:setPropertyCompat(lp, "CharacterAppearanceId", targetUid)
	local uidWritten = self:setPropertyCompat(lp, "UserId", targetUid)

	local liveUid, okLiveUid = self:getPropertyCompat(lp, "UserId")
	local liveAp, okLiveAp = self:getPropertyCompat(lp, "CharacterAppearanceId")
	local liveName, okLiveName = self:getPropertyCompat(lp, "Name")
	local liveDN, okLiveDN = self:getPropertyCompat(lp, "DisplayName")

	local uidNum = tonumber(liveUid)
	local apNum = tonumber(liveAp)
	local canRead = okLiveUid and okLiveAp
	local applied = false
	if canRead then
		applied = uidNum and apNum and math.floor(uidNum) == targetUid and math.floor(apNum) == targetUid
	else
		applied = uidWritten and apWritten
	end

	local nameApplied = (okLiveName and tostring(liveName or "") == targetUsername) or nWritten
	local dnApplied = (okLiveDN and tostring(liveDN or "") == targetDisplayName) or dnWritten

	if not applied or not nameApplied or not dnApplied then
		self:setPropertyCompat(lp, "Name", targetUsername)
		self:setPropertyCompat(lp, "DisplayName", targetDisplayName)
		self:setPropertyCompat(lp, "UserId", targetUid)
		self:setPropertyCompat(lp, "CharacterAppearanceId", targetUid)
		liveUid, okLiveUid = self:getPropertyCompat(lp, "UserId")
		liveAp, okLiveAp = self:getPropertyCompat(lp, "CharacterAppearanceId")
		liveName, okLiveName = self:getPropertyCompat(lp, "Name")
		liveDN, okLiveDN = self:getPropertyCompat(lp, "DisplayName")
		uidNum = tonumber(liveUid)
		apNum = tonumber(liveAp)
		canRead = okLiveUid and okLiveAp
		if canRead then
			applied = uidNum and apNum and math.floor(uidNum) == targetUid and math.floor(apNum) == targetUid
		end
		if okLiveName then nameApplied = tostring(liveName or "") == targetUsername end
		if okLiveDN then dnApplied = tostring(liveDN or "") == targetDisplayName end
	end

	if applied then
		self.identitySpoofApplied = true
		self.identitySpoofTargetUserId = targetUid
	else
		self.identitySpoofApplied = false
		self.identitySpoofTargetUserId = nil
	end
	self.identitySpoofNameApplied = nameApplied == true
	self.identitySpoofDisplayNameApplied = dnApplied == true
	return applied
end

function UISpoofer:restoreLocalIdentitySpoof()
	if not self.identitySpoofOriginalCaptured then return end
	local lp = self:lp()
	if lp then
		if self.identitySpoofOriginalName ~= nil then
			self:setPropertyCompat(lp, "Name", self.identitySpoofOriginalName)
		end
		if self.identitySpoofOriginalDisplayName ~= nil then
			self:setPropertyCompat(lp, "DisplayName", self.identitySpoofOriginalDisplayName)
		end
		if self.identitySpoofOriginalUserId ~= nil then
			self:setPropertyCompat(lp, "UserId", self.identitySpoofOriginalUserId)
		end
		if self.identitySpoofOriginalAppearanceId ~= nil then
			self:setPropertyCompat(lp, "CharacterAppearanceId", self.identitySpoofOriginalAppearanceId)
		end
	end
	self.identitySpoofApplied = false
	self.identitySpoofNameApplied = false
	self.identitySpoofDisplayNameApplied = false
	self.identitySpoofTargetUserId = nil
	self.nextIdentitySpoofReapplyAt = 0
end

function UISpoofer:updateRowPrimaryText(row)
	local lbl = row and self.rowPrimaryLabelByRow[row] or nil
	if not lbl or not lbl.Parent or not TEXT_CLASS_SET[lbl.ClassName] then return end
	local tName = self.targetName or tostring(self.targetUserId or "")
	local tDisplay = self.targetDisplayName or tName
	self:captureLabelOriginal(lbl)
	if not self:isLeaderboardHoverEligibleCached(row) then
		pcall(function() lbl.Text = tDisplay end)
		return
	end
	local hovering = self.rowHoverStateByRow[row] == true
	pcall(function() lbl.Text = hovering and tName or tDisplay end)
end

function UISpoofer:ensureRowHoverBehavior(row)
	if not row or not row:IsA("GuiObject") then return end
	if not self:isLeaderboardHoverEligibleCached(row) then
		self.rowHoverStateByRow[row] = false
		self:updateRowPrimaryText(row)
		return
	end
	if self.rowHoverHookedByRow[row] then
		self:updateRowPrimaryText(row)
		return
	end
	local function onEnter()
		self.rowHoverStateByRow[row] = true
		self:updateRowPrimaryText(row)
	end
	local function onLeave()
		self.rowHoverStateByRow[row] = false
		self:updateRowPrimaryText(row)
	end
	local ok1, c1 = pcall(function() return row.MouseEnter:Connect(onEnter) end)
	if ok1 and c1 then self.rowHoverConnections[#self.rowHoverConnections + 1] = c1 end
	local ok2, c2 = pcall(function() return row.MouseLeave:Connect(onLeave) end)
	if ok2 and c2 then self.rowHoverConnections[#self.rowHoverConnections + 1] = c2 end
	self.rowHoverHookedByRow[row] = true
	self:updateRowPrimaryText(row)
end

function UISpoofer:applyRowVisuals(row)
	if not row then return end
	local tName = self.targetName or tostring(self.targetUserId or "")
	local tDisplay = self.targetDisplayName or tName

	local dn = row:FindFirstChild("DisplayNameLabel", true) or row:FindFirstChild("DisplayName", true)
	local un = row:FindFirstChild("UserNameLabel", true)
		or row:FindFirstChild("NameLabel", true)
		or row:FindFirstChild("Username", true)
	if not (dn and TEXT_CLASS_SET[dn.ClassName]) or not (un and TEXT_CLASS_SET[un.ClassName]) then
		dn, un = findNameLabels(row)
	end

	local isLeaderboard = self:isLeaderboardHoverEligibleCached(row)

	if isLeaderboard then
		local primary, secondary = nil, nil
		local dnOk = dn and TEXT_CLASS_SET[dn.ClassName]
		local unOk = un and TEXT_CLASS_SET[un.ClassName]
		if dnOk and unOk then
			local ok, dnX, unX = pcall(function() return dn.AbsolutePosition.X, un.AbsolutePosition.X end)
			if ok and unX < dnX then
				primary = un
				secondary = dn
			else
				primary = dn
				secondary = un
			end
		elseif unOk then primary = un
		elseif dnOk then primary = dn end

		if primary then
			self:captureLabelOriginal(primary)
			self.rowPrimaryLabelByRow[row] = primary
			self:ensureRowHoverBehavior(row)
		end

		if secondary and TEXT_CLASS_SET[secondary.ClassName] then
			local sec = normalizeLower(trimString(secondary.Text))
			local loD = normalizeLower(tDisplay)
			local loN = normalizeLower(tName)
			if sec == loD or sec == loN or sec == "@" .. loN or sec == "@" .. loD then
				self:captureLabelOriginal(secondary)
				pcall(function() secondary.Text = "" end)
			end
		end
	else
		if dn and TEXT_CLASS_SET[dn.ClassName] then
			self:captureLabelOriginal(dn)
			pcall(function() dn.Text = tDisplay end)
		end
		if un and TEXT_CLASS_SET[un.ClassName] then
			self:captureLabelOriginal(un)
			pcall(function() un.Text = "@" .. tName end)
		end
	end

	local avatar = row:FindFirstChild("Avatar", true)
	if not avatar or not IMAGE_CLASS_SET[avatar.ClassName] then
		local ok, descs = pcall(function() return row:GetDescendants() end)
		if ok and descs then
			for _, inst in ipairs(descs) do
				if IMAGE_CLASS_SET[inst.ClassName] and isAvatarThumb(inst.Image) then
					avatar = inst
					break
				end
			end
		end
	end
	if avatar and IMAGE_CLASS_SET[avatar.ClassName] then
		self:captureImageOriginal(avatar)
		if self.targetAvatarThumb then
			pcall(function() avatar.Image = self.targetAvatarThumb end)
		elseif self.targetHeadshot then
			pcall(function() avatar.Image = self.targetHeadshot end)
		end
	end
end

function UISpoofer:discoverPeopleSourceRows()
	local lp = self:lp()
	if not lp then return {}, { sourceCount = 0, ctxHits = 0, fbHits = 0 } end

	local tokenSet = {}
	local function addToken(raw)
		local t = normalizeLower(trimString(raw))
		if t == "" then return end
		tokenSet[t] = true
		if t:sub(1, 1) == "@" then tokenSet[t:sub(2)] = true end
	end

	addToken(self.localIdentitySeedName)
	addToken(self.localIdentitySeedDisplayName)
	addToken(self.identitySpoofOriginalName)
	addToken(self.identitySpoofOriginalDisplayName)
	if not self.identitySpoofApplied then
		addToken(lp.Name)
		addToken(lp.DisplayName)
	end
	if not next(tokenSet) then
		return {}, { sourceCount = 0, ctxHits = 0, fbHits = 0 }
	end

	local function isLocalText(raw)
		if type(raw) ~= "string" or raw == "" then return false end
		local t = normalizeLower(trimString(raw))
		if tokenSet[t] then return true end
		return t:sub(1, 1) == "@" and tokenSet[t:sub(2)] == true
	end

	local candidateByRow = {}
	local ctxHits, fbHits = 0, 0

	local function addRow(row, isCtx)
		if not row or not row.Parent then return end
		local s = scoreRow(row)
		if not s or s < 70 then return end
		local info = candidateByRow[row]
		if not info then
			info = { score = s, hits = 0, ctxHits = 0, parent = row.Parent }
			candidateByRow[row] = info
		end
		info.hits = info.hits + 1
		if isCtx then info.ctxHits = info.ctxHits + 1 end
	end

	for _, root in ipairs(self:getUiSearchRoots()) do
		local ok, descs = pcall(function() return root:GetDescendants() end)
		if ok and descs then
			for _, inst in ipairs(descs) do
				if TEXT_CLASS_SET[inst.ClassName] and inst.Visible
					and isLikelyPeopleContext(inst) and isLocalText(inst.Text) then
					addRow(rowFromText(inst), true)
					ctxHits = ctxHits + 1
				end
			end
		end
	end

	if not next(candidateByRow) then
		for _, root in ipairs(self:getUiSearchRoots()) do
			local ok, descs = pcall(function() return root:GetDescendants() end)
			if ok and descs then
				for _, inst in ipairs(descs) do
					if TEXT_CLASS_SET[inst.ClassName] and inst.Visible and isLocalText(inst.Text) then
						addRow(rowFromText(inst), false)
						fbHits = fbHits + 1
					end
				end
			end
		end
	end

	local sourceRows = {}
	local bestByParent = {}
	for row, info in pairs(candidateByRow) do
		local weight = (info.ctxHits * 1000) + (info.hits * 100) + info.score
		local cur = bestByParent[info.parent]
		if not cur or weight > cur.weight then
			bestByParent[info.parent] = { row = row, weight = weight }
		end
	end
	for _, entry in pairs(bestByParent) do sourceRows[entry.row] = true end

	local count = 0
	for _ in pairs(sourceRows) do count = count + 1 end
	return sourceRows, { sourceCount = count, ctxHits = ctxHits, fbHits = fbHits }
end

function UISpoofer:syncPeopleRows(forceDiscover)
	if not self.enabled or not self.targetUserId then return end
	local sourceRows = nil
	if not forceDiscover then
		local cached = nil
		cached = select(1, self:getCachedSourceRows())
		sourceRows = cached
	end
	if not sourceRows then
		local stats = nil
		sourceRows, stats = self:discoverPeopleSourceRows()
		self.cachedSourceRows = setmetatable({}, { __mode = "k" })
		for row in pairs(sourceRows) do self.cachedSourceRows[row] = true end
		self.debugSyncStats = stats
	end
	for row in pairs(sourceRows) do
		self:applyRowVisuals(row)
	end
end

function UISpoofer:clearRows()
	self:disconnectRowHoverConnections()
	self:restorePatchedRows()
	self.rowPrimaryLabelByRow = setmetatable({}, { __mode = "k" })
	self.rowHoverHookedByRow = setmetatable({}, { __mode = "k" })
	self.rowHoverStateByRow = setmetatable({}, { __mode = "k" })
	self.rowHoverEligibilityCache = setmetatable({}, { __mode = "k" })
	self.cachedSourceRows = setmetatable({}, { __mode = "k" })
	self.syncPending = false
	self.syncRerun = false
end

function UISpoofer:sync()
	if not self.enabled or not self.targetUserId then
		self:clearRows()
		return
	end
	local forceDiscover = self.dirty == true or os.clock() < (self.fastSyncUntil or 0)
	self.lastSyncAt = os.clock()
	self:syncPeopleRows(forceDiscover)
	self.dirty = false
end

function UISpoofer:requestSync()
	if not self.enabled then return end
	if self.syncRunning then self.syncRerun = true return end
	if self.syncPending then return end
	self.syncPending = true
	task.spawn(function()
		if not self.enabled then
			self.syncPending = false
			self.syncRerun = false
			return
		end
		self.syncRunning = true
		local burst = 0
		repeat
			self.syncPending = false
			self.syncRerun = false
			self:sync()
			if self.syncRerun then
				burst = burst + 1
				if burst >= 3 then
					self.syncRerun = false
					break
				end
				task.wait(0.05)
			end
		until not self.syncRerun or not self.enabled
		self.syncRunning = false
	end)
end

function UISpoofer:disconnectAll()
	for i = #self.connections, 1, -1 do
		local c = self.connections[i]
		if c and c.Connected then c:Disconnect() end
		self.connections[i] = nil
	end
	self.syncPending = false
	self.syncRunning = false
	self.syncRerun = false
	self.lastSyncAt = 0
	self.fastSyncUntil = 0
	self.nextFastSyncKickAt = 0
	self.dirty = false
	self:restoreLocalIdentitySpoof()
end

function UISpoofer:setEnabled(enabled)
	enabled = enabled == true
	if self.enabled == enabled then return end
	self.enabled = enabled
	if not enabled then
		self:disconnectAll()
		self:clearRows()
		return
	end

	self.lastSyncAt = 0
	self.fastSyncUntil = 0
	self.nextFastSyncKickAt = 0
	self.nextIdentitySpoofReapplyAt = 0
	self.dirty = false

	self:clearRows()
	if self.targetUserId then self:syncPeopleRows(true) end
	self:ensureLocalIdentitySpoof()

	local function onDescAdded(inst)
		if not self.enabled then return end
		if TEXT_CLASS_SET[inst.ClassName] or IMAGE_CLASS_SET[inst.ClassName]
			or inst:IsA("Frame") or inst:IsA("ScrollingFrame") then
			self.dirty = true
			local now = os.clock()
			if now < (self.fastSyncUntil or 0) and now >= (self.nextFastSyncKickAt or 0) then
				self.nextFastSyncKickAt = now + FAST_SYNC_DESC_KICK_COOLDOWN
				self.lastSyncAt = 0
				self:requestSync()
			end
		end
	end

	local ok1, c1 = pcall(function() return CoreGui.DescendantAdded:Connect(onDescAdded) end)
	if ok1 and c1 then self.connections[#self.connections + 1] = c1 end

	local ok2, c2 = pcall(function()
		return GuiService.MenuOpened:Connect(function()
			if not self.enabled then return end
			self.fastSyncUntil = os.clock() + MENU_FAST_SYNC_DURATION
			self.nextFastSyncKickAt = 0
			self.lastSyncAt = 0
			self.dirty = true
			self:requestSync()
			for _, d in ipairs({ 0.08, 0.22 }) do
				task.delay(d, function()
					if self.enabled and os.clock() < (self.fastSyncUntil or 0) then
						self.lastSyncAt = 0
						self.dirty = true
						self:requestSync()
					end
				end)
			end
		end)
	end)
	if ok2 and c2 then self.connections[#self.connections + 1] = c2 end

	local ok3, c3 = pcall(function()
		return GuiService.MenuClosed:Connect(function()
			self.fastSyncUntil = 0
		end)
	end)
	if ok3 and c3 then self.connections[#self.connections + 1] = c3 end

	local lp = self:lp()
	local pg = lp and lp:FindFirstChildOfClass("PlayerGui") or nil
	if pg then
		local ok4, c4 = pcall(function() return pg.DescendantAdded:Connect(onDescAdded) end)
		if ok4 and c4 then self.connections[#self.connections + 1] = c4 end
	end

	local ok5, c5 = pcall(function()
		return RunService.Heartbeat:Connect(function()
			if not self.enabled then return end
			local now = os.clock()
			if now >= (self.nextIdentitySpoofReapplyAt or 0) then
				self.nextIdentitySpoofReapplyAt = now + IDENTITY_SPOOF_REAPPLY_INTERVAL
				self:ensureLocalIdentitySpoof()
			end
			local interval = (now < (self.fastSyncUntil or 0)) and FAST_SYNC_INTERVAL or SYNC_INTERVAL
			local hasCached = next(self.cachedSourceRows) ~= nil
			if self.dirty or (hasCached and (now - self.lastSyncAt >= interval)) then
				self:requestSync()
			end
		end)
	end)
	if ok5 and c5 then self.connections[#self.connections + 1] = c5 end

	self.dirty = true
	self:requestSync()
	for _, d in ipairs({ 0.1, 0.3, 0.7, 1.5 }) do
		task.delay(d, function()
			if self.enabled then
				self.dirty = true
				self:requestSync()
			end
		end)
	end
end

function UISpoofer:resolveUserId(target)
	local n = normalizeTarget(target)
	if n == "" then return nil end
	local num = tonumber(n)
	if num then return math.floor(num) end
	local ok, uid = pcall(function() return Players:GetUserIdFromNameAsync(n) end)
	return ok and type(uid) == "number" and math.floor(uid) or nil
end

function UISpoofer:refreshProfile(userId)
	self.profileFetchToken = self.profileFetchToken + 1
	local fetchToken = self.profileFetchToken
	local numericUserId = tonumber(userId)
	local previousName = self.targetName
	local previousDisplayName = self.targetDisplayName

	self.targetName = tostring(userId)
	self.targetDisplayName = nil
	self.targetHeadshot = nil
	self.targetAvatarThumb = nil

	local ok1, inGame = pcall(function() return Players:GetPlayerByUserId(userId) end)
	if ok1 and inGame then
		local pn = tostring(inGame.Name or "")
		local pd = tostring(inGame.DisplayName or "")
		if pn ~= "" then self.targetName = pn end
		if pd ~= "" then self.targetDisplayName = pd end
	end

	if self.targetName == tostring(userId) then
		local ok2, name = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
		if ok2 and type(name) == "string" and name ~= "" then self.targetName = name end
	end

	if not self.targetDisplayName then
		local ok3, info = pcall(function() return UserService:GetUserInfosByUserIdsAsync({ userId }) end)
		if ok3 and type(info) == "table" then
			local matched = nil
			for _, entry in ipairs(info) do
				if type(entry) == "table" and tonumber(entry.Id) == tonumber(userId) then
					matched = entry
					break
				end
			end
			if not matched then matched = info[1] end
			if type(matched) == "table" then
				local dn = matched.DisplayName
				if type(dn) == "string" and dn ~= "" then self.targetDisplayName = dn end
			end
		end
	end

	self.targetDisplayName = self.targetDisplayName or self.targetName

	local ok4, hs = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
	end)
	self.targetHeadshot = ok4 and hs or nil

	local ok5, av = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.AvatarThumbnail, Enum.ThumbnailSize.Size420x420)
	end)
	self.targetAvatarThumb = ok5 and av or nil

	if numericUserId and previousName and previousName ~= ""
		and looksUnresolvedName(self.targetName, numericUserId)
		and not looksUnresolvedName(previousName, numericUserId) then
		self.targetName = previousName
	end
	if numericUserId and previousDisplayName and previousDisplayName ~= ""
		and looksUnresolvedName(self.targetDisplayName, numericUserId)
		and not looksUnresolvedName(previousDisplayName, numericUserId) then
		self.targetDisplayName = previousDisplayName
	end
	self.targetDisplayName = self.targetDisplayName or self.targetName

	if not looksUnresolvedName(self.targetName, userId)
		and not looksUnresolvedName(self.targetDisplayName, userId) then
		return
	end

	task.spawn(function()
		local delays = { 0.35, 0.75, 1.2, 1.8 }
		for _, delayTime in ipairs(delays) do
			task.wait(delayTime)
			if fetchToken ~= self.profileFetchToken then return end
			if tonumber(self.targetUserId) ~= tonumber(userId) then return end

			local beforeName = self.targetName
			local beforeDisplay = self.targetDisplayName

			if looksUnresolvedName(self.targetName, userId) then
				local ok2, name = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
				if ok2 and type(name) == "string" and name ~= "" then self.targetName = name end
			end

			if self.targetDisplayName == nil or looksUnresolvedName(self.targetDisplayName, userId) then
				local ok3, info = pcall(function() return UserService:GetUserInfosByUserIdsAsync({ userId }) end)
				if ok3 and type(info) == "table" then
					local matched = nil
					for _, entry in ipairs(info) do
						if type(entry) == "table" and tonumber(entry.Id) == tonumber(userId) then
							matched = entry
							break
						end
					end
					if not matched then matched = info[1] end
					if type(matched) == "table" then
						local dn = matched.DisplayName
						if type(dn) == "string" and dn ~= "" then self.targetDisplayName = dn end
					end
				end
			end

			self.targetDisplayName = self.targetDisplayName or self.targetName

			if self.targetName ~= beforeName or self.targetDisplayName ~= beforeDisplay then
				if self.enabled then
					self:ensureLocalIdentitySpoof()
					self.dirty = true
					self:requestSync()
				end
			end

			if not looksUnresolvedName(self.targetName, userId)
				and not looksUnresolvedName(self.targetDisplayName, userId) then
				return
			end
		end
	end)
end

function UISpoofer:setTarget(target)
	local uid = self:resolveUserId(target)
	if not uid then return false end

	local wasEnabled = self.enabled == true
	local isSwitching = self.targetUserId ~= nil and tonumber(self.targetUserId) ~= tonumber(uid)

	if wasEnabled and isSwitching then self:setEnabled(false) end

	self.targetUserId = uid
	self:refreshProfile(uid)

	if wasEnabled and not self.enabled then self:setEnabled(true) end

	if self.enabled then
		self:ensureLocalIdentitySpoof()
		self.lastSyncAt = 0
		self.fastSyncUntil = os.clock() + MENU_FAST_SYNC_DURATION
		self.nextFastSyncKickAt = 0
		self.dirty = true
		self:requestSync()
		for _, d in ipairs({ 0.07, 0.18, 0.36 }) do
			task.delay(d, function()
				if self.enabled and tonumber(self.targetUserId) == tonumber(uid) then
					self.lastSyncAt = 0
					self.dirty = true
					self:requestSync()
				end
			end)
		end
	end
	return true
end

function UISpoofer:switchTarget(target)
	return self:setTarget(target)
end

function UISpoofer:setTargetByUserId(target)
	return self:setTarget(target)
end

function UISpoofer:setTargetByUsername(target)
	return self:setTarget(target)
end

function UISpoofer:getTargetInfo()
	return {
		userId = self.targetUserId,
		username = self.targetName,
		displayName = self.targetDisplayName,
		hasHeadshot = self.targetHeadshot ~= nil,
		hasAvatarThumb = self.targetAvatarThumb ~= nil,
		identitySpoofApplied = self.identitySpoofApplied == true,
		identitySpoofNameApplied = self.identitySpoofNameApplied == true,
		identitySpoofDisplayNameApplied = self.identitySpoofDisplayNameApplied == true,
		identitySpoofTargetUserId = self.identitySpoofTargetUserId,
		enabled = self.enabled,
	}
end

function UISpoofer:getDebugState()
	local st = self.debugSyncStats or {}
	return {
		enabled = self.enabled,
		targetUserId = self.targetUserId,
		targetName = self.targetName,
		targetDisplayName = self.targetDisplayName,
		hasHeadshot = self.targetHeadshot ~= nil,
		hasAvatarThumb = self.targetAvatarThumb ~= nil,
		identitySpoofApplied = self.identitySpoofApplied == true,
		identitySpoofNameApplied = self.identitySpoofNameApplied == true,
		identitySpoofDisplayNameApplied = self.identitySpoofDisplayNameApplied == true,
		identitySpoofTargetUserId = self.identitySpoofTargetUserId,
		sourceCount = st.sourceCount or 0,
		ctxHits = st.ctxHits or 0,
		fbHits = st.fbHits or 0,
	}
end

function UISpoofer:reapply()
	if self.targetUserId then
		if self.enabled then
			self.lastSyncAt = 0
			self.fastSyncUntil = os.clock() + MENU_FAST_SYNC_DURATION
			self.nextFastSyncKickAt = 0
			self.dirty = true
			self:ensureLocalIdentitySpoof()
			self:requestSync()
		end
		return true
	end
	return false
end

function UISpoofer:onCharacterAdded(_char)
	if not self.enabled then return end
	self.nextIdentitySpoofReapplyAt = 0
	self.lastSyncAt = 0
	self.fastSyncUntil = os.clock() + MENU_FAST_SYNC_DURATION
	self.nextFastSyncKickAt = 0
	self.dirty = true
	self:ensureLocalIdentitySpoof()
	self:requestSync()
	for _, d in ipairs({ 0.1, 0.25, 0.5 }) do
		task.delay(d, function()
			if self.enabled then
				self.nextIdentitySpoofReapplyAt = 0
				self.dirty = true
				self:ensureLocalIdentitySpoof()
				self:requestSync()
			end
		end)
	end
end

function UISpoofer:cleanup()
	self.enabled = false
	self.targetUserId = nil
	self.targetName = nil
	self.targetDisplayName = nil
	self.targetHeadshot = nil
	self.targetAvatarThumb = nil
	self.debugSyncStats = nil
	self:disconnectAll()
	self:clearRows()
end

return UISpoofer
