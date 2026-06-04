--!strict
-- Wood species. Every tree belongs to a species; felling it yields that
-- species' logs, and the mill turns each log into cash worth
-- `plankPrice` (a log mills into a couple of planks — the per-log mill
-- value is baked into plankPrice for simplicity in this slice). Rarer,
-- tougher species are worth more, which drives the upgrade loop: you
-- need a chainsaw to fell oak/redwood in reasonable time.

export type Species = {
	id: string,
	name: string,
	hp: number, -- chop damage needed to fell one tree
	logsMin: number,
	logsMax: number,
	plankPrice: number, -- cash credited per log when milled
	logColor: Color3,
	leafColor: Color3,
	trunkHeight: number,
	trunkRadius: number,
	canopyRadius: number,
	conical: boolean, -- pine/redwood = tall conical canopy; oak = round
}

local Wood = {}

Wood.Species = {
	pine = {
		id = "pine",
		name = "Pine",
		hp = 90,
		logsMin = 2,
		logsMax = 3,
		plankPrice = 9,
		logColor = Color3.fromRGB(120, 84, 52),
		leafColor = Color3.fromRGB(48, 96, 60),
		trunkHeight = 26,
		trunkRadius = 1.4,
		canopyRadius = 6,
		conical = true,
	},
	oak = {
		id = "oak",
		name = "Oak",
		hp = 180,
		logsMin = 3,
		logsMax = 5,
		plankPrice = 17,
		logColor = Color3.fromRGB(110, 76, 48),
		leafColor = Color3.fromRGB(74, 112, 52),
		trunkHeight = 22,
		trunkRadius = 2.1,
		canopyRadius = 8.5,
		conical = false,
	},
	redwood = {
		id = "redwood",
		name = "Redwood",
		hp = 420,
		logsMin = 6,
		logsMax = 9,
		plankPrice = 30,
		logColor = Color3.fromRGB(150, 78, 56),
		leafColor = Color3.fromRGB(46, 84, 54),
		trunkHeight = 44,
		trunkRadius = 3.0,
		canopyRadius = 10,
		conical = true,
	},
} :: { [string]: Species }

function Wood.get(id: string): Species?
	return Wood.Species[id]
end

return Wood
