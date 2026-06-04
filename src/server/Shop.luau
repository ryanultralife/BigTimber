--!strict
-- Handles BuyUpgrade remote: "tool" upgrades the axe/chainsaw tier,
-- "rig" upgrades the truck tier. Server validates cash, deducts, and
-- updates the profile. After a rig upgrade it respawns the new vehicle.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Tools = require(Shared:WaitForChild("Tools"))
local Rigs = require(Shared:WaitForChild("Rigs"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local Net = require(script.Parent:WaitForChild("Net"))
local Loadout = require(script.Parent:WaitForChild("Loadout"))
local RigService = require(script.Parent:WaitForChild("RigService"))

Remotes.BuyUpgrade.OnServerInvoke = function(player, track)
	if typeof(track) ~= "string" then
		return false, "bad request"
	end
	if not PlayerData.isLoaded(player) then
		return false, "not loaded"
	end
	local prof = PlayerData.get(player)

	if track == "tool" then
		local nextIdx = prof.toolTier + 1
		local nextTier = Tools.Tiers[nextIdx]
		if not nextTier then
			return false, "Already at max tool tier"
		end
		if prof.cash < nextTier.cost then
			return false, ("Need $%d"):format(nextTier.cost)
		end
		prof.cash -= nextTier.cost
		prof.toolTier = nextIdx
		pcall(Loadout.equip, player)
		Net.push(player)
		return true

	elseif track == "rig" then
		local nextIdx = prof.rigTier + 1
		local nextTier = Rigs.Tiers[nextIdx]
		if not nextTier then
			return false, "Already at max rig tier"
		end
		if prof.cash < nextTier.cost then
			return false, ("Need $%d"):format(nextTier.cost)
		end
		prof.cash -= nextTier.cost
		prof.rigTier = nextIdx
		RigService.upgradeAndRespawn(player)
		Net.push(player)
		return true
	end

	return false, "unknown track"
end

return {}
