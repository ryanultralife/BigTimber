--!strict
-- Big Timber client boot.
-- Mounts the two UI panels (HUD + Shop), starts the chop controller and
-- toast layer, and wires the rig/truck key bindings.

local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screen = Instance.new("ScreenGui")
screen.Name = "BigTimberUI"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

-- Mount UI panels.
local UI = script:WaitForChild("UI")
local Hud = require(UI:WaitForChild("Hud"))
local ShopUI = require(UI:WaitForChild("Shop"))
Hud.mount(screen)
ShopUI.mount(screen)

-- Toast notifications + chop controller.
require(script:WaitForChild("NoticeToast"))
require(script:WaitForChild("ToolController"))

-- Walk speed.
local function applyWalkSpeed(character: Model)
	local h = character:WaitForChild("Humanoid") :: Humanoid
	h.WalkSpeed = GameConfig.WalkSpeed
end
player.CharacterAdded:Connect(applyWalkSpeed)
if player.Character then
	applyWalkSpeed(player.Character)
end

-- T = call / recall your truck. Fires the server to (re)spawn the rig
-- next to you. Useful after upgrades or after getting stuck.
local function onCallRig(_name: string, state: Enum.UserInputState, _input: InputObject)
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	Remotes.CallRig:FireServer()
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction("CallRig", onCallRig, false, Enum.KeyCode.T)

-- A small on-screen hint in the bottom-left so the kid knows the keys.
local hint = Instance.new("TextLabel")
hint.Name = "KeyHint"
hint.AnchorPoint = Vector2.new(0, 1)
hint.Position = UDim2.new(0, 14, 1, -14)
hint.Size = UDim2.fromOffset(560, 42)
hint.BackgroundColor3 = Color3.fromRGB(18, 22, 18)
hint.BackgroundTransparency = 0.35
hint.BorderSizePixel = 0
hint.Font = Enum.Font.Gotham
hint.TextSize = 12
hint.TextColor3 = Color3.fromRGB(180, 210, 180)
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.Text = "  [Hold Click] Chop   [T] Call truck   Park near your logs to load them  •  Mill is south through the tunnel"
hint.Parent = screen
local hc = Instance.new("UICorner")
hc.CornerRadius = UDim.new(0, 8)
hc.Parent = hint

print("[Client] Big Timber ready.")
