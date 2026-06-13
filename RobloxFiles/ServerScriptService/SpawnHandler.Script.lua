local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local spawnEvent = Instance.new("RemoteEvent")
spawnEvent.Name = "SetSpawnPosition"
spawnEvent.Parent = ReplicatedStorage

local cachedSpawn = nil

local function fetchMinecraftSpawn()
	if cachedSpawn then return cachedSpawn end

	local success, response = pcall(function()
		return HttpService:GetAsync("http://" .. ReplicatedStorage.IP.Value .. "/spawn")
	end)

	if success then
		local data = HttpService:JSONDecode(response)
		-- +4.5 studs (1.5 blocks) above the spawn block so the character stands on top
		cachedSpawn = Vector3.new(data.x * 3, data.y * 3 + 4.5, data.z * 3)
		return cachedSpawn
	else
		warn("SpawnHandler: Could not fetch Minecraft spawn point:", response)
		return nil
	end
end

local function onCharacterAdded(player, character)
	local spawnPos = fetchMinecraftSpawn()
	if not spawnPos then return end

	local hrp = character:WaitForChild("HumanoidRootPart", 5)
	if not hrp then return end

	-- Brief pause to let the character fully load, then teleport
	task.wait(0.3)
	spawnEvent:FireClient(player, spawnPos)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
end)
