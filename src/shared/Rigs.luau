--!strict
-- Drivable-equipment progression: Pickup → Flatbed → Logging Truck →
-- Feller Buncher. The player owns one rig tier (Profile.rigTier); the
-- server spawns the matching model and drives it via seat physics
-- (RigService). `logCapacity` is how many logs you can carry before you
-- must unload at the mill — so each upgrade immediately means "haul more
-- per trip", even before physical log-loading exists.

export type RigTier = {
	id: string,
	name: string,
	kind: string, -- "pickup" | "flatbed" | "logging_truck" | "feller_buncher"
	logCapacity: number,
	driveSpeed: number, -- top speed, studs/s
	turnSpeed: number, -- yaw rate, deg/s
	cost: number, -- price to upgrade INTO this tier
	bodyColor: Color3,
	bedColor: Color3,
	length: number, -- chassis length (studs)
	width: number, -- chassis width (studs)
}

local Rigs = {}

Rigs.Tiers = {
	{
		id = "pickup",
		name = "Pickup Truck",
		kind = "pickup",
		logCapacity = 8,
		driveSpeed = 56,
		turnSpeed = 95,
		cost = 0,
		bodyColor = Color3.fromRGB(190, 70, 60),
		bedColor = Color3.fromRGB(60, 62, 70),
		length = 12,
		width = 5.5,
	},
	{
		id = "flatbed",
		name = "Flatbed Truck",
		kind = "flatbed",
		logCapacity = 20,
		driveSpeed = 60,
		turnSpeed = 82,
		cost = 1200,
		bodyColor = Color3.fromRGB(70, 110, 175),
		bedColor = Color3.fromRGB(120, 90, 55),
		length = 16,
		width = 6,
	},
	{
		id = "logging_truck",
		name = "Logging Truck",
		kind = "logging_truck",
		logCapacity = 48,
		driveSpeed = 66,
		turnSpeed = 64,
		cost = 5000,
		bodyColor = Color3.fromRGB(50, 105, 70),
		bedColor = Color3.fromRGB(90, 64, 40),
		length = 24,
		width = 6.5,
	},
	{
		id = "feller_buncher",
		name = "Feller Buncher",
		kind = "feller_buncher",
		logCapacity = 30,
		driveSpeed = 38,
		turnSpeed = 72,
		cost = 12000,
		bodyColor = Color3.fromRGB(220, 170, 40),
		bedColor = Color3.fromRGB(50, 50, 56),
		length = 14,
		width = 8,
	},
} :: { RigTier }

function Rigs.tier(index: number): RigTier
	return Rigs.Tiers[math.clamp(index, 1, #Rigs.Tiers)]
end

return Rigs
