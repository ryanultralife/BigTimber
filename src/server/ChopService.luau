--!strict
-- Authoritative chopping. The client fires ChopTree(uid) per swing; we
-- validate reach + cooldown, apply the equipped tool's damage, and play
-- the swing/chip feedback every player can see. On the killing swing the
-- tree topples and drops REAL logs on the ground (LogService) — they get
-- onto the truck only when the truck is parked near them.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Tools = require(Shared:WaitForChild("Tools"))
local Wood = require(Shared:WaitForChild("Wood"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local Forest = require(script.Parent:WaitForChild("Forest"))
local Net = require(script.Parent:WaitForChild("Net"))
local LogService = require(script.Parent:WaitForChild("LogService"))
local Loadout = require(script.Parent:WaitForChild("Loadout"))

local ChopService = {}

local C = GameConfig.Chop
local lastSwing: { [Player]: number } = {}
local rng = Random.new()

local function horizontalDist(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Wood chips burst + knock sound at the impact point, facing the chopper.
local function chipBurst(treeModel: Model, hrp: BasePart)
	local trunk = treeModel.PrimaryPart
	if not trunk then
		return
	end
	local dir = hrp.Position - trunk.Position
	dir = Vector3.new(dir.X, 0, dir.Z)
	dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.zAxis

	local hitPos = trunk.Position + dir * (trunk.Size.X / 2) + Vector3.new(0, 0.6, 0)
	local fx = Instance.new("Part")
	fx.Size = Vector3.new(0.2, 0.2, 0.2)
	fx.Transparency = 1
	fx.Anchored = true
	fx.CanCollide = false
	fx.CFrame = CFrame.lookAt(hitPos, hitPos + dir)
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(trunk.Color)
	pe.Size = NumberSequence.new(0.22)
	pe.Lifetime = NumberRange.new(0.3, 0.6)
	pe.Speed = NumberRange.new(5, 9)
	pe.SpreadAngle = Vector2.new(35, 35)
	pe.Rate = 0
	pe.EmissionDirection = Enum.NormalId.Front
	pe.Parent = fx
	-- Placeholder audio: built-in snap pitched down reads as a wood knock.
	-- Swap for real chop/saw assets in a dedicated audio pass.
	local snd = Instance.new("Sound")
	snd.SoundId = "rbxasset://sounds/snap.mp3"
	snd.PlaybackSpeed = 0.55 + rng:NextNumber() * 0.2
	snd.Volume = 0.7
	snd.Parent = fx
	fx.Parent = Workspace
	pe:Emit(14)
	snd:Play()
	Debris:AddItem(fx, 1.2)
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
		return
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
		return
	end

	lastSwing[player] = now

	-- Swing + chips on every accepted hit, visible to everyone.
	pcall(Loadout.swing, player)
	chipBurst(model, hrp)

	local hp = model:GetAttribute("Hp")
	local maxHp = model:GetAttribute("MaxHp")
	if typeof(hp) ~= "number" or typeof(maxHp) ~= "number" then
		return
	end

	local prof = PlayerData.get(player)
	hp -= Tools.tier(prof.toolTier).damagePerSwing
	if hp > 0 then
		model:SetAttribute("Hp", hp)
		Forest.updateHealthBar(model, hp / maxHp)
		return
	end

	-- Killing swing: topple the tree and drop physical logs at the stump.
	model:SetAttribute("Hp", 0)
	local result = Forest.fell(uid)
	if not result then
		return
	end
	local species = Wood.get(result.speciesId)
	prof.lifetimeTrees = (prof.lifetimeTrees or 0) + 1
	LogService.spawnLogs(player, result.speciesId, result.logs, result.position)
	Net.notice(player, ("TIMBER! %d %s logs — bring the truck close to load them"):format(
		result.logs, species and species.name or "wood"))
end)

Players.PlayerRemoving:Connect(function(player)
	lastSwing[player] = nil
end)

return ChopService
