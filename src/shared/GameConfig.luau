--!strict
-- Big Timber — every tunable constant lives here. Per the project rule,
-- no magic numbers anywhere else: services and builders read from this
-- module so the whole game can be balanced from one file.

local GameConfig = {}

-- Economy --------------------------------------------------------------
GameConfig.StartingCash = 150
GameConfig.AutosaveIntervalSeconds = 30
GameConfig.StateBroadcastInterval = 0.4 -- seconds between HUD snapshots

-- Player ---------------------------------------------------------------
GameConfig.WalkSpeed = 18

-- World / terrain ------------------------------------------------------
-- The map is a square of voxel terrain centred on the origin. A flat
-- circular "yard" in the middle holds the mill + spawn; rolling forested
-- hills ring it; a lake sits off to one side for scenery.
GameConfig.Terrain = {
	HalfExtent = 480, -- studs from centre to each edge (~960-stud square)
	CellSize = 16, -- footprint of each terrain column (smaller = smoother, slower)
	FloorY = -40, -- terrain is filled from here up to the surface height
	HillAmplitude = 46, -- tallest hill above yard level
	NoiseScale = 130, -- larger = broader, gentler hills
	YardRadius = 130, -- flat central area (mill + spawn) sits at y = 0
	YardBlend = 70, -- band outside the yard where hills ramp up from flat
	LakeCenter = Vector3.new(280, 0, -250),
	LakeRadius = 95,
	LakeDepth = 24,
}

-- Forest ---------------------------------------------------------------
GameConfig.Forest = {
	TreeCount = 150,
	MinSpacing = 16, -- minimum studs between two trees
	RegrowSeconds = 25, -- a felled tree regrows after this delay
	MinRadius = 165, -- trees only spawn in this ring from centre, keeping
	MaxRadius = 470, -- the yard clear and the very edge walkable
	-- Species weighting for the starter forest (must sum to ~1.0). More
	-- valuable species are rarer, so the kid chases them.
	SpeciesWeights = {
		pine = 0.64,
		oak = 0.28,
		redwood = 0.08,
	},
}

-- Chopping -------------------------------------------------------------
GameConfig.Chop = {
	ReachStuds = 15, -- how close you must stand to a tree to land a swing
	ServerSwingCooldown = 0.16, -- min seconds between accepted swings (anti-spam)
}

-- Mill -----------------------------------------------------------------
GameConfig.Mill = {
	Position = Vector3.new(0, 0, 92), -- on the flat yard, in front of spawn
	IntakeRadius = 24, -- stand or park within this of the mill to unload
	ProcessLogsPerSecond = 7, -- how fast the saw eats your load
}

return GameConfig
