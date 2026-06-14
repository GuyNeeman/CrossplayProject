local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local updateInterval = 60 / 100  -- 100 requests per minute
local npcUrl = "http://" .. ReplicatedStorage.IP.Value .. "/npc"

local lastPositions = {}

local function sendData(player, disconnect)
	local postData

	if disconnect then
		postData = HttpService:JSONEncode({ user = tostring(player.Name), disconnect = true })
	else
		local humanoidRootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not humanoidRootPart then return end

		local adjustedX = humanoidRootPart.Position.X / 3
		local adjustedY = (humanoidRootPart.Position.Y - 1.5) / 3
		local adjustedZ = humanoidRootPart.Position.Z / 3
		local yaw       = (humanoidRootPart.Orientation.Y * -1) + 180
		local pitch     = 0

		local lastPosition = lastPositions[player]
		if lastPosition
			and lastPosition.x == adjustedX
			and lastPosition.y == adjustedY
			and lastPosition.z == adjustedZ
			and lastPosition.ya == yaw then
			return
		end

		postData = HttpService:JSONEncode({
			user  = tostring(player.Name),
			x     = adjustedX,
			y     = adjustedY,
			z     = adjustedZ,
			yaw   = yaw,
			pitch = pitch,
		})

		lastPositions[player] = { x = adjustedX, y = adjustedY, z = adjustedZ, ya = yaw }
	end

	local ok, err = pcall(function()
		HttpService:PostAsync(npcUrl, postData, Enum.HttpContentType.ApplicationJson, false)
	end)

	if not ok then
		warn("NPCHandler: Failed to send player data:", err)
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart")
		task.spawn(function()
			while character.Parent do
				local hrp = character:FindFirstChild("HumanoidRootPart")
				if hrp then sendData(player, false) end
				task.wait(updateInterval)
			end
		end)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	sendData(player, true)
	lastPositions[player] = nil
end)
