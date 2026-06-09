--!strict
-- Loose felled logs + truck loading. The realism loop the game is built
-- around: felling a tree drops REAL log parts on the ground; they only
-- get onto your truck when the truck is parked close to them.
--
-- Flow:
--   1. ChopService fells a tree → LogService.spawnLogs scatters physical
--      log cylinders at the stump (owner-tagged to the feller).
--   2. A 0.25s scan loop checks each player's rig: if it has free
--      capacity and one of THEIR logs is within Logs.LoadRadius, the log
--      tweens up onto the bunk and the profile load increments.
--   3. Full truck → logs wait on the ground. Abandoned logs despawn
--      after Logs.DespawnSeconds.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Wood = require(Shared:WaitForChild("Wood"))

local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local RigService = require(script.Parent:WaitForChild("RigService"))
local Net = require(script.Parent:WaitForChild("Net"))

local LogService = {}

local LG = GameConfig.Logs

type Loose = {
	part: Part,
	owner: number, -- UserId of the player who felled the tree
	value: number, -- cash this log mills into
	speciesId: string,
	bornAt: number,
}

local loose: { Loose } = {}
local logsFolder: Folder? = nil
local rng = Random.new()

local function folder(): Folder
	if logsFolder and logsFolder.Parent then
		return logsFolder
	end
	local f = Instance.new("Folder")
	f.Name = "LooseLogs"
	f.Parent = Workspace
	logsFolder = f
	return f
end

-- ══════════════════════════════ spawning ════════════════════════════

function LogService.spawnLogs(player: Player, speciesId: string, count: number, pos: Vector3)
	local species = Wood.get(speciesId)
	if not species then
		return
	end
	local dia = math.clamp(species.trunkRadius * 1.4, 1.3, 2.6)
	local len = math.clamp(species.trunkHeight * 0.28, 4, 8)

	for i = 1, count do
		local log = Instance.new("Part")
		log.Name = "LooseLog"
		log.Shape = Enum.PartType.Cylinder
		log.Size = Vector3.new(len, dia, dia)
		log.Color = species.logColor
		log.Material = Enum.Material.Wood
		log.Anchored = false
		log.CanCollide = true
		log.CFrame = CFrame.new(
			pos.X + rng:NextNumber(-3, 3),
			pos.Y + 1 + i * 1.2,
			pos.Z + rng:NextNumber(-3, 3))
			* CFrame.Angles(0, rng:NextNumber() * math.pi, math.rad(rng:NextNumber(-15, 15)))
		log.AssemblyLinearVelocity = Vector3.new(
			rng:NextNumber(-5, 5), 4, rng:NextNumber(-5, 5))
		log:SetAttribute("Species", speciesId)
		log.Parent = folder()

		table.insert(loose, {
			part = log,
			owner = player.UserId,
			value = species.plankPrice,
			speciesId = speciesId,
			bornAt = os.clock(),
		})
	end

	-- Perf guard: too many loose logs → oldest vanish first.
	while #loose > LG.MaxLoose do
		local oldest = table.remove(loose, 1)
		if oldest and oldest.part.Parent then
			oldest.part:Destroy()
		end
	end
end

-- ══════════════════════════════ loading ═════════════════════════════

local function loadOntoRig(entry: Loose, rigModel: Model)
	local root = rigModel.PrimaryPart
	local log = entry.part
	if not root or not log.Parent then
		return
	end
	-- Quick hop animation onto the bunk, then the part disappears into
	-- the load count (the truck's visual stack shows it from then on).
	log.Anchored = true
	log.CanCollide = false
	local target = CFrame.new(root.Position + Vector3.new(0, 4.5, 0))
		* CFrame.Angles(0, math.rad(90), 0)
	local tw = TweenService:Create(log,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = target })
	tw:Play()
	tw.Completed:Once(function()
		log:Destroy()
	end)
end

function LogService.start()
	folder()
	task.spawn(function()
		while true do
			task.wait(0.25)
			local now = os.clock()

			-- Prune despawned / destroyed logs (iterate backwards).
			for i = #loose, 1, -1 do
				local l = loose[i]
				if not l.part.Parent then
					table.remove(loose, i)
				elseif now - l.bornAt > LG.DespawnSeconds then
					l.part:Destroy()
					table.remove(loose, i)
				end
			end

			-- Vacuum logs onto nearby owned rigs.
			for _, player in Players:GetPlayers() do
				if not PlayerData.isLoaded(player) then
					continue
				end
				local rigModel, capacity = RigService.getRigInfo(player)
				if not rigModel or not rigModel.PrimaryPart or not capacity then
					continue
				end
				local prof = PlayerData.get(player)
				local free = math.floor(capacity - prof.loadLogs)
				if free < 1 then
					continue
				end

				local rigPos = rigModel.PrimaryPart.Position
				local taken = 0
				local takenValue = 0
				for i = #loose, 1, -1 do
					if taken >= free then
						break
					end
					local l = loose[i]
					if l.owner ~= player.UserId then
						continue
					end
					if not l.part.Parent then
						continue
					end
					if (l.part.Position - rigPos).Magnitude > LG.LoadRadius then
						continue
					end
					table.remove(loose, i)
					loadOntoRig(l, rigModel)
					taken += 1
					takenValue += l.value
				end

				if taken > 0 then
					prof.loadLogs = math.min(prof.loadLogs + taken, capacity)
					prof.loadValue += takenValue
					prof.lifetimeLogs += taken
					RigService.updateVisualLogs(player, prof.loadLogs, capacity)
					Net.push(player)
					Net.notice(player, ("Loaded +%d logs  (%d/%d)"):format(
						taken, math.floor(prof.loadLogs), capacity))
				end
			end
		end
	end)
end

return LogService
