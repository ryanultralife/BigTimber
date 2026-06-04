--!strict
-- Single source of truth for every RemoteEvent / RemoteFunction, following
-- the same getOrCreate-folder pattern as the rest of the studio. Client
-- sends intents; the server validates, mutates the authoritative profile,
-- and broadcasts snapshots back via StateChanged.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:FindFirstChild("Remotes")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
end

local function getOrCreate(name: string, className: string): Instance
	local existing = folder:FindFirstChild(name)
	if existing then
		return existing
	end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = folder
	return remote
end

return {
	-- Client → server: a single swing of the equipped tool against a tree.
	-- Arg is the tree's Uid attribute (string). Server checks reach +
	-- cooldown, applies damage, fells + rewards when HP hits zero.
	ChopTree = getOrCreate("ChopTree", "RemoteEvent") :: RemoteEvent,
	-- Client → server: "bring my truck to me" — (re)spawns the player's
	-- current rig next to their character on the yard.
	CallRig = getOrCreate("CallRig", "RemoteEvent") :: RemoteEvent,
	-- Client → server RemoteFunction: buy the next tier on a track.
	-- Arg is "tool" or "rig". Returns (true) or (false, message).
	BuyUpgrade = getOrCreate("BuyUpgrade", "RemoteFunction") :: RemoteFunction,
	-- Server → client: short toast messages ("Truck full — unload!", etc.)
	Notice = getOrCreate("Notice", "RemoteEvent") :: RemoteEvent,
	-- Server → client: the HUD snapshot, pushed every StateBroadcastInterval.
	StateChanged = getOrCreate("StateChanged", "RemoteEvent") :: RemoteEvent,
}
