--!strict
-- The sawmill loop. Any player carrying logs who stands (or parks their
-- truck) within the mill's intake radius has their load eaten over time and
-- converted to cash. The saw blade idles slowly and spins up while cutting.
--
-- The load tracks two numbers: loadLogs (for the capacity gate in
-- ChopService) and loadValue (the cash it mills into). We drain both in
-- proportion so a mixed load of pine + oak pays out correctly.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local Net = require(script.Parent:WaitForChild("Net"))

local MillService = {}

local M = GameConfig.Mill
-- Cash milled in the current visit, per player — flushed to a notice when
-- the load hits zero so the kid sees "Milled your load for $X".
local sessionCash: { [Player]: number } = {}

local blade: BasePart? = nil
local bladeBase: CFrame? = nil
local bladeAngle = 0

local function getBlade(): BasePart?
	if blade and blade.Parent then
		return blade
	end
	local mill = Workspace:FindFirstChild("Mill")
	local found = mill and mill:FindFirstChild("SawBlade")
	if found and found:IsA("BasePart") then
		blade = found
		bladeBase = found.CFrame
		return found
	end
	return nil
end

RunService.Heartbeat:Connect(function(dt)
	local anyCutting = false

	for _, player in Players:GetPlayers() do
		if not PlayerData.isLoaded(player) then
			continue
		end
		local prof = PlayerData.get(player)
		if prof.loadLogs <= 0 then
			continue
		end
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp or not hrp:IsA("BasePart") then
			continue
		end
		local dx = hrp.Position.X - M.Position.X
		local dz = hrp.Position.Z - M.Position.Z
		if math.sqrt(dx * dx + dz * dz) > M.IntakeRadius then
			continue
		end

		-- Drain the load proportionally and credit the cash.
		local n = math.min(prof.loadLogs, M.ProcessLogsPerSecond * dt)
		local frac = n / prof.loadLogs
		local gain = prof.loadValue * frac
		prof.loadLogs -= n
		prof.loadValue -= gain
		prof.cash += gain
		prof.lifetimeCash += gain
		sessionCash[player] = (sessionCash[player] or 0) + gain
		anyCutting = true

		if prof.loadLogs <= 0.05 then
			prof.loadLogs = 0
			prof.loadValue = 0
			local total = sessionCash[player] or 0
			sessionCash[player] = nil
			if total >= 1 then
				Net.notice(player, ("Milled your load for $%d"):format(math.floor(total + 0.5)))
			end
		end
	end

	local b = getBlade()
	if b and bladeBase then
		bladeAngle += (anyCutting and 16 or 2) * dt
		b.CFrame = bladeBase * CFrame.Angles(bladeAngle, 0, 0)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	sessionCash[player] = nil
end)

return MillService
