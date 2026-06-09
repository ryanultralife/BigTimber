--!strict
-- The held felling tool: builds the axe/chainsaw prop in the player's
-- hand, and swings it when ChopService accepts a hit (server-side tween
-- on the grip weld, so every player sees the swing).
--
-- Cosmetic only — chopping is validated in ChopService. Call sites wrap
-- equip/swing in pcall so an avatar quirk can never break the chop loop.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Tools = require(Shared:WaitForChild("Tools"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local Loadout = {}

-- Rest pose of each player's grip weld; swing() tweens away and back.
local gripBase: { [Player]: CFrame } = {}

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
		-- Chainsaw: motor block + a bar pointing forward.
		head = part({ Name = "Bar", Size = Vector3.new(0.3, 0.55, 3.2), Color = tier.headColor })
		head.CFrame = handle.CFrame * CFrame.new(0, 1.0, -1.5)
	else
		-- Axe head near the top of the haft.
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

	-- Grip weld into the hand. swing() tweens this weld's C0.
	local grip = Instance.new("Weld")
	grip.Name = "Grip"
	grip.Part0 = hand
	grip.Part1 = handle
	grip.C0 = CFrame.new(0, -0.2, -0.4) * CFrame.Angles(math.rad(90), 0, 0)
	grip.Parent = handle

	gripBase[player] = grip.C0
	model.Parent = char
end

-- One chop arc: rotate the tool sharply forward, then ease back to rest.
function Loadout.swing(player: Player)
	local char = player.Character
	if not char then
		return
	end
	local tool = char:FindFirstChild("HeldTool")
	local handle = tool and tool:FindFirstChild("Handle")
	local grip = handle and handle:FindFirstChild("Grip")
	if not grip or not grip:IsA("Weld") then
		return
	end
	if grip:GetAttribute("Swinging") then
		return
	end
	grip:SetAttribute("Swinging", true)

	local base = gripBase[player] or grip.C0
	local swungOut = TweenService:Create(grip,
		TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ C0 = base * CFrame.Angles(math.rad(-80), 0, 0) })
	swungOut:Play()
	swungOut.Completed:Once(function()
		local back = TweenService:Create(grip,
			TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ C0 = base })
		back:Play()
		back.Completed:Once(function()
			if grip.Parent then
				grip:SetAttribute("Swinging", nil)
			end
		end)
	end)
end

Players.PlayerRemoving:Connect(function(player)
	gripBase[player] = nil
end)

return Loadout
