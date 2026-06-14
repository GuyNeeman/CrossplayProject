local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")

local respawnEvent = Instance.new("RemoteEvent")
respawnEvent.Name   = "RespawnEvent"
respawnEvent.Parent = ReplicatedStorage

local respawnUrl = "http://" .. ReplicatedStorage.IP.Value .. "/respawn"

respawnEvent.OnServerEvent:Connect(function(player)
	local data = HttpService:JSONEncode({ user = player.Name })
	local ok, err = pcall(function()
		HttpService:PostAsync(respawnUrl, data, Enum.HttpContentType.ApplicationJson, false)
	end)
	if not ok then
		warn("RespawnHandler: failed for", player.Name, "-", err)
	end
end)
