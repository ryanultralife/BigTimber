--!strict
-- Per-player profiles, persisted via DataStoreService when available.
--
-- DataStore in Studio playtest needs the place published OR Game Settings →
-- Security → "Enable Studio Access to API Services" on. Without either,
-- GetDataStore can throw at module load and take down everything that
-- requires us — so it's pcall-wrapped and we degrade to in-memory profiles.
-- The game still runs; balances just reset each session.
--
-- Every persisted field is nil-checked + defaulted in migrate(), so a save
-- written by an older build always loads cleanly (migration over breakage).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

export type Profile = {
	cash: number,
	toolTier: number, -- index into Tools.Tiers (>= 1)
	rigTier: number, -- index into Rigs.Tiers (>= 1)
	loadLogs: number, -- logs currently carried
	loadValue: number, -- cash the current load mills into
	lifetimeLogs: number,
	lifetimeCash: number,
}

local PlayerData = {}

local STORE_NAME = "BigTimber_Profiles_v1"
local profileStore: DataStore? = nil
local storeAvailable = false
do
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok and store then
		profileStore = store
		storeAvailable = true
		print("[PlayerData] DataStore ready — progress will persist.")
	else
		warn(("[PlayerData] DataStore unavailable (%s) — in-memory only. Progress resets each session."):format(tostring(store)))
	end
end

local profiles: { [Player]: Profile } = {}
local loaded: { [Player]: boolean } = {}

local loadedEvent = Instance.new("BindableEvent")
PlayerData.ProfileLoaded = loadedEvent.Event

local function key(player: Player): string
	return "Player_" .. player.UserId
end

local function newProfile(): Profile
	return {
		cash = GameConfig.StartingCash,
		toolTier = 1,
		rigTier = 1,
		loadLogs = 0,
		loadValue = 0,
		lifetimeLogs = 0,
		lifetimeCash = 0,
	}
end

local function isValid(t: any): boolean
	return type(t) == "table" and type(t.cash) == "number"
end

-- Defence-in-depth: coerce every field to a sane default so an old or
-- partial save never errors a downstream read.
local function migrate(p: any): Profile
	p.cash = p.cash or GameConfig.StartingCash
	p.toolTier = p.toolTier or 1
	p.rigTier = p.rigTier or 1
	p.loadLogs = p.loadLogs or 0
	p.loadValue = p.loadValue or 0
	p.lifetimeLogs = p.lifetimeLogs or 0
	p.lifetimeCash = p.lifetimeCash or 0
	return p
end

local function loadFromStore(player: Player): Profile
	if not storeAvailable or not profileStore then
		return newProfile()
	end
	local store = profileStore :: DataStore
	local ok, result = pcall(function()
		return store:GetAsync(key(player))
	end)
	if ok and isValid(result) then
		return migrate(result)
	end
	if not ok then
		warn(("[PlayerData] load failed for %s: %s"):format(player.Name, tostring(result)))
	end
	return newProfile()
end

local function saveToStore(player: Player)
	if not storeAvailable or not profileStore then
		return
	end
	local profile = profiles[player]
	if not profile then
		return
	end
	local store = profileStore :: DataStore
	local ok, err = pcall(function()
		store:SetAsync(key(player), profile)
	end)
	if not ok then
		warn(("[PlayerData] save failed for %s: %s"):format(player.Name, tostring(err)))
	end
end

-- Yields until the profile is loaded (polls every 50ms). Tick loops and
-- remote handlers gate on isLoaded first so this rarely actually waits.
function PlayerData.get(player: Player): Profile
	while not loaded[player] do
		if not player.Parent then
			return newProfile()
		end
		task.wait(0.05)
	end
	local p = profiles[player]
	if not p then
		p = newProfile()
		profiles[player] = p
	end
	return p
end

function PlayerData.isLoaded(player: Player): boolean
	return loaded[player] == true
end

function PlayerData.release(player: Player)
	saveToStore(player)
	profiles[player] = nil
	loaded[player] = nil
end

Players.PlayerAdded:Connect(function(player)
	local profile = loadFromStore(player)
	profiles[player] = profile
	loaded[player] = true
	loadedEvent:Fire(player)
end)

Players.PlayerRemoving:Connect(function(player)
	PlayerData.release(player)
end)

task.spawn(function()
	while true do
		task.wait(GameConfig.AutosaveIntervalSeconds)
		for player in profiles do
			if player.Parent then
				saveToStore(player)
			end
		end
	end
end)

game:BindToClose(function()
	for player in profiles do
		saveToStore(player)
	end
end)

return PlayerData
