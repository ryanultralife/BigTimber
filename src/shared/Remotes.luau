--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:FindFirstChild("Remotes")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
end

local function getOrCreate(name: string, className: string): Instance
	local existing = folder:FindFirstChild(name)
	if existing then return existing end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = folder
	return remote
end

return {
	ChopTree = getOrCreate("ChopTree", "RemoteEvent") :: RemoteEvent,
	CallRig = getOrCreate("CallRig", "RemoteEvent") :: RemoteEvent,
	BuyUpgrade = getOrCreate("BuyUpgrade", "RemoteFunction") :: RemoteFunction,
	Notice = getOrCreate("Notice", "RemoteEvent") :: RemoteEvent,
	StateChanged = getOrCreate("StateChanged", "RemoteEvent") :: RemoteEvent,
	-- Server → client: open the upgrade shop dialog (fired when the player
	-- interacts with Big Dale the NPC dealer).
	OpenShop = getOrCreate("OpenShop", "RemoteEvent") :: RemoteEvent,
	-- Client → server: the player finished (or skipped) the tutorial.
	-- Sets Profile.tutorialComplete so it never nags again.
	CompleteTutorial = getOrCreate("CompleteTutorial", "RemoteEvent") :: RemoteEvent,
	-- Client → server: swing animation pulse (cosmetic only — the server
	-- ChopTree remote does the authoritative hit check).
	SwingPulse = getOrCreate("SwingPulse", "RemoteEvent") :: RemoteEvent,
}
