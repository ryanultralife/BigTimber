--!strict
-- Big Timber — every tunable constant lives here.
-- No magic numbers anywhere else in the codebase.

local GameConfig = {}

-- Economy --------------------------------------------------------------
GameConfig.StartingCash = 150
GameConfig.AutosaveIntervalSeconds = 30
GameConfig.StateBroadcastInterval = 0.4

-- Player ---------------------------------------------------------------
GameConfig.WalkSpeed = 18

-- World / terrain -------------------------------------------------------
-- Layout (Z axis, +Z = north away from spawn):
--   Spawn at (0,0,0). Flat logging yard around it; forest hills north/east/west.
--   Paved road runs SOUTH (decreasing Z) from the yard.
--   Tunnel hill straddles z = TunnelHillZ; the road punches through it.
--   Sawmill, then Big Dale's shop, in the valley south of the tunnel.
GameConfig.Terrain = {
	HalfExtent = 620,
	CellSize = 16,
	FloorY = -44,
	HillAmplitude = 50,
	NoiseScale = 140,
	YardRadius = 140,
	YardBlend = 75,
	LakeCenter = Vector3.new(310, 0, 210),
	LakeRadius = 90,
	LakeDepth = 24,
	-- Tunnel hill: raised ridge the paved road tunnels through. The flat
	-- corridor is RoadHW + half a terrain cell wide so the 16-stud cell
	-- grid (which is offset 4 studs from x=0) never juts into the road.
	TunnelHillZ = -270,
	TunnelHillRadius = 130,
	TunnelHillHeight = 46,
	TunnelRoadHW = 11,
	TunnelTubeHalf = 57, -- half-length of the concrete tube (parts)
}

-- Forest ---------------------------------------------------------------
GameConfig.Forest = {
	TreeCount = 220,
	MinSpacing = 16,
	RegrowSeconds = 25,
	MinRadius = 150,
	MaxRadius = 560,
	-- Trees only north of this Z (keeps road/tunnel/town clear).
	NorthOnly_MinZ = -100,
	SpeciesWeights = { pine = 0.62, oak = 0.28, redwood = 0.10 },
}

-- Chopping -------------------------------------------------------------
GameConfig.Chop = {
	ReachStuds = 16, -- single source of truth; client + server both read this
	ServerSwingCooldown = 0.15,
}

-- Loose logs (felled trees drop these; trucks load them) ----------------
GameConfig.Logs = {
	LoadRadius = 16, -- park the rig within this of a log to load it
	DespawnSeconds = 180, -- abandoned logs rot away
	MaxLoose = 60, -- oldest logs despawn past this count (perf guard)
}

-- Mill -----------------------------------------------------------------
GameConfig.Mill = {
	Position = Vector3.new(0, 0, -420),
	IntakePadOffset = Vector3.new(0, 0, -22), -- pad centre relative to Position;
	-- unload detection is centred HERE (must match the visible pad)
	IntakeRadius = 26,
	ProcessLogsPerSecond = 7,
}

-- Shop -----------------------------------------------------------------
GameConfig.Shop = {
	Position = Vector3.new(0, 0, -560),
	NpcName = "Big Dale",
}

return GameConfig
