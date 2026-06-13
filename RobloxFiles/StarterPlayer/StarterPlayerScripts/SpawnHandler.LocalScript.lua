local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local spawnEvent = ReplicatedStorage:WaitForChild("SetSpawnPosition", 10)

if not spawnEvent then
	warn("SpawnHandler: SetSpawnPosition event not found")
	return
end

-- Anchor the HumanoidRootPart as early as possible so the character doesn't fall
-- before the Minecraft spawn position is received.
local function anchorImmediately(character)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.Anchored = true
		return
	end

	-- HRP not yet in the character — watch for it with DescendantAdded (synchronous, no yield)
	local conn
	conn = character.DescendantAdded:Connect(function(desc)
		if desc.Name == "HumanoidRootPart" and desc:IsA("BasePart") then
			desc.Anchored = true
			conn:Disconnect()
		end
	end)

	-- Async fallback in case DescendantAdded fires after WaitForChild anyway
	local hrpFallback = character:WaitForChild("HumanoidRootPart", 5)
	if hrpFallback then
		hrpFallback.Anchored = true
	end
end

if player.Character then
	anchorImmediately(player.Character)
end
player.CharacterAdded:Connect(anchorImmediately)

spawnEvent.OnClientEvent:Connect(function(position)
	local character = player.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		hrp = character:WaitForChild("HumanoidRootPart", 3)
	end
	if not hrp then return end

	-- Teleport to Minecraft spawn
	hrp.CFrame = CFrame.new(position)

	-- Stay anchored for 3 seconds after teleport.
	-- BlockHandler runs every 0.6 s; 3 s gives it ~5 cycles to load terrain at the
	-- new position before physics can drop the player through a missing floor.
	task.wait(3)

	-- One physics frame pause so the engine sees the CFrame before unanchoring
	RunService.Heartbeat:Wait()
	hrp.Anchored = false
end)
