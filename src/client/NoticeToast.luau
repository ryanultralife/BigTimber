--!strict
-- Short pop-up toasts from server notices ("Timber! +3 pine logs", etc.).
-- Toasts slide in from the top-centre, linger 2.5 s, then fade out.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screen = Instance.new("ScreenGui")
screen.Name = "ToastLayer"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

local function showToast(msg: string)
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, -60)
	frame.Size = UDim2.fromOffset(380, 48)
	frame.BackgroundColor3 = Color3.fromRGB(28, 44, 28)
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.Parent = screen
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = frame
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = 15
	l.TextColor3 = Color3.fromRGB(235, 255, 235)
	l.Text = msg
	l.Parent = frame

	-- Slide in
	TweenService:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0, 14) }):Play()

	task.delay(2.5, function()
		TweenService:Create(frame, TweenInfo.new(0.2),
			{ Position = UDim2.new(0.5, 0, 0, -60),
			  BackgroundTransparency = 1 }):Play()
		task.delay(0.25, function() frame:Destroy() end)
	end)
end

Remotes.Notice.OnClientEvent:Connect(showToast)

return {}
