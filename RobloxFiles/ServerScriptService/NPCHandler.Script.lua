local HttpService = game:GetService("HttpService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local updateInterval = 60 / 100 -- 100 requests per minute
local npcUrl = "http://" .. replicatedStorage.IP.Value .. "/npc"

local lastPositions = {}
local citizensWarned = false  -- only warn once

local function sendData(player, disconnect)
	local postData

	if disconnect then
		postData = HttpService:JSONEncode({ user = tostring(player.DisplayName), disconnect = true })
	else
		local humanoidRootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not humanoidRootPart then return end

		local adjustedX = humanoidRootPart.Position.X / 3
		local adjustedY = (humanoidRootPart.Position.Y - 1.5) / 3
		local adjustedZ = humanoidRootPart.Position.Z / 3
		local yaw = (humanoidRootPart.Orientation.Y * -1) + 180
		local pitch = 0

		local lastPosition = lastPositions[player]
		if lastPosition
			and lastPosition.x == adjustedX
			and lastPosition.y == adjustedY
			and lastPosition.z == adjustedZ
			and lastPosition.ya == yaw
			and lastPosition.pi == pitch then
			return
		end

		postData = HttpService:JSONEncode({
			user = tostring(player.DisplayName),
			x = adjustedX,
			y = adjustedY,
			z = adjustedZ,
			yaw = yaw,
			pitch = pitch
		})

		lastPositions[player] = { x = adjustedX, y = adjustedY, z = adjustedZ, ya = yaw, pi = pitch }
	end

	local success, response = pcall(function()
		return HttpService:PostAsync(npcUrl, postData, Enum.HttpContentType.ApplicationJson, false)
	end)

	if not success then
		-- 503 means Citizens plugin is not installed on the Minecraft server
		if not citizensWarned and tostring(response):find("503") then
			citizensWarned = true
			warn("────────────────────────────────────────────────────")
			warn("NPCHandler: Minecraft server returned 503 for /npc.")
			warn("The Citizens plugin is NOT installed or not enabled.")
			warn("Roblox players will NOT appear in Minecraft until")
			warn("Citizens 2.0+ is installed in the plugins/ folder.")
			warn("Download: https://ci.citizensnpcs.co/job/Citizens2/")
			warn("────────────────────────────────────────────────────")
		elseif not tostring(response):find("503") then
			warn("NPCHandler: Failed to send NPC data:", response)
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart")
		task.spawn(function()
			while character.Parent do
				local hrp = character:FindFirstChild("HumanoidRootPart")
				if hrp then
					sendData(player, false)
				end
				task.wait(updateInterval)
			end
		end)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	sendData(player, true)
	lastPositions[player] = nil
end)
