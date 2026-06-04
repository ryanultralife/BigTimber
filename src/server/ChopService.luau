--!strict
-- Authoritative chopping. The client fires ChopTree(uid) once per swing of
-- the equipped tool; we validate reach + a per-player cooldown, apply the
-- tool's damage to the tree, and on the killing swing fell it and credit the
-- player's load. Server owns all HP and rewards.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Tools = require(Shared:WaitForChild("Tools"))
local Rigs = require(Shared:WaitForChild("Rigs"))
local Wood = require(Shared:WaitForChild("Wood"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local Forest = require(script.Parent:WaitForChild("Forest"))
local Net = require(script.Parent:WaitForChild("Net"))

local ChopService = {}

local C = GameConfig.Chop
local lastSwing: { [Player]: number } = {}

local function horizontalDist(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

Remotes.ChopTree.OnServerEvent:Connect(function(player, uid)
	if typeof(uid) ~= "string" then
		return
	end
	if not PlayerData.isLoaded(player) then
		return
	end
	local now = os.clock()
	if (lastSwing[player] or 0) + C.ServerSwingCooldown > now then
		return -- swinging too fast; ignore (anti-spam)
	end

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		return
	end
	local model = Forest.getTree(uid)
	if not model or not model.PrimaryPart then
		return
	end
	if horizontalDist(hrp.Position, model.PrimaryPart.Position) > C.ReachStuds then
		return -- too far from the tree
	end

	local prof = PlayerData.get(player)
	-- Can't START on a fresh tree while the load is already full. (A tree
	-- already in progress can still tip you over capacity, so you never
	-- lose a tree you've worked on.)
	local cap = Rigs.tier(prof.rigTier).logCapacity
	if prof.loadLogs >= cap then
		Net.notice(player, "Load full — drive to the sawmill and unload!")
		return
	end

	lastSwing[player] = now

	local hp = model:GetAttribute("Hp")
	local maxHp = model:GetAttribute("MaxHp")
	if typeof(hp) ~= "number" or typeof(maxHp) ~= "number" then
		return
	end

	hp -= Tools.tier(prof.toolTier).damagePerSwing
	if hp > 0 then
		model:SetAttribute("Hp", hp)
		Forest.updateHealthBar(model, hp / maxHp)
		return
	end

	-- Killing swing: fell + reward.
	model:SetAttribute("Hp", 0)
	local result = Forest.fell(uid)
	if not result then
		return
	end
	local species = Wood.get(result.speciesId)
	local price = species and species.plankPrice or 0
	prof.loadLogs += result.logs
	prof.loadValue += result.logs * price
	prof.lifetimeLogs += result.logs
	Net.notice(player, ("Timber!  +%d %s logs"):format(result.logs, species and species.name or "wood"))
	Net.push(player)
end)

Players.PlayerRemoving:Connect(function(player)
	lastSwing[player] = nil
end)

return ChopService
