--!strict
-- Builds the HUD snapshot from a profile and pushes it to the client.
-- The snapshot is the single payload every client UI reads from, so the
-- shape here is the contract with Hud.luau / Shop.luau.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tools = require(Shared:WaitForChild("Tools"))
local Rigs = require(Shared:WaitForChild("Rigs"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local Net = {}

function Net.snapshot(player: Player)
	local p = PlayerData.get(player)
	local tool = Tools.tier(p.toolTier)
	local rig = Rigs.tier(p.rigTier)
	local nextTool = Tools.Tiers[p.toolTier + 1]
	local nextRig = Rigs.Tiers[p.rigTier + 1]
	return {
		cash = p.cash,
		loadLogs = p.loadLogs,
		loadValue = p.loadValue,
		capacity = rig.logCapacity,
		toolName = tool.name,
		rigName = rig.name,
		lifetimeLogs = p.lifetimeLogs,
		nextTool = nextTool and { name = nextTool.name, cost = nextTool.cost } or nil,
		nextRig = nextRig and { name = nextRig.name, cost = nextRig.cost } or nil,
	}
end

function Net.push(player: Player)
	Remotes.StateChanged:FireClient(player, Net.snapshot(player))
end

function Net.notice(player: Player, message: string)
	Remotes.Notice:FireClient(player, message)
end

return Net
