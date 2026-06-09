--!strict
-- Click-to-chop: when the player left-clicks while NOT seated, we raycast
-- from the camera through the mouse position. If the first hit part is
-- inside a Tree model and within reach, we fire ChopTree to the server.
-- A local swing cooldown matches the tool tier's swingInterval so we
-- don't flood the server and the sound/animation rhythm feels right.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tools = require(Shared:WaitForChild("Tools"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- Tracks the local tool tier; updated from StateChanged so the local
-- cooldown always matches whatever the server just confirmed.
local toolTierIndex = 1
local lastSwing = 0

local function getReach(): number
	-- Same constant the server validates against (GameConfig is the single
	-- source of truth) so the marker never lies about what will land.
	return GameConfig.Chop.ReachStuds
end

local function getSwingInterval(): number
	return Tools.tier(toolTierIndex).swingInterval
end

local function findTreeUid(part: BasePart): string?
	local model = part:FindFirstAncestorWhichIsA("Model")
	if not model then return nil end
	local uid = model:GetAttribute("Uid")
	return typeof(uid) == "string" and uid or nil
end

local function humanoidRootPart(): BasePart?
	local char = player.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	return hrp and hrp:IsA("BasePart") and hrp or nil
end

local function isSeated(): boolean
	local char = player.Character
	if not char then return false end
	local h = char:FindFirstChildOfClass("Humanoid") :: Humanoid?
	return h ~= nil and h.SeatPart ~= nil
end

-- On mouse-down: begin the auto-swing loop. Fires to server every
-- swingInterval seconds as long as the button is held and a tree is hit.
local swinging = false

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if isSeated() then return end
	swinging = true
	task.spawn(function()
		while swinging do
			local mousePos = UserInputService:GetMouseLocation()
			local ray = camera:ScreenPointToRay(mousePos.X, mousePos.Y)

			-- Exclude the player's own character so the ray reaches the tree
			-- instead of hitting the player's torso/arms first.
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			local char = player.Character
			if char then
				params.FilterDescendantsInstances = { char }
			end

			local result = Workspace:Raycast(ray.Origin, ray.Direction * 160, params)
			if result and result.Instance and result.Instance:IsA("BasePart") then
				local uid = findTreeUid(result.Instance)
				if uid then
					local hrp = humanoidRootPart()
					if hrp then
						local dx = result.Position.X - hrp.Position.X
						local dz = result.Position.Z - hrp.Position.Z
						if math.sqrt(dx * dx + dz * dz) <= getReach() then
							lastSwing = os.clock()
							Remotes.ChopTree:FireServer(uid)
						end
					end
				end
			end

			-- Wait one swing interval before the next attempt. task.wait is
			-- cleaner than per-frame polling and naturally matches the tool rhythm.
			task.wait(getSwingInterval())
		end
	end)
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		swinging = false
	end
end)

-- Sync local tier from HUD snapshot so the swing interval stays current.
Remotes.StateChanged.OnClientEvent:Connect(function(snap)
	if snap.toolName then
		local Tools2 = Tools
		for i, t in Tools2.Tiers do
			if t.name == snap.toolName then
				toolTierIndex = i
				break
			end
		end
	end
end)

return {}
