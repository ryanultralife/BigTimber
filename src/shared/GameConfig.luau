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
--   Spawn at (0,0,0). Flat logging yard extends north.
--   Forest hills north + east/west of yard.
--   Paved road runs SOUTH from the yard (decreasing Z).
--   Tunnel hill straddles z = TunnelHillZ.
--   Town (mill + shop) south of the tunnel.
GameConfig.Terrain = {
	HalfExtent = 620,
	CellSize = 16,
	FloorY = -44,
	HillAmplitude = 50,
	NoiseScale = 140,
	-- The flat yard around spawn. Trees and roads start outside this.
	YardRadius = 140,
	YardBlend = 75,
	-- Lake sits in the northeast forest for scenery.
	LakeCenter = Vector3.new(310, 0, 210),
	LakeRadius = 90,
	LakeDepth = 24,
	-- Tunnel hill: a raised ridge the paved road punches through.
	-- Only terrain OUTSIDE the road corridor (|x| > TunnelRoadHW) is raised.
	TunnelHillZ = -270,
	TunnelHillRadius = 130,
	TunnelHillHeight = 46,
	TunnelRoadHW = 11, -- road half-width kept flat through the hill
}

-- Forest ---------------------------------------------------------------
GameConfig.Forest = {
	TreeCount = 220,
	MinSpacing = 16,
	RegrowSeconds = 25,
	MinRadius = 150,
	MaxRadius = 560,
	-- Trees must be NORTH of this Z (don't plant in the road/town area).
	NorthOnly_MinZ = -100,
	SpeciesWeights = { pine = 0.62, oak = 0.28, redwood = 0.10 },
}

-- Chopping -------------------------------------------------------------
GameConfig.Chop = {
	ReachStuds = 16,
	ServerSwingCooldown = 0.15,
}

-- Mill -----------------------------------------------------------------
-- Sits south of the tunnel in the town valley.
GameConfig.Mill = {
	Position = Vector3.new(0, 0, -420),
	IntakeRadius = 26,
	ProcessLogsPerSecond = 7,
}

-- Shop -----------------------------------------------------------------
-- NPC dealer, further down the road from the mill.
GameConfig.Shop = {
	Position = Vector3.new(0, 0, -560),
	NpcName = "Big Dale",
}

return GameConfig
