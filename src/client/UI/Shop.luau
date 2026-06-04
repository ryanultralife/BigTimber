--!strict
-- Bottom-right upgrade shop: two columns (Tool / Rig), each showing the
-- current tier and a "Upgrade → NextTier  $cost" button. The server
-- validates cash and returns (true) or (false, msg). Buttons go grey when
-- max tier is reached or cash is short (the server still enforces it).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local ShopUI = {}

local function btn(props: { [string]: any }): TextButton
	local b = Instance.new("TextButton")
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextScaled = false
	for k, v in props do
		(b :: any)[k] = v
	end
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 7)
	c.Parent = b
	return b
end

local lastSnap: any = nil

function ShopUI.mount(parent: ScreenGui)
	local frame = Instance.new("Frame")
	frame.Name = "Shop"
	frame.AnchorPoint = Vector2.new(1, 1)
	frame.Position = UDim2.new(1, -14, 1, -14)
	frame.Size = UDim2.fromOffset(310, 190)
	frame.BackgroundColor3 = Color3.fromRGB(18, 22, 18)
	frame.BackgroundTransparency = 0.18
	frame.BorderSizePixel = 0
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(80, 140, 80)
	stroke.Thickness = 1.5
	stroke.Parent = frame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 28)
	title.Position = UDim2.fromOffset(0, 6)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextSize = 17
	title.TextColor3 = Color3.fromRGB(200, 240, 200)
	title.Text = "UPGRADE SHOP"
	title.Parent = frame

	-- Tool column
	local toolCur = Instance.new("TextLabel")
	toolCur.Size = UDim2.fromOffset(136, 20)
	toolCur.Position = UDim2.fromOffset(10, 38)
	toolCur.BackgroundTransparency = 1
	toolCur.Font = Enum.Font.Gotham
	toolCur.TextSize = 12
	toolCur.TextColor3 = Color3.fromRGB(190, 215, 190)
	toolCur.TextXAlignment = Enum.TextXAlignment.Left
	toolCur.Text = "Tool: Hand Axe"
	toolCur.Parent = frame

	local toolBtn = btn({
		Size = UDim2.fromOffset(136, 54),
		Position = UDim2.fromOffset(10, 62),
		BackgroundColor3 = Color3.fromRGB(60, 130, 70),
		TextColor3 = Color3.fromRGB(240, 255, 240),
		TextSize = 12,
		Text = "Upgrade Tool\n→ Felling Axe\n$250",
	})
	toolBtn.Parent = frame

	-- Rig column
	local rigCur = Instance.new("TextLabel")
	rigCur.Size = UDim2.fromOffset(148, 20)
	rigCur.Position = UDim2.fromOffset(158, 38)
	rigCur.BackgroundTransparency = 1
	rigCur.Font = Enum.Font.Gotham
	rigCur.TextSize = 12
	rigCur.TextColor3 = Color3.fromRGB(190, 215, 190)
	rigCur.TextXAlignment = Enum.TextXAlignment.Left
	rigCur.Text = "Rig: Pickup Truck"
	rigCur.Parent = frame

	local rigBtn = btn({
		Size = UDim2.fromOffset(140, 54),
		Position = UDim2.fromOffset(160, 62),
		BackgroundColor3 = Color3.fromRGB(60, 100, 160),
		TextColor3 = Color3.fromRGB(230, 240, 255),
		TextSize = 12,
		Text = "Upgrade Rig\n→ Flatbed\n$1200",
	})
	rigBtn.Parent = frame

	local notice = Instance.new("TextLabel")
	notice.Size = UDim2.new(1, -16, 0, 28)
	notice.Position = UDim2.fromOffset(8, 152)
	notice.BackgroundTransparency = 1
	notice.Font = Enum.Font.Gotham
	notice.TextSize = 12
	notice.TextColor3 = Color3.fromRGB(220, 180, 100)
	notice.Text = ""
	notice.Parent = frame

	local function showNotice(msg: string)
		notice.Text = msg
		task.delay(3, function()
			if notice.Text == msg then notice.Text = "" end
		end)
	end

	local function refreshButtons(snap: any)
		lastSnap = snap
		if snap.toolName then toolCur.Text = "Tool: " .. snap.toolName end
		if snap.rigName  then rigCur.Text  = "Rig: "  .. snap.rigName  end
		if snap.nextTool then
			toolBtn.Text = ("Upgrade Tool\n→ %s\n$%d"):format(snap.nextTool.name, snap.nextTool.cost)
			toolBtn.BackgroundColor3 = if (snap.cash or 0) >= snap.nextTool.cost
				then Color3.fromRGB(60, 130, 70)
				else Color3.fromRGB(80, 80, 80)
		else
			toolBtn.Text = "Max Tool Tier"
			toolBtn.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
		end
		if snap.nextRig then
			rigBtn.Text = ("Upgrade Rig\n→ %s\n$%d"):format(snap.nextRig.name, snap.nextRig.cost)
			rigBtn.BackgroundColor3 = if (snap.cash or 0) >= snap.nextRig.cost
				then Color3.fromRGB(60, 100, 160)
				else Color3.fromRGB(80, 80, 80)
		else
			rigBtn.Text = "Max Rig Tier"
			rigBtn.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
		end
	end

	toolBtn.Activated:Connect(function()
		if not lastSnap or not lastSnap.nextTool then return end
		local ok, msg = Remotes.BuyUpgrade:InvokeServer("tool")
		if not ok then showNotice(msg or "Cannot upgrade") end
	end)

	rigBtn.Activated:Connect(function()
		if not lastSnap or not lastSnap.nextRig then return end
		local ok, msg = Remotes.BuyUpgrade:InvokeServer("rig")
		if not ok then showNotice(msg or "Cannot upgrade") end
	end)

	Remotes.StateChanged.OnClientEvent:Connect(refreshButtons)
end

return ShopUI
