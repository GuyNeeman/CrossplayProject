-- Polls /events/:username for each connected Roblox player and relays the
-- queued server-sent events (titles, actionbar, sound, health) to the client.
-- Architecture mirrors Geyser's packet relay: the Java-side PacketInterceptor
-- captures outbound packets bound for the NPC's Netty channel and queues them;
-- this script drains the queue and forwards events over a RemoteEvent.
local HttpService       = game:GetService("HttpService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local POLL_INTERVAL = 0.6

local ip      = ReplicatedStorage:WaitForChild("IP").Value
local baseUrl = "http://" .. ip

-- Create the RemoteEvent clients listen to for MC server events.
local gameEvent = Instance.new("RemoteEvent")
gameEvent.Name   = "GameEvent"
gameEvent.Parent = ReplicatedStorage

local function pollLoop(player)
	local url = baseUrl .. "/events/" .. HttpService:UrlEncode(player.Name)
	while player.Parent ~= nil do
		local ok, raw = pcall(function() return HttpService:GetAsync(url, true) end)
		if ok and raw and #raw > 2 then
			local decodeOk, events = pcall(function() return HttpService:JSONDecode(raw) end)
			if decodeOk and type(events) == "table" then
				for _, evt in ipairs(events) do
					if type(evt.type) == "string" then
						gameEvent:FireClient(player, evt.type, evt.data or "")
					end
				end
			end
		end
		task.wait(POLL_INTERVAL)
	end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(pollLoop, player)
end)

-- Handle players already in-game when this script starts
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(pollLoop, player)
end
