--!strict
-- Builds "Big Dale" the equipment dealer NPC inside the shop building
-- and wires up his ProximityPrompt to fire Remotes.OpenShop to the
-- triggering player. The actual upgrade logic lives in Shop.luau.

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local ShopNPC = {}

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do (p :: any)[k] = v end
	return p
end

function ShopNPC.spawn()
	local P = GameConfig.Shop.Position + Vector3.new(0, 0, 9) -- behind the counter

	local model = Instance.new("Model")
	model.Name = "BigDale"

	local SKIN = Color3.fromRGB(255, 218, 170)
	local SHIRT = Color3.fromRGB(180, 60, 55) -- red/black plaid
	local JEANS = Color3.fromRGB(58, 80, 105)
	local HAT = Color3.fromRGB(230, 210, 40) -- yellow hard hat
	local BOOT = Color3.fromRGB(80, 58, 40)

	-- Torso (root)
	local torso = part({ Name = "Torso",
		Size = Vector3.new(2, 2, 1), Position = P + Vector3.new(0, 3.5, 0),
		Color = SHIRT, CanCollide = false })
	torso.Parent = model
	model.PrimaryPart = torso

	local function limb(name: string, sz: Vector3, offset: Vector3, col: Color3): Part
		local l = part({ Name = name, Size = sz,
			Position = P + offset, Color = col })
		l.Parent = model
		local w = Instance.new("WeldConstraint")
		w.Part0 = torso; w.Part1 = l; w.Parent = torso
		return l
	end

	-- Head + hat
	limb("Head", Vector3.new(2, 2, 2), Vector3.new(0, 5.5, 0), SKIN)
	limb("HardHat", Vector3.new(2.5, 0.9, 2.5), Vector3.new(0, 6.85, 0), HAT)
	limb("HatBrim", Vector3.new(3.4, 0.25, 3.4), Vector3.new(0, 6.35, 0), HAT)
	-- Face detail (dark eyes)
	limb("EyeL", Vector3.new(0.3, 0.3, 0.05),
		Vector3.new(-0.5, 5.5, -0.5), Color3.fromRGB(40, 30, 20))
	limb("EyeR", Vector3.new(0.3, 0.3, 0.05),
		Vector3.new(0.5, 5.5, -0.5), Color3.fromRGB(40, 30, 20))
	-- Mustache
	limb("Stache", Vector3.new(1.2, 0.25, 0.05),
		Vector3.new(0, 4.85, -0.5), Color3.fromRGB(80, 50, 30))

	-- Arms (held slightly outward + forward — welcoming pose)
	local leftArm = limb("LeftArm", Vector3.new(1, 2, 1),
		Vector3.new(-1.5, 3.5, 0), SHIRT)
	leftArm.CFrame = CFrame.new(P + Vector3.new(-1.7, 3.6, -0.3))
		* CFrame.Angles(math.rad(-15), 0, math.rad(-15))
	local rightArm = limb("RightArm", Vector3.new(1, 2, 1),
		Vector3.new(1.5, 3.5, 0), SHIRT)
	rightArm.CFrame = CFrame.new(P + Vector3.new(1.7, 3.6, -0.3))
		* CFrame.Angles(math.rad(-15), 0, math.rad(15))
	-- Hands
	limb("HandL", Vector3.new(0.9, 0.9, 0.9), Vector3.new(-2.1, 2.5, -0.5), SKIN)
	limb("HandR", Vector3.new(0.9, 0.9, 0.9), Vector3.new(2.1, 2.5, -0.5), SKIN)

	-- Legs
	limb("LeftLeg", Vector3.new(0.9, 2, 0.9), Vector3.new(-0.5, 1.5, 0), JEANS)
	limb("RightLeg", Vector3.new(0.9, 2, 0.9), Vector3.new(0.5, 1.5, 0), JEANS)
	limb("BootL", Vector3.new(0.95, 0.7, 1.3), Vector3.new(-0.5, 0.35, -0.2), BOOT)
	limb("BootR", Vector3.new(0.95, 0.7, 1.3), Vector3.new(0.5, 0.35, -0.2), BOOT)
	-- Suspenders (two thin straps)
	for _, sx in { -0.5, 0.5 } do
		limb("Suspender", Vector3.new(0.25, 2.1, 0.1),
			Vector3.new(sx, 3.5, -0.46), Color3.fromRGB(90, 58, 28))
	end

	-- Nametag billboard
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(240, 56)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
	bb.AlwaysOnTop = false
	bb.Parent = torso
	local nl = Instance.new("TextLabel")
	nl.Size = UDim2.fromScale(1, 1)
	nl.BackgroundTransparency = 1
	nl.Font = Enum.Font.GothamBold
	nl.TextSize = 15
	nl.TextColor3 = Color3.fromRGB(255, 255, 255)
	nl.TextStrokeTransparency = 0.25
	nl.Text = "Big Dale\nEquipment Dealer"
	nl.Parent = bb

	-- ProximityPrompt on the root part
	local pp = Instance.new("ProximityPrompt")
	pp.ObjectText = "Big Dale"
	pp.ActionText = "Talk"
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.MaxActivationDistance = 12
	pp.RequiresLineOfSight = false
	pp.HoldDuration = 0
	pp.Parent = torso

	pp.Triggered:Connect(function(player: Player)
		if not PlayerData.isLoaded(player) then return end
		Remotes.OpenShop:FireClient(player)
	end)

	model.Parent = Workspace
end

return ShopNPC
