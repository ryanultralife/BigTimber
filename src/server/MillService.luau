--!strict
-- The sawmill. Drains a nearby player's log load into cash, and runs the
-- machinery so the mill visibly WORKS while it does:
--   • Sash saw blade strokes up and down (fast while cutting, slow idle)
--   • Debarker drum rolls, green-chain rollers turn, edger blades spin
--   • Log carriage rides forward THROUGH the saw and back
--   • A visible log travels rollway → carriage → saw, bursts sawdust,
--     and boards come out the far side down the green chain
--
-- Animation pattern: every animated part caches its BASE CFrame once and
-- sets `base * offset(t)` each frame. Never multiply onto the current
-- CFrame — that compounds and the part spins up forever.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Rigs = require(Shared:WaitForChild("Rigs"))

local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local Net = require(script.Parent:WaitForChild("Net"))
local RigService = require(script.Parent:WaitForChild("RigService"))

local MillService = {}

local M = GameConfig.Mill
local INTAKE_CENTER = M.Position + M.IntakePadOffset

-- Cash milled in the current visit per player; flushed to a toast when
-- the load hits zero.
local sessionCash: { [Player]: number } = {}
-- Last integer log count shown on each player's truck (visual refresh).
local lastShown: { [Player]: number } = {}

-- ═════════════════════════ mill part cache ══════════════════════════

type MillParts = {
	millModel: Model?,
	debarker: BasePart?,
	debarkerBase: CFrame?,
	sawBlade: BasePart?,
	sawBase: CFrame?,
	carriage: BasePart?,
	carriageBase: CFrame?,
	gcRollers: { BasePart },
	edgerBlades: { BasePart },
	sawdust: ParticleEmitter?,
}

local millCache: MillParts? = nil

local function getMillParts(): MillParts
	if millCache then
		return millCache
	end
	local cache: MillParts = { gcRollers = {}, edgerBlades = {} }
	local mill = Workspace:FindFirstChild("Mill")
	if not mill or not mill:IsA("Model") then
		millCache = cache
		return cache
	end
	cache.millModel = mill

	local drum = mill:FindFirstChild("DebarkerDrum")
	if drum and drum:IsA("BasePart") then
		cache.debarker = drum
		cache.debarkerBase = drum.CFrame
	end
	local blade = mill:FindFirstChild("SawBlade")
	if blade and blade:IsA("BasePart") then
		cache.sawBlade = blade
		cache.sawBase = blade.CFrame
	end
	local carr = mill:FindFirstChild("Carriage")
	if carr and carr:IsA("BasePart") then
		cache.carriage = carr
		cache.carriageBase = carr.CFrame
	end
	local gcFolder = mill:FindFirstChild("GreenChain")
	if gcFolder then
		for _, d in gcFolder:GetChildren() do
			if d:IsA("BasePart") and d.Name == "GCRoller" then
				table.insert(cache.gcRollers, d)
			end
		end
	end
	for _, d in mill:GetChildren() do
		if d:IsA("BasePart") and d.Name == "EdgerBlade" then
			table.insert(cache.edgerBlades, d)
		end
	end

	-- Sawdust burst emitter, parked at the blade.
	local dustAnchor = Instance.new("Part")
	dustAnchor.Name = "SawdustAnchor"
	dustAnchor.Size = Vector3.new(0.4, 0.4, 0.4)
	dustAnchor.Transparency = 1
	dustAnchor.Anchored = true
	dustAnchor.CanCollide = false
	dustAnchor.CFrame = CFrame.new(M.Position + Vector3.new(0, 4, 5))
	dustAnchor.Parent = mill
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(Color3.fromRGB(214, 184, 130))
	pe.Size = NumberSequence.new(0.3)
	pe.Lifetime = NumberRange.new(0.4, 0.9)
	pe.Speed = NumberRange.new(4, 9)
	pe.SpreadAngle = Vector2.new(50, 50)
	pe.Rate = 0
	pe.Parent = dustAnchor
	cache.sawdust = pe

	millCache = cache
	return cache
end

-- ══════════════════════════ animation state ═════════════════════════

local drumAngle = 0
local gcAngle = 0
local edgerAngle = 0
local sawPhase = 0
local carriageT = 0
local carriageDir = 1
local CARRIAGE_RANGE = 16 -- studs forward THROUGH the saw (z -4 → +12)
local SAW_STROKE = 2.4 -- up/down amplitude, studs
local lastCutAt = 0

RunService.Heartbeat:Connect(function(dt)
	local anyCutting = false

	-- ── Drain loads for players parked on the intake pad ────────────
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
		local dx = hrp.Position.X - INTAKE_CENTER.X
		local dz = hrp.Position.Z - INTAKE_CENTER.Z
		if math.sqrt(dx * dx + dz * dz) > M.IntakeRadius then
			continue
		end

		local n = math.min(prof.loadLogs, M.ProcessLogsPerSecond * dt)
		local frac = if prof.loadLogs > 0 then n / prof.loadLogs else 0
		local gain = prof.loadValue * frac
		prof.loadLogs -= n
		prof.loadValue -= gain
		prof.cash += gain
		prof.lifetimeCash += gain
		sessionCash[player] = (sessionCash[player] or 0) + gain
		anyCutting = true

		local cap = Rigs.tier(prof.rigTier).logCapacity
		local shown = math.floor(prof.loadLogs)
		if lastShown[player] ~= shown then
			lastShown[player] = shown
			RigService.updateVisualLogs(player, prof.loadLogs, cap)
		end

		if prof.loadLogs <= 0.05 then
			prof.loadLogs = 0
			prof.loadValue = 0
			lastShown[player] = nil
			local total = sessionCash[player] or 0
			sessionCash[player] = nil
			if total >= 1 then
				Net.notice(player, ("Milled! +$%d"):format(math.floor(total + 0.5)))
			end
			RigService.updateVisualLogs(player, 0, cap)
		end
	end

	if anyCutting then
		lastCutAt = os.clock()
	end

	-- ── Machinery animation (base-CFrame pattern, never compounding) ─
	local parts = getMillParts()
	local spd = if anyCutting then 1.0 else 0.25

	drumAngle += 3.5 * spd * dt
	if parts.debarker and parts.debarker.Parent and parts.debarkerBase then
		parts.debarker.CFrame = parts.debarkerBase * CFrame.Angles(drumAngle, 0, 0)
	end

	-- Sash saw: vertical stroke. ~7 strokes/s cutting, gentle idle.
	sawPhase += (if anyCutting then 14 else 2.5) * dt
	if parts.sawBlade and parts.sawBlade.Parent and parts.sawBase then
		parts.sawBlade.CFrame = parts.sawBase
			* CFrame.new(0, math.sin(sawPhase) * SAW_STROKE, 0)
	end

	-- Carriage rides forward through the blade, then returns.
	if anyCutting and parts.carriage and parts.carriage.Parent and parts.carriageBase then
		carriageT += carriageDir * 0.55 * dt
		if carriageT >= 1 then
			carriageT = 1
			carriageDir = -1
		elseif carriageT <= 0 then
			carriageT = 0
			carriageDir = 1
		end
		parts.carriage.CFrame = parts.carriageBase
			* CFrame.new(0, 0, carriageT * CARRIAGE_RANGE)
	end

	gcAngle += 2.5 * spd * dt
	for _, roller in parts.gcRollers do
		if roller.Parent then
			roller.CFrame = CFrame.new(roller.Position) * CFrame.Angles(gcAngle, 0, 0)
		end
	end

	edgerAngle += 14 * spd * dt
	for _, eb in parts.edgerBlades do
		if eb.Parent then
			eb.CFrame = CFrame.new(eb.Position) * CFrame.Angles(edgerAngle, 0, 0)
		end
	end
end)

-- ═══════════════════ visible log → boards pipeline ══════════════════
-- While someone is unloading, a stream of visual logs rides the rollway
-- onto the carriage, passes through the stroking blade (sawdust burst),
-- and boards come out along the green chain. Pure theatre — the cash
-- drain above is the actual economy — but it's what makes the mill feel
-- like a mill.

local visBusy = false

local function tweenTo(part: BasePart, cf: CFrame, secs: number)
	local tw = TweenService:Create(part,
		TweenInfo.new(secs, Enum.EasingStyle.Linear), { CFrame = cf })
	tw:Play()
	tw.Completed:Wait()
end

local function runVisCycle(parts: MillParts)
	visBusy = true
	local P = M.Position
	local parent: Instance = parts.millModel or Workspace

	local log = Instance.new("Part")
	log.Name = "VisLog"
	log.Shape = Enum.PartType.Cylinder
	log.Size = Vector3.new(8, 2.2, 2.2)
	log.Color = Color3.fromRGB(128, 88, 58)
	log.Material = Enum.Material.Wood
	log.Anchored = true
	log.CanCollide = false
	local lying = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis along Z
	log.CFrame = CFrame.new(P + Vector3.new(0, 2.3, -20)) * lying
	log.Parent = parent

	-- Up the rollway, through the debarker, onto the carriage…
	tweenTo(log, CFrame.new(P + Vector3.new(0, 2.3, -4)) * lying, 1.0)
	-- …and through the saw.
	tweenTo(log, CFrame.new(P + Vector3.new(0, 2.3, 12)) * lying, 1.4)
	log:Destroy()

	if parts.sawdust then
		parts.sawdust:Emit(24)
	end

	-- Boards out along the green chain.
	for i = 1, 2 do
		local b = Instance.new("Part")
		b.Name = "VisBoard"
		b.Size = Vector3.new(1.7, 0.35, 6)
		b.Color = Color3.fromRGB(214, 178, 120)
		b.Material = Enum.Material.WoodPlanks
		b.Anchored = true
		b.CanCollide = false
		b.CFrame = CFrame.new(P + Vector3.new(16 + (i - 1.5) * 2.2, 2.0, -12))
		b.Parent = parent
		task.spawn(function()
			local tw = TweenService:Create(b,
				TweenInfo.new(1.7, Enum.EasingStyle.Linear),
				{ CFrame = b.CFrame + Vector3.new(0, 0, 22) })
			tw:Play()
			tw.Completed:Wait()
			b:Destroy()
		end)
	end
	visBusy = false
end

task.spawn(function()
	while true do
		if os.clock() - lastCutAt < 0.7 and not visBusy then
			local ok, err = pcall(runVisCycle, getMillParts())
			if not ok then
				visBusy = false
				warn("[Mill] vis cycle failed: " .. tostring(err))
			end
		else
			task.wait(0.2)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	sessionCash[player] = nil
	lastShown[player] = nil
end)

return MillService
