--!strict
-- Big Timber — server boot.
-- Load order matters: World and Forest build the 3D environment before
-- any player can join. Then PlayerData is set up so ProfileLoaded fires
-- before services start handling remotes.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local World = require(script:WaitForChild("World"))
local Forest = require(script:WaitForChild("Forest"))
local PlayerData = require(script:WaitForChild("PlayerData"))
local Net = require(script:WaitForChild("Net"))
local Loadout = require(script:WaitForChild("Loadout"))
local RigService = require(script:WaitForChild("RigService"))

-- Services that only need to exist for their OnServerEvent side-effects:
require(script:WaitForChild("ChopService"))
require(script:WaitForChild("MillService"))
require(script:WaitForChild("Shop"))

local ShopNPC = require(script:WaitForChild("ShopNPC"))
local LogService = require(script:WaitForChild("LogService"))

-- Build the world synchronously before any player character spawns.
-- Each phase is pcall-guarded so one failure degrades (missing structure,
-- loud warning) instead of killing the whole boot — a single bad FillBlock
-- once took out trees, rigs, and the HUD with it.
local function phase(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn(("[BigTimber] BOOT PHASE FAILED — %s: %s"):format(name, tostring(err)))
	end
end

phase("World.build", World.build)
phase("Forest.start", Forest.start)
phase("ShopNPC.spawn", ShopNPC.spawn)
phase("LogService.start", LogService.start)

-- When a player's profile loads: equip their tool cosmetic, spawn their rig,
-- and send the first HUD snapshot.
PlayerData.ProfileLoaded:Connect(function(player: Player)
	pcall(Loadout.equip, player)
	RigService.spawn(player)
	Net.push(player)
end)

-- Broadcast HUD snapshots on an interval so cash/load stays live.
task.spawn(function()
	while true do
		task.wait(GameConfig.StateBroadcastInterval)
		for _, player in Players:GetPlayers() do
			if PlayerData.isLoaded(player) then
				Net.push(player)
			end
		end
	end
end)

-- Re-equip the tool whenever the character respawns (avatar reloads on death).
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		task.wait(1)
		if PlayerData.isLoaded(player) then
			pcall(Loadout.equip, player)
		end
	end)
end)

print("[BigTimber] server ready.")
