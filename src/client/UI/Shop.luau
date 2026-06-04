--!strict
-- Shop dialog — opens when the player interacts with Big Dale (Remotes.OpenShop).
-- Displays current tier, next upgrade, and cost for both tools and rigs.
-- Closes on the X button or pressing Escape.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local ShopUI = {}

local lastSnap: any = nil

function ShopUI.mount(parent: ScreenGui)
	-- Dark overlay behind the dialog
	local overlay = Instance.new("Frame")
	overlay.Name = "ShopOverlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 0.45
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.ZIndex = 10
	overlay.Parent = parent

	-- Dialog frame
	local dialog = Instance.new("Frame")
	dialog.Name = "ShopDialog"
	dialog.AnchorPoint = Vector2.new(0.5, 0.5)
	dialog.Position = UDim2.fromScale(0.5, 0.5)
	dialog.Size = UDim2.fromOffset(560, 440)
	dialog.BackgroundColor3 = Color3.fromRGB(28, 24, 20)
	dialog.BackgroundTransparency = 0.04
	dialog.BorderSizePixel = 0
	dialog.ZIndex = 11
	dialog.Visible = false
	dialog.Parent = parent
	local dc = Instance.new("UICorner")
	dc.CornerRadius = UDim.new(0, 14)
	dc.Parent = dialog
	local dstroke = Instance.new("UIStroke")
	dstroke.Color = Color3.fromRGB(180, 140, 60)
	dstroke.Thickness = 2
	dstroke.Parent = dialog

	-- NPC portrait strip
	local portrait = Instance.new("Frame")
	portrait.Size = UDim2.new(1, 0, 0, 88)
	portrait.BackgroundColor3 = Color3.fromRGB(80, 54, 32)
	portrait.BorderSizePixel = 0
	portrait.ZIndex = 12
	portrait.Parent = dialog
	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(0, 14)
	pc.Parent = portrait
	-- Dale's icon (coloured square with his initials — no asset needed)
	local icon = Instance.new("TextLabel")
	icon.Size = UDim2.fromOffset(72, 72)
	icon.Position = UDim2.fromOffset(12, 8)
	icon.BackgroundColor3 = Color3.fromRGB(220, 200, 40)
	icon.BorderSizePixel = 0
	icon.Font = Enum.Font.FredokaOne
	icon.TextSize = 28
	icon.Text = "BD"
	icon.TextColor3 = Color3.fromRGB(60, 40, 20)
	icon.ZIndex = 13
	icon.Parent = portrait
	local ic2 = Instance.new("UICorner")
	ic2.CornerRadius = UDim.new(0, 36)
	ic2.Parent = icon
	local greeting = Instance.new("TextLabel")
	greeting.Size = UDim2.new(1, -108, 1, 0)
	greeting.Position = UDim2.fromOffset(100, 0)
	greeting.BackgroundTransparency = 1
	greeting.Font = Enum.Font.GothamBold
	greeting.TextSize = 15
	greeting.TextColor3 = Color3.fromRGB(240, 235, 210)
	greeting.TextXAlignment = Enum.TextXAlignment.Left
	greeting.TextWrapped = true
	greeting.Text = "Howdy! I'm Big Dale. Best equipment in the whole county.\nWhat're you looking for today?"
	greeting.ZIndex = 12
	greeting.Parent = portrait

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromOffset(36, 36)
	closeBtn.Position = UDim2.new(1, -46, 0, 10)
	closeBtn.BackgroundColor3 = Color3.fromRGB(160, 50, 45)
	closeBtn.BorderSizePixel = 0
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 18
	closeBtn.Text = "✕"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.ZIndex = 14
	closeBtn.Parent = dialog
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, 6)
	cc.Parent = closeBtn

	-- Status label (buy errors / notices)
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Size = UDim2.new(1, -24, 0, 28)
	statusLabel.Position = UDim2.fromOffset(12, 400)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextSize = 13
	statusLabel.TextColor3 = Color3.fromRGB(230, 180, 80)
	statusLabel.Text = ""
	statusLabel.ZIndex = 12
	statusLabel.Parent = dialog

	local function showStatus(msg: string)
		statusLabel.Text = msg
		task.delay(3.5, function()
			if statusLabel.Text == msg then statusLabel.Text = "" end
		end)
	end

	-- Build one upgrade card (tool OR rig)
	local function makeCard(xOffset: number, label: string,
		onBuy: () -> ()): (TextLabel, TextLabel, TextButton)

		local card = Instance.new("Frame")
		card.Size = UDim2.fromOffset(252, 224)
		card.Position = UDim2.fromOffset(xOffset, 98)
		card.BackgroundColor3 = Color3.fromRGB(38, 32, 28)
		card.BorderSizePixel = 0
		card.ZIndex = 12
		card.Parent = dialog
		local cc2 = Instance.new("UICorner")
		cc2.CornerRadius = UDim.new(0, 10)
		cc2.Parent = card
		local cs = Instance.new("UIStroke")
		cs.Color = Color3.fromRGB(90, 70, 40)
		cs.Thickness = 1.2
		cs.Parent = card

		local header = Instance.new("TextLabel")
		header.Size = UDim2.new(1, 0, 0, 30)
		header.Position = UDim2.fromOffset(0, 6)
		header.BackgroundTransparency = 1
		header.Font = Enum.Font.FredokaOne
		header.TextSize = 16
		header.TextColor3 = Color3.fromRGB(255, 220, 100)
		header.Text = label
		header.ZIndex = 13
		header.Parent = card

		local curLabel = Instance.new("TextLabel")
		curLabel.Size = UDim2.new(1, -16, 0, 40)
		curLabel.Position = UDim2.fromOffset(8, 38)
		curLabel.BackgroundTransparency = 1
		curLabel.Font = Enum.Font.Gotham
		curLabel.TextSize = 13
		curLabel.TextColor3 = Color3.fromRGB(200, 220, 200)
		curLabel.TextXAlignment = Enum.TextXAlignment.Left
		curLabel.TextWrapped = true
		curLabel.Text = "Current: —"
		curLabel.ZIndex = 13
		curLabel.Parent = card

		local nextLabel = Instance.new("TextLabel")
		nextLabel.Size = UDim2.new(1, -16, 0, 72)
		nextLabel.Position = UDim2.fromOffset(8, 82)
		nextLabel.BackgroundTransparency = 1
		nextLabel.Font = Enum.Font.Gotham
		nextLabel.TextSize = 13
		nextLabel.TextColor3 = Color3.fromRGB(160, 200, 255)
		nextLabel.TextXAlignment = Enum.TextXAlignment.Left
		nextLabel.TextWrapped = true
		nextLabel.Text = "Next: —"
		nextLabel.ZIndex = 13
		nextLabel.Parent = card

		local buyBtn = Instance.new("TextButton")
		buyBtn.Size = UDim2.new(1, -16, 0, 48)
		buyBtn.Position = UDim2.fromOffset(8, 164)
		buyBtn.BackgroundColor3 = Color3.fromRGB(55, 120, 65)
		buyBtn.BorderSizePixel = 0
		buyBtn.Font = Enum.Font.GothamBold
		buyBtn.TextSize = 14
		buyBtn.TextColor3 = Color3.fromRGB(240, 255, 240)
		buyBtn.Text = "Buy"
		buyBtn.ZIndex = 13
		buyBtn.Parent = card
		local bc3 = Instance.new("UICorner")
		bc3.CornerRadius = UDim.new(0, 8)
		bc3.Parent = buyBtn

		buyBtn.Activated:Connect(onBuy)
		return curLabel, nextLabel, buyBtn
	end

	local toolCur, toolNext, toolBtn = makeCard(20, "🪓  TOOLS", function()
		if not lastSnap or not lastSnap.nextTool then return end
		local ok, msg = Remotes.BuyUpgrade:InvokeServer("tool")
		if not ok then showStatus(tostring(msg)) end
	end)

	local rigCur, rigNext, rigBtn = makeCard(288, "🚛  RIGS", function()
		if not lastSnap or not lastSnap.nextRig then return end
		local ok, msg = Remotes.BuyUpgrade:InvokeServer("rig")
		if not ok then showStatus(tostring(msg)) end
	end)

	-- Refresh card content whenever the HUD snapshot arrives.
	local function refresh(snap: any)
		lastSnap = snap
		-- Tools
		toolCur.Text = "Current: " .. (snap.toolName or "—")
		if snap.nextTool then
			toolNext.Text = ("Upgrade to:\n%s\nCost: $%d"):format(
				snap.nextTool.name, snap.nextTool.cost)
			toolBtn.Text = ("Buy  ·  $%d"):format(snap.nextTool.cost)
			toolBtn.BackgroundColor3 = if (snap.cash or 0) >= snap.nextTool.cost
				then Color3.fromRGB(55, 120, 65) else Color3.fromRGB(70, 70, 70)
		else
			toolNext.Text = "Max tier reached!"
			toolBtn.Text = "✓ Maxed"
			toolBtn.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
		end
		-- Rigs
		rigCur.Text = "Current: " .. (snap.rigName or "—")
		if snap.nextRig then
			rigNext.Text = ("Upgrade to:\n%s\nCost: $%d"):format(
				snap.nextRig.name, snap.nextRig.cost)
			rigBtn.Text = ("Buy  ·  $%d"):format(snap.nextRig.cost)
			rigBtn.BackgroundColor3 = if (snap.cash or 0) >= snap.nextRig.cost
				then Color3.fromRGB(55, 90, 150) else Color3.fromRGB(70, 70, 70)
		else
			rigNext.Text = "Max tier reached!"
			rigBtn.Text = "✓ Maxed"
			rigBtn.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
		end
	end

	Remotes.StateChanged.OnClientEvent:Connect(function(snap)
		refresh(snap)
	end)

	-- Open / close logic
	local function openShop()
		overlay.Visible = true
		dialog.Visible = true
	end

	local function closeShop()
		overlay.Visible = false
		dialog.Visible = false
	end

	Remotes.OpenShop.OnClientEvent:Connect(openShop)
	closeBtn.Activated:Connect(closeShop)
	overlay.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			closeShop()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.Escape then closeShop() end
	end)
end

return ShopUI
