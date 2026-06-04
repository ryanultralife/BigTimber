--!strict
-- Felling-tool progression: Axe → Chainsaw. The player owns one tier at a
-- time (Profile.toolTier = index into Tiers). Each swing deals
-- `damagePerSwing`; the client swings every `swingInterval` seconds.
-- Buying the next tier costs `cost` (tier 1 is the free starter). The
-- server Shop validates and applies the upgrade.

export type ToolTier = {
	id: string,
	name: string,
	damagePerSwing: number,
	swingInterval: number, -- seconds between swings on the client
	cost: number, -- price to upgrade INTO this tier
	powered: boolean, -- chainsaw vs. axe (drives sound/shake cosmetics later)
	handleColor: Color3,
	headColor: Color3,
}

local Tools = {}

Tools.Tiers = {
	{
		id = "hand_axe",
		name = "Hand Axe",
		damagePerSwing = 22,
		swingInterval = 0.55,
		cost = 0,
		powered = false,
		handleColor = Color3.fromRGB(120, 84, 52),
		headColor = Color3.fromRGB(170, 175, 185),
	},
	{
		id = "felling_axe",
		name = "Felling Axe",
		damagePerSwing = 40,
		swingInterval = 0.48,
		cost = 250,
		powered = false,
		handleColor = Color3.fromRGB(96, 64, 40),
		headColor = Color3.fromRGB(200, 205, 215),
	},
	{
		id = "chainsaw",
		name = "Chainsaw",
		damagePerSwing = 64,
		swingInterval = 0.3,
		cost = 950,
		powered = true,
		handleColor = Color3.fromRGB(220, 150, 30),
		headColor = Color3.fromRGB(60, 60, 66),
	},
	{
		id = "pro_chainsaw",
		name = "Pro Chainsaw",
		damagePerSwing = 120,
		swingInterval = 0.24,
		cost = 3400,
		powered = true,
		handleColor = Color3.fromRGB(220, 60, 50),
		headColor = Color3.fromRGB(40, 40, 46),
	},
} :: { ToolTier }

-- Clamp so a bad/missing index can never error a tick.
function Tools.tier(index: number): ToolTier
	return Tools.Tiers[math.clamp(index, 1, #Tools.Tiers)]
end

return Tools
