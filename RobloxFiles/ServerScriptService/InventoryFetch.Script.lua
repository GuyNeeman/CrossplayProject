-- Server-side bridge for inventory fetching (HttpService is forbidden in LocalScripts).
-- The LocalScript calls InventoryFetch:InvokeServer(username) and this returns the result.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local inventoryFetch = Instance.new("RemoteFunction")
inventoryFetch.Name = "InventoryFetch"
inventoryFetch.Parent = ReplicatedStorage

inventoryFetch.OnServerInvoke = function(player, username)
	if type(username) ~= "string" or #username == 0 then return {} end
	-- Sanitize: only alphanumeric + underscore
	username = username:match("^[%w_]+$")
	if not username then return {} end

	local ok, body = pcall(function()
		return HttpService:GetAsync("http://" .. ReplicatedStorage.IP.Value .. "/inventory/" .. username)
	end)

	if not ok or not body then return {} end

	local ok2, data = pcall(function() return HttpService:JSONDecode(body) end)
	return (ok2 and type(data) == "table") and data or {}
end
