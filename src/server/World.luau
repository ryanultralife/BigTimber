--!strict
-- Builds the map: a square of voxel terrain with a flat central yard
-- (mill + spawn), rolling forested hills around it, and a lake off to one
-- side. Logging-Inc style: real Roblox Terrain, not a flat baseplate.
--
-- Terrain is generated procedurally at boot from a math.noise heightmap so
-- the place file stays tiny and the map is easy to retune from GameConfig.
-- World.surfaceAt(x, z) is the exact heightmap the generator used, so the
-- Forest can plant trees on the ground without raycasting.

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local World = {}

local T = GameConfig.Terrain

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Two octaves of Perlin → broad hills with some finer roll on top.
local function hillAt(x: number, z: number): number
	local n1 = math.noise(x / T.NoiseScale, z / T.NoiseScale, 0)
	local n2 = math.noise(x / (T.NoiseScale * 0.45) + 50, z / (T.NoiseScale * 0.45) + 50, 9)
	local n = (n1 * 0.7 + n2 * 0.3) + 0.5
	return math.clamp(n, 0, 1) * T.HillAmplitude
end

-- The authoritative surface height at (x, z): flat in the yard, ramping up
-- to hills past the blend band, carved down inside the lake.
function World.surfaceAt(x: number, z: number): number
	local distC = math.sqrt(x * x + z * z)
	local hill = hillAt(x, z)
	local surface: number
	if distC <= T.YardRadius then
		surface = 0
	elseif distC <= T.YardRadius + T.YardBlend then
		surface = hill * smoothstep((distC - T.YardRadius) / T.YardBlend)
	else
		surface = hill
	end

	local lx = x - T.LakeCenter.X
	local lz = z - T.LakeCenter.Z
	local dl = math.sqrt(lx * lx + lz * lz)
	if dl < T.LakeRadius then
		local lakeSurface = -T.LakeDepth * smoothstep(1 - dl / T.LakeRadius)
		surface = math.min(surface, lakeSurface)
	end
	return surface
end

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local function generateTerrain()
	local terrain = Workspace.Terrain
	terrain:Clear()
	local half = T.HalfExtent
	local cell = T.CellSize
	for x = -half, half, cell do
		for z = -half, half, cell do
			local s = World.surfaceAt(x, z)
			local height = s - T.FloorY
			if height > 0 then
				local mat = Enum.Material.Grass
				if s < -2 then
					mat = Enum.Material.Sand -- lakebed
				elseif s > 30 then
					mat = Enum.Material.Rock -- bald hilltops
				elseif s > 12 then
					mat = Enum.Material.LeafyGrass
				end
				terrain:FillBlock(
					CFrame.new(x, T.FloorY + height / 2, z),
					Vector3.new(cell, height, cell),
					mat
				)
			end
			-- Lake water sits from the carved bed up to just below yard level.
			local lx = x - T.LakeCenter.X
			local lz = z - T.LakeCenter.Z
			if math.sqrt(lx * lx + lz * lz) < T.LakeRadius and s < -1 then
				local waterTop = -2
				local wh = waterTop - s
				if wh > 0 then
					terrain:FillBlock(
						CFrame.new(x, (s + waterTop) / 2, z),
						Vector3.new(cell, wh, cell),
						Enum.Material.Water
					)
				end
			end
		end
	end
end

local function buildSpawn()
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "YardSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.Position = Vector3.new(0, 0.5, -34)
	spawn.Material = Enum.Material.WoodPlanks
	spawn.Color = Color3.fromRGB(120, 90, 58)
	spawn.Duration = 0 -- no forcefield flicker
	spawn.Parent = Workspace

	-- A welcome sign behind the spawn.
	local sign = part({
		Name = "WelcomeSign",
		Size = Vector3.new(20, 7, 0.6),
		Position = Vector3.new(0, 5, -46),
		Color = Color3.fromRGB(86, 58, 36),
		Material = Enum.Material.WoodPlanks,
	})
	sign.Parent = Workspace

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(600, 210)
	gui.Parent = sign
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.55)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.Text = "BIG TIMBER"
	title.TextColor3 = Color3.fromRGB(255, 224, 130)
	title.TextScaled = true
	title.Parent = gui
	local sub = Instance.new("TextLabel")
	sub.Position = UDim2.fromScale(0, 0.58)
	sub.Size = UDim2.fromScale(1, 0.4)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamMedium
	sub.Text = "Chop trees  •  Haul to the mill  •  Sell  •  Upgrade"
	sub.TextColor3 = Color3.fromRGB(230, 235, 245)
	sub.TextScaled = true
	sub.Parent = gui
end

-- The sawmill. A deck, a roof frame, a spinning blade (spun by MillService),
-- and a glowing intake pad you drive your logs onto.
local function buildMill()
	local pos = GameConfig.Mill.Position
	local model = Instance.new("Model")
	model.Name = "Mill"

	local deck = part({
		Name = "Deck",
		Size = Vector3.new(46, 2, 30),
		Position = pos + Vector3.new(0, 1, 0),
		Color = Color3.fromRGB(96, 70, 46),
		Material = Enum.Material.WoodPlanks,
	})
	deck.Parent = model
	model.PrimaryPart = deck

	-- Roof posts + gable.
	for _, sx in { -20, 20 } do
		for _, sz in { -12, 12 } do
			local post = part({
				Name = "Post",
				Size = Vector3.new(1.4, 16, 1.4),
				Position = pos + Vector3.new(sx, 9, sz),
				Color = Color3.fromRGB(80, 56, 36),
				Material = Enum.Material.Wood,
			})
			post.Parent = model
		end
	end
	local roof = part({
		Name = "Roof",
		Size = Vector3.new(50, 1.5, 34),
		Position = pos + Vector3.new(0, 17.5, 0),
		Color = Color3.fromRGB(120, 50, 44),
		Material = Enum.Material.Metal,
	})
	roof.Parent = model

	-- Saw blade (a thin disc). Cylinder parts run along local X, so a disc
	-- faces ±X; MillService spins it about that axis.
	local blade = part({
		Name = "SawBlade",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 9, 9),
		Position = pos + Vector3.new(-22, 6, 0),
		Color = Color3.fromRGB(190, 195, 205),
		Material = Enum.Material.Metal,
		Reflectance = 0.3,
	})
	blade.Parent = model

	-- Glowing intake pad on the ground at the mill's front edge.
	local pad = part({
		Name = "IntakePad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, GameConfig.Mill.IntakeRadius * 2, GameConfig.Mill.IntakeRadius * 2),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.3, -2)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(90, 220, 120),
		Material = Enum.Material.Neon,
		Transparency = 0.45,
		CanCollide = false,
	})
	pad.Parent = model

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(260, 70)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 14, 0)
	billboard.AlwaysOnTop = false
	billboard.Parent = deck
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = "🪵 SAWMILL\nbring logs here"
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.4
	label.TextScaled = true
	label.Parent = billboard

	model.Parent = Workspace
end

-- Invisible walls so trucks and players can't drive off the map edge.
local function buildBorders()
	local half = T.HalfExtent + 8
	local folder = Instance.new("Folder")
	folder.Name = "Borders"
	for _, def in {
		{ Vector3.new(half * 2, 120, 4), Vector3.new(0, 40, -half) },
		{ Vector3.new(half * 2, 120, 4), Vector3.new(0, 40, half) },
		{ Vector3.new(4, 120, half * 2), Vector3.new(-half, 40, 0) },
		{ Vector3.new(4, 120, half * 2), Vector3.new(half, 40, 0) },
	} do
		local wall = part({
			Name = "Wall",
			Size = def[1],
			Position = def[2],
			Transparency = 1,
			CanCollide = true,
		})
		wall.Parent = folder
	end
	folder.Parent = Workspace
end

function World.build()
	print("[World] generating terrain…")
	generateTerrain()
	buildBorders()
	buildSpawn()
	buildMill()
	print("[World] done.")
end

return World
