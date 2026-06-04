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
-- ═══════════════════════════════════════════════════════════════════
-- SAWMILL — realistic industrial layout
--   Log yard (south) → rollway → debarker → head-rig saw → green chain
--   → edger station → board stacking yard (north)
--
-- Named parts read by MillService for animation:
--   "DebarkerDrum"   — spinning drum, axis = X
--   "SawBlade"       — band-saw disc, axis = X (kept for MillService compat)
--   "Carriage"       — log carriage that slides along Z rails when cutting
--   "GreenChain"     — output conveyor rollers folder
--   "IntakePad"      — proximity trigger for auto-unload
-- ═══════════════════════════════════════════════════════════════════
local function buildMill()
	local P = GameConfig.Mill.Position -- (0, 0, 92) — centre of complex
	local model = Instance.new("Model")
	model.Name = "Mill"
	local STEEL = Color3.fromRGB(48, 52, 58)
	local WOOD = Color3.fromRGB(96, 70, 46)
	local ROOF_C = Color3.fromRGB(88, 44, 36)
	local MC = Color3.fromRGB(180, 185, 192) -- machined metal

	local function mp(props: { [string]: any }): Part
		local pp = Instance.new("Part")
		pp.Anchored = true
		pp.TopSurface = Enum.SurfaceType.Smooth
		pp.BottomSurface = Enum.SurfaceType.Smooth
		pp.CanCollide = true
		pp.Material = Enum.Material.SmoothPlastic
		for k, v in props do (pp :: any)[k] = v end
		return pp
	end

	local function cyl(props: { [string]: any }): Part
		local c = mp(props); c.Shape = Enum.PartType.Cylinder; return c
	end

	local function add(p2: Part): Part
		p2.Parent = model; return p2
	end

	-- ── Concrete apron (the whole complex floor) ────────────────────
	local apron = add(mp({ Name = "Apron",
		Size = Vector3.new(100, 0.8, 70),
		Position = P + Vector3.new(0, -0.4, 0),
		Color = Color3.fromRGB(120, 118, 114), Material = Enum.Material.Concrete }))
	model.PrimaryPart = apron

	-- ── Steel frame posts (6 pairs, running N-S along Z) ────────────
	for _, px in { -22, 0, 22 } do
		for _, pz in { -14, 14 } do
			add(mp({ Name = "Post", Size = Vector3.new(1.0, 22, 1.0),
				Position = P + Vector3.new(px, 11, pz),
				Color = STEEL, Material = Enum.Material.Metal }))
		end
	end
	-- East-west roof trusses across the top
	for _, pz in { -14, -5, 5, 14 } do
		add(mp({ Name = "Truss", Size = Vector3.new(48, 0.7, 0.7),
			Position = P + Vector3.new(0, 21.6, pz),
			Color = STEEL, Material = Enum.Material.Metal }))
	end
	-- Roof (two angled panels for a gable)
	add(mp({ Name = "RoofL",
		Size = Vector3.new(52, 0.55, 18),
		CFrame = CFrame.new(P + Vector3.new(-11, 22.5, 0)) * CFrame.Angles(0, 0, math.rad(18)),
		Color = ROOF_C, Material = Enum.Material.Metal }))
	add(mp({ Name = "RoofR",
		Size = Vector3.new(52, 0.55, 18),
		CFrame = CFrame.new(P + Vector3.new(11, 22.5, 0)) * CFrame.Angles(0, 0, math.rad(-18)),
		Color = ROOF_C, Material = Enum.Material.Metal }))
	-- Corrugated wall panels (south face — open north for log intake)
	add(mp({ Name = "WallS",
		Size = Vector3.new(50, 20, 0.55),
		Position = P + Vector3.new(0, 10, 15),
		Color = Color3.fromRGB(130, 60, 46), Material = Enum.Material.Metal }))
	add(mp({ Name = "WallW",
		Size = Vector3.new(0.55, 20, 30),
		Position = P + Vector3.new(-24, 10, 0),
		Color = Color3.fromRGB(130, 60, 46), Material = Enum.Material.Metal }))
	add(mp({ Name = "WallE",
		Size = Vector3.new(0.55, 20, 30),
		Position = P + Vector3.new(24, 10, 0),
		Color = Color3.fromRGB(130, 60, 46), Material = Enum.Material.Metal }))

	-- ── Log yard / rollway (south, trucks park here) ─────────────────
	-- Concrete log deck
	add(mp({ Name = "LogDeck",
		Size = Vector3.new(50, 0.8, 20),
		Position = P + Vector3.new(0, 0.4, -26),
		Color = Color3.fromRGB(108, 106, 100), Material = Enum.Material.Concrete }))
	-- Rollway rollers (logs rest on these and roll into the mill)
	for k = 0, 7 do
		local rz = -16 + k * 1.6
		add(cyl({ Name = "Roller",
			Size = Vector3.new(14, 0.75, 0.75),
			CFrame = CFrame.new(P + Vector3.new(0, 1.55, rz)),
			Color = MC, Material = Enum.Material.Metal }))
	end
	-- Side guides (keep logs centred on the rollway)
	for _, gx in { -7.5, 7.5 } do
		add(mp({ Name = "Guide",
			Size = Vector3.new(0.5, 1.6, 14),
			Position = P + Vector3.new(gx, 1.1, -10),
			Color = STEEL, Material = Enum.Material.Metal }))
	end

	-- ── Debarker unit ────────────────────────────────────────────────
	-- Frame
	add(mp({ Name = "DebarkerFrame",
		Size = Vector3.new(12, 10, 8),
		Position = P + Vector3.new(0, 5, -4),
		Color = STEEL, Material = Enum.Material.Metal }))
	-- The spinning drum (MillService animates this)
	add(cyl({ Name = "DebarkerDrum",
		Size = Vector3.new(10, 6.5, 6.5),
		CFrame = CFrame.new(P + Vector3.new(0, 5, -4)),
		Color = Color3.fromRGB(80, 82, 86), Material = Enum.Material.Metal,
		Reflectance = 0.15 }))
	-- Feed-in funnel
	add(mp({ Name = "DebarkerFunnel",
		Size = Vector3.new(10, 1.2, 3.5),
		Position = P + Vector3.new(0, 8.8, -6.5),
		Color = STEEL, Material = Enum.Material.Metal }))
	-- Water spray nozzles (visual detail)
	for _, nx in { -4, -1.5, 1.5, 4 } do
		add(cyl({ Name = "Nozzle",
			Size = Vector3.new(0.8, 0.4, 0.4),
			CFrame = CFrame.new(P + Vector3.new(nx, 9.2, -4)),
			Color = MC, Material = Enum.Material.Metal,
			CanCollide = false }))
	end

	-- ── Head-rig / band-saw ───────────────────────────────────────────
	-- Vertical saw frame (two tall guide columns)
	for _, sx in { -3.5, 3.5 } do
		add(mp({ Name = "SawColumn",
			Size = Vector3.new(0.9, 14, 0.9),
			Position = P + Vector3.new(sx, 7, 5),
			Color = STEEL, Material = Enum.Material.Metal }))
	end
	-- Upper and lower wheels (band-saw wheels)
	for _, sy in { 13.5, 1.5 } do
		add(cyl({ Name = "SawWheel",
			Size = Vector3.new(1.5, 5.0, 5.0),
			CFrame = CFrame.new(P + Vector3.new(0, sy, 5)),
			Color = Color3.fromRGB(55, 58, 62), Material = Enum.Material.Metal }))
	end
	-- The band blade itself (thin flat box between the wheels — MillService spins it)
	add(mp({ Name = "SawBlade",
		Size = Vector3.new(0.22, 12, 0.9),
		Position = P + Vector3.new(0, 7.5, 5),
		Color = Color3.fromRGB(210, 215, 222), Material = Enum.Material.Metal,
		Reflectance = 0.35 }))
	-- Blade guard housings (top + bottom)
	for _, gy in { 13, 2 } do
		add(mp({ Name = "BladeGuard",
			Size = Vector3.new(9, 2.5, 4),
			Position = P + Vector3.new(0, gy, 5),
			Color = Color3.fromRGB(220, 190, 40), Material = Enum.Material.Metal }))
	end
	-- Sawdust chute (angled trough)
	add(mp({ Name = "SawdustChute",
		Size = Vector3.new(10, 0.5, 4),
		CFrame = CFrame.new(P + Vector3.new(0, 2.5, 8)) * CFrame.Angles(0, 0, math.rad(-12)),
		Color = WOOD }))

	-- ── Log carriage + rails ─────────────────────────────────────────
	-- Two horizontal rails the carriage slides along
	for _, crx in { -5, 5 } do
		add(mp({ Name = "Rail",
			Size = Vector3.new(0.55, 0.55, 20),
			Position = P + Vector3.new(crx, 1.0, 3),
			Color = MC, Material = Enum.Material.Metal }))
	end
	-- The carriage itself (MillService slides this along Z)
	add(mp({ Name = "Carriage",
		Size = Vector3.new(12, 1.0, 4.5),
		Position = P + Vector3.new(0, 1.55, -4),
		Color = Color3.fromRGB(60, 130, 60), Material = Enum.Material.Metal }))
	-- Carriage dogs (the steel clamps that grip the log)
	for _, dz in { -1.5, 1.5 } do
		add(mp({ Name = "Dog",
			Size = Vector3.new(1.0, 2.5, 0.7),
			Position = P + Vector3.new(0, 2.8, -4 + dz),
			Color = STEEL, Material = Enum.Material.Metal }))
	end

	-- ── Green chain (output conveyor) ───────────────────────────────
	local gcFolder = Instance.new("Folder")
	gcFolder.Name = "GreenChain"
	gcFolder.Parent = model
	add(mp({ Name = "ChainFrame",
		Size = Vector3.new(16, 0.8, 28),
		Position = P + Vector3.new(16, 0.8, -2),
		Color = Color3.fromRGB(36, 96, 36), Material = Enum.Material.Metal }))
	for k = 0, 12 do
		local gcz = -13 + k * 2.1
		local roller = cyl({ Name = "GCRoller",
			Size = Vector3.new(15, 0.65, 0.65),
			CFrame = CFrame.new(P + Vector3.new(16, 1.45, gcz)),
			Color = MC, Material = Enum.Material.Metal })
		roller.Parent = gcFolder
	end
	-- Side walls of the green chain
	for _, sx in { 23.5, 8.5 } do
		add(mp({ Name = "ChainWall",
			Size = Vector3.new(0.4, 1.8, 28),
			Position = P + Vector3.new(sx, 1.6, -2),
			Color = Color3.fromRGB(36, 96, 36), Material = Enum.Material.Metal }))
	end

	-- ── Edger station (trims boards to width) ────────────────────────
	add(mp({ Name = "EdgerFrame",
		Size = Vector3.new(6, 8, 6),
		Position = P + Vector3.new(16, 4, 10),
		Color = STEEL, Material = Enum.Material.Metal }))
	-- Edger saw blades (two thin discs on the same shaft, adjustable spacing)
	for _, ex in { 14.5, 17.5 } do
		add(cyl({ Name = "EdgerBlade",
			Size = Vector3.new(0.3, 4.8, 4.8),
			CFrame = CFrame.new(P + Vector3.new(ex, 4.5, 10)),
			Color = MC, Material = Enum.Material.Metal,
			Reflectance = 0.3 }))
	end

	-- ── Board stacking yard (east end) ───────────────────────────────
	add(mp({ Name = "StackingPad",
		Size = Vector3.new(20, 0.5, 28),
		Position = P + Vector3.new(34, 0.25, -2),
		Color = Color3.fromRGB(108, 106, 100), Material = Enum.Material.Concrete }))
	-- A couple of board stacks (cosmetic)
	for k = 0, 2 do
		add(mp({ Name = "BoardStack",
			Size = Vector3.new(12, 0.5 + k * 0.9, 3),
			Position = P + Vector3.new(34, 0.75 + k * 0.45, -6 + k * 6),
			Color = Color3.fromRGB(205, 170, 110), Material = Enum.Material.WoodPlanks }))
	end

	-- ── Intake pad (glowing, where trucks unload) ────────────────────
	add(cyl({ Name = "IntakePad",
		Size = Vector3.new(0.55, GameConfig.Mill.IntakeRadius * 2, GameConfig.Mill.IntakeRadius * 2),
		CFrame = CFrame.new(P + Vector3.new(0, 0.4, -20)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(90, 220, 120), Material = Enum.Material.Neon,
		Transparency = 0.40, CanCollide = false }))

	-- ── Billboard sign ──────────────────────────────────────────────
	local board = add(mp({ Name = "Sign",
		Size = Vector3.new(20, 5, 0.5),
		Position = P + Vector3.new(0, 26, 15.4),
		Color = WOOD }))
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.CanvasSize = Vector2.new(600, 150)
	sg.Parent = board
	local sl = Instance.new("TextLabel")
	sl.Size = UDim2.fromScale(1, 1)
	sl.BackgroundTransparency = 1
	sl.Font = Enum.Font.FredokaOne
	sl.Text = "BIG TIMBER SAWMILL"
	sl.TextColor3 = Color3.fromRGB(255, 230, 120)
	sl.TextScaled = true
	sl.Parent = sg

	-- ── Forklift (parked, decorative) ───────────────────────────────
	local fkPos = P + Vector3.new(30, 0.5, 12)
	for _, fb in {
		mp({ Size = Vector3.new(4, 3, 6), Position = fkPos + Vector3.new(0, 1.5, 0),
			Color = Color3.fromRGB(220, 180, 40) }),
		mp({ Size = Vector3.new(4.2, 0.5, 6.2), Position = fkPos + Vector3.new(0, 0.3, 0),
			Color = Color3.fromRGB(36, 36, 38), Material = Enum.Material.Metal }),
		mp({ Size = Vector3.new(0.4, 6, 0.4), Position = fkPos + Vector3.new(1.5, 4, -4),
			Color = STEEL, Material = Enum.Material.Metal }),
		mp({ Size = Vector3.new(0.4, 6, 0.4), Position = fkPos + Vector3.new(-1.5, 4, -4),
			Color = STEEL, Material = Enum.Material.Metal }),
		mp({ Size = Vector3.new(3.5, 0.35, 1.8), Position = fkPos + Vector3.new(0, 1.2, -5.5),
			Color = MC, Material = Enum.Material.Metal }),
	} do
		fb.Parent = model
	end

	model.Parent = Workspace
end

-- ═══════════════════════════════════════════════════════════════════
-- ROADS — paved main road (spawn → mill) + dirt network into forest
-- ═══════════════════════════════════════════════════════════════════
local function buildRoads()
	local terrain = Workspace.Terrain

	-- Paint a road segment from (x1,z1) to (x2,z2) at the surface height.
	local function roadSeg(x1: number, z1: number, x2: number, z2: number,
		width: number, material: Enum.Material)
		local dx, dz = x2 - x1, z2 - z1
		local len = math.sqrt(dx * dx + dz * dz)
		local steps = math.ceil(len / 2.5)
		for i = 0, steps do
			local t = i / steps
			local x = x1 + dx * t
			local z = z1 + dz * t
			local y = World.surfaceAt(x, z)
			terrain:FillBlock(
				CFrame.new(x, y - 0.6, z),
				Vector3.new(width, 2.0, 3.0),
				material
			)
		end
	end

	-- Paved road: from behind spawn sign straight to the mill log yard
	roadSeg(0, -52, 0, 70, 14, Enum.Material.Pavement)

	-- Widen the entrance to the log yard into a turning circle
	terrain:FillBlock(
		CFrame.new(0, World.surfaceAt(0, -12) - 0.5, -12),
		Vector3.new(26, 1.5, 26),
		Enum.Material.Pavement
	)

	-- Painted centre line (thin strip of a different pavement shade —
	-- we just use two parallel Pavement columns with a bright stripe)
	roadSeg(0, -52, 0, 70, 1, Enum.Material.SmoothPlastic)

	-- Dirt road NE: branches from the paved road into the pine/redwood hills
	local NE = {
		{0, 75}, {28, 110}, {60, 145}, {95, 175}, {130, 200}, {168, 215},
	}
	for i = 1, #NE - 1 do
		roadSeg(NE[i][1], NE[i][2], NE[i+1][1], NE[i+1][2], 9, Enum.Material.Ground)
	end

	-- Dirt road NW: into the oak-heavy west hills
	local NW = {
		{0, 75}, {-30, 112}, {-65, 148}, {-105, 180}, {-140, 200},
	}
	for i = 1, #NW - 1 do
		roadSeg(NW[i][1], NW[i][2], NW[i+1][1], NW[i+1][2], 9, Enum.Material.Ground)
	end

	-- Dirt road E: cuts through to the eastern plateau
	local ER = {
		{14, 30}, {55, 22}, {95, 18}, {140, 28}, {185, 55},
	}
	for i = 1, #ER - 1 do
		roadSeg(ER[i][1], ER[i][2], ER[i+1][1], ER[i+1][2], 8, Enum.Material.Ground)
	end

	-- Dirt road W: west side logging trail
	local WR = {
		{-14, 30}, {-55, 18}, {-100, 14}, {-145, 26}, {-190, 55},
	}
	for i = 1, #WR - 1 do
		roadSeg(WR[i][1], WR[i][2], WR[i+1][1], WR[i+1][2], 8, Enum.Material.Ground)
	end

	-- Short spur connecting the two east/west roads at the back
	roadSeg(168, 215, 130, 200, 7, Enum.Material.Ground)
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
	buildRoads()
	buildMill()
	print("[World] done.")
end

return World
