--[[ VOIMA Map Maker (Roblox Studio plugin)
Build a map in Studio, press Convert, and it becomes a VOIMA world:
  * parts become VOIMA slabs (tilted parts become steps, unions keep their holes, overlaps are cut away)
  * each part's material is matched to a VOIMA slab (same name first, else the closest texture), colour fitted to VOIMA
  * object markers (from the Objects tab, or any model named like a VOIMA card) become cards at full health
  * the player start marker (Spawns tab), else a SpawnLocation, is where you start as the bear
  * enemy markers (Spawns tab) become VOIMA creatures that hunt you
  * "VOIMA look" puts VOIMA's own slab textures on your parts (an overlay: your parts' materials and colours stay as they are)
It talks to the VOIMA Bridge on this PC (127.0.0.1:7878), which reads your VOIMA universe and writes world.save. ]]

local HttpService = game:GetService("HttpService")
local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local AssetService = game:GetService("AssetService")

local URL = "http://127.0.0.1:7878"
local CHUNK = 700

-- ------------------------------------------------------------------ settings
local function setting(key, default)
	local ok, v = pcall(function() return plugin:GetSetting("voima_" .. key) end)
	if ok and v ~= nil then return v end
	return default
end
local function save(key, v) pcall(function() plugin:SetSetting("voima_" .. key, v) end) end

local S = {
	world = setting("world", "Roblox Map"),
	scale = setting("scale", 0.4),         -- metres per stud: 0.4 makes a Roblox avatar about the size of the VOIMA bear
	step = setting("step", 0.25),          -- layer height (m) for tilted parts
	style = setting("style", true),
	overlaps = setting("overlaps", true),
	peaceful = setting("peaceful", true),
	spawning = setting("spawning", false),
	time = setting("time", 0.35),
	selectionOnly = setting("selectionOnly", false),
	enemyCount = setting("enemyCount", 1),
	enemySpread = setting("enemySpread", 12),
}

local catalog = { slabs = {}, cards = {} }
local cardByName = {}
local slabByName = {}

-- ------------------------------------------------------------------ bridge
local function request(method, path, body)
	local ok, res = pcall(function()
		return HttpService:RequestAsync({
			Url = URL .. path, Method = method,
			Headers = { ["Content-Type"] = "application/json" },
			Body = body and HttpService:JSONEncode(body) or nil,
		})
	end)
	if not ok then return nil, "The VOIMA Bridge isn't running. Double-click 'Start VOIMA Bridge' on your PC, then press Refresh. (" .. tostring(res) .. ")" end
	local data = nil
	pcall(function() data = HttpService:JSONDecode(res.Body) end)
	if not res.Success then return nil, (data and data.error) or ("Bridge error " .. res.StatusCode) end
	return data
end

-- ------------------------------------------------------------------ VOIMA textures (EditableImages made from the bridge's pixels)
local images = {}        -- "slab|sat|max" -> { img, w, h, tile }

local function texture(slab, sat, max)
	local key = slab .. "|" .. sat .. "|" .. max
	if images[key] then return images[key] end
	local ok, res = pcall(function()
		return HttpService:RequestAsync({ Url = ("%s/texture?name=%s&sat=%s&max=%d"):format(URL, HttpService:UrlEncode(slab), tostring(sat), max), Method = "GET" })
	end)
	if not ok or not res.Success then return nil end
	local w, h, tile = tonumber(res.Headers["x-width"]), tonumber(res.Headers["x-height"]), tonumber(res.Headers["x-tile"])
	if not w or #res.Body ~= w * h * 4 then return nil end
	local img = AssetService:CreateEditableImage({ Size = Vector2.new(w, h) })
	img:WritePixelsBuffer(Vector2.zero, Vector2.new(w, h), buffer.fromstring(res.Body))
	images[key] = { img = img, w = w, h = h, tile = tile }
	return images[key]
end

local FACES = { Enum.NormalId.Top, Enum.NormalId.Bottom, Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }

local function clearLook(part)
	for _, c in part:GetChildren() do if c:IsA("Texture") and c.Name == "VoimaLook" then c:Destroy() end end
end

-- col = VOIMA colour { r, g, b, saturation, brightness }: the texture at that saturation, tinted r g b x (1 + brightness)
local function applyLook(part, slab, col, info)
	local t = texture(slab, col[4], 1024)
	if not t then return false end
	clearLook(part)
	local b = 1 + (col[5] or 0)
	local tint = Color3.new(math.min(1, col[1] * b), math.min(1, col[2] * b), math.min(1, col[3] * b))
	local see = info and (info.see_through or info.fluid)
	for _, face in FACES do
		local tex = Instance.new("Texture")
		tex.Name = "VoimaLook"; tex.Face = face; tex.Archivable = false      -- never saved or published with the place
		tex.ColorMapContent = Content.fromObject(t.img)
		tex.StudsPerTileU = t.tile / S.scale; tex.StudsPerTileV = t.tile * t.h / t.w / S.scale
		tex.Color3 = tint; tex.Transparency = see and 0.45 or 0
		tex.Parent = part
	end
	part:SetAttribute("VoimaLook", true)
	return true
end

-- ------------------------------------------------------------------ slab look inside Studio (preview only)
local LOOK = {
	moss = "Grass", bush = "LeafyGrass", ["blueberry bush"] = "LeafyGrass", dirt = "Ground", sand = "Sand", snow = "Snow",
	ice = "Ice", stone = "Slate", ["mossy stone"] = "Rock", rocks = "Pebble", cobble = "Cobblestone", concrete = "Concrete",
	brick = "Brick", ["brick tile"] = "ClayRoofTiles", plank = "WoodPlanks", wood = "Wood", logs = "Wood", ["mossy log"] = "Wood",
	["pine bark"] = "Wood", metal = "Metal", glass = "Glass", water = "Glass", lava = "CrackedLava", ash = "Basalt",
	fur = "Fabric", hay = "Fabric", honey = "SmoothPlastic", ["white checker"] = "SmoothPlastic",
}

local function c3(t) return Color3.new(t[1], t[2], t[3]) end

local function applySlabLook(part, slab)
	part:SetAttribute("VoimaSlab", slab.name)
	local mat = LOOK[slab.name] or "SmoothPlastic"
	pcall(function() part.Material = Enum.Material[mat] end)
	part.Color = c3(slab.color)
	part:SetAttribute("VoimaColor", part.Color:ToHex())     -- unchanged colour = the slab's own texture colours
	if slab.name == "water" then part.Transparency = 0.5 elseif slab.name == "glass" then part.Transparency = 0.4 end
end

-- ------------------------------------------------------------------ placing things where the camera looks
local function lookPoint()
	local cam = workspace.CurrentCamera
	local params = RaycastParams.new()
	local hit = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * 1000, params)
	if hit then return hit.Position end
	local p = cam.CFrame.Position + cam.CFrame.LookVector * 30     -- looking at the sky: drop down onto whatever is below
	local down = workspace:Raycast(p, Vector3.new(0, -2000, 0), params)
	if down then return down.Position end
	return p
end

local function folder(name)
	local f = workspace:FindFirstChild(name)
	if not f then f = Instance.new("Folder"); f.Name = name; f.Parent = workspace end
	return f
end

local function makeMarker(card, pos, yaw, text, tint)
	local h = math.max(0.5, card.height / S.scale); local w = math.max(0.5, card.width / S.scale)
	local p = Instance.new("Part")
	p.Name = card.name
	p.Anchored = true; p.CanCollide = false; p.CastShadow = false
	p.Size = Vector3.new(w, h, math.max(0.5, w * 0.3))
	p.Material = Enum.Material.SmoothPlastic; p.Color = tint or c3(card.color); p.Transparency = 0.35
	p.CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, yaw or 0, 0)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(170, 26); bb.StudsOffset = Vector3.new(0, h / 2 + 1, 0); bb.MaxDistance = 250
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1); t.BackgroundTransparency = 0.4; t.BackgroundColor3 = tint and tint:Lerp(Color3.new(0, 0, 0), 0.5) or Color3.new(0, 0, 0)
	t.TextColor3 = Color3.new(1, 1, 1); t.Font = Enum.Font.GothamBold; t.TextScaled = true; t.Text = text or card.name
	t.Parent = bb; bb.Parent = p
	local sg = Instance.new("SurfaceGui")                  -- shows which way it faces (rotate the marker to turn it)
	sg.Face = Enum.NormalId.Front; sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud; sg.PixelsPerStud = 20
	local f = Instance.new("TextLabel")
	f.Size = UDim2.fromScale(1, 0.25); f.Position = UDim2.fromScale(0, 0.375); f.BackgroundTransparency = 1
	f.TextColor3 = Color3.new(1, 1, 1); f.TextScaled = true; f.Font = Enum.Font.GothamBold; f.Text = "▲ FRONT"
	f.Parent = sg; sg.Parent = p
	return p
end

local function placeObject(card)
	local rec = ChangeHistoryService:TryBeginRecording("Place VOIMA object")
	local p = makeMarker(card, lookPoint(), 0)
	p:SetAttribute("VoimaCard", card.name)
	p.Parent = folder("VOIMA Objects")
	Selection:Set({ p })
	if rec then ChangeHistoryService:FinishRecording(rec, Enum.FinishRecordingOperation.Commit) end
end

local function groundBelow(pos)
	local params = RaycastParams.new()
	local skip = {}
	for _, n in { "VOIMA Objects", "VOIMA Enemies", "VOIMA Player" } do
		local f = workspace:FindFirstChild(n)
		if f then table.insert(skip, f) end
	end
	params.FilterDescendantsInstances = skip; params.FilterType = Enum.RaycastFilterType.Exclude
	local hit = workspace:Raycast(pos + Vector3.new(0, 200, 0), Vector3.new(0, -2000, 0), params)
	return hit and hit.Position or pos
end

local onPeacefulChanged = function() end

local function placeEnemies(card)
	local rec = ChangeHistoryService:TryBeginRecording("Place VOIMA enemies")
	local centre = lookPoint()
	local made = {}
	local n = math.clamp(math.floor(S.enemyCount), 1, 50)
	for i = 1, n do
		local pos = centre
		if n > 1 then
			local a, d = math.random() * math.pi * 2, math.sqrt(math.random()) * S.enemySpread
			pos = groundBelow(centre + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d))
		end
		local p = makeMarker(card, pos, math.random() * math.pi * 2, "⚔ " .. card.name, Color3.fromRGB(200, 50, 50))
		p:SetAttribute("VoimaCard", card.name)
		p.Parent = folder("VOIMA Enemies")
		table.insert(made, p)
	end
	if card.aggressive and S.peaceful then                -- "peaceful beings" stops every creature from attacking
		S.peaceful = false; save("peaceful", false); onPeacefulChanged()
	end
	Selection:Set(made)
	if rec then ChangeHistoryService:FinishRecording(rec, Enum.FinishRecordingOperation.Commit) end
end

local function placePlayer()
	local rec = ChangeHistoryService:TryBeginRecording("Place VOIMA player start")
	local old = workspace:FindFirstChild("VOIMA Player")
	if old then old:ClearAllChildren() end                -- only one start: placing again moves it
	local card = cardByName["bear"] or { name = "bear", height = 2, width = 1.2, color = { 0.4, 0.3, 0.2 } }   -- the player is the bear
	local cam = workspace.CurrentCamera
	local yaw = math.atan2(-cam.CFrame.LookVector.X, -cam.CFrame.LookVector.Z)   -- face the way the camera looks
	local p = makeMarker(card, lookPoint(), yaw, "★ PLAYER START", Color3.fromRGB(60, 140, 255))
	p.Name = "Player Start"
	p:SetAttribute("VoimaPlayer", true)
	p.Parent = folder("VOIMA Player")
	Selection:Set({ p })
	if rec then ChangeHistoryService:FinishRecording(rec, Enum.FinishRecordingOperation.Commit) end
end

local function useSlab(slab)
	local rec = ChangeHistoryService:TryBeginRecording("VOIMA slab " .. slab.name)
	local parts = {}
	for _, o in Selection:Get() do
		if o:IsA("BasePart") and not o:GetAttribute("VoimaCard") then table.insert(parts, o) end
		for _, d in o:GetDescendants() do if d:IsA("BasePart") and not d:GetAttribute("VoimaCard") then table.insert(parts, d) end end
	end
	if #parts == 0 then                       -- nothing selected: drop a new 8x1x8 slab where you're looking
		local p = Instance.new("Part")
		p.Anchored = true; p.Size = Vector3.new(8, 1, 8); p.TopSurface = Enum.SurfaceType.Smooth
		local pos = lookPoint()
		p.CFrame = CFrame.new(pos + Vector3.new(0, 0.5, 0))
		p.Name = slab.name
		applySlabLook(p, slab)
		p.Parent = folder("VOIMA Map")
		Selection:Set({ p })
	else
		for _, p in parts do applySlabLook(p, slab) end
	end
	for _, p in (#parts > 0 and parts or Selection:Get()) do
		if p:IsA("BasePart") then applyLook(p, slab.name, { 1, 1, 1, 1, 0 }, slab) end
	end
	if rec then ChangeHistoryService:FinishRecording(rec, Enum.FinishRecordingOperation.Commit) end
end

-- ------------------------------------------------------------------ VOIMA look over the map
local MARKER_FOLDERS = { ["VOIMA Objects"] = true, ["VOIMA Enemies"] = true, ["VOIMA Player"] = true, ["VOIMA temp (safe to delete)"] = true }

local function lookTargets(onlySelected, onlyLooked)
	local out = {}
	local function visit(o)
		if MARKER_FOLDERS[o.Name] or o:IsA("Camera") or o:IsA("Terrain") then return end
		if o:GetAttribute("VoimaCard") or o:GetAttribute("VoimaPlayer") then return end
		if o:IsA("Model") and (o:FindFirstChildOfClass("Humanoid") or cardByName[string.lower(o.Name)]) then return end
		if o:IsA("BasePart") then
			if not onlyLooked or o:GetAttribute("VoimaLook") then table.insert(out, o) end
			return
		end
		for _, c in o:GetChildren() do visit(c) end
	end
	for _, r in (onlySelected and Selection:Get() or { workspace }) do visit(r) end
	return out
end

local function lookKey(p)
	local hex = p:GetAttribute("VoimaColor")
	return table.concat({ p.Material.Name, p.Color:ToHex(), ("%.2f"):format(p.Transparency), p.MaterialVariant,
		tostring(p:GetAttribute("VoimaSlab") or ""), tostring(hex ~= nil and hex == p.Color:ToHex()) }, "|")
end

local function lookMap(onlySelected, onlyLooked, say)
	local parts = lookTargets(onlySelected, onlyLooked)
	if #parts == 0 then return say("Nothing to show: no parts found.") end
	local keys, items, index = {}, {}, {}
	for _, p in parts do
		local k = lookKey(p)
		if not index[k] then
			index[k] = #items + 1
			table.insert(items, { material = p.Material.Name, color = { p.Color.R, p.Color.G, p.Color.B }, transparency = p.Transparency,
				variant = p.MaterialVariant, slab = p:GetAttribute("VoimaSlab"), natural = (p:GetAttribute("VoimaColor") == p.Color:ToHex()) })
		end
		keys[p] = index[k]
	end
	say(("Matching %d looks…"):format(#items))
	local res, err = request("POST", "/preview", { items = items, style = S.style })
	if not res then return say("✖ " .. tostring(err)) end
	local done = 0
	for i, p in parts do
		local l = res.looks[keys[p]]
		if l and l.slab then applyLook(p, l.slab, l.color, slabByName[l.slab]) else clearLook(p) end
		done += 1
		if i % 150 == 0 then say(("Texturing %d / %d parts…"):format(i, #parts)); task.wait() end
	end
	say(("✔ VOIMA look on %d parts. It's an overlay: Remove takes it off, and it isn't saved with the place."):format(done))
end

local function removeLook(say)
	local n = 0
	for _, d in workspace:GetDescendants() do
		if d:IsA("Texture") and d.Name == "VoimaLook" then d:Destroy() elseif d:IsA("BasePart") and d:GetAttribute("VoimaLook") then d:SetAttribute("VoimaLook", nil); n += 1 end
	end
	say(("Removed the VOIMA look from %d parts."):format(n))
end

-- ------------------------------------------------------------------ reading the map
local function partData(p, group, negative, union)
	local shape = "Block"
	if p:IsA("WedgePart") then shape = "Wedge"
	elseif p:IsA("CornerWedgePart") then shape = "CornerWedge"
	elseif p:IsA("Part") then shape = p.Shape.Name end
	local src = union or p
	local color = src.Color
	if union and not union.UsePartColor then color = p.Color end
	local natural = false
	local hex = p:GetAttribute("VoimaColor") or (union and union:GetAttribute("VoimaColor"))
	if hex and color:ToHex() == hex then natural = true end
	local cf = { p.CFrame:GetComponents() }
	return {
		shape = shape, cf = cf, size = { p.Size.X, p.Size.Y, p.Size.Z },
		material = p.Material.Name,
		variant = p.MaterialVariant,
		color = { color.R, color.G, color.B }, transparency = src.Transparency,
		slab = p:GetAttribute("VoimaSlab") or (union and union:GetAttribute("VoimaSlab")) or nil,
		natural = natural, group = group, negative = negative or nil,
	}
end

local function cardData(o, name)
	local cf, size
	if o:IsA("Model") then cf, size = o:GetBoundingBox() else cf, size = o.CFrame, o.Size end
	local look = cf.LookVector
	local feet = cf.Position - Vector3.new(0, size.Y / 2, 0)
	if o:IsA("BasePart") then
		-- a marker part: its bottom face is the feet
		feet = (cf * CFrame.new(0, -size.Y / 2, 0)).Position
	end
	-- VOIMA faces (sin v, cos v) in (x, z), and its z is Roblox's -z
	return { type = name, x = feet.X, y = feet.Y, z = feet.Z, view = math.atan2(look.X, -look.Z) }
end

local function separate(union, tmp)
	-- take a copy apart (never the original): solid parts, and negated parts turned back into normal parts
	local copy = union:Clone()
	copy.Parent = tmp
	local ok, parts = pcall(function() return plugin:Separate({ copy }) end)
	if not ok then return nil, tostring(parts) end
	local out = {}
	for _, p in parts do
		if p:IsA("NegateOperation") then
			local ok2, back = pcall(function() return plugin:Negate({ p }) end)
			if ok2 and back[1] then table.insert(out, { part = back[1], negative = true }) else table.insert(out, { part = p, negative = true }) end
		else
			table.insert(out, { part = p, negative = false })
		end
	end
	return out
end

local function gather(report)
	local parts, cards, spawn, spawnView, startFound = {}, {}, nil, 0, false
	local roots = {}
	if S.selectionOnly then roots = Selection:Get() else roots = { workspace } end
	local tmp = Instance.new("Folder"); tmp.Name = "VOIMA temp (safe to delete)"; tmp.Parent = workspace
	local groupN = 0
	local seen = {}

	local function addUnion(u, depth, group)
		local pieces, err = separate(u, tmp)
		if not pieces then
			report.notes["union kept as a box (" .. err .. ")"] = (report.notes["union kept as a box (" .. err .. ")"] or 0) + 1
			table.insert(parts, partData(u, group))
			return
		end
		for _, pc in pieces do
			if pc.part:IsA("UnionOperation") and depth < 6 then
				if pc.negative then
					table.insert(parts, partData(pc.part, group, true, nil))
				else
					addUnion(pc.part, depth + 1, group)
				end
			else
				table.insert(parts, partData(pc.part, group, pc.negative, u))
			end
		end
	end

	local function visit(o)
		if seen[o] then return end
		seen[o] = true
		if o == tmp or o.Name == "VOIMA temp (safe to delete)" or o:IsA("Camera") or o:IsA("Terrain") then return end
		if o:GetAttribute("VoimaPlayer") then
			local c = cardData(o, "player")
			spawn = { c.x, c.y, c.z }; spawnView = c.view; startFound = true
			return
		end
		local cardName = o:GetAttribute("VoimaCard")
		if not cardName and o:IsA("Model") and cardByName[string.lower(o.Name)] and not o:GetAttribute("VoimaSlab") then
			cardName = string.lower(o.Name)
		end
		if cardName then table.insert(cards, cardData(o, cardName)); return end
		if o:IsA("Model") and o:FindFirstChildOfClass("Humanoid") then
			report.notes["characters skipped"] = (report.notes["characters skipped"] or 0) + 1; return
		end
		if o:IsA("BasePart") then
			if (o:IsA("SpawnLocation") or o:GetAttribute("VoimaSpawn")) and not startFound then
				local top = (o.CFrame * CFrame.new(0, o.Size.Y / 2, 0)).Position
				if not spawn then spawn = { top.X, top.Y, top.Z } end
			end
			if o:IsA("UnionOperation") then
				groupN += 1; addUnion(o, 0, groupN)
			elseif o:IsA("NegateOperation") then
				report.notes["loose negated parts skipped"] = (report.notes["loose negated parts skipped"] or 0) + 1
			elseif o:IsA("MeshPart") or o:IsA("PartOperation") then
				report.notes["mesh parts made into boxes"] = (report.notes["mesh parts made into boxes"] or 0) + 1
				table.insert(parts, partData(o))
			else
				table.insert(parts, partData(o))
			end
			return                                -- a part's children are not more map
		end
		for _, c in o:GetChildren() do visit(c) end
	end

	ChangeHistoryService:SetWaypoint("VOIMA before convert")
	local ok, err = pcall(function() for _, r in roots do visit(r) end end)
	tmp:Destroy()
	ChangeHistoryService:SetWaypoint("VOIMA after convert")
	if not ok then error(err) end
	if not startFound then                                  -- the start marker counts even when it isn't in the selection
		local f = workspace:FindFirstChild("VOIMA Player")
		for _, m in (f and f:GetChildren() or {}) do
			if m:GetAttribute("VoimaPlayer") then local c = cardData(m, "player"); spawn = { c.x, c.y, c.z }; spawnView = c.view end
		end
	end
	return parts, cards, spawn, spawnView
end

-- ------------------------------------------------------------------ UI
local toolbar = plugin:CreateToolbar("VOIMA")
local button = toolbar:CreateButton("VoimaMapMaker", "Build maps for VOIMA and convert them to a VOIMA world", "rbxasset://textures/TerrainTools/mt_terrain_import.png", "Map Maker")
button.ClickableWhenViewportHidden = true
local widget = plugin:CreateDockWidgetPluginGui("VoimaMapMaker", DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 340, 640, 280, 320))
widget.Title = "VOIMA Map Maker"
button.Click:Connect(function() widget.Enabled = not widget.Enabled end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function() button:SetActive(widget.Enabled) end)

local theme = settings().Studio.Theme
local function tc(item) return theme:GetColor(item) end
local BG, TEXT, FIELD, BTN = tc(Enum.StudioStyleGuideColor.MainBackground), tc(Enum.StudioStyleGuideColor.MainText), tc(Enum.StudioStyleGuideColor.InputFieldBackground), tc(Enum.StudioStyleGuideColor.Button)
local ACCENT = Color3.fromRGB(116, 156, 70)

local root = Instance.new("Frame"); root.Size = UDim2.fromScale(1, 1); root.BackgroundColor3 = BG; root.BorderSizePixel = 0; root.Parent = widget

local function corner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 6); c.Parent = o end
local function label(parent, text, size, bold)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1; l.TextColor3 = TEXT; l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
	l.TextSize = size or 13; l.Text = text; l.TextXAlignment = Enum.TextXAlignment.Left; l.TextWrapped = true
	l.AutomaticSize = Enum.AutomaticSize.Y; l.Size = UDim2.new(1, 0, 0, 0); l.Parent = parent
	return l
end
local function btn(parent, text, color, cb)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 34); b.BackgroundColor3 = color or BTN; b.TextColor3 = color and Color3.new(1, 1, 1) or TEXT
	b.Font = Enum.Font.GothamBold; b.TextSize = 14; b.Text = text; b.AutoButtonColor = true; b.Parent = parent
	corner(b); b.MouseButton1Click:Connect(cb)
	return b
end
local function list(parent, pad)
	local l = Instance.new("UIListLayout"); l.Padding = UDim.new(0, pad or 6); l.SortOrder = Enum.SortOrder.LayoutOrder; l.Parent = parent
	local p = Instance.new("UIPadding"); p.PaddingLeft = UDim.new(0, 10); p.PaddingRight = UDim.new(0, 10); p.PaddingTop = UDim.new(0, 8); p.PaddingBottom = UDim.new(0, 8); p.Parent = parent
end
local function scroller(parent)
	local s = Instance.new("ScrollingFrame")
	s.Size = UDim2.new(1, 0, 1, -40); s.Position = UDim2.fromOffset(0, 40); s.BackgroundTransparency = 1; s.BorderSizePixel = 0
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y; s.CanvasSize = UDim2.new(); s.ScrollBarThickness = 6; s.Parent = parent
	return s
end
local function field(parent, name, value, onSet)
	local row = Instance.new("Frame"); row.Size = UDim2.new(1, 0, 0, 26); row.BackgroundTransparency = 1; row.Parent = parent
	local l = label(row, name); l.Size = UDim2.new(0.55, 0, 1, 0); l.AutomaticSize = Enum.AutomaticSize.None
	local box = Instance.new("TextBox")
	box.Size = UDim2.new(0.45, 0, 1, 0); box.Position = UDim2.fromScale(0.55, 0); box.BackgroundColor3 = FIELD; box.TextColor3 = TEXT
	box.Font = Enum.Font.Gotham; box.TextSize = 13; box.Text = tostring(value); box.ClearTextOnFocus = false; box.Parent = row
	corner(box, 4)
	box.FocusLost:Connect(function() box.Text = tostring(onSet(box.Text)) end)
	return box
end
local function toggle(parent, name, key)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 24); b.BackgroundTransparency = 1; b.TextColor3 = TEXT; b.Font = Enum.Font.Gotham; b.TextSize = 13
	b.TextXAlignment = Enum.TextXAlignment.Left; b.Parent = parent
	local function draw() b.Text = (S[key] and "☑  " or "☐  ") .. name end
	draw()
	b.MouseButton1Click:Connect(function() S[key] = not S[key]; save(key, S[key]); draw() end)
	return draw
end

-- tabs
local tabsBar = Instance.new("Frame"); tabsBar.Size = UDim2.new(1, 0, 0, 36); tabsBar.BackgroundTransparency = 1; tabsBar.Parent = root
local tl = Instance.new("UIListLayout"); tl.FillDirection = Enum.FillDirection.Horizontal; tl.Padding = UDim.new(0, 4); tl.Parent = tabsBar
local pages, tabButtons = {}, {}
local function showTab(n)
	for k, p in pages do p.Visible = (k == n) end
	for k, b in tabButtons do b.BackgroundColor3 = (k == n) and ACCENT or BTN; b.TextColor3 = (k == n) and Color3.new(1, 1, 1) or TEXT end
end
for i, n in { "Convert", "Slabs", "Objects", "Spawns" } do
	local b = Instance.new("TextButton"); b.Size = UDim2.new(1 / 4, -3, 1, -4); b.Font = Enum.Font.GothamBold; b.TextSize = 13; b.Text = n
	b.LayoutOrder = i; b.Parent = tabsBar; corner(b); tabButtons[n] = b
	local page = Instance.new("Frame"); page.Size = UDim2.new(1, 0, 1, -36); page.Position = UDim2.fromOffset(0, 36); page.BackgroundTransparency = 1; page.Parent = root
	pages[n] = page
	b.MouseButton1Click:Connect(function() showTab(n) end)
end

-- ---- Convert page
local cv = Instance.new("ScrollingFrame"); cv.Size = UDim2.fromScale(1, 1); cv.BackgroundTransparency = 1; cv.BorderSizePixel = 0
cv.AutomaticCanvasSize = Enum.AutomaticSize.Y; cv.CanvasSize = UDim2.new(); cv.ScrollBarThickness = 6; cv.Parent = pages.Convert
list(cv)
local status = label(cv, "Connecting to the VOIMA Bridge…", 13, true)
field(cv, "World name", S.world, function(t) S.world = t ~= "" and t or "Roblox Map"; save("world", S.world); return S.world end)
field(cv, "Metres per stud", S.scale, function(t) S.scale = math.clamp(tonumber(t) or S.scale, 0.05, 5); save("scale", S.scale); return S.scale end)
field(cv, "Step height for slopes (m)", S.step, function(t) S.step = math.clamp(tonumber(t) or S.step, 0.05, 2); save("step", S.step); return S.step end)
field(cv, "Time of day (0–1)", S.time, function(t) S.time = math.clamp(tonumber(t) or S.time, 0, 1); save("time", S.time); return S.time end)
toggle(cv, "Only the selected things", "selectionOnly")
toggle(cv, "Fit colours to VOIMA's look", "style")
toggle(cv, "Cut away overlapping parts", "overlaps")
onPeacefulChanged = toggle(cv, "Peaceful creatures (nothing attacks)", "peaceful")
toggle(cv, "Creatures spawn naturally", "spawning")
local convertBtn, checkBtn
local result = label(cv, "", 12)

local function run(dry)
	result.Text = ""
	status.Text = "Reading the map…"
	local report = { notes = {} }
	local ok, parts, cards, spawn, spawnView = pcall(gather, report)
	if not ok then status.Text = "Couldn't read the map: " .. tostring(parts); return end
	status.Text = ("Sending %d parts and %d objects…"):format(#parts, #cards)
	local begin, err = request("POST", "/export/begin", {
		world = S.world, dry = dry, spawn = spawn, spawn_view = spawnView,
		options = { scale = S.scale, step = S.step, style = S.style, fix_overlaps = S.overlaps, peaceful = S.peaceful, spawning = S.spawning, time = S.time },
	})
	if not begin then status.Text = err; return end
	for i = 1, math.max(#parts, 1), CHUNK do
		local chunk = table.move(parts, i, math.min(i + CHUNK - 1, #parts), 1, {})
		local r, e = request("POST", "/export/chunk", { id = begin.id, parts = chunk, cards = (i == 1) and cards or {} })
		if not r then status.Text = e; return end
		task.wait()
	end
	status.Text = dry and "Checking…" or "Building the VOIMA world…"
	local rep, e2 = request("POST", "/export/finish", { id = begin.id })
	if not rep then status.Text = "✖ " .. e2; return end
	local lines = {}
	table.insert(lines, ("%d parts → %d slabs, %d objects%s"):format(rep.parts, rep.slabs, rep.cards, rep.holes > 0 and (", " .. rep.holes .. " union holes cut") or ""))
	if rep.carved > 0 then table.insert(lines, rep.carved .. " overlapping pieces were cut to fit") end
	table.insert(lines, "\nMaterials:")
	local mats = {}
	for k, v in rep.materials do table.insert(mats, "  " .. k .. "  (" .. v .. ")") end
	table.sort(mats)
	for _, m in mats do table.insert(lines, m) end
	for k, v in rep.skipped do table.insert(lines, ("Skipped %d %s"):format(v, k)) end
	for k, v in report.notes do table.insert(lines, ("%d %s"):format(v, k)) end
	if #rep.unknown_cards > 0 then table.insert(lines, "Not in VOIMA (skipped): " .. table.concat(rep.unknown_cards, ", ")) end
	if rep.enemies and rep.enemies > 0 then table.insert(lines, rep.enemies .. " enemies") end
	if not spawn then table.insert(lines, "No player start: you'll start in the middle of the map.") end
	for _, w in rep.warnings or {} do table.insert(lines, "⚠ " .. w) end
	if dry then
		status.Text = "✔ Check done. Nothing written yet."
	else
		status.Text = ("✔ World \"%s\" made (%.1f MB). Restart VOIMA to play it."):format(rep.world, rep.size_mb)
		if rep.backup then table.insert(lines, "Old version backed up to " .. rep.backup) end
	end
	result.Text = table.concat(lines, "\n")
end
local busy = false
local function go(dry)
	if busy then return end
	busy = true
	task.spawn(function()
		local ok, e = pcall(run, dry)
		if not ok then status.Text = "✖ " .. tostring(e) end
		busy = false
	end)
end
convertBtn = btn(cv, "Convert to VOIMA world", ACCENT, function() go(false) end)
checkBtn = btn(cv, "Check map (no file written)", nil, function() go(true) end)
convertBtn.LayoutOrder = 50; checkBtn.LayoutOrder = 51; result.LayoutOrder = 60
local refreshBtn
refreshBtn = btn(cv, "Refresh (re-read VOIMA)", nil, function() end)
refreshBtn.LayoutOrder = 52

-- ---- Slabs page
local slTop = Instance.new("Frame"); slTop.Size = UDim2.new(1, 0, 0, 132); slTop.BackgroundTransparency = 1; slTop.Parent = pages.Slabs
list(slTop, 4)
local lookStatus = label(slTop, "VOIMA look: see your map with VOIMA's real textures.", 12, true); lookStatus.LayoutOrder = 1
local lookRow = Instance.new("Frame"); lookRow.Size = UDim2.new(1, 0, 0, 30); lookRow.BackgroundTransparency = 1; lookRow.LayoutOrder = 2; lookRow.Parent = slTop
local lr = Instance.new("UIListLayout"); lr.FillDirection = Enum.FillDirection.Horizontal; lr.Padding = UDim.new(0, 4); lr.Parent = lookRow
local lookBusy = false
local function lookButton(text, color, fn)
	local b = btn(lookRow, text, color, function()
		if lookBusy then return end
		lookBusy = true
		task.spawn(function()
			local ok, e = pcall(fn, function(t) lookStatus.Text = t end)
			if not ok then lookStatus.Text = "✖ " .. tostring(e) end
			lookBusy = false
		end)
	end)
	b.Size = UDim2.new(1 / 3, -3, 1, 0); b.TextSize = 12
end
lookButton("Whole map", ACCENT, function(say) lookMap(false, false, say) end)
lookButton("Selected", nil, function(say) lookMap(true, false, say) end)
lookButton("Remove", nil, function(say) removeLook(say) end)
local slabHint = label(slTop, "Select parts and click a slab to use it. Nothing selected = a new slab where you look.", 12)
slabHint.LayoutOrder = 3
local slabGrid = scroller(pages.Slabs)
slabGrid.Size = UDim2.new(1, 0, 1, -132); slabGrid.Position = UDim2.fromOffset(0, 132)
local g = Instance.new("UIGridLayout"); g.CellSize = UDim2.new(0.5, -6, 0, 30); g.CellPadding = UDim2.fromOffset(4, 4); g.SortOrder = Enum.SortOrder.LayoutOrder; g.Parent = slabGrid
local sp = Instance.new("UIPadding"); sp.PaddingLeft = UDim.new(0, 8); sp.PaddingRight = UDim.new(0, 8); sp.Parent = slabGrid

-- ---- Objects page
local search = Instance.new("TextBox")
search.Size = UDim2.new(1, -16, 0, 28); search.Position = UDim2.fromOffset(8, 6); search.BackgroundColor3 = FIELD; search.TextColor3 = TEXT
search.PlaceholderText = "Search objects (trees, lamps, creatures…)"; search.Text = ""; search.Font = Enum.Font.Gotham; search.TextSize = 13
search.ClearTextOnFocus = false; search.Parent = pages.Objects; corner(search, 4)
local objList = scroller(pages.Objects)
list(objList, 3)

local function swatchButton(parent, text, color, sub, cb)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 30); b.BackgroundColor3 = BTN; b.Text = ""; b.AutoButtonColor = true; b.Parent = parent; corner(b, 4)
	local sw = Instance.new("ImageLabel"); sw.Name = "Swatch"; sw.Size = UDim2.fromOffset(20, 20); sw.Position = UDim2.fromOffset(5, 5)
	sw.BackgroundColor3 = color; sw.ScaleType = Enum.ScaleType.Crop; sw.ResampleMode = Enum.ResamplerMode.Pixelated; sw.Parent = b; corner(sw, 3)
	local t = Instance.new("TextLabel"); t.BackgroundTransparency = 1; t.Position = UDim2.fromOffset(30, 0); t.Size = UDim2.new(1, -34, 1, 0)
	t.Font = Enum.Font.Gotham; t.TextSize = 12; t.TextColor3 = TEXT; t.TextXAlignment = Enum.TextXAlignment.Left; t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Text = sub and (text .. "  ·  " .. sub) or text; t.Parent = b
	b.MouseButton1Click:Connect(cb)
	return b
end

local function fillObjects()
	for _, c in objList:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
	local q = string.lower(search.Text)
	local lastType, order = nil, 0
	for _, card in catalog.cards do
		if q == "" or string.find(card.name, q, 1, true) or string.find(string.lower(card.type), q, 1, true) then
			if card.type ~= lastType then
				order += 1
				local h = label(objList, card.type, 13, true); h.LayoutOrder = order; lastType = card.type
			end
			order += 1
			local sub = ("%.1f m%s"):format(card.height, card.source ~= "VOIMA" and (", " .. card.source) or "")
			swatchButton(objList, card.name, c3(card.color), sub, function() placeObject(card) end).LayoutOrder = order
		end
	end
end
search:GetPropertyChangedSignal("Text"):Connect(fillObjects)

-- ---- Spawns page: your start point, and enemies
local spTop = Instance.new("Frame"); spTop.Size = UDim2.new(1, 0, 0, 170); spTop.BackgroundTransparency = 1; spTop.Parent = pages.Spawns
list(spTop, 5)
label(spTop, "Player (the bear)", 14, true).LayoutOrder = 1
btn(spTop, "★ Place player start where I look", Color3.fromRGB(60, 120, 220), function() placePlayer() end).LayoutOrder = 3
label(spTop, "Enemies: click one to place it where you look", 14, true).LayoutOrder = 4
field(spTop, "How many per click", S.enemyCount, function(t) S.enemyCount = math.clamp(math.floor(tonumber(t) or S.enemyCount), 1, 50); save("enemyCount", S.enemyCount); return S.enemyCount end).Parent.LayoutOrder = 5
field(spTop, "Spread (studs)", S.enemySpread, function(t) S.enemySpread = math.clamp(tonumber(t) or S.enemySpread, 0, 500); save("enemySpread", S.enemySpread); return S.enemySpread end).Parent.LayoutOrder = 6
local enemyList = Instance.new("ScrollingFrame")
enemyList.Size = UDim2.new(1, 0, 1, -170); enemyList.Position = UDim2.fromOffset(0, 170); enemyList.BackgroundTransparency = 1; enemyList.BorderSizePixel = 0
enemyList.AutomaticCanvasSize = Enum.AutomaticSize.Y; enemyList.CanvasSize = UDim2.new(); enemyList.ScrollBarThickness = 6; enemyList.Parent = pages.Spawns
list(enemyList, 3)

local function fillEnemies()
	for _, c in enemyList:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
	local order = 0
	for _, group in { { "Attack you", true }, { "Other creatures (won't attack)", false } } do
		order += 1
		local h = label(enemyList, group[1], 13, true); h.LayoutOrder = order
		for _, card in catalog.cards do
			if card.type == "Animal" and (card.aggressive == true) == group[2] then
				order += 1
				local sub = ("%.1f m%s"):format(card.height, card.source ~= "VOIMA" and (", " .. card.source) or "")
				swatchButton(enemyList, card.name, c3(card.color), sub, function() placeEnemies(card) end).LayoutOrder = order
			end
		end
	end
end

local function fillSlabs()
	for _, c in slabGrid:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
	for i, slab in catalog.slabs do
		if not slab.special then
			local sub = slab.fluid and "fluid" or (slab.source ~= "VOIMA" and slab.source or nil)
			local b = swatchButton(slabGrid, slab.name, c3(slab.color), sub, function() useSlab(slab) end)
			b.LayoutOrder = i
			task.spawn(function()                  -- the real VOIMA texture as the swatch
				local t = texture(slab.name, 1, 64)
				if t and b.Parent then b.Swatch.ImageContent = Content.fromObject(t.img) end
			end)
		end
	end
end

local function connect(refresh)
	status.Text = "Connecting to the VOIMA Bridge…"
	local ping, err = request("GET", "/ping")
	if not ping then status.Text = "✖ " .. err; return end
	local cat, e2 = request("GET", refresh and "/catalog?refresh=1" or "/catalog")
	if not cat then status.Text = "✖ " .. e2; return end
	catalog = cat; cardByName = {}; slabByName = {}
	for _, c in cat.cards do cardByName[c.name] = c end
	for _, s in cat.slabs do slabByName[s.name] = s end
	images = {}
	fillSlabs(); fillObjects(); fillEnemies()
	if #lookTargets(false, true) > 0 then
		task.spawn(function() lookBusy = true; pcall(lookMap, false, true, function(t) lookStatus.Text = t end); lookBusy = false end)
	end
	status.Text = ("✔ Connected: %d slabs, %d objects%s"):format(#cat.slabs, #cat.cards, ping.voima_running and "  (VOIMA is open)" or "")
end
refreshBtn.MouseButton1Click:Connect(function() task.spawn(connect, true) end)

showTab("Convert")
widget:GetPropertyChangedSignal("Enabled"):Connect(function() if widget.Enabled and not next(cardByName) then task.spawn(connect, false) end end)
if widget.Enabled then task.spawn(connect, false) end
