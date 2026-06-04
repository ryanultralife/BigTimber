--!strict
-- Cosmetic only: welds a little axe / chainsaw into the player's right hand
-- so the kid SEES the tool they bought. Chopping itself is validated in
-- ChopService — this is pure decoration, and every call site wraps it in a
-- pcall so an avatar quirk can never break the chop loop.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Tools = require(Shared:WaitForChild("Tools"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local Loadout = {}

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = false
	p.CanCollide = false
	p.Massless = true
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

function Loadout.equip(player: Player)
	local char = player.Character
	if not char then
		return
	end
	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		return
	end

	local existing = char:FindFirstChild("HeldTool")
	if existing then
		existing:Destroy()
	end

	local prof = PlayerData.get(player)
	local tier = Tools.tier(prof.toolTier)

	local model = Instance.new("Model")
	model.Name = "HeldTool"

	local handle = part({ Name = "Handle", Size = Vector3.new(0.25, 2.2, 0.25), Color = tier.handleColor })
	handle.Material = Enum.Material.Wood
	model.PrimaryPart = handle

	local head: Part
	if tier.powered then
		-- chainsaw: motor block + a bar pointing forward
		head = part({ Name = "Bar", Size = Vector3.new(0.3, 0.55, 3.2), Color = tier.headColor })
		head.CFrame = handle.CFrame * CFrame.new(0, 1.0, -1.5)
	else
		-- axe head near the top of the haft
		head = part({ Name = "Head", Size = Vector3.new(0.35, 1.0, 1.4), Color = tier.headColor })
		head.Material = Enum.Material.Metal
		head.CFrame = handle.CFrame * CFrame.new(0, 0.85, -0.45)
	end

	local hw = Instance.new("Weld")
	hw.Part0 = handle
	hw.Part1 = head
	hw.C0 = handle.CFrame:Inverse() * head.CFrame
	hw.Parent = head
	head.Parent = model
	handle.Parent = model

	-- Weld the haft into the hand. Offsets are eyeballed for R15; close
	-- enough for a stylized look.
	local grip = Instance.new("Weld")
	grip.Part0 = hand
	grip.Part1 = handle
	grip.C0 = CFrame.new(0, -0.2, -0.4) * CFrame.Angles(math.rad(90), 0, 0)
	grip.Parent = handle

	model.Parent = char
end

return Loadout
