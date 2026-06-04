--!strict
-- Spawns and drives the player's current rig (pickup → flatbed → logging
-- truck → feller buncher). One rig per player at a time; calling CallRig
-- destroys the old one and spawns a fresh one next to the player's character.
--
-- Physics: same VectorForce + AlignOrientation pattern as the MB Vehicles.
-- Trucks are big, so we boost mass + damping vs. the lighter aircraft.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Rigs = require(Shared:WaitForChild("Rigs"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local RigService = {}

type Mover = {
	attachment: Attachment?,
	force: VectorForce?,
	orient: AlignOrientation?,
}

type RigEntry = {
	player: Player,
	model: Model,
	seat: VehicleSeat,
	tier: Rigs.RigTier,
	pilot: Humanoid?,
	mover: Mover,
	yawCFrame: CFrame?,
}

local registry: { [Player]: RigEntry } = {}

-- ===================== builders ===================================

local function p(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(part :: any)[k] = v
	end
	return part
end

local function weldTo(root: BasePart, other: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = other
	w.Parent = root
end

local function buildPickup(tier: Rigs.RigTier, pos: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Rig_" .. tier.id
	local L, W = tier.length, tier.width
	local cab = p({ Name = "Cab", Size = Vector3.new(L * 0.42, 3.0, W), Color = tier.bodyColor })
	cab.CFrame = CFrame.new(pos + Vector3.new(L * 0.22, 1.6, 0))
	cab.Parent = model
	model.PrimaryPart = cab
	local bed = p({ Name = "Bed", Size = Vector3.new(L * 0.55, 0.6, W), Color = tier.bedColor,
		Material = Enum.Material.WoodPlanks })
	bed.CFrame = CFrame.new(pos + Vector3.new(-L * 0.23, 0.35, 0))
	bed.Parent = model
	weldTo(cab, bed)
	local chassis = p({ Name = "Chassis", Size = Vector3.new(L, 1.0, W), Color = Color3.fromRGB(38, 38, 40) })
	chassis.CFrame = CFrame.new(pos + Vector3.new(0, -0.1, 0))
	chassis.Parent = model
	weldTo(cab, chassis)
	for _, wx in { L * 0.3, -L * 0.28 } do
		for _, wz in { W * 0.52, -W * 0.52 } do
			local wh = p({ Name = "Wheel", Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1.1, 2.5, 2.5), Color = Color3.fromRGB(28, 28, 28),
				Material = Enum.Material.SmoothPlastic })
			wh.CFrame = CFrame.new(pos + Vector3.new(wx, -0.7, wz)) * CFrame.Angles(0, 0, math.rad(90))
			wh.Parent = model
			weldTo(cab, wh)
		end
	end
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriveSeat"
	seat.Size = Vector3.new(2.2, 0.6, 2.2)
	seat.Color = Color3.fromRGB(30, 30, 36)
	seat.CFrame = CFrame.new(pos + Vector3.new(L * 0.18, 3.25, 0))
	seat.HeadsUpDisplay = false
	seat:SetAttribute("VehicleKind", tier.id)
	seat.Parent = model
	weldTo(cab, seat)
	return model
end

local function buildFlatbed(tier: Rigs.RigTier, pos: Vector3): Model
	local model = buildPickup(tier, pos) -- same cab shape, longer bed handled by L
	model.Name = "Rig_" .. tier.id
	-- Add stake rails on the sides of the bed.
	local L, W = tier.length, tier.width
	local cab = model.PrimaryPart :: BasePart
	for _, wz in { W * 0.55, -W * 0.55 } do
		local rail = p({ Name = "Rail", Size = Vector3.new(L * 0.58, 1.2, 0.4), Color = tier.bodyColor })
		rail.CFrame = CFrame.new(pos + Vector3.new(-L * 0.23, 1.0, wz))
		rail.Parent = model
		weldTo(cab, rail)
	end
	return model
end

local function buildLoggingTruck(tier: Rigs.RigTier, pos: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Rig_" .. tier.id
	local L, W = tier.length, tier.width
	-- Longer nose, sleeper cab, heavy bunk in the back.
	local cab = p({ Name = "Cab", Size = Vector3.new(L * 0.28, 4.0, W), Color = tier.bodyColor })
	cab.CFrame = CFrame.new(pos + Vector3.new(L * 0.36, 2.2, 0))
	cab.Parent = model
	model.PrimaryPart = cab
	local bunk = p({ Name = "Bunk", Size = Vector3.new(L * 0.70, 1.2, W * 0.8), Color = tier.bedColor,
		Material = Enum.Material.Metal })
	bunk.CFrame = CFrame.new(pos + Vector3.new(-L * 0.2, 0.7, 0))
	bunk.Parent = model
	weldTo(cab, bunk)
	-- Two log stanchions sticking up from the bunk.
	for _, bx in { -L * 0.08, -L * 0.35 } do
		local st = p({ Name = "Stanchion", Size = Vector3.new(1.2, 4.8, 1.2), Color = Color3.fromRGB(50, 52, 56) })
		st.CFrame = CFrame.new(pos + Vector3.new(bx, 3.1, 0))
		st.Parent = model
		weldTo(cab, st)
	end
	local chassis = p({ Name = "Chassis", Size = Vector3.new(L, 1.2, W), Color = Color3.fromRGB(28, 28, 30) })
	chassis.CFrame = CFrame.new(pos + Vector3.new(0, -0.2, 0))
	chassis.Parent = model
	weldTo(cab, chassis)
	for _, wx in { L * 0.38, L * 0.06, -L * 0.26 } do
		for _, wz in { W * 0.52, -W * 0.52 } do
			local wh = p({ Name = "Wheel", Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1.4, 3.0, 3.0), Color = Color3.fromRGB(24, 24, 24) })
			wh.CFrame = CFrame.new(pos + Vector3.new(wx, -0.8, wz)) * CFrame.Angles(0, 0, math.rad(90))
			wh.Parent = model
			weldTo(cab, wh)
		end
	end
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriveSeat"
	seat.Size = Vector3.new(2.4, 0.6, 2.4)
	seat.Color = Color3.fromRGB(30, 30, 36)
	seat.CFrame = CFrame.new(pos + Vector3.new(L * 0.34, 4.4, 0))
	seat.HeadsUpDisplay = false
	seat:SetAttribute("VehicleKind", tier.id)
	seat.Parent = model
	weldTo(cab, seat)
	return model
end

local function buildFellerBuncher(tier: Rigs.RigTier, pos: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Rig_" .. tier.id
	local L, W = tier.length, tier.width
	-- Boxy tracked body, articulated arm, spinning cutting head.
	local body = p({ Name = "Body", Size = Vector3.new(L * 0.6, 4.0, W * 0.85), Color = tier.bodyColor })
	body.CFrame = CFrame.new(pos + Vector3.new(0, 2.5, 0))
	body.Parent = model
	model.PrimaryPart = body
	-- Track frames (wide, flat, on each side).
	for _, wz in { W * 0.52, -W * 0.52 } do
		local track = p({ Name = "Track", Size = Vector3.new(L * 0.78, 1.6, 2.8), Color = Color3.fromRGB(28, 28, 28) })
		track.CFrame = CFrame.new(pos + Vector3.new(0, 0.0, wz))
		track.Parent = model
		weldTo(body, track)
	end
	-- Boom arm pointing forward-up.
	local boom = p({ Name = "Boom", Size = Vector3.new(1.4, 1.4, L * 0.50), Color = Color3.fromRGB(50, 52, 56),
		Material = Enum.Material.Metal })
	boom.CFrame = CFrame.new(pos + Vector3.new(0, 5.2, -L * 0.35)) * CFrame.Angles(math.rad(-28), 0, 0)
	boom.Parent = model
	weldTo(body, boom)
	-- Cutting head at the tip of the boom (a flat disc + spikes).
	local head = p({ Name = "CutHead", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.0, 3.8, 3.8), Color = Color3.fromRGB(200, 50, 40),
		Material = Enum.Material.Metal })
	head.CFrame = CFrame.new(pos + Vector3.new(0, 3.2, -L * 0.62)) * CFrame.Angles(0, 0, math.rad(90))
	head.Parent = model
	weldTo(body, head)
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriveSeat"
	seat.Size = Vector3.new(2.2, 0.6, 2.2)
	seat.Color = Color3.fromRGB(30, 30, 36)
	seat.CFrame = CFrame.new(pos + Vector3.new(0, 5.1, 0))
	seat.HeadsUpDisplay = false
	seat:SetAttribute("VehicleKind", tier.id)
	seat.Parent = model
	weldTo(body, seat)
	return model
end

local builders: { [string]: (tier: Rigs.RigTier, pos: Vector3) -> Model } = {
	pickup = buildPickup,
	flatbed = buildFlatbed,
	logging_truck = buildLoggingTruck,
	feller_buncher = buildFellerBuncher,
}

-- ===================== physics ====================================

local function setAnchored(model: Model, anchored: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = anchored
		end
	end
end

local function attachMovers(entry: RigEntry)
	local root = entry.model.PrimaryPart
	if not root then return end
	local at = Instance.new("Attachment")
	at.Name = "RigRoot"
	at.Parent = root
	local force = Instance.new("VectorForce")
	force.Attachment0 = at
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = Vector3.zero
	force.Parent = root
	local orient = Instance.new("AlignOrientation")
	orient.Attachment0 = at
	orient.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orient.CFrame = root.CFrame
	orient.MaxAngularVelocity = math.rad(entry.tier.turnSpeed)
	orient.MaxTorque = 5e7
	orient.Responsiveness = 25
	orient.Parent = root
	local _, yaw = root.CFrame:ToEulerAnglesYXZ()
	entry.mover.attachment = at
	entry.mover.force = force
	entry.mover.orient = orient
	entry.yawCFrame = CFrame.Angles(0, yaw, 0)
end

local function clearMovers(entry: RigEntry)
	if entry.mover.force then entry.mover.force:Destroy() end
	if entry.mover.orient then entry.mover.orient:Destroy() end
	if entry.mover.attachment then entry.mover.attachment:Destroy() end
	entry.mover.force = nil
	entry.mover.orient = nil
	entry.mover.attachment = nil
end

local function onPilotIn(entry: RigEntry, humanoid: Humanoid)
	entry.pilot = humanoid
	humanoid.AutoRotate = false
	setAnchored(entry.model, false)
	attachMovers(entry)
end

local function onPilotOut(entry: RigEntry)
	if entry.pilot then
		entry.pilot.AutoRotate = true
	end
	entry.pilot = nil
	local root = entry.model.PrimaryPart
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	clearMovers(entry)
	setAnchored(entry.model, true)
end

RunService.Heartbeat:Connect(function(dt)
	for _, entry in registry do
		if not entry.pilot then continue end
		local root = entry.model.PrimaryPart
		if not root then continue end
		local seat = entry.seat
		local throttle = seat.Throttle
		local steer = seat.Steer
		local mass = root.AssemblyMass
		local gravity = Workspace.Gravity
		-- Trucks are ground vehicles: apply just enough upward force to
		-- counteract gravity so physics + terrain keep them grounded.
		-- The terrain constraint does the heavy lifting; we don't want lift.
		local groundForce = mass * gravity * 1.02
		local spd = entry.tier.driveSpeed
		local fwd = seat.CFrame.LookVector
		local thrust = Vector3.new(fwd.X, 0, fwd.Z).Unit * (mass * spd * 0.3) * throttle
		local force = entry.mover.force
		if force then
			force.Force = Vector3.new(thrust.X, groundForce, thrust.Z)
		end
		local yawRate = math.rad(entry.tier.turnSpeed)
		local cur = entry.yawCFrame or CFrame.new()
		cur = cur * CFrame.Angles(0, -steer * yawRate * dt, 0)
		entry.yawCFrame = cur
		if entry.mover.orient then
			entry.mover.orient.CFrame = cur
		end
	end
end)

-- ===================== public API =================================

function RigService.spawn(player: Player)
	if not PlayerData.isLoaded(player) then return end
	-- Remove any existing rig for this player.
	local old = registry[player]
	if old then
		if old.pilot then onPilotOut(old) end
		old.model:Destroy()
		registry[player] = nil
	end
	local prof = PlayerData.get(player)
	local tier = Rigs.tier(prof.rigTier)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local spawnPos = hrp and (hrp :: BasePart).Position + Vector3.new(12, 1, 0) or Vector3.new(16, 4, 0)
	local builder = builders[tier.kind] or buildPickup
	local model = builder(tier, spawnPos)
	model.Parent = Workspace
	local seat = model:FindFirstChild("DriveSeat") :: VehicleSeat
	if not seat then
		model:Destroy()
		return
	end
	local entry: RigEntry = {
		player = player,
		model = model,
		seat = seat,
		tier = tier,
		pilot = nil,
		mover = {},
		yawCFrame = nil,
	}
	registry[player] = entry
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occ = seat.Occupant
		if occ then
			onPilotIn(entry, occ)
		else
			onPilotOut(entry)
		end
	end)
end

function RigService.respawnForPlayer(player: Player)
	RigService.spawn(player)
end

-- Called from Shop after a rig upgrade so the new model appears immediately.
function RigService.upgradeAndRespawn(player: Player)
	RigService.spawn(player)
end

Remotes.CallRig.OnServerEvent:Connect(function(player)
	if not PlayerData.isLoaded(player) then return end
	RigService.spawn(player)
end)

Players.PlayerRemoving:Connect(function(player)
	local entry = registry[player]
	if entry then
		if entry.pilot then onPilotOut(entry) end
		entry.model:Destroy()
		registry[player] = nil
	end
end)

return RigService
