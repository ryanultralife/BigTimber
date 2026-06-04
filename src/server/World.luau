--!strict
-- World builder for Big Timber.
--
-- MAP LAYOUT (Z axis, +Z = north, -Z = south toward town):
--
--   +Z  ────────────────────────────────────────────────────────────
--        FOREST HILLS  (pine, oak, redwood on rolling terrain)
--        Dirt logging roads branch through here.
--   z=+150
--        FLAT LOGGING YARD  (spawn, truck parking, flat ground)
--   z=0  [SPAWN]
--        Paved road leaves the yard heading SOUTH (decreasing Z)
--   z=-130
--        TUNNEL HILL  (terrain rises either side; road punches through)
--   z=-270  [TUNNEL]
--   z=-390
--        VALLEY — post-tunnel, flatter ground
--        SAWMILL  at z=-420
--        Road continues south...
--   z=-560  [SHOP — Big Dale, NPC dealer]
--   -Z  ────────────────────────────────────────────────────────────
--
-- World.surfaceAt(x,z) is the authoritative heightmap used both by the
-- terrain generator and by Forest to plant trees on the surface.

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local World = {}

local T = GameConfig.Terrain
local M = GameConfig.Mill
local S = GameConfig.Shop

-- ═════════════════════════════════ helpers ══════════════════════════

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function hillAt(x: number, z: number): number
	local n1 = math.noise(x / T.NoiseScale, z / T.NoiseScale, 0)
	local n2 = math.noise(x / (T.NoiseScale * 0.45) + 50, z / (T.NoiseScale * 0.45) + 50, 9)
	return math.clamp((n1 * 0.7 + n2 * 0.3) + 0.5, 0, 1) * T.HillAmplitude
end

function World.surfaceAt(x: number, z: number): number
	-- Base Perlin hills, flattened near the spawn yard.
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

	-- Lake (northeast forest, decorative).
	local lx = x - T.LakeCenter.X
	local lz = z - T.LakeCenter.Z
	local dl = math.sqrt(lx * lx + lz * lz)
	if dl < T.LakeRadius then
		surface = math.min(surface, -T.LakeDepth * smoothstep(1 - dl / T.LakeRadius))
	end

	-- Tunnel hill: raised ridge south of the yard; road corridor stays flat.
	-- The tunnel model provides ceiling/walls at road level inside the hill.
	local dth = math.abs(z - T.TunnelHillZ)
	if dth < T.TunnelHillRadius then
		local bump = T.TunnelHillHeight * smoothstep(1 - dth / T.TunnelHillRadius)
		if math.abs(x) > T.TunnelRoadHW then
			-- Sides of the hill rise up.
			surface = math.max(surface, bump)
		else
			-- Road corridor: keep flat even inside the raised hill.
			surface = math.min(surface, 0)
		end
	end

	-- Valley floor south of the tunnel: gently flatten for the mill/shop area.
	if z < T.TunnelHillZ - T.TunnelHillRadius then
		local valleyT = math.clamp(
			(-(z - (T.TunnelHillZ - T.TunnelHillRadius))) / 120, 0, 1)
		surface = surface * (1 - smoothstep(valleyT))
	end

	return surface
end

-- ═════════════════════════════════ terrain ══════════════════════════

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = true
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do (p :: any)[k] = v end
	return p
end

local function generateTerrain()
	local terrain = Workspace.Terrain
	terrain:Clear()
	local half, cell = T.HalfExtent, T.CellSize
	for x = -half, half, cell do
		for z = -half, half, cell do
			local s = World.surfaceAt(x, z)
			local height = s - T.FloorY
			if height > 0 then
				local mat = Enum.Material.Grass
				if s < -2 then mat = Enum.Material.Sand
				elseif s > 32 then mat = Enum.Material.Rock
				elseif s > 14 then mat = Enum.Material.LeafyGrass end
				terrain:FillBlock(CFrame.new(x, T.FloorY + height / 2, z),
					Vector3.new(cell, height, cell), mat)
			end
			-- Lake water.
			local lx2 = x - T.LakeCenter.X
			local lz2 = z - T.LakeCenter.Z
			if math.sqrt(lx2 * lx2 + lz2 * lz2) < T.LakeRadius and s < -1 then
				local wh = -2 - s
				if wh > 0 then
					terrain:FillBlock(CFrame.new(x, (s - 2) / 2, z),
						Vector3.new(cell, wh, cell), Enum.Material.Water)
				end
			end
		end
	end
end

-- ═════════════════════════════════ spawn ════════════════════════════

local function buildSpawn()
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "YardSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(16, 1, 16)
	spawn.CFrame = CFrame.new(0, 0.5, 20)	-- slightly north of centre, faces south
	spawn.Material = Enum.Material.WoodPlanks
	spawn.Color = Color3.fromRGB(120, 90, 58)
	spawn.Duration = 0
	spawn.Parent = Workspace

	-- Log storage racks on the flat yard
	for _, rx in { -40, 40 } do
		local rack = part({ Name = "LogRack",
			Size = Vector3.new(20, 4, 4),
			Position = Vector3.new(rx, 2, 60),
			Color = Color3.fromRGB(86, 60, 38), Material = Enum.Material.Wood })
		rack.Parent = Workspace
		-- Stacked log rounds on the rack
		for k = 0, 2 do
			local logStack = part({ Name = "LogStack",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(3.8, 1.8, 1.8),
				CFrame = CFrame.new(rx, 3.4 + k * 1.9, 60) * CFrame.Angles(0, math.rad(90), 0),
				Color = Color3.fromRGB(128, 88, 58), Material = Enum.Material.Wood })
			logStack.Parent = Workspace
		end
	end

	-- Welcome sign facing south (players see it as they walk toward the road)
	local sign = part({ Name = "WelcomeSign",
		Size = Vector3.new(22, 7, 0.6),
		Position = Vector3.new(0, 5, -28),
		Color = Color3.fromRGB(86, 58, 36), Material = Enum.Material.WoodPlanks })
	sign.Parent = Workspace
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.CanvasSize = Vector2.new(660, 210)
	gui.Parent = sign
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.52)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.Text = "BIG TIMBER"
	title.TextColor3 = Color3.fromRGB(255, 224, 130)
	title.TextScaled = true
	title.Parent = gui
	local sub = Instance.new("TextLabel")
	sub.Position = UDim2.fromScale(0, 0.54)
	sub.Size = UDim2.fromScale(1, 0.44)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamMedium
	sub.Text = "Chop north  •  Drive south to the mill  •  See Big Dale for upgrades"
	sub.TextColor3 = Color3.fromRGB(230, 235, 245)
	sub.TextScaled = true
	sub.Parent = gui
end

-- ═════════════════════════════════ roads ════════════════════════════

local function buildRoads()
	local terrain = Workspace.Terrain

	local function roadSeg(x1: number, z1: number, x2: number, z2: number,
		width: number, mat: Enum.Material)
		local dx, dz = x2 - x1, z2 - z1
		local steps = math.ceil(math.sqrt(dx * dx + dz * dz) / 2.5)
		for i = 0, steps do
			local t = i / steps
			local x = x1 + dx * t
			local z = z1 + dz * t
			local y = World.surfaceAt(x, z)
			terrain:FillBlock(CFrame.new(x, y - 0.6, z),
				Vector3.new(width, 2.0, 3.2), mat)
		end
	end

	-- Paved main road: yard (z=-30) south all the way past the mill to the shop
	roadSeg(0, -30, 0, -600, 16, Enum.Material.Pavement)

	-- Turning apron in front of the yard
	terrain:FillBlock(CFrame.new(0, -0.5, -30),
		Vector3.new(32, 1.5, 28), Enum.Material.Pavement)

	-- Painted centre line (bright stripe)
	roadSeg(0, -30, 0, -600, 1.5, Enum.Material.SmoothPlastic)

	-- Road shoulder markings (decorative concrete strips each side)
	for _, sx in { 9, -9 } do
		roadSeg(sx, -30, sx, -600, 1.2, Enum.Material.Concrete)
	end

	-- Dirt logging road NORTH through the forest (from yard edge)
	local northRoad = {
		{0, 140}, {0, 200}, {18, 260}, {40, 320}, {70, 375}, {95, 420},
	}
	for i = 1, #northRoad - 1 do
		roadSeg(northRoad[i][1], northRoad[i][2],
			northRoad[i+1][1], northRoad[i+1][2], 10, Enum.Material.Ground)
	end

	-- Dirt road NE branch
	local neRoad = {
		{40, 320}, {85, 355}, {135, 390}, {185, 415}, {230, 425},
	}
	for i = 1, #neRoad - 1 do
		roadSeg(neRoad[i][1], neRoad[i][2],
			neRoad[i+1][1], neRoad[i+1][2], 9, Enum.Material.Ground)
	end

	-- Dirt road NW branch
	local nwRoad = {
		{0, 200}, {-40, 255}, {-85, 300}, {-130, 335}, {-165, 358},
	}
	for i = 1, #nwRoad - 1 do
		roadSeg(nwRoad[i][1], nwRoad[i][2],
			nwRoad[i+1][1], nwRoad[i+1][2], 9, Enum.Material.Ground)
	end

	-- Dirt road east spur (flatter east slope)
	local eRoad = {
		{80, 50}, {130, 80}, {185, 120}, {230, 165}, {260, 210},
	}
	for i = 1, #eRoad - 1 do
		roadSeg(eRoad[i][1], eRoad[i][2],
			eRoad[i+1][1], eRoad[i+1][2], 8, Enum.Material.Ground)
	end

	-- Dirt road west spur
	local wRoad = {
		{-80, 50}, {-130, 75}, {-185, 115}, {-230, 158}, {-258, 200},
	}
	for i = 1, #wRoad - 1 do
		roadSeg(wRoad[i][1], wRoad[i][2],
			wRoad[i+1][1], wRoad[i+1][2], 8, Enum.Material.Ground)
	end

	-- Small paved spur into the mill log yard (branch off main road)
	roadSeg(-24, M.Position.Z, M.Position.X - 24, M.Position.Z, 10, Enum.Material.Pavement)
end

-- ═════════════════════════════════ tunnel ═══════════════════════════

local function buildTunnel()
	local TZ = T.TunnelHillZ           -- -270
	local HALF = T.TunnelHillRadius * 0.44 -- half length of the actual tunnel tube (~57)
	local W = T.TunnelRoadHW * 2 + 4  -- interior width (~26)
	local H = 16                       -- interior height
	local WT = 2.8                     -- wall thickness
	local CT = 4                       -- ceiling thickness
	local STONE = Color3.fromRGB(84, 80, 74)
	local CONC = Color3.fromRGB(100, 97, 92)
	local ARCH_STEPS = 16
	local SECT_LEN = (HALF * 2) / ARCH_STEPS

	local model = Instance.new("Model")
	model.Name = "Tunnel"

	local function mp(props: { [string]: any }): Part
		local p2 = Instance.new("Part")
		p2.Anchored = true
		p2.TopSurface = Enum.SurfaceType.Smooth
		p2.BottomSurface = Enum.SurfaceType.Smooth
		p2.CanCollide = true
		p2.Material = Enum.Material.Concrete
		for k, v in props do (p2 :: any)[k] = v end
		return p2
	end

	-- Build arch sections
	for i = 0, ARCH_STEPS - 1 do
		local sz = (TZ - HALF) + i * SECT_LEN + SECT_LEN / 2
		local sl = SECT_LEN + 0.15 -- slight overlap

		-- Left wall
		mp({ Name = "TWallL", Size = Vector3.new(WT, H + CT, sl),
			Position = Vector3.new(-(W / 2 + WT / 2), (H + CT) / 2, sz),
			Color = CONC }):Parent(model)

		-- Right wall
		mp({ Name = "TwallR", Size = Vector3.new(WT, H + CT, sl),
			Position = Vector3.new(W / 2 + WT / 2, (H + CT) / 2, sz),
			Color = CONC }):Parent(model)

		-- Ceiling
		mp({ Name = "TCeil", Size = Vector3.new(W + WT * 2, CT, sl),
			Position = Vector3.new(0, H + CT / 2, sz),
			Color = CONC }):Parent(model)

		-- Ceiling light strip every other section
		if i % 2 == 0 then
			local lamp = mp({ Name = "TunnelLight",
				Size = Vector3.new(W - 4, 0.45, 1.4),
				Position = Vector3.new(0, H - 0.3, sz),
				Color = Color3.fromRGB(255, 248, 210),
				Material = Enum.Material.Neon,
				CanCollide = false })
			lamp.Parent = model
		end

		-- Road kerb (low trim strips inside at road level)
		for _, kx in { W / 2 - 0.8, -(W / 2 - 0.8) } do
			mp({ Name = "Kerb", Size = Vector3.new(0.9, 0.7, sl),
				Position = Vector3.new(kx, 0.35, sz),
				Color = Color3.fromRGB(230, 228, 222) }):Parent(model)
		end
	end

	-- Portal frames (decorative stone frames at each tunnel mouth)
	for _, pz in { TZ - HALF - 0.5, TZ + HALF + 0.5 } do
		-- Side pilasters
		for _, px in { -(W / 2 + WT + 1.5), W / 2 + WT + 1.5 } do
			mp({ Name = "Portal",
				Size = Vector3.new(3.5, H + CT + 6, 3.5),
				Position = Vector3.new(px, (H + CT + 6) / 2, pz),
				Color = STONE }):Parent(model)
		end
		-- Lintel
		mp({ Name = "Lintel",
			Size = Vector3.new(W + WT * 2 + 10, 3.5, 3.5),
			Position = Vector3.new(0, H + CT + 5, pz),
			Color = STONE }):Parent(model)
		-- "BIG TIMBER" carved portal sign
		local sign = mp({ Name = "PortalSign",
			Size = Vector3.new(W + WT * 2 + 6, 2.0, 0.5),
			Position = Vector3.new(0, H + CT + 2, pz - (pz < 0 and -0.3 or 0.3)),
			Color = Color3.fromRGB(60, 56, 50), CanCollide = false })
		sign.Parent = model
		local sg = Instance.new("SurfaceGui")
		sg.Face = if pz < 0 then Enum.NormalId.Back else Enum.NormalId.Front
		sg.CanvasSize = Vector2.new(400, 80)
		sg.Parent = sign
		local sl2 = Instance.new("TextLabel")
		sl2.Size = UDim2.fromScale(1, 1)
		sl2.BackgroundTransparency = 1
		sl2.Font = Enum.Font.FredokaOne
		sl2.Text = "BIG TIMBER"
		sl2.TextColor3 = Color3.fromRGB(255, 220, 100)
		sl2.TextScaled = true
		sl2.Parent = sg
	end

	model.Parent = Workspace
end

-- ══════════════════════════════════ mill ════════════════════════════
-- (Same detailed mill as before, repositioned to GameConfig.Mill.Position)

local function buildMill()
	local P = M.Position
	local model = Instance.new("Model")
	model.Name = "Mill"
	local STEEL = Color3.fromRGB(48, 52, 58)
	local WOOD = Color3.fromRGB(96, 70, 46)
	local ROOF_C = Color3.fromRGB(88, 44, 36)
	local MC = Color3.fromRGB(180, 185, 192)

	local function mp(props: { [string]: any }): Part
		local p2 = Instance.new("Part")
		p2.Anchored = true
		p2.TopSurface = Enum.SurfaceType.Smooth
		p2.BottomSurface = Enum.SurfaceType.Smooth
		p2.CanCollide = true
		p2.Material = Enum.Material.SmoothPlastic
		for k, v in props do (p2 :: any)[k] = v end
		return p2
	end

	local function cyl(props: { [string]: any }): Part
		local c = mp(props)
		c.Shape = Enum.PartType.Cylinder
		return c
	end

	local function add(p2: Part): Part
		p2.Parent = model; return p2
	end

	-- Concrete apron
	local apron = add(mp({ Name = "Apron",
		Size = Vector3.new(100, 0.8, 72),
		Position = P + Vector3.new(0, -0.4, 0),
		Color = Color3.fromRGB(118, 116, 112), Material = Enum.Material.Concrete }))
	model.PrimaryPart = apron

	-- Steel frame posts
	for _, px in { -22, 0, 22 } do
		for _, pz in { -14, 14 } do
			add(mp({ Name = "Post", Size = Vector3.new(1.0, 22, 1.0),
				Position = P + Vector3.new(px, 11, pz),
				Color = STEEL, Material = Enum.Material.Metal }))
		end
	end
	for _, pz in { -14, -5, 5, 14 } do
		add(mp({ Name = "Truss", Size = Vector3.new(48, 0.7, 0.7),
			Position = P + Vector3.new(0, 21.6, pz),
			Color = STEEL, Material = Enum.Material.Metal }))
	end
	-- Gabled roof
	add(mp({ Name = "RoofL", Size = Vector3.new(52, 0.55, 18),
		CFrame = CFrame.new(P + Vector3.new(-11, 22.5, 0)) * CFrame.Angles(0, 0, math.rad(18)),
		Color = ROOF_C, Material = Enum.Material.Metal }))
	add(mp({ Name = "RoofR", Size = Vector3.new(52, 0.55, 18),
		CFrame = CFrame.new(P + Vector3.new(11, 22.5, 0)) * CFrame.Angles(0, 0, math.rad(-18)),
		Color = ROOF_C, Material = Enum.Material.Metal }))
	add(mp({ Name = "WallS", Size = Vector3.new(50, 20, 0.55),
		Position = P + Vector3.new(0, 10, 15),
		Color = Color3.fromRGB(128, 58, 46), Material = Enum.Material.Metal }))
	add(mp({ Name = "WallW", Size = Vector3.new(0.55, 20, 30),
		Position = P + Vector3.new(-24, 10, 0),
		Color = Color3.fromRGB(128, 58, 46), Material = Enum.Material.Metal }))
	add(mp({ Name = "WallE", Size = Vector3.new(0.55, 20, 30),
		Position = P + Vector3.new(24, 10, 0),
		Color = Color3.fromRGB(128, 58, 46), Material = Enum.Material.Metal }))

	-- Log deck / rollway
	add(mp({ Name = "LogDeck", Size = Vector3.new(52, 0.8, 22),
		Position = P + Vector3.new(0, 0.4, -26),
		Color = Color3.fromRGB(106, 104, 100), Material = Enum.Material.Concrete }))
	for k = 0, 9 do
		add(cyl({ Name = "Roller", Size = Vector3.new(15, 0.72, 0.72),
			CFrame = CFrame.new(P + Vector3.new(0, 1.55, -16 + k * 1.5)),
			Color = MC, Material = Enum.Material.Metal }))
	end
	for _, gx in { -7.5, 7.5 } do
		add(mp({ Name = "Guide", Size = Vector3.new(0.5, 1.6, 16),
			Position = P + Vector3.new(gx, 1.1, -12),
			Color = STEEL, Material = Enum.Material.Metal }))
	end

	-- Debarker
	add(mp({ Name = "DebarkerFrame", Size = Vector3.new(12, 10, 8),
		Position = P + Vector3.new(0, 5, -3),
		Color = STEEL, Material = Enum.Material.Metal }))
	add(cyl({ Name = "DebarkerDrum", Size = Vector3.new(10, 6.5, 6.5),
		CFrame = CFrame.new(P + Vector3.new(0, 5, -3)),
		Color = Color3.fromRGB(78, 80, 84), Material = Enum.Material.Metal, Reflectance = 0.15 }))
	for _, nx in { -4, -1.3, 1.3, 4 } do
		add(cyl({ Name = "Nozzle", Size = Vector3.new(0.8, 0.38, 0.38),
			CFrame = CFrame.new(P + Vector3.new(nx, 9.2, -3)),
			Color = MC, Material = Enum.Material.Metal, CanCollide = false }))
	end

	-- Band-saw columns + wheels + blade
	for _, sx in { -3.5, 3.5 } do
		add(mp({ Name = "SawColumn", Size = Vector3.new(0.9, 14, 0.9),
			Position = P + Vector3.new(sx, 7, 5),
			Color = STEEL, Material = Enum.Material.Metal }))
	end
	for _, sy in { 13.5, 1.5 } do
		add(cyl({ Name = "SawWheel", Size = Vector3.new(1.5, 5.0, 5.0),
			CFrame = CFrame.new(P + Vector3.new(0, sy, 5)),
			Color = Color3.fromRGB(55, 58, 62), Material = Enum.Material.Metal }))
	end
	add(mp({ Name = "SawBlade", Size = Vector3.new(0.22, 12, 0.9),
		Position = P + Vector3.new(0, 7.5, 5),
		Color = Color3.fromRGB(210, 215, 222), Material = Enum.Material.Metal, Reflectance = 0.35 }))
	for _, gy in { 13, 2 } do
		add(mp({ Name = "BladeGuard", Size = Vector3.new(9, 2.5, 4),
			Position = P + Vector3.new(0, gy, 5),
			Color = Color3.fromRGB(220, 190, 40), Material = Enum.Material.Metal }))
	end
	add(mp({ Name = "SawdustChute", Size = Vector3.new(10, 0.5, 4),
		CFrame = CFrame.new(P + Vector3.new(0, 2.5, 8)) * CFrame.Angles(0, 0, math.rad(-12)),
		Color = WOOD }))

	-- Log carriage + rails
	for _, crx in { -5, 5 } do
		add(mp({ Name = "Rail", Size = Vector3.new(0.55, 0.55, 22),
			Position = P + Vector3.new(crx, 1.0, 4),
			Color = MC, Material = Enum.Material.Metal }))
	end
	add(mp({ Name = "Carriage", Size = Vector3.new(12, 1.0, 4.5),
		Position = P + Vector3.new(0, 1.55, -4),
		Color = Color3.fromRGB(60, 130, 60), Material = Enum.Material.Metal }))
	for _, dz in { -1.5, 1.5 } do
		add(mp({ Name = "Dog", Size = Vector3.new(1.0, 2.5, 0.7),
			Position = P + Vector3.new(0, 2.8, -4 + dz),
			Color = STEEL, Material = Enum.Material.Metal }))
	end

	-- Green chain
	local gcFolder = Instance.new("Folder")
	gcFolder.Name = "GreenChain"
	gcFolder.Parent = model
	add(mp({ Name = "ChainFrame", Size = Vector3.new(16, 0.8, 28),
		Position = P + Vector3.new(16, 0.8, -2),
		Color = Color3.fromRGB(36, 96, 36), Material = Enum.Material.Metal }))
	for k = 0, 12 do
		local r = cyl({ Name = "GCRoller", Size = Vector3.new(15, 0.65, 0.65),
			CFrame = CFrame.new(P + Vector3.new(16, 1.45, -13 + k * 2.1)),
			Color = MC, Material = Enum.Material.Metal })
		r.Parent = gcFolder
	end
	for _, sx in { 23.5, 8.5 } do
		add(mp({ Name = "ChainWall", Size = Vector3.new(0.4, 1.8, 28),
			Position = P + Vector3.new(sx, 1.6, -2),
			Color = Color3.fromRGB(36, 96, 36), Material = Enum.Material.Metal }))
	end

	-- Edger
	add(mp({ Name = "EdgerFrame", Size = Vector3.new(6, 8, 6),
		Position = P + Vector3.new(16, 4, 10),
		Color = STEEL, Material = Enum.Material.Metal }))
	for _, ex in { 14.5, 17.5 } do
		add(cyl({ Name = "EdgerBlade", Size = Vector3.new(0.3, 4.8, 4.8),
			CFrame = CFrame.new(P + Vector3.new(ex, 4.5, 10)),
			Color = MC, Material = Enum.Material.Metal, Reflectance = 0.3 }))
	end

	-- Board stacking yard + forklift
	add(mp({ Name = "StackingPad", Size = Vector3.new(22, 0.5, 30),
		Position = P + Vector3.new(34, 0.25, -2),
		Color = Color3.fromRGB(106, 104, 100), Material = Enum.Material.Concrete }))
	for k = 0, 2 do
		add(mp({ Name = "BoardStack", Size = Vector3.new(12, 0.5 + k * 0.9, 3),
			Position = P + Vector3.new(34, 0.75 + k * 0.45, -6 + k * 6),
			Color = Color3.fromRGB(205, 170, 110), Material = Enum.Material.WoodPlanks }))
	end

	-- Intake pad (glowing, where trucks pull up to unload)
	add(cyl({ Name = "IntakePad",
		Size = Vector3.new(0.55, M.IntakeRadius * 2, M.IntakeRadius * 2),
		CFrame = CFrame.new(P + Vector3.new(0, 0.4, -22)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(90, 220, 120), Material = Enum.Material.Neon,
		Transparency = 0.40, CanCollide = false }))

	-- Billboard sign
	local board = add(mp({ Name = "Sign", Size = Vector3.new(22, 6, 0.5),
		Position = P + Vector3.new(0, 27, 15.4),
		Color = WOOD }))
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.CanvasSize = Vector2.new(660, 180)
	sg.Parent = board
	local sl = Instance.new("TextLabel")
	sl.Size = UDim2.fromScale(1, 1)
	sl.BackgroundTransparency = 1
	sl.Font = Enum.Font.FredokaOne
	sl.Text = "BIG TIMBER SAWMILL"
	sl.TextColor3 = Color3.fromRGB(255, 230, 120)
	sl.TextScaled = true
	sl.Parent = sg

	model.Parent = Workspace
end

-- ══════════════════════════════════ shop ════════════════════════════
-- Big Dale's Equipment shop: a building with an NPC dealer inside.
-- The actual ProximityPrompt + OpenShop firing is in ShopNPC.luau;
-- here we just build the physical structure.

local function buildShop()
	local P = S.Position -- (0, 0, -560)
	local model = Instance.new("Model")
	model.Name = "Shop"
	local LOG_WALL = Color3.fromRGB(100, 72, 50)
	local ROOF_C = Color3.fromRGB(70, 44, 36)
	local TRIM = Color3.fromRGB(220, 200, 140)

	local function mp(props: { [string]: any }): Part
		local p2 = Instance.new("Part")
		p2.Anchored = true
		p2.TopSurface = Enum.SurfaceType.Smooth
		p2.BottomSurface = Enum.SurfaceType.Smooth
		p2.CanCollide = true
		p2.Material = Enum.Material.SmoothPlastic
		for k, v in props do (p2 :: any)[k] = v end
		return p2
	end

	-- Concrete foundation
	mp({ Name = "Foundation", Size = Vector3.new(36, 0.8, 28),
		Position = P + Vector3.new(0, -0.4, 0),
		Color = Color3.fromRGB(110, 108, 104), Material = Enum.Material.Concrete }):Parent(model)

	-- Log-cabin style walls (south face open for entry)
	-- North wall
	mp({ Name = "WallN", Size = Vector3.new(36, 14, 1.0),
		Position = P + Vector3.new(0, 7, 14),
		Color = LOG_WALL, Material = Enum.Material.Wood }):Parent(model)
	-- East wall
	mp({ Name = "WallE", Size = Vector3.new(1.0, 14, 28),
		Position = P + Vector3.new(18, 7, 0),
		Color = LOG_WALL, Material = Enum.Material.Wood }):Parent(model)
	-- West wall
	mp({ Name = "WallW", Size = Vector3.new(1.0, 14, 28),
		Position = P + Vector3.new(-18, 7, 0),
		Color = LOG_WALL, Material = Enum.Material.Wood }):Parent(model)
	-- South wall with door opening (two side panels + header)
	mp({ Name = "DoorL", Size = Vector3.new(11, 14, 1.0),
		Position = P + Vector3.new(-12.5, 7, -14),
		Color = LOG_WALL, Material = Enum.Material.Wood }):Parent(model)
	mp({ Name = "DoorR", Size = Vector3.new(11, 14, 1.0),
		Position = P + Vector3.new(12.5, 7, -14),
		Color = LOG_WALL, Material = Enum.Material.Wood }):Parent(model)
	mp({ Name = "DoorHeader", Size = Vector3.new(14, 3, 1.0),
		Position = P + Vector3.new(0, 11.5, -14),
		Color = LOG_WALL, Material = Enum.Material.Wood }):Parent(model)

	-- Roof (simple gable)
	mp({ Name = "RoofL", Size = Vector3.new(40, 0.6, 18),
		CFrame = CFrame.new(P + Vector3.new(-9, 16.5, 0)) * CFrame.Angles(0, 0, math.rad(20)),
		Color = ROOF_C, Material = Enum.Material.Metal }):Parent(model)
	mp({ Name = "RoofR", Size = Vector3.new(40, 0.6, 18),
		CFrame = CFrame.new(P + Vector3.new(9, 16.5, 0)) * CFrame.Angles(0, 0, math.rad(-20)),
		Color = ROOF_C, Material = Enum.Material.Metal }):Parent(model)

	-- Interior floor
	mp({ Name = "Floor", Size = Vector3.new(34, 0.5, 26),
		Position = P + Vector3.new(0, 0.25, 0),
		Color = Color3.fromRGB(110, 80, 54), Material = Enum.Material.WoodPlanks }):Parent(model)

	-- Counter / desk where Dale stands
	mp({ Name = "Counter", Size = Vector3.new(14, 3.5, 3),
		Position = P + Vector3.new(0, 1.75, 8),
		Color = Color3.fromRGB(130, 96, 62), Material = Enum.Material.WoodPlanks }):Parent(model)
	mp({ Name = "CounterTop", Size = Vector3.new(14.5, 0.4, 3.5),
		Position = P + Vector3.new(0, 3.7, 8),
		Color = Color3.fromRGB(90, 68, 46), Material = Enum.Material.Wood }):Parent(model)

	-- Shelves with equipment props
	for _, sx in { -13, 13 } do
		mp({ Name = "Shelf", Size = Vector3.new(0.5, 10, 22),
			Position = P + Vector3.new(sx, 5, 2),
			Color = LOG_WALL, Material = Enum.Material.Wood }):Parent(model)
		for k = 0, 3 do
			mp({ Name = "ShelfPlank", Size = Vector3.new(1.5, 0.35, 20),
				Position = P + Vector3.new(sx + (sx > 0 and -0.7 or 0.7), 2.5 + k * 2.5, 2),
				Color = Color3.fromRGB(140, 105, 68), Material = Enum.Material.WoodPlanks }):Parent(model)
		end
	end

	-- Hanging sign above door
	local sign = mp({ Name = "ShopSign",
		Size = Vector3.new(14, 4, 0.6),
		Position = P + Vector3.new(0, 16.5, -14.5),
		Color = Color3.fromRGB(80, 54, 32) })
	sign.Parent = model
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.CanvasSize = Vector2.new(420, 120)
	sg.Parent = sign
	local sl = Instance.new("TextLabel")
	sl.Size = UDim2.fromScale(1, 0.55)
	sl.BackgroundTransparency = 1
	sl.Font = Enum.Font.FredokaOne
	sl.Text = "BIG DALE'S"
	sl.TextColor3 = Color3.fromRGB(255, 220, 90)
	sl.TextScaled = true
	sl.Parent = sg
	local sl2 = Instance.new("TextLabel")
	sl2.Position = UDim2.fromScale(0, 0.57)
	sl2.Size = UDim2.fromScale(1, 0.40)
	sl2.BackgroundTransparency = 1
	sl2.Font = Enum.Font.GothamBold
	sl2.Text = "Equipment & Upgrades"
	sl2.TextColor3 = Color3.fromRGB(235, 230, 210)
	sl2.TextScaled = true
	sl2.Parent = sg

	-- Outdoor parking/approach pad
	mp({ Name = "Approach", Size = Vector3.new(36, 0.5, 22),
		Position = P + Vector3.new(0, 0.25, -24),
		Color = Color3.fromRGB(110, 108, 104), Material = Enum.Material.Concrete }):Parent(model)

	model.Parent = Workspace
end

-- ═════════════════════════════════ borders ══════════════════════════

local function buildBorders()
	local half = T.HalfExtent + 8
	local folder = Instance.new("Folder")
	folder.Name = "Borders"
	for _, def in {
		{ Vector3.new(half * 2, 130, 4), Vector3.new(0, 50, -half) },
		{ Vector3.new(half * 2, 130, 4), Vector3.new(0, 50, half) },
		{ Vector3.new(4, 130, half * 2), Vector3.new(-half, 50, 0) },
		{ Vector3.new(4, 130, half * 2), Vector3.new(half, 50, 0) },
	} do
		local wall = part({ Name = "Wall", Size = def[1], Position = def[2],
			Transparency = 1, CanCollide = true })
		wall.Parent = folder
	end
	folder.Parent = Workspace
end

-- ═════════════════════════════════ entry ════════════════════════════

function World.build()
	print("[World] generating terrain…")
	generateTerrain()
	buildBorders()
	buildSpawn()
	buildRoads()
	buildTunnel()
	buildMill()
	buildShop()
	print("[World] done.")
end

return World
