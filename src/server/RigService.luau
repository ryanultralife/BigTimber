--!strict
-- Vehicle spawning and seat-physics for all four rig tiers.
--
-- ALL models are built with the cab (front) at –Z and the bed/bunk at +Z,
-- which matches the VehicleSeat's default LookVector of (0,0,–1). Pressing
-- W → Throttle=1 → fwd = seat.LookVector = (0,0,–1) → truck moves into –Z
-- = toward its grille. No seat rotation needed; no sideways driving.
--
-- Ground physics: direct AssemblyLinearVelocity on X/Z only (preserving Y
-- so gravity + terrain keep the truck on the ground). No VectorForce.
-- Steering via AlignOrientation on the chassis PrimaryPart.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Rigs = require(Shared:WaitForChild("Rigs"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local RigService = {}

-- ============================ types ================================

type Mover = {
	attachment: Attachment?,
	orient: AlignOrientation?,
}

type RigEntry = {
	player: Player,
	model: Model,
	seat: VehicleSeat,
	tier: Rigs.RigTier,
	pilot: Humanoid?,
	mover: Mover,
	yawCFrame: CFrame?,
}

local registry: { [Player]: RigEntry } = {}
local rng = Random.new()

-- ============================ helpers ==============================

local function p(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = true
	part.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(part :: any)[k] = v
	end
	return part
end

local function cyl(props: { [string]: any }): Part
	local c = p(props)
	c.Shape = Enum.PartType.Cylinder
	return c
end

local function weld(root: BasePart, other: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = other
	w.Parent = root
end

local function neon(pos: Vector3, col: Color3, sz: Vector3, model: Model, root: BasePart)
	local l = p({ Size = sz, CFrame = CFrame.new(pos), Color = col,
		Material = Enum.Material.Neon, CanCollide = false })
	l.Parent = model
	weld(root, l)
end

-- Roblox Cylinder axis = X. To stand a cylinder upright (axis = Y) rotate
-- Angles(0,0,π/2). To lay it along Z (axle = Z) rotate Angles(0,π/2,0).
-- Wheels need axis = X (default) so no rotation — the flat face shows from
-- the front/rear and the tread shows from the side. ✓

local function wheel(center: Vector3, dia: number, thick: number,
	col: Color3, hubCol: Color3, model: Model, root: BasePart)
	local tyre = cyl({ Name = "Wheel", Size = Vector3.new(thick, dia, dia),
		CFrame = CFrame.new(center), Color = col })
	tyre.Parent = model; weld(root, tyre)
	local hub = cyl({ Name = "Hub",
		Size = Vector3.new(thick + 0.12, dia * 0.52, dia * 0.52),
		CFrame = CFrame.new(center), Color = hubCol, Material = Enum.Material.Metal })
	hub.Parent = model; weld(root, hub)
end

local function seat(model: Model, root: BasePart, cf: CFrame): VehicleSeat
	local s = Instance.new("VehicleSeat")
	s.Name = "DriveSeat"
	s.Size = Vector3.new(1.6, 0.4, 2.0)
	s.Color = Color3.fromRGB(28, 28, 34)
	s.CFrame = cf
	s.HeadsUpDisplay = false
	s.Parent = model
	weld(root, s)
	return s
end

-- ============================ log stacking =========================

local LOG_WOOD = {
	Color3.fromRGB(132, 92, 60),
	Color3.fromRGB(116, 80, 52),
	Color3.fromRGB(148, 104, 66),
}

local function clearLogVisuals(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "LoadedLog" then
			d:Destroy()
		end
	end
end

-- Stacks log cylinders in the bed, proportional to loadLogs/capacity.
-- Cylinders lie length-wise (Z axis = truck length = along the bed).
-- Max 12 visible logs — enough to feel full without cluttering the screen.
function RigService.updateVisualLogs(player: Player, loadLogs: number, capacity: number)
	local entry = registry[player]
	if not entry then return end
	local model = entry.model
	clearLogVisuals(model)
	if loadLogs <= 0 then return end

	local root = model.PrimaryPart
	if not root then return end

	local tier = entry.tier
	local frac = math.clamp(loadLogs / capacity, 0, 1)
	local maxShow = math.min(12, capacity)
	local numLogs = math.max(1, math.round(frac * maxShow))

	local L, W = tier.length, tier.width
	-- Bed/bunk starts at roughly z = +L*0.10 from centre, runs to +L*0.46
	local bedCenterZ = L * 0.28
	local logLen = math.clamp(L * 0.30 - 0.3, 2.5, 5.5)
	local logDia = if tier.kind == "logging_truck" then 1.05 else 0.82
	local spacing = logDia + 0.14
	local cols = math.max(1, math.floor((W * 0.78) / spacing))
	local col, layer = 0, 0
	local bedStartX = -((cols - 1) * spacing) / 2

	for i = 1, numLogs do
		local bx = bedStartX + col * spacing
		local by = 2.1 + layer * (logDia + 0.08)
		-- Cylinder laid along Z: rotate around Y by 90° so axis points in Z
		local cf = root.CFrame
			* CFrame.new(bx, by, bedCenterZ)
			* CFrame.Angles(0, math.rad(90), 0)
		local logPart = cyl({
			Name = "LoadedLog",
			Size = Vector3.new(logLen, logDia, logDia),
			Color = LOG_WOOD[((i - 1) % #LOG_WOOD) + 1],
			Material = Enum.Material.Wood,
			CanCollide = false,
			Massless = true,
		})
		logPart.CFrame = cf
		logPart.Parent = model
		local w2 = Instance.new("WeldConstraint")
		w2.Part0 = root; w2.Part1 = logPart; w2.Parent = root
		col += 1
		if col >= cols then col = 0; layer += 1 end
	end
end

-- ============================ builders =============================
-- All trucks: front = –Z, rear = +Z, seat default-facing –Z (no rotation).

-- ──────────────────────────────── Pickup Truck ────────────────────
-- Full-size American pickup (F-150 / Silverado silhouette).
local function buildPickup(tier: Rigs.RigTier, pos: Vector3): Model
	local m = Instance.new("Model"); m.Name = "Rig_" .. tier.id
	local L, W = tier.length, tier.width
	local bc = tier.bodyColor; local dc = tier.bedColor
	local wc = Color3.fromRGB(22, 22, 22)
	local mc = Color3.fromRGB(165, 170, 178) -- chrome/metal

	-- Chassis (frame rails, low, full length)
	local ch = p({ Name = "Chassis", Size = Vector3.new(W * 0.52, 0.7, L * 0.96),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.42, 0)),
		Color = Color3.fromRGB(26, 26, 28), Material = Enum.Material.Metal })
	ch.Parent = m; m.PrimaryPart = ch

	-- Hood (long, slightly lower than cab roof)
	local hZ = -L * 0.30
	-- Hood: CanCollide=false so the interior seat is reachable from outside.
	local hood = p({ Name = "Hood", Size = Vector3.new(W - 0.3, 2.1, L * 0.34),
		CFrame = CFrame.new(pos + Vector3.new(0, 1.86, hZ)), Color = bc, CanCollide = false })
	hood.Parent = m; weld(ch, hood)

	-- Fender flares
	for _, fx in { (W - 0.3) / 2 + 0.22, -((W - 0.3) / 2 + 0.22) } do
		local fl = p({ Name = "Fender", Size = Vector3.new(0.45, 1.6, L * 0.26),
			CFrame = CFrame.new(pos + Vector3.new(fx, 1.5, hZ)), Color = bc, CanCollide = false })
		fl.Parent = m; weld(ch, fl)
	end

	-- Front bumper + grille
	local grille = p({ Name = "Grille", Size = Vector3.new(W - 0.2, 1.9, 0.55),
		CFrame = CFrame.new(pos + Vector3.new(0, 1.4, -L / 2 + 0.28)),
		Color = Color3.fromRGB(38, 40, 42), Material = Enum.Material.Metal })
	grille.Parent = m; weld(ch, grille)
	local fbump = p({ Name = "FrontBump", Size = Vector3.new(W + 0.3, 0.7, 0.6),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.72, -L / 2 + 0.0)),
		Color = mc, Material = Enum.Material.Metal })
	fbump.Parent = m; weld(ch, fbump)

	-- Headlights (neon)
	for _, hx in { W * 0.36, -W * 0.36 } do
		neon(pos + Vector3.new(hx, 1.95, -L / 2 + 0.15), Color3.fromRGB(255, 248, 220),
			Vector3.new(0.7, 0.52, 0.22), m, ch)
	end

	-- Cab: CanCollide=false — walls are visual only; player walks through to sit inside
	local cabZ = L * 0.06
	local cab = p({ Name = "Cab", Size = Vector3.new(W - 0.1, 2.9, L * 0.30),
		CFrame = CFrame.new(pos + Vector3.new(0, 2.52, cabZ)), Color = bc, CanCollide = false })
	cab.Parent = m; weld(ch, cab)

	-- Windshield (glass, angled ~20°)
	local ws = p({ Name = "Windshield", Size = Vector3.new(W - 0.55, 2.0, 0.18),
		CFrame = CFrame.new(pos + Vector3.new(0, 2.72, -L * 0.10)) * CFrame.Angles(math.rad(22), 0, 0),
		Color = Color3.fromRGB(190, 220, 255), Material = Enum.Material.Glass,
		Transparency = 0.5, CanCollide = false })
	ws.Parent = m; weld(ch, ws)

	-- Rear window (vertical, smaller)
	local rw = p({ Name = "RearWindow", Size = Vector3.new(W - 0.6, 1.6, 0.15),
		CFrame = CFrame.new(pos + Vector3.new(0, 2.7, cabZ + L * 0.145)),
		Color = Color3.fromRGB(190, 220, 255), Material = Enum.Material.Glass,
		Transparency = 0.5, CanCollide = false })
	rw.Parent = m; weld(ch, rw)

	-- Cab roof (darker shade)
	local roofC = Color3.fromRGB(
		math.round(bc.R * 255 * 0.80), math.round(bc.G * 255 * 0.80), math.round(bc.B * 255 * 0.80))
	local roof = p({ Name = "Roof", Size = Vector3.new(W - 0.08, 0.45, L * 0.29),
		CFrame = CFrame.new(pos + Vector3.new(0, 3.97, cabZ)), Color = roofC, CanCollide = false })
	roof.Parent = m; weld(ch, roof)

	-- Step rail (running board) below each cab door
	for _, sx in { W * 0.47, -W * 0.47 } do
		local step = p({ Name = "Step", Size = Vector3.new(0.3, 0.2, L * 0.24),
			CFrame = CFrame.new(pos + Vector3.new(sx, 0.85, cabZ)),
			Color = mc, Material = Enum.Material.Metal })
		step.Parent = m; weld(ch, step)
	end

	-- Rear cab fenders (over rear wheels)
	for _, fx in { (W - 0.1) / 2 + 0.22, -((W - 0.1) / 2 + 0.22) } do
		local rf = p({ Name = "RearFender", Size = Vector3.new(0.42, 1.5, L * 0.24),
			CFrame = CFrame.new(pos + Vector3.new(fx, 1.4, L * 0.20)), Color = bc })
		rf.Parent = m; weld(ch, rf)
	end

	-- Bed floor (wood planks)
	local bedZ = L * 0.29
	local bedFloor = p({ Name = "BedFloor", Size = Vector3.new(W - 0.35, 0.38, L * 0.32),
		CFrame = CFrame.new(pos + Vector3.new(0, 1.15, bedZ)),
		Color = dc, Material = Enum.Material.WoodPlanks })
	bedFloor.Parent = m; weld(ch, bedFloor)

	-- Bed sides
	for _, bsx in { (W - 0.35) / 2 + 0.18, -((W - 0.35) / 2 + 0.18) } do
		local bs = p({ Name = "BedSide", Size = Vector3.new(0.34, 1.4, L * 0.32),
			CFrame = CFrame.new(pos + Vector3.new(bsx, 1.88, bedZ)), Color = bc })
		bs.Parent = m; weld(ch, bs)
	end

	-- Tailgate
	local tg = p({ Name = "Tailgate", Size = Vector3.new(W - 0.35, 1.4, 0.32),
		CFrame = CFrame.new(pos + Vector3.new(0, 1.88, bedZ + L * 0.16)), Color = bc })
	tg.Parent = m; weld(ch, tg)

	-- Taillights + rear bumper
	for _, tx in { W * 0.36, -W * 0.36 } do
		neon(pos + Vector3.new(tx, 1.65, L / 2 - 0.1), Color3.fromRGB(220, 55, 45),
			Vector3.new(0.52, 0.40, 0.18), m, ch)
	end
	local rbump = p({ Name = "RearBump", Size = Vector3.new(W + 0.3, 0.6, 0.55),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.68, L / 2 + 0.05)),
		Color = mc, Material = Enum.Material.Metal })
	rbump.Parent = m; weld(ch, rbump)

	-- Mirrors (small nubs on cab sides)
	for _, mx in { W * 0.5 + 0.1, -(W * 0.5 + 0.1) } do
		local mir = p({ Name = "Mirror", Size = Vector3.new(0.25, 0.5, 0.55),
			CFrame = CFrame.new(pos + Vector3.new(mx, 3.1, -L * 0.08)),
			Color = mc, Material = Enum.Material.Metal, CanCollide = false })
		mir.Parent = m; weld(ch, mir)
	end

	-- 4 Wheels: front pair and rear pair
	for _, wz in { -L * 0.28, L * 0.22 } do
		for _, wx in { W * 0.50, -W * 0.50 } do
			wheel(pos + Vector3.new(wx, 0.88, wz), 2.18, 1.25, wc, mc, m, ch)
		end
	end

	-- Door windows (side glass panels)
	for _, wx2 in { (W - 0.1) / 2 + 0.05, -((W - 0.1) / 2 + 0.05) } do
		local dw = p({ Name = "DoorWindow", Size = Vector3.new(0.14, 1.55, L * 0.22),
			CFrame = CFrame.new(pos + Vector3.new(wx2, 2.78, cabZ)),
			Color = Color3.fromRGB(185, 220, 255), Material = Enum.Material.Glass,
			Transparency = 0.52, CanCollide = false })
		dw.Parent = m; weld(ch, dw)
	end

	-- Interior: dashboard, steering column, steering wheel ring
	local dash = p({ Name = "Dashboard", Size = Vector3.new(W - 0.7, 0.55, 0.8),
		CFrame = CFrame.new(pos + Vector3.new(0, 2.18, cabZ - L * 0.13)),
		Color = Color3.fromRGB(20, 20, 24), CanCollide = false })
	dash.Parent = m; weld(ch, dash)
	local stcol = cyl({ Name = "SteerColumn", Size = Vector3.new(1.5, 0.28, 0.28),
		CFrame = CFrame.new(pos + Vector3.new(0, 2.7, cabZ - L * 0.10))
			* CFrame.Angles(0, 0, math.rad(30)),
		Color = Color3.fromRGB(22, 22, 26), CanCollide = false })
	stcol.Parent = m; weld(ch, stcol)
	local sw = cyl({ Name = "SteerWheel", Size = Vector3.new(0.18, 1.85, 1.85),
		CFrame = CFrame.new(pos + Vector3.new(0, 3.08, cabZ - L * 0.09)),
		Color = Color3.fromRGB(22, 22, 26), CanCollide = false })
	sw.Parent = m; weld(ch, sw)

	-- Seat is INSIDE the cab at driver height. Cab walls are CanCollide=false
	-- so the player walks through them — exactly like Driving Empire.
	seat(m, ch, CFrame.new(pos + Vector3.new(0, 2.32, cabZ - 0.48)))
	return m
end

-- ──────────────────────────────── Flatbed Truck ───────────────────
-- Medium-duty cabover-style truck with a long flat platform.
local function buildFlatbed(tier: Rigs.RigTier, pos: Vector3): Model
	local m = Instance.new("Model"); m.Name = "Rig_" .. tier.id
	local L, W = tier.length, tier.width
	local bc, dc = tier.bodyColor, tier.bedColor
	local mc = Color3.fromRGB(160, 165, 172)
	local wc = Color3.fromRGB(22, 22, 22)

	local ch = p({ Name = "Chassis", Size = Vector3.new(W * 0.55, 0.85, L * 0.97),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.45, 0)),
		Color = Color3.fromRGB(26, 26, 28), Material = Enum.Material.Metal })
	ch.Parent = m; m.PrimaryPart = ch

	-- Cab (forward cab-over: no long hood, cab starts right at front)
	local cabZ = -L * 0.24
	local cab = p({ Name = "Cab", Size = Vector3.new(W - 0.2, 3.4, L * 0.26),
		CFrame = CFrame.new(pos + Vector3.new(0, 2.35, cabZ)), Color = bc, CanCollide = false })
	cab.Parent = m; weld(ch, cab)

	-- Windshield (nearly vertical on cab-over)
	local ws = p({ Name = "Windshield", Size = Vector3.new(W - 0.6, 2.6, 0.18),
		CFrame = CFrame.new(pos + Vector3.new(0, 2.55, -L * 0.36)) * CFrame.Angles(math.rad(6), 0, 0),
		Color = Color3.fromRGB(190, 225, 255), Material = Enum.Material.Glass,
		Transparency = 0.48, CanCollide = false })
	ws.Parent = m; weld(ch, ws)

	-- Cab roof + visor lip
	local roof = p({ Name = "Roof", Size = Vector3.new(W - 0.18, 0.45, L * 0.26),
		CFrame = CFrame.new(pos + Vector3.new(0, 4.05, cabZ)), Color = bc, CanCollide = false })
	roof.Parent = m; weld(ch, roof)
	local visor = p({ Name = "Visor", Size = Vector3.new(W - 0.16, 0.18, 0.9),
		CFrame = CFrame.new(pos + Vector3.new(0, 4.30, -L * 0.36)),
		Color = bc, CanCollide = false })
	visor.Parent = m; weld(ch, visor)

	-- Front face: grille / bumper
	local grille = p({ Name = "Grille", Size = Vector3.new(W - 0.2, 2.6, 0.5),
		CFrame = CFrame.new(pos + Vector3.new(0, 2.0, -L / 2 + 0.26)),
		Color = Color3.fromRGB(34, 36, 38), Material = Enum.Material.Metal })
	grille.Parent = m; weld(ch, grille)
	local fbump = p({ Name = "FrontBump", Size = Vector3.new(W + 0.4, 0.75, 0.65),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.68, -L / 2)),
		Color = mc, Material = Enum.Material.Metal })
	fbump.Parent = m; weld(ch, fbump)
	for _, hx in { W * 0.35, -W * 0.35 } do
		neon(pos + Vector3.new(hx, 2.3, -L / 2 + 0.14), Color3.fromRGB(255, 250, 220),
			Vector3.new(0.7, 0.55, 0.22), m, ch)
	end

	-- Flatbed platform (diamond-plate)
	local bedZ = L * 0.12
	local flatbed = p({ Name = "FlatBed", Size = Vector3.new(W + 0.2, 0.3, L * 0.64),
		CFrame = CFrame.new(pos + Vector3.new(0, 1.25, bedZ)),
		Color = dc, Material = Enum.Material.Metal })
	flatbed.Parent = m; weld(ch, flatbed)

	-- Stake pockets (6 small vertical posts along each side)
	for _, sx in { W * 0.56, -W * 0.56 } do
		for k = 0, 4 do
			local stake = p({ Name = "Stake", Size = Vector3.new(0.3, 1.1, 0.3),
				CFrame = CFrame.new(pos + Vector3.new(sx, 1.85, -L * 0.18 + k * L * 0.12)),
				Color = mc, Material = Enum.Material.Metal })
			stake.Parent = m; weld(ch, stake)
		end
	end

	-- Rear bumper
	local rbump = p({ Name = "RearBump", Size = Vector3.new(W + 0.4, 0.65, 0.6),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.68, L / 2)),
		Color = mc, Material = Enum.Material.Metal })
	rbump.Parent = m; weld(ch, rbump)
	for _, tx in { W * 0.37, -W * 0.37 } do
		neon(pos + Vector3.new(tx, 1.5, L / 2 - 0.1), Color3.fromRGB(220, 55, 45),
			Vector3.new(0.52, 0.42, 0.18), m, ch)
	end

	-- Mirrors
	for _, mx in { W * 0.53, -W * 0.53 } do
		local mir = p({ Name = "Mirror", Size = Vector3.new(0.25, 0.55, 0.6),
			CFrame = CFrame.new(pos + Vector3.new(mx, 3.3, cabZ + 0.2)),
			Color = mc, Material = Enum.Material.Metal, CanCollide = false })
		mir.Parent = m; weld(ch, mir)
	end

	-- 4 Wheels (two single front, two single rear)
	for _, wz in { -L * 0.33, L * 0.18 } do
		for _, wx in { W * 0.53, -W * 0.53 } do
			wheel(pos + Vector3.new(wx, 0.92, wz), 2.35, 1.35, wc, mc, m, ch)
		end
	end

	-- Flatbed interior: dashboard + steering wheel
	local fdash = p({ Name = "Dashboard", Size = Vector3.new(W - 0.7, 0.55, 0.8),
		CFrame = CFrame.new(pos + Vector3.new(0, 2.55, cabZ - L * 0.12)),
		Color = Color3.fromRGB(20, 20, 24), CanCollide = false })
	fdash.Parent = m; weld(ch, fdash)
	local fsw = cyl({ Name = "SteerWheel", Size = Vector3.new(0.18, 1.85, 1.85),
		CFrame = CFrame.new(pos + Vector3.new(0, 3.15, cabZ - L * 0.10)),
		Color = Color3.fromRGB(22, 22, 26), CanCollide = false })
	fsw.Parent = m; weld(ch, fsw)
	for _, wx2 in { (W - 0.2) / 2 + 0.05, -((W - 0.2) / 2 + 0.05) } do
		local dw = p({ Name = "DoorWindow", Size = Vector3.new(0.14, 2.2, L * 0.22),
			CFrame = CFrame.new(pos + Vector3.new(wx2, 2.6, cabZ)),
			Color = Color3.fromRGB(185, 220, 255), Material = Enum.Material.Glass,
			Transparency = 0.52, CanCollide = false })
		dw.Parent = m; weld(ch, dw)
	end
	seat(m, ch, CFrame.new(pos + Vector3.new(0, 2.55, cabZ - 0.4)))
	return m
end

-- ──────────────────────────────── Logging Truck ───────────────────
-- Class 8 conventional long-nose semi (Peterbilt 379 / Kenworth W900 vibe).
local function buildLoggingTruck(tier: Rigs.RigTier, pos: Vector3): Model
	local m = Instance.new("Model"); m.Name = "Rig_" .. tier.id
	local L, W = tier.length, tier.width
	local bc = tier.bodyColor
	local mc = Color3.fromRGB(210, 215, 220) -- chrome
	local wc = Color3.fromRGB(20, 20, 20)

	-- Long frame rails
	local ch = p({ Name = "Chassis", Size = Vector3.new(W * 0.44, 0.9, L * 0.98),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.48, 0)),
		Color = Color3.fromRGB(24, 24, 26), Material = Enum.Material.Metal })
	ch.Parent = m; m.PrimaryPart = ch

	-- Very long hood (the signature of a conventional semi)
	local hoodZ = -L * 0.28
	local hood = p({ Name = "Hood", Size = Vector3.new(W - 0.4, 2.5, L * 0.44),
		CFrame = CFrame.new(pos + Vector3.new(0, 2.0, hoodZ)), Color = bc })
	hood.Parent = m; weld(ch, hood)

	-- Hood top (slightly raised center line — V-shaped hood detail)
	local hoodTop = p({ Name = "HoodTop", Size = Vector3.new(W * 0.35, 0.3, L * 0.42),
		CFrame = CFrame.new(pos + Vector3.new(0, 3.24, hoodZ + 0.05)),
		Color = bc, CanCollide = false })
	hoodTop.Parent = m; weld(ch, hoodTop)

	-- Prominent chrome grille (tall, wide)
	local grille = p({ Name = "Grille", Size = Vector3.new(W - 0.3, 3.1, 0.6),
		CFrame = CFrame.new(pos + Vector3.new(0, 2.0, -L / 2 + 0.32)),
		Color = Color3.fromRGB(38, 40, 42), Material = Enum.Material.Metal })
	grille.Parent = m; weld(ch, grille)
	-- Chrome grille bars (horizontal strips)
	for k = 0, 4 do
		local bar = p({ Name = "GrilleBar", Size = Vector3.new(W - 0.28, 0.14, 0.5),
			CFrame = CFrame.new(pos + Vector3.new(0, 1.0 + k * 0.6, -L / 2 + 0.31)),
			Color = mc, Material = Enum.Material.Metal, CanCollide = false })
		bar.Parent = m; weld(ch, bar)
	end

	-- Chrome front bumper + air dam below
	local fbump = p({ Name = "FrontBump", Size = Vector3.new(W + 0.5, 0.9, 0.75),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.72, -L / 2 - 0.02)),
		Color = mc, Material = Enum.Material.Metal })
	fbump.Parent = m; weld(ch, fbump)

	-- Headlights (round, neon)
	for _, hx in { W * 0.35, -W * 0.35 } do
		local hl = cyl({ Name = "Headlight",
			Size = Vector3.new(0.4, 1.2, 1.2),
			CFrame = CFrame.new(pos + Vector3.new(hx, 2.3, -L / 2 + 0.22)),
			Color = Color3.fromRGB(255, 252, 230),
			Material = Enum.Material.Neon, CanCollide = false })
		hl.Parent = m; weld(ch, hl)
	end

	-- Cab (day cab — shorter than a full sleeper)
	local cabZ = L * 0.09
	local cab = p({ Name = "Cab", Size = Vector3.new(W - 0.1, 3.6, L * 0.22),
		CFrame = CFrame.new(pos + Vector3.new(0, 2.65, cabZ)), Color = bc, CanCollide = false })
	cab.Parent = m; weld(ch, cab)

	-- Windshield + visor lip
	local ws = p({ Name = "Windshield", Size = Vector3.new(W - 0.5, 2.6, 0.18),
		CFrame = CFrame.new(pos + Vector3.new(0, 2.75, -L * 0.02)) * CFrame.Angles(math.rad(12), 0, 0),
		Color = Color3.fromRGB(185, 218, 255), Material = Enum.Material.Glass,
		Transparency = 0.48, CanCollide = false })
	ws.Parent = m; weld(ch, ws)
	local visor = p({ Name = "Visor", Size = Vector3.new(W - 0.1, 0.2, 1.2),
		CFrame = CFrame.new(pos + Vector3.new(0, 4.47, -L * 0.02)),
		Color = bc, CanCollide = false })
	visor.Parent = m; weld(ch, visor)

	-- Cab roof + sleeper bump
	local roof = p({ Name = "Roof", Size = Vector3.new(W - 0.06, 0.48, L * 0.22),
		CFrame = CFrame.new(pos + Vector3.new(0, 4.45, cabZ)), Color = bc, CanCollide = false })
	roof.Parent = m; weld(ch, roof)

	-- Vertical chrome exhaust stacks (two)
	for _, sx in { W * 0.46, -W * 0.46 } do
		local stack = cyl({ Name = "ExhaustStack",
			Size = Vector3.new(L * 0.28, 0.55, 0.55),
			CFrame = CFrame.new(pos + Vector3.new(sx, 5.2, cabZ - L * 0.04))
				* CFrame.Angles(0, 0, math.rad(90)),
			Color = mc, Material = Enum.Material.Metal })
		stack.Parent = m; weld(ch, stack)
		-- Stack tip (neon spark — exhaust heat visual)
		neon(pos + Vector3.new(sx, 6.6, cabZ - L * 0.04),
			Color3.fromRGB(255, 160, 40), Vector3.new(0.45, 0.45, 0.45), m, ch)
	end

	-- Large west-coast mirrors
	for _, mx in { W * 0.56, -W * 0.56 } do
		local arm = p({ Name = "MirrorArm", Size = Vector3.new(0.25, 0.2, 1.0),
			CFrame = CFrame.new(pos + Vector3.new(mx, 3.5, -L * 0.02)),
			Color = mc, Material = Enum.Material.Metal, CanCollide = false })
		arm.Parent = m; weld(ch, arm)
		local mirFace = p({ Name = "Mirror", Size = Vector3.new(0.2, 0.9, 0.72),
			CFrame = CFrame.new(pos + Vector3.new(mx + (mx > 0 and 0.1 or -0.1), 3.5, -L * 0.05)),
			Color = mc, Material = Enum.Material.Metal, CanCollide = false })
		mirFace.Parent = m; weld(ch, mirFace)
	end

	-- Log bunk at the rear: two pairs of upright stakes with a crossbar
	local bunkZ1, bunkZ2 = L * 0.20, L * 0.44
	for _, bz in { bunkZ1, bunkZ2 } do
		-- Cross-bunk floor
		local bunk = p({ Name = "Bunk", Size = Vector3.new(W + 0.3, 0.55, 1.2),
			CFrame = CFrame.new(pos + Vector3.new(0, 1.0, bz)),
			Color = Color3.fromRGB(48, 50, 52), Material = Enum.Material.Metal })
		bunk.Parent = m; weld(ch, bunk)
		-- Upright stakes
		for _, bsx in { W * 0.50, -W * 0.50 } do
			local stake = p({ Name = "BunkStake", Size = Vector3.new(0.65, 5.5, 0.65),
				CFrame = CFrame.new(pos + Vector3.new(bsx, 3.8, bz)),
				Color = Color3.fromRGB(48, 50, 52), Material = Enum.Material.Metal })
			stake.Parent = m; weld(ch, stake)
		end
		-- Chain detail across the top (thin bar)
		local chain = p({ Name = "BunkChain", Size = Vector3.new(W + 0.1, 0.2, 0.2),
			CFrame = CFrame.new(pos + Vector3.new(0, 6.2, bz)),
			Color = mc, Material = Enum.Material.Metal, CanCollide = false })
		chain.Parent = m; weld(ch, chain)
	end

	-- Taillights + rear bumper
	for _, tx in { W * 0.37, -W * 0.37 } do
		neon(pos + Vector3.new(tx, 1.6, L / 2 - 0.1), Color3.fromRGB(220, 55, 45),
			Vector3.new(0.55, 0.42, 0.22), m, ch)
	end
	local rbump = p({ Name = "RearBump", Size = Vector3.new(W + 0.45, 0.7, 0.6),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.68, L / 2)),
		Color = mc, Material = Enum.Material.Metal })
	rbump.Parent = m; weld(ch, rbump)

	-- 6 wheels (2 steering front + 4 drive in tandem rear)
	local wheelDia, wheelThick = 2.55, 1.42
	wheel(pos + Vector3.new(W * 0.50, 1.0, -L * 0.34), wheelDia, wheelThick, wc, mc, m, ch)
	wheel(pos + Vector3.new(-W * 0.50, 1.0, -L * 0.34), wheelDia, wheelThick, wc, mc, m, ch)
	for _, wz in { L * 0.26, L * 0.40 } do
		for _, wx in { W * 0.52, W * 0.52 + 1.45, -W * 0.52, -(W * 0.52 + 1.45) } do
			wheel(pos + Vector3.new(wx, 1.0, wz), wheelDia, wheelThick * 0.9, wc, mc, m, ch)
		end
	end

	-- Semi interior: large dashboard, air horn pulls, steering wheel
	local ldash = p({ Name = "Dashboard", Size = Vector3.new(W - 0.6, 0.7, 1.1),
		CFrame = CFrame.new(pos + Vector3.new(0, 2.7, cabZ - L * 0.09)),
		Color = Color3.fromRGB(18, 18, 22), CanCollide = false })
	ldash.Parent = m; weld(ch, ldash)
	local lsw = cyl({ Name = "SteerWheel", Size = Vector3.new(0.2, 2.2, 2.2),
		CFrame = CFrame.new(pos + Vector3.new(0, 3.35, cabZ - L * 0.09)),
		Color = Color3.fromRGB(22, 22, 26), CanCollide = false })
	lsw.Parent = m; weld(ch, lsw)
	for _, wx2 in { (W - 0.1) / 2 + 0.05, -((W - 0.1) / 2 + 0.05) } do
		local dw = p({ Name = "DoorWindow", Size = Vector3.new(0.14, 2.4, L * 0.20),
			CFrame = CFrame.new(pos + Vector3.new(wx2, 2.9, cabZ)),
			Color = Color3.fromRGB(185, 218, 255), Material = Enum.Material.Glass,
			Transparency = 0.52, CanCollide = false })
		dw.Parent = m; weld(ch, dw)
	end
	-- Air horn lanyard (visual detail)
	local horn = p({ Name = "HornPull", Size = Vector3.new(0.15, 0.9, 0.15),
		CFrame = CFrame.new(pos + Vector3.new(W * 0.22, 3.5, cabZ - L * 0.04)),
		Color = Color3.fromRGB(200, 170, 80), CanCollide = false })
	horn.Parent = m; weld(ch, horn)
	-- Hood (long nose): CanCollide=false
	hood.CanCollide = false
	seat(m, ch, CFrame.new(pos + Vector3.new(0, 2.75, cabZ - 0.4)))
	return m
end

-- ──────────────────────────────── Feller Buncher ──────────────────
-- Tracked excavator-style machine (Tigercat / John Deere vibe).
local function buildFellerBuncher(tier: Rigs.RigTier, pos: Vector3): Model
	local m = Instance.new("Model"); m.Name = "Rig_" .. tier.id
	local L, W = tier.length, tier.width
	local bc = tier.bodyColor -- bright yellow
	local sc = Color3.fromRGB(44, 46, 50) -- steel frame
	local mc = Color3.fromRGB(160, 165, 172)

	-- Track undercarriage (wide, low, runs full length)
	-- Two track frames (left + right) with visible track pads
	local ch = p({ Name = "Chassis", Size = Vector3.new(W * 0.30, 1.0, L * 0.96),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.55, 0)),
		Color = sc, Material = Enum.Material.Metal })
	ch.Parent = m; m.PrimaryPart = ch

	for _, tx in { W * 0.38, -W * 0.38 } do
		local trackFrame = p({ Name = "Track", Size = Vector3.new(2.6, 1.4, L * 0.94),
			CFrame = CFrame.new(pos + Vector3.new(tx, 0.75, 0)),
			Color = Color3.fromRGB(28, 28, 28), Material = Enum.Material.SmoothPlastic })
		trackFrame.Parent = m; weld(ch, trackFrame)
		-- Track top rail (yellow, contrasting)
		local rail = p({ Name = "TrackRail", Size = Vector3.new(2.62, 0.22, L * 0.94),
			CFrame = CFrame.new(pos + Vector3.new(tx, 1.45, 0)),
			Color = bc, Material = Enum.Material.Metal })
		rail.Parent = m; weld(ch, rail)
		-- Idler wheels at front and rear
		for _, iz in { -L * 0.44, L * 0.44 } do
			local idler = cyl({ Name = "Idler",
				Size = Vector3.new(2.5, 1.8, 1.8),
				CFrame = CFrame.new(pos + Vector3.new(tx, 0.7, iz)),
				Color = Color3.fromRGB(55, 57, 60), Material = Enum.Material.Metal })
			idler.Parent = m; weld(ch, idler)
		end
	end

	-- Upper body / turntable ring
	local bodyZ = -L * 0.04
	local body = p({ Name = "Body", Size = Vector3.new(W - 0.2, 3.4, L * 0.58),
		CFrame = CFrame.new(pos + Vector3.new(0, 3.2, bodyZ)), Color = bc })
	body.Parent = m; weld(ch, body)

	-- Engine hood hump (rear of body)
	local engHood = p({ Name = "EngineHood", Size = Vector3.new(W - 0.4, 1.1, L * 0.20),
		CFrame = CFrame.new(pos + Vector3.new(0, 4.35, L * 0.20)),
		Color = bc })
	engHood.Parent = m; weld(ch, engHood)

	-- Cab box (CanCollide=false — ROPS provides the visual shell, player sits inside)
	local cabZ2 = -L * 0.22
	local cab = p({ Name = "Cab", Size = Vector3.new(W * 0.72, 3.0, L * 0.28),
		CFrame = CFrame.new(pos + Vector3.new(0, 3.1, cabZ2)), Color = bc, CanCollide = false })
	cab.Parent = m; weld(ch, cab)

	-- ROPS posts (four corners of the cab)
	for _, rpx in { W * 0.30, -W * 0.30 } do
		for _, rpz in { cabZ2 - L * 0.13, cabZ2 + L * 0.13 } do
			local post = p({ Name = "ROPS", Size = Vector3.new(0.4, 3.2, 0.4),
				CFrame = CFrame.new(pos + Vector3.new(rpx, 4.75, rpz)),
				Color = Color3.fromRGB(220, 180, 40), Material = Enum.Material.Metal })
			post.Parent = m; weld(ch, post)
		end
	end
	-- ROPS top bar
	local ropsTop = p({ Name = "ROPSTop", Size = Vector3.new(W * 0.68, 0.4, L * 0.28),
		CFrame = CFrame.new(pos + Vector3.new(0, 6.35, cabZ2)),
		Color = Color3.fromRGB(220, 180, 40), Material = Enum.Material.Metal })
	ropsTop.Parent = m; weld(ch, ropsTop)

	-- Large front windshield
	local fbws = p({ Name = "Windshield", Size = Vector3.new(W * 0.68, 2.6, 0.16),
		CFrame = CFrame.new(pos + Vector3.new(0, 3.3, cabZ2 - L * 0.13)) * CFrame.Angles(math.rad(5), 0, 0),
		Color = Color3.fromRGB(185, 220, 255), Material = Enum.Material.Glass,
		Transparency = 0.45, CanCollide = false })
	fbws.Parent = m; weld(ch, fbws)

	-- Boom arm (thick hydraulic arm from body top-front)
	local boomLen = L * 0.60
	local boomCenterZ = cabZ2 - L * 0.18 - boomLen / 2
	local boom = p({ Name = "Boom", Size = Vector3.new(1.6, 1.6, boomLen),
		CFrame = CFrame.new(pos + Vector3.new(0, 5.8, boomCenterZ))
			* CFrame.Angles(math.rad(-22), 0, 0),
		Color = Color3.fromRGB(200, 165, 35), Material = Enum.Material.Metal })
	boom.Parent = m; weld(ch, boom)

	-- Stick / dipper arm (second arm segment)
	local stickLen = L * 0.42
	local stickTipZ = boomCenterZ - boomLen * 0.48
	local stickTipY = 5.8 - boomLen * 0.5 * math.sin(math.rad(22))
	local stickCenterZ = stickTipZ - stickLen * 0.46
	local stick = p({ Name = "Stick", Size = Vector3.new(1.1, 1.1, stickLen),
		CFrame = CFrame.new(pos + Vector3.new(0, stickTipY + 0.4, stickCenterZ))
			* CFrame.Angles(math.rad(16), 0, 0),
		Color = Color3.fromRGB(190, 155, 30), Material = Enum.Material.Metal })
	stick.Parent = m; weld(ch, stick)

	-- Disc saw head (the business end — large circular saw)
	local headZ = stickCenterZ - stickLen * 0.52
	local headY = stickTipY - 1.2
	local discSaw = cyl({ Name = "DiscSaw",
		Size = Vector3.new(0.8, 4.2, 4.2),
		CFrame = CFrame.new(pos + Vector3.new(0, headY, headZ)),
		Color = Color3.fromRGB(200, 200, 208), Material = Enum.Material.Metal,
		Reflectance = 0.25 })
	discSaw.Parent = m; weld(ch, discSaw)
	-- Saw teeth ring (neon orange for danger visual)
	local teethRing = cyl({ Name = "SawTeeth",
		Size = Vector3.new(0.55, 4.6, 4.6),
		CFrame = CFrame.new(pos + Vector3.new(0, headY, headZ)),
		Color = Color3.fromRGB(255, 140, 30),
		Material = Enum.Material.Neon, CanCollide = false })
	teethRing.Parent = m; weld(ch, teethRing)
	-- Grabber forks above the saw (two prongs that hold the tree)
	for _, fx in { 0.9, -0.9 } do
		local fork = p({ Name = "Fork", Size = Vector3.new(0.55, 2.8, 0.55),
			CFrame = CFrame.new(pos + Vector3.new(fx, headY + 2.6, headZ)),
			Color = Color3.fromRGB(200, 170, 35), Material = Enum.Material.Metal })
		fork.Parent = m; weld(ch, fork)
	end

	-- Taillights + rear indicators
	for _, tx in { W * 0.38, -W * 0.38 } do
		neon(pos + Vector3.new(tx, 2.0, L / 2 - 0.1), Color3.fromRGB(220, 55, 45),
			Vector3.new(0.5, 0.4, 0.2), m, ch)
	end

	-- No traditional wheels — tracks are the ground contact
	-- Feller buncher interior (simple — mostly glass panels + joystick)
	local jstick = p({ Name = "Joystick", Size = Vector3.new(0.25, 1.0, 0.25),
		CFrame = CFrame.new(pos + Vector3.new(0.5, 4.1, cabZ2)),
		Color = Color3.fromRGB(22, 22, 26), CanCollide = false })
	jstick.Parent = m; weld(ch, jstick)
	seat(m, ch, CFrame.new(pos + Vector3.new(0, 4.1, cabZ2 + 0.3)))
	return m
end

local builders: { [string]: (tier: Rigs.RigTier, pos: Vector3) -> Model } = {
	pickup = buildPickup,
	flatbed = buildFlatbed,
	logging_truck = buildLoggingTruck,
	feller_buncher = buildFellerBuncher,
}

-- ============================ physics ==============================

local function setAnchored(model: Model, anchored: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then d.Anchored = anchored end
	end
end

local function attachMovers(entry: RigEntry)
	local root = entry.model.PrimaryPart
	if not root then return end
	local at = Instance.new("Attachment"); at.Name = "RigRoot"; at.Parent = root
	local orient = Instance.new("AlignOrientation")
	orient.Attachment0 = at
	orient.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orient.CFrame = root.CFrame
	orient.MaxAngularVelocity = math.rad(entry.tier.turnSpeed)
	orient.MaxTorque = 6e7
	orient.Responsiveness = 28
	orient.Parent = root
	local _, yaw = root.CFrame:ToEulerAnglesYXZ()
	entry.mover.attachment = at
	entry.mover.orient = orient
	entry.yawCFrame = CFrame.Angles(0, yaw, 0)
end

local function clearMovers(entry: RigEntry)
	if entry.mover.orient then entry.mover.orient:Destroy() end
	if entry.mover.attachment then entry.mover.attachment:Destroy() end
	entry.mover.orient = nil; entry.mover.attachment = nil
end

local function onPilotIn(entry: RigEntry, humanoid: Humanoid)
	entry.pilot = humanoid
	humanoid.AutoRotate = false
	setAnchored(entry.model, false)
	attachMovers(entry)
end

local function onPilotOut(entry: RigEntry)
	if entry.pilot then entry.pilot.AutoRotate = true end
	entry.pilot = nil
	local root = entry.model.PrimaryPart
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	clearMovers(entry)
	setAnchored(entry.model, true)
end

RunService.Heartbeat:Connect(function(dt)
	for _, entry in registry do
		if not entry.pilot then continue end
		local root = entry.model.PrimaryPart
		if not root then continue end
		local seat = entry.seat
		local throttle = seat.Throttle
		local steer = seat.Steer
		local spd = entry.tier.driveSpeed
		local fwd = seat.CFrame.LookVector
		local horiz = Vector3.new(fwd.X, 0, fwd.Z)
		if horiz.Magnitude > 0.001 then horiz = horiz.Unit end
		local cur = root.AssemblyLinearVelocity
		local accel = if math.abs(throttle) > 0.01 then 7 else 16
		root.AssemblyLinearVelocity = Vector3.new(
			cur.X + (horiz.X * throttle * spd - cur.X) * math.min(1, accel * dt),
			cur.Y,
			cur.Z + (horiz.Z * throttle * spd - cur.Z) * math.min(1, accel * dt)
		)
		local yawRate = math.rad(entry.tier.turnSpeed)
		local cf = entry.yawCFrame or CFrame.new()
		cf = cf * CFrame.Angles(0, -steer * yawRate * dt, 0)
		entry.yawCFrame = cf
		if entry.mover.orient then entry.mover.orient.CFrame = cf end
	end
end)

-- ============================ public API ===========================

function RigService.spawn(player: Player)
	if not PlayerData.isLoaded(player) then return end
	local old = registry[player]
	if old then
		if old.pilot then onPilotOut(old) end
		old.model:Destroy()
		registry[player] = nil
	end
	local prof = PlayerData.get(player)
	local tier = Rigs.tier(prof.rigTier)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local basePos = if hrp then (hrp :: BasePart).Position else Vector3.new(0, 4, 0)
	local spawnPos = basePos + Vector3.new(0, 2, -16) -- in front of player
	local builder = builders[tier.kind] or buildPickup
	local model = builder(tier, spawnPos)
	model.Parent = Workspace
	local s = model:FindFirstChild("DriveSeat") :: VehicleSeat
	if not s then model:Destroy(); return end
	local entry: RigEntry = {
		player = player, model = model, seat = s, tier = tier,
		pilot = nil, mover = {}, yawCFrame = nil,
	}
	registry[player] = entry
	s:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occ = s.Occupant
		if occ then onPilotIn(entry, occ) else onPilotOut(entry) end
	end)
	-- Restore visual log stack on respawn.
	local prof2 = PlayerData.get(player)
	if prof2.loadLogs > 0 then
		RigService.updateVisualLogs(player, prof2.loadLogs, tier.logCapacity)
	end
end

function RigService.upgradeAndRespawn(player: Player)
	RigService.spawn(player)
end

Remotes.CallRig.OnServerEvent:Connect(function(player)
	if PlayerData.isLoaded(player) then RigService.spawn(player) end
end)

Players.PlayerRemoving:Connect(function(player)
	local entry = registry[player]
	if entry then
		if entry.pilot then onPilotOut(entry) end
		entry.model:Destroy()
		registry[player] = nil
	end
end)

return RigService
