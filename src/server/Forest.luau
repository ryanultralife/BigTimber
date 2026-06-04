--!strict
-- The choppable forest. Scatters trees across the hills, tracks their HP,
-- and handles felling (a scripted topple + log drop) and regrow.
--
-- Trees are static anchored Models in Workspace.Forest. Each carries
-- attributes the client reads to target it: Uid, Species, Hp, MaxHp.
-- A registry maps Uid → entry for O(1) lookup from ChopService.

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

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

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local function pickSpeciesId(): string
	local r = rng:NextNumber()
	local acc = 0
	for id, w in F.SpeciesWeights do
		acc += w
		if r <= acc then
			return id
		end
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

	local trunk = part({
		Name = "Trunk",
		Size = Vector3.new(species.trunkRadius * 2, species.trunkHeight, species.trunkRadius * 2),
		Color = species.logColor,
		Material = Enum.Material.Wood,
		CanCollide = true,
	})
	trunk.CFrame = baseCFrame * CFrame.new(0, species.trunkHeight / 2, 0)
	trunk.Parent = model
	model.PrimaryPart = trunk

	local topY = species.trunkHeight
	if species.conical then
		-- Pine / redwood: three stacked, squashed balls tapering upward.
		for i = 0, 2 do
			local r = species.canopyRadius * (1 - i * 0.26)
			local leaf = part({
				Name = "Leaf",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(r * 2, r * 2.3, r * 2),
				Color = species.leafColor,
				Material = Enum.Material.Grass,
				CanCollide = false,
			})
			leaf.CFrame = baseCFrame * CFrame.new(0, topY - 1 + i * species.canopyRadius, 0)
			leaf.Parent = model
		end
	else
		-- Oak: a broad round crown from two overlapping balls.
		local r = species.canopyRadius
		local lower = part({
			Name = "Leaf",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(r * 2, r * 1.7, r * 2),
			Color = species.leafColor,
			Material = Enum.Material.Grass,
			CanCollide = false,
		})
		lower.CFrame = baseCFrame * CFrame.new(0, topY + r * 0.35, 0)
		lower.Parent = model
		local upper = part({
			Name = "Leaf",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(r * 1.5, r * 1.4, r * 1.5),
			Color = species.leafColor,
			Material = Enum.Material.Grass,
			CanCollide = false,
		})
		upper.CFrame = baseCFrame * CFrame.new(0, topY + r * 1.1, 0)
		upper.Parent = model
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
	local y = World.surfaceAt(x, z) - 1 -- sink the base a stud so it never floats
	local base = CFrame.new(x, y, z) * CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0)
	nextId += 1
	local uid = "t" .. nextId
	local model = buildTree(species, base, uid)
	local entry: Entry = { model = model, speciesId = speciesId, x = x, z = z }
	registry[uid] = entry
	return entry
end

-- Drop a couple of stubby log props at the stump for visual juice. These
-- are cosmetic — the actual logs are credited to the player in ChopService.
local function dropLogProps(species: Wood.Species, x: number, y: number, z: number)
	for i = 1, 3 do
		local log = part({
			Name = "LogProp",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(4, 1.6, 1.6),
			Color = species.logColor,
			Material = Enum.Material.Wood,
			Anchored = false,
			CanCollide = true,
		})
		log.CFrame = CFrame.new(x + rng:NextNumber(-2, 2), y + 2 + i, z + rng:NextNumber(-2, 2))
			* CFrame.Angles(0, rng:NextNumber() * math.pi, math.rad(rng:NextNumber(-20, 20)))
		log.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-6, 6), 6, rng:NextNumber(-6, 6))
		log.Parent = forestFolder
		Debris:AddItem(log, 8)
	end
end

-- Scripted topple: pivot the whole (anchored) tree about its base over ~0.7s,
-- then fade and remove. PivotTo moves all parts as a unit, so this is robust
-- without unanchoring anything into the physics solver.
local function toppleAndRemove(model: Model)
	task.spawn(function()
		local trunk = model.PrimaryPart
		if not trunk then
			model:Destroy()
			return
		end
		-- Hide the health bar immediately.
		local hb = trunk:FindFirstChild("HealthBar")
		if hb and hb:IsA("BillboardGui") then
			hb.Enabled = false
		end
		local base = trunk.CFrame * CFrame.new(0, -trunk.Size.Y / 2, 0)
		model.WorldPivot = base
		local dir = if rng:NextNumber() < 0.5 then 1 else -1
		local dur = 0.7
		local elapsed = 0
		while elapsed < dur do
			local dt = RunService.Heartbeat:Wait()
			elapsed += dt
			local angle = math.rad(86) * smoothstep(elapsed / dur) * dir
			model:PivotTo(base * CFrame.Angles(0, 0, angle))
		end
		-- Fade out the toppled trunk before removing.
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				p.CanCollide = false
			end
		end
		task.wait(0.5)
		model:Destroy()
	end)
end

-- ============================ public API ===========================

function Forest.getTree(uid: string): Model?
	local entry = registry[uid]
	return entry and entry.model or nil
end

-- Update the floating HP bar after a swing. frac is current/max in [0,1].
function Forest.updateHealthBar(model: Model, frac: number)
	local trunk = model.PrimaryPart
	if not trunk then
		return
	end
	local hb = trunk:FindFirstChild("HealthBar")
	if not hb or not hb:IsA("BillboardGui") then
		return
	end
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

-- Fell a tree: returns the species id + number of logs yielded, runs the
-- topple animation, drops props, and schedules a regrow at the same spot.
-- Returns nil if the uid is unknown (already felled / never existed).
function Forest.fell(uid: string): { speciesId: string, logs: number }?
	local entry = registry[uid]
	if not entry then
		return nil
	end
	registry[uid] = nil
	local species = Wood.get(entry.speciesId) :: Wood.Species
	local logs = rng:NextInteger(species.logsMin, species.logsMax)

	local trunk = entry.model.PrimaryPart
	local groundY = trunk and (trunk.Position.Y - species.trunkHeight / 2) or World.surfaceAt(entry.x, entry.z)
	dropLogProps(species, entry.x, groundY, entry.z)
	toppleAndRemove(entry.model)

	local x, z, speciesId = entry.x, entry.z, entry.speciesId
	task.delay(F.RegrowSeconds, function()
		plantAt(x, z, speciesId)
	end)

	return { speciesId = species.id, logs = logs }
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
		-- Uniform-by-area placement in the [MinRadius, MaxRadius] ring.
		local angle = rng:NextNumber() * math.pi * 2
		local t = rng:NextNumber()
		local radius = math.sqrt(t * (F.MaxRadius ^ 2 - F.MinRadius ^ 2) + F.MinRadius ^ 2)
		local x = math.cos(angle) * radius
		local z = math.sin(angle) * radius

		-- Don't plant in the lake / on the shoreline.
		if World.surfaceAt(x, z) < 0.5 then
			continue
		end
		-- Respect minimum spacing.
		local spot = Vector2.new(x, z)
		local ok = true
		for _, other in placed do
			if (spot - other).Magnitude < F.MinSpacing then
				ok = false
				break
			end
		end
		if not ok then
			continue
		end

		table.insert(placed, spot)
		plantAt(x, z, pickSpeciesId())
	end
	print(("[Forest] planted %d trees."):format(#placed))
end

return Forest
