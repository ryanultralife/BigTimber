--!strict
-- Choppable forest: scatter trees across the hills north of the yard,
-- track HP, handle felling (physics topple + log drop), and regrow.
--
-- Trees are NOT planted in:
--   • The flat yard (inside YardRadius)
--   • The lake / shoreline (surfaceAt < 0.5)
--   • The paved road corridor (|x| < 18, z < NorthOnly_MinZ)
--   • The town/tunnel area south of NorthOnly_MinZ
-- This keeps the south road, tunnel, mill and shop clear of trees.

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Wood = require(Shared:WaitForChild("Wood"))
local World = require(script.Parent:WaitForChild("World"))

local Forest = {}

type Entry = { model: Model, speciesId: string, x: number, z: number }

local registry: { [string]: Entry } = {}
local forestFolder: Folder
local rng = Random.new()
local nextId = 0

local F = GameConfig.Forest

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = true
	for k, v in props do (p :: any)[k] = v end
	return p
end

local function pickSpeciesId(): string
	local r = rng:NextNumber()
	local acc = 0
	for id, w in F.SpeciesWeights do
		acc += w
		if r <= acc then return id end
	end
	return "pine"
end

local function buildHealthBar(trunk: BasePart, species: Wood.Species)
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Size = UDim2.fromOffset(80, 10)
	gui.StudsOffsetWorldSpace = Vector3.new(0, species.trunkHeight / 2 + 3, 0)
	gui.AlwaysOnTop = true
	gui.Enabled = false
	gui.Parent = trunk
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	bg.BackgroundTransparency = 0.3
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(90, 220, 110)
	fill.BorderSizePixel = 0
	fill.Parent = bg
end

local function buildTree(species: Wood.Species, baseCFrame: CFrame, uid: string): Model
	local model = Instance.new("Model")
	model.Name = "Tree_" .. uid

	local trunk = part({ Name = "Trunk",
		Size = Vector3.new(species.trunkRadius * 2, species.trunkHeight, species.trunkRadius * 2),
		Color = species.logColor, Material = Enum.Material.Wood, CanCollide = true })
	trunk.CFrame = baseCFrame * CFrame.new(0, species.trunkHeight / 2, 0)
	trunk.Parent = model
	model.PrimaryPart = trunk

	local topY = species.trunkHeight
	if species.conical then
		for i = 0, 2 do
			local r = species.canopyRadius * (1 - i * 0.26)
			local leaf = part({ Name = "Leaf", Shape = Enum.PartType.Ball,
				Size = Vector3.new(r * 2, r * 2.3, r * 2),
				Color = species.leafColor, Material = Enum.Material.Grass,
				CanCollide = false })
			leaf.CFrame = baseCFrame * CFrame.new(0, topY - 1 + i * species.canopyRadius, 0)
			leaf.Parent = model
		end
	else
		local r = species.canopyRadius
		local lower = part({ Name = "Leaf", Shape = Enum.PartType.Ball,
			Size = Vector3.new(r * 2, r * 1.7, r * 2),
			Color = species.leafColor, Material = Enum.Material.Grass, CanCollide = false })
		lower.CFrame = baseCFrame * CFrame.new(0, topY + r * 0.35, 0)
		lower.Parent = model
		local upper = part({ Name = "Leaf", Shape = Enum.PartType.Ball,
			Size = Vector3.new(r * 1.5, r * 1.4, r * 1.5),
			Color = species.leafColor, Material = Enum.Material.Grass, CanCollide = false })
		upper.CFrame = baseCFrame * CFrame.new(0, topY + r * 1.1, 0)
		upper.Parent = model
	end

	-- Weld leaves to trunk so the whole tree falls as one body
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") and desc ~= trunk then
			local w = Instance.new("WeldConstraint")
			w.Part0 = trunk; w.Part1 = desc; w.Parent = trunk
		end
	end

	model:SetAttribute("Uid", uid)
	model:SetAttribute("Species", species.id)
	model:SetAttribute("Hp", species.hp)
	model:SetAttribute("MaxHp", species.hp)
	buildHealthBar(trunk, species)
	model.Parent = forestFolder
	return model
end

local function plantAt(x: number, z: number, speciesId: string): Entry
	local species = Wood.get(speciesId) :: Wood.Species
	local y = World.surfaceAt(x, z) - 1
	local base = CFrame.new(x, y, z) * CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0)
	nextId += 1
	local uid = "t" .. nextId
	local model = buildTree(species, base, uid)
	local entry: Entry = { model = model, speciesId = speciesId, x = x, z = z }
	registry[uid] = entry
	return entry
end

local function toppleAndRemove(model: Model)
	task.spawn(function()
		local trunk = model.PrimaryPart
		if not trunk then model:Destroy(); return end
		local hb = trunk:FindFirstChild("HealthBar")
		if hb and hb:IsA("BillboardGui") then hb.Enabled = false end
		for _, desc in model:GetDescendants() do
			if desc:IsA("BasePart") and desc.Name == "Leaf" then
				desc.CanCollide = false; desc.Massless = true
			end
		end
		for _, desc in model:GetDescendants() do
			if desc:IsA("BasePart") then desc.Anchored = false end
		end
		-- Falling creak (placeholder built-in pitched low; real audio later).
		local creak = Instance.new("Sound")
		creak.SoundId = "rbxasset://sounds/snap.mp3"
		creak.PlaybackSpeed = 0.3
		creak.Volume = 0.9
		creak.Parent = trunk
		creak:Play()
		local tipX = (rng:NextNumber() < 0.5 and 1 or -1) * rng:NextNumber(1.0, 1.8)
		trunk.AssemblyAngularVelocity = Vector3.new(tipX, 0, rng:NextNumber(-0.6, 0.6))
		task.wait(5)
		if model and model.Parent then model:Destroy() end
	end)
end

-- ══════════════════════════════ public API ══════════════════════════

function Forest.getTree(uid: string): Model?
	local entry = registry[uid]
	return entry and entry.model or nil
end

function Forest.updateHealthBar(model: Model, frac: number)
	local trunk = model.PrimaryPart
	if not trunk then return end
	local hb = trunk:FindFirstChild("HealthBar")
	if not hb or not hb:IsA("BillboardGui") then return end
	hb.Enabled = frac < 0.999
	local bg = hb:FindFirstChildOfClass("Frame")
	local fill = bg and bg:FindFirstChild("Fill")
	if fill and fill:IsA("Frame") then
		fill.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1)
		fill.BackgroundColor3 = if frac > 0.5
			then Color3.fromRGB(90, 220, 110)
			elseif frac > 0.25 then Color3.fromRGB(230, 200, 70)
			else Color3.fromRGB(230, 90, 70)
	end
end

function Forest.fell(uid: string): { speciesId: string, logs: number, position: Vector3 }?
	local entry = registry[uid]
	if not entry then return nil end
	registry[uid] = nil
	local species = Wood.get(entry.speciesId) :: Wood.Species
	local logs = rng:NextInteger(species.logsMin, species.logsMax)
	local trunk = entry.model.PrimaryPart
	local groundY = trunk and (trunk.Position.Y - species.trunkHeight / 2)
		or World.surfaceAt(entry.x, entry.z)
	toppleAndRemove(entry.model)
	local x, z, speciesId = entry.x, entry.z, entry.speciesId
	task.delay(F.RegrowSeconds, function()
		plantAt(x, z, speciesId)
	end)
	-- Position is where LogService scatters the physical logs.
	return { speciesId = species.id, logs = logs, position = Vector3.new(x, groundY + 2, z) }
end

function Forest.start()
	forestFolder = Instance.new("Folder")
	forestFolder.Name = "Forest"
	forestFolder.Parent = Workspace

	local placed: { Vector2 } = {}
	local attempts = 0
	local maxAttempts = F.TreeCount * 30

	while #placed < F.TreeCount and attempts < maxAttempts do
		attempts += 1
		local angle = rng:NextNumber() * math.pi * 2
		local t = rng:NextNumber()
		local radius = math.sqrt(t * (F.MaxRadius ^ 2 - F.MinRadius ^ 2) + F.MinRadius ^ 2)
		local x = math.cos(angle) * radius
		local z = math.sin(angle) * radius

		-- Exclusion zones
		local onRoad = math.abs(x) < 18 and z < F.NorthOnly_MinZ
		local inTown = z < F.NorthOnly_MinZ - 20
		if onRoad or inTown then continue end
		if World.surfaceAt(x, z) < 0.5 then continue end

		local spot = Vector2.new(x, z)
		local ok = true
		for _, other in placed do
			if (spot - other).Magnitude < F.MinSpacing then ok = false; break end
		end
		if not ok then continue end
		table.insert(placed, spot)
		plantAt(x, z, pickSpeciesId())
	end
	print(("[Forest] planted %d trees."):format(#placed))
end

return Forest
