--!strict
-- Guided tutorial for new loggers. PROGRESS-DRIVEN: each step only advances
-- when the player actually does the thing (fells a tree, loads logs, drives
-- through the tunnel, sells at the mill, talks to Dale, buys the Felling
-- Axe). A glowing waypoint beacon shows WHERE to go for each step.
--
-- Completion (or Skip) fires Remotes.CompleteTutorial; the server persists
-- Profile.tutorialComplete so each account sees the tutorial exactly once.
-- The whole thing stays dormant until the first StateChanged snapshot
-- arrives, so returning players never see a flash of step 1.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local Tutorial = {}

local player = Players.LocalPlayer

local MILL_PAD = GameConfig.Mill.Position + GameConfig.Mill.IntakePadOffset
local SHOP_DOOR = GameConfig.Shop.Position + Vector3.new(0, 0, -20)
local FOREST_EDGE = Vector3.new(0, 0, 175)

-- ═════════════════════════════ steps ════════════════════════════════

type Step = {
	title: string,
	body: string,
	beacon: Vector3?,
	beaconLabel: string?,
	-- snap = latest StateChanged snapshot; pos = character position (or nil)
	isDone: (snap: any, pos: Vector3?) -> boolean,
}

local shopOpened = false

local STEPS: { Step } = {
	{
		title = "🪓 CHOP A TREE!",
		body = "Walk NORTH past the big sign into the forest. Stand next to a tree and HOLD CLICK until it falls!",
		beacon = FOREST_EDGE,
		beaconLabel = "FOREST",
		isDone = function(snap, _pos)
			return (snap.lifetimeTrees or 0) >= 1
		end,
	},
	{
		title = "🪵 LOAD YOUR LOGS",
		body = "Press T to call your truck over to the fallen logs — watch them float aboard!",
		beacon = nil,
		beaconLabel = nil,
		isDone = function(snap, _pos)
			return (snap.lifetimeLogs or 0) >= 1
		end,
	},
	{
		title = "🚚 DRIVE TO THE MILL",
		body = "Hop in your truck and drive SOUTH down the paved road — straight through the tunnel!",
		beacon = MILL_PAD,
		beaconLabel = "SAWMILL",
		isDone = function(snap, pos)
			return (pos ~= nil and pos.Z < -380) or (snap.lifetimeCash or 0) >= 1
		end,
	},
	{
		title = "💰 SELL YOUR LOGS",
		body = "Park right on the glowing GREEN PAD. The mill saws your logs into boards and pays you cash!",
		beacon = MILL_PAD,
		beaconLabel = "GREEN PAD",
		isDone = function(snap, _pos)
			return (snap.lifetimeCash or 0) >= 1
		end,
	},
	{
		title = "👋 MEET BIG DALE",
		body = "Keep driving south to the log cabin. Hop out, walk up to the counter, and press E to talk to Big Dale!",
		beacon = SHOP_DOOR,
		beaconLabel = "DALE'S SHOP",
		isDone = function(_snap, _pos)
			return shopOpened
		end,
	},
	{
		title = "⚒ BUY THE FELLING AXE",
		body = "Chop and sell until you have $250, then buy the FELLING AXE from Dale — it chops way faster!",
		beacon = nil,
		beaconLabel = nil,
		isDone = function(snap, _pos)
			return snap.toolName ~= nil and snap.toolName ~= "Hand Axe"
		end,
	},
}

-- ═════════════════════════════ beacon ═══════════════════════════════

local beaconBeam: Part? = nil
local beaconPulse: Tween? = nil

local function clearBeacon()
	if beaconPulse then
		beaconPulse:Cancel()
		beaconPulse = nil
	end
	if beaconBeam then
		beaconBeam:Destroy()
		beaconBeam = nil
	end
end

-- Client-local glowing pillar + floating label. AlwaysOnTop billboard so
-- the kid can see where to go even through hills and the tunnel.
local function setBeacon(pos: Vector3?, label: string?)
	clearBeacon()
	if not pos then
		return
	end
	local beam = Instance.new("Part")
	beam.Name = "TutorialBeacon"
	beam.Size = Vector3.new(1.6, 70, 1.6)
	beam.Position = pos + Vector3.new(0, 35, 0)
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(120, 255, 140)
	beam.Transparency = 0.25
	beam.Parent = Workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(220, 84)
	bb.StudsOffset = Vector3.new(0, 42, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 2000
	bb.Parent = beam
	local arrow = Instance.new("TextLabel")
	arrow.Size = UDim2.new(1, 0, 0, 34)
	arrow.BackgroundTransparency = 1
	arrow.Font = Enum.Font.FredokaOne
	arrow.TextSize = 30
	arrow.Text = "⬇"
	arrow.TextColor3 = Color3.fromRGB(140, 255, 160)
	arrow.TextStrokeTransparency = 0.3
	arrow.Parent = bb
	local tag = Instance.new("TextLabel")
	tag.Position = UDim2.fromOffset(0, 34)
	tag.Size = UDim2.new(1, 0, 0, 30)
	tag.BackgroundTransparency = 1
	tag.Font = Enum.Font.FredokaOne
	tag.TextSize = 22
	tag.Text = label or ""
	tag.TextColor3 = Color3.fromRGB(255, 255, 255)
	tag.TextStrokeTransparency = 0.25
	tag.Parent = bb

	local pulse = TweenService:Create(beam,
		TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.65 })
	pulse:Play()
	beaconBeam = beam
	beaconPulse = pulse
end

-- ═════════════════════════════ panel ════════════════════════════════

function Tutorial.mount(parent: ScreenGui)
	local frame = Instance.new("Frame")
	frame.Name = "Tutorial"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 70)
	frame.Size = UDim2.fromOffset(470, 104)
	frame.BackgroundColor3 = Color3.fromRGB(22, 30, 22)
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(120, 220, 130)
	stroke.Thickness = 2
	stroke.Parent = frame

	local stepChip = Instance.new("TextLabel")
	stepChip.Size = UDim2.fromOffset(92, 22)
	stepChip.Position = UDim2.fromOffset(10, 8)
	stepChip.BackgroundColor3 = Color3.fromRGB(60, 130, 70)
	stepChip.BorderSizePixel = 0
	stepChip.Font = Enum.Font.GothamBold
	stepChip.TextSize = 12
	stepChip.TextColor3 = Color3.fromRGB(235, 255, 235)
	stepChip.Text = "STEP 1 of 6"
	stepChip.Parent = frame
	local chipCorner = Instance.new("UICorner")
	chipCorner.CornerRadius = UDim.new(0, 11)
	chipCorner.Parent = stepChip

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -130, 0, 26)
	title.Position = UDim2.fromOffset(110, 6)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextSize = 20
	title.TextColor3 = Color3.fromRGB(255, 230, 110)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = ""
	title.Parent = frame

	local body = Instance.new("TextLabel")
	body.Size = UDim2.new(1, -20, 0, 56)
	body.Position = UDim2.fromOffset(10, 38)
	body.BackgroundTransparency = 1
	body.Font = Enum.Font.GothamMedium
	body.TextSize = 14
	body.TextColor3 = Color3.fromRGB(225, 240, 225)
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextWrapped = true
	body.Text = ""
	body.Parent = frame

	local skipBtn = Instance.new("TextButton")
	skipBtn.Size = UDim2.fromOffset(58, 20)
	skipBtn.AnchorPoint = Vector2.new(1, 0)
	skipBtn.Position = UDim2.new(1, -8, 0, 8)
	skipBtn.BackgroundTransparency = 1
	skipBtn.Font = Enum.Font.Gotham
	skipBtn.TextSize = 11
	skipBtn.TextColor3 = Color3.fromRGB(150, 170, 150)
	skipBtn.Text = "Skip"
	skipBtn.Parent = frame

	-- ── state machine ────────────────────────────────────────────────
	local stepIndex = 1
	local active = false -- becomes true on first snapshot (if not completed)
	local finished = false
	local lastSnap: any = nil

	local function showStep()
		local step = STEPS[stepIndex]
		stepChip.Text = ("STEP %d of %d"):format(stepIndex, #STEPS)
		title.Text = step.title
		body.Text = step.body
		setBeacon(step.beacon, step.beaconLabel)
	end

	local function finish(celebrate: boolean)
		if finished then
			return
		end
		finished = true
		active = false
		clearBeacon()
		Remotes.CompleteTutorial:FireServer()
		if celebrate then
			stepChip.Text = "DONE!"
			title.Text = "🏆 YOU'RE A REAL LOGGER!"
			body.Text = "You know the whole job now: chop, load, haul, sell, upgrade. The forest is yours — go build a logging empire!"
			task.delay(8, function()
				frame.Visible = false
			end)
		else
			frame.Visible = false
		end
	end

	skipBtn.Activated:Connect(function()
		finish(false)
	end)

	local function charPos(): Vector3?
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		return if hrp and hrp:IsA("BasePart") then hrp.Position else nil
	end

	-- Flash "NICE!" briefly between steps so completion feels rewarding.
	local function flashThenShow()
		stepChip.Text = "✓"
		title.Text = "✓ NICE ONE!"
		body.Text = ""
		task.delay(0.9, function()
			if active then
				showStep()
			end
		end)
	end

	local function evaluate()
		if not active or finished or not lastSnap then
			return
		end
		local pos = charPos()
		local advanced = 0
		while stepIndex <= #STEPS and STEPS[stepIndex].isDone(lastSnap, pos) do
			stepIndex += 1
			advanced += 1
		end
		if stepIndex > #STEPS then
			finish(true)
		elseif advanced == 1 then
			flashThenShow()
		elseif advanced > 1 then
			-- Multiple steps satisfied at once (e.g. rejoining mid-progress):
			-- jump straight to the current one, no flash spam.
			showStep()
		end
	end

	Remotes.OpenShop.OnClientEvent:Connect(function()
		shopOpened = true
		evaluate()
	end)

	Remotes.StateChanged.OnClientEvent:Connect(function(snap)
		lastSnap = snap
		if finished then
			return
		end
		if not active then
			-- First snapshot decides everything: completed accounts never
			-- see the panel at all.
			if snap.tutorialComplete then
				finished = true
				return
			end
			active = true
			-- Fast-forward past anything already done (rejoin mid-progress).
			local pos = charPos()
			while stepIndex <= #STEPS and STEPS[stepIndex].isDone(snap, pos) do
				stepIndex += 1
			end
			if stepIndex > #STEPS then
				finished = true
				Remotes.CompleteTutorial:FireServer()
				return
			end
			frame.Visible = true
			showStep()
			return
		end
		evaluate()
	end)

	-- Position-based steps (the tunnel drive) need polling between
	-- snapshots; cheap at 0.3s.
	task.spawn(function()
		while true do
			task.wait(0.3)
			if finished then
				break
			end
			evaluate()
		end
	end)
end

return Tutorial
