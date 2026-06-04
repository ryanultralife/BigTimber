--!strict
-- Top-left HUD: cash, current load, current tool + rig name. Driven
-- entirely by the StateChanged snapshot from the server — no local state.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local Hud = {}

local function fmt(n: number): string
	if n >= 1e6 then return ("%.1fM"):format(n / 1e6) end
	if n >= 1e3 then return ("%.1fk"):format(n / 1e3) end
	return tostring(math.floor(n + 0.5))
end

function Hud.mount(parent: ScreenGui)
	local frame = Instance.new("Frame")
	frame.Name = "Hud"
	frame.AnchorPoint = Vector2.new(0, 0)
	frame.Position = UDim2.fromOffset(14, 14)
	frame.Size = UDim2.fromOffset(270, 148)
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

	local function label(y: number, text: string, size: number, color: Color3): TextLabel
		local l = Instance.new("TextLabel")
		l.Size = UDim2.new(1, -16, 0, size + 4)
		l.Position = UDim2.fromOffset(10, y)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBold
		l.TextSize = size
		l.TextColor3 = color
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Text = text
		l.Parent = frame
		return l
	end

	local cashLabel = label(10,  "$ 0",                     22, Color3.fromRGB(255, 230, 100))
	local loadLabel = label(40,  "Load: 0 / 8 logs",        15, Color3.fromRGB(200, 235, 200))
	local toolLabel = label(66,  "Tool: Hand Axe",          13, Color3.fromRGB(180, 200, 230))
	local rigLabel  = label(88,  "Rig: Pickup Truck",       13, Color3.fromRGB(180, 200, 230))
	local lifeLabel = label(114, "Lifetime: 0 logs",        11, Color3.fromRGB(140, 160, 140))

	Remotes.StateChanged.OnClientEvent:Connect(function(snap)
		cashLabel.Text = ("$ %s"):format(fmt(snap.cash))
		loadLabel.Text = ("Load: %d / %d logs  ($%s)"):format(
			math.floor(snap.loadLogs + 0.5),
			snap.capacity,
			fmt(snap.loadValue))
		toolLabel.Text = "Tool: " .. snap.toolName
		rigLabel.Text  = "Rig: "  .. snap.rigName
		lifeLabel.Text = ("Lifetime: %s logs"):format(fmt(snap.lifetimeLogs))
	end)
end

return Hud
