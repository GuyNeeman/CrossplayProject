-- Server-side connection checker. LocalScripts cannot use HttpService,
-- so this script pings the Minecraft server and broadcasts the result to all clients.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local statusEvent = Instance.new("RemoteEvent")
statusEvent.Name = "ServerStatusEvent"
statusEvent.Parent = ReplicatedStorage

local baseUrl = "http://" .. ReplicatedStorage.IP.Value

while true do
	local t0 = tick()
	local ok, _ = pcall(function()
		HttpService:GetAsync(baseUrl .. "/chat")
	end)
	local ms = math.floor((tick() - t0) * 1000)

	statusEvent:FireAllClients(ok, ms)
	task.wait(3)
end
