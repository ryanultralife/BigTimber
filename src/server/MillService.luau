--!strict
-- The sawmill loop. Any player who drives their truck within the mill's
-- intake radius has their log load consumed over time and converted to cash.
-- Simultaneously animates the mill machinery (debarker drum, band-saw blade,
-- log carriage, green chain rollers, edger blades) so it looks like a real
-- working mill when logs are being processed.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Rigs = require(Shared:WaitForChild("Rigs"))

local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local Net = require(script.Parent:WaitForChild("Net"))
local RigService = require(script.Parent:WaitForChild("RigService"))

local MillService = {}

local M = GameConfig.Mill

-- Cash milled in the current visit per player, flushed to a notice when
-- the load hits zero so the player sees "Milled your load for $X".
local sessionCash: { [Player]: number } = {}

-- ══════════════════════════════════════════════════════════════════
-- Mill part cache — look up once, hold references
-- ══════════════════════════════════════════════════════════════════
type MillParts = {
	debarker: BasePart?,
	sawBlade: BasePart?,
	carriage: BasePart?,
	gcRollers: { BasePart },
	edgerBlades: { BasePart },
	carriageBase: CFrame?,
}

local millCache: MillParts? = nil

local function getMillParts(): MillParts
	if millCache then return millCache end
	local mill = Workspace:FindFirstChild("Mill")
	if not mill then
		millCache = { gcRollers = {}, edgerBlades = {} }
		return millCache :: MillParts
	end

	local cache: MillParts = { gcRollers = {}, edgerBlades = {} }
	cache.debarker = mill:FindFirstChild("DebarkerDrum") :: BasePart?
	cache.sawBlade = mill:FindFirstChild("SawBlade") :: BasePart?
	local carr = mill:FindFirstChild("Carriage")
	if carr and carr:IsA("BasePart") then
		cache.carriage = carr
		cache.carriageBase = carr.CFrame
	end
	local gcFolder = mill:FindFirstChild("GreenChain")
	if gcFolder then
		for _, d in gcFolder:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "GCRoller" then
				table.insert(cache.gcRollers, d)
			end
		end
	end
	for _, d in mill:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "EdgerBlade" then
			table.insert(cache.edgerBlades, d)
		end
	end
	millCache = cache
	return cache
end

-- ══════════════════════════════════════════════════════════════════
-- Animation state
-- ══════════════════════════════════════════════════════════════════
local debarkAngle = 0
local sawAngle = 0
local gcAngle = 0
local edgerAngle = 0
local carriageT = 0
local carriageDir = 1 -- 1 = forward through saw, -1 = return
local CARRIAGE_RANGE = 16 -- studs the carriage travels each pass

RunService.Heartbeat:Connect(function(dt)
	-- ── Determine if any player is currently milling ────────────────
	local anyCutting = false

	for _, player in Players:GetPlayers() do
		if not PlayerData.isLoaded(player) then continue end
		local prof = PlayerData.get(player)
		if prof.loadLogs <= 0 then continue end
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp or not hrp:IsA("BasePart") then continue end
		local dx = hrp.Position.X - M.Position.X
		local dz = hrp.Position.Z - M.Position.Z
		if math.sqrt(dx * dx + dz * dz) > M.IntakeRadius then continue end

		-- ── Process the load ──────────────────────────────────────
		local n = math.min(prof.loadLogs, M.ProcessLogsPerSecond * dt)
		local frac = if prof.loadLogs > 0 then n / prof.loadLogs else 0
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
				Net.notice(player, ("Milled! +$%d"):format(math.floor(total + 0.5)))
			end
			-- Clear physical log visuals from the truck.
			local cap = Rigs.tier(prof.rigTier).logCapacity
			RigService.updateVisualLogs(player, 0, cap)
		end
	end

	-- ── Animate mill machinery ────────────────────────────────────
	local parts = getMillParts()
	local idleSpd = 0.4
	local activeSpd = 1.0
	local spd = if anyCutting then activeSpd else idleSpd

	-- Debarker drum: continuous spin about X axis
	debarkAngle += 3.5 * spd * dt
	if parts.debarker and parts.debarker.Parent then
		local base = parts.debarker.CFrame
		parts.debarker.CFrame = CFrame.new(base.Position)
			* CFrame.fromMatrix(Vector3.zero, base.RightVector, base.UpVector)
			* CFrame.Angles(debarkAngle, 0, 0)
	end

	-- Band-saw blade: fast spin (just the flat blade part)
	sawAngle += 18 * spd * dt
	if parts.sawBlade and parts.sawBlade.Parent then
		local bs = parts.sawBlade
		bs.CFrame = CFrame.new(bs.CFrame.Position) * CFrame.Angles(0, sawAngle, 0)
	end

	-- Log carriage: slides back and forth along Z rails when cutting
	if anyCutting and parts.carriage and parts.carriageBase then
		carriageT += carriageDir * 2.2 * dt
		if carriageT >= 1 then carriageT = 1; carriageDir = -1
		elseif carriageT <= 0 then carriageT = 0; carriageDir = 1 end
		local base = parts.carriageBase :: CFrame
		parts.carriage.CFrame = base * CFrame.new(0, 0, -carriageT * CARRIAGE_RANGE)
	end

	-- Green chain rollers: slow continuous roll, speeds up when cutting
	gcAngle += 2.5 * spd * dt
	for _, roller in parts.gcRollers do
		if roller.Parent then
			local rp = roller.CFrame.Position
			roller.CFrame = CFrame.new(rp) * CFrame.Angles(gcAngle, 0, 0)
		end
	end

	-- Edger blades: spin about X axis (they're face-on cylinders, axis = X)
	edgerAngle += 14 * spd * dt
	for _, eb in parts.edgerBlades do
		if eb.Parent then
			local ep = eb.CFrame.Position
			eb.CFrame = CFrame.new(ep) * CFrame.Angles(edgerAngle, 0, 0)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	sessionCash[player] = nil
end)

return MillService
