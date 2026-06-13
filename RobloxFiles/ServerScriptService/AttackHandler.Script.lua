local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local attackEvent = Instance.new("RemoteEvent")
attackEvent.Name = "AttackEvent"
attackEvent.Parent = ReplicatedStorage

local attackUrl = "http://" .. ReplicatedStorage.IP.Value .. "/attack"

-- Server-side cooldown per Roblox player (prevents spam)
local COOLDOWN = 0.5
local lastAttack = {}

attackEvent.OnServerEvent:Connect(function(player, targetName)
	if not targetName or targetName == "" then return end

	local now = tick()
	if lastAttack[player] and now - lastAttack[player] < COOLDOWN then return end
	lastAttack[player] = now

	-- POST directly to /attack — more reliable than running /damage command
	local data = HttpService:JSONEncode({ target = targetName, damage = 1.0 })
	local ok, err = pcall(function()
		HttpService:PostAsync(attackUrl, data, Enum.HttpContentType.ApplicationJson, false)
	end)

	if not ok then
		warn("AttackHandler: failed to send attack on", targetName, "-", err)
	end
end)

game.Players.PlayerRemoving:Connect(function(player)
	lastAttack[player] = nil
end)
