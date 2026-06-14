local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local currentBlocks = require(ReplicatedStorage:WaitForChild("CurrentBlocks"))

local remoteEvent = Instance.new("RemoteEvent")
remoteEvent.Name = "BlockBrokenEvent"
remoteEvent.Parent = ReplicatedStorage

local function onBlockInteraction(player, blockPosition)
	local key = string.format("%d,%d,%d",
		math.round(blockPosition.X / 3),
		math.round(blockPosition.Y / 3),
		math.round(blockPosition.Z / 3))
	local block = currentBlocks[key]

	if block then
		block:Destroy()
		currentBlocks[key] = nil

		-- Include the Roblox player's name so the Java side can route natural
		-- drops to their real ServerPlayer (with correct tool enchantments).
		local data = {
			x      = blockPosition.X / 3,
			y      = blockPosition.Y / 3,
			z      = blockPosition.Z / 3,
			action = "BREAK",
			player = player.Name,
		}

		task.spawn(function()
			local url = "http://" .. ReplicatedStorage.IP.Value .. "/post"
			local ok, err = pcall(function()
				HttpService:PostAsync(url, HttpService:JSONEncode(data),
					Enum.HttpContentType.ApplicationJson)
			end)
			if not ok then
				warn("BlockBreakHandler: failed to send break -", err)
			end
		end)
	end
end

remoteEvent.OnServerEvent:Connect(onBlockInteraction)
