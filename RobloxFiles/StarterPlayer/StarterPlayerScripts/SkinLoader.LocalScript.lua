local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote_img = require(ReplicatedStorage:WaitForChild("remote_img"))

ReplicatedStorage:WaitForChild("loadPlayerSkin").OnClientEvent:Connect(function(uuid, username, Character)
	-- Fetch skin from our local Minecraft server proxy instead of Crafatar directly.
	-- The Java plugin downloads & caches the PNG from Crafatar server-side, so Roblox
	-- only ever needs to reach the server it's already connected to.
	local skinUrl = "http://" .. ReplicatedStorage.IP.Value .. "/skin/" .. uuid

	local ok, skin = pcall(function()
		return remote_img.create_image(skinUrl)
	end)

	if not ok or not skin then
		warn("SkinLoader: failed to load skin for", username, "| URL:", skinUrl, "| Error:", skin)
		return
	end

	task.wait()

	-- Apply to outer (second layer) parts
	local secondLayer = Character:FindFirstChild("SecondLayer")
	if secondLayer then
		for _, part in pairs(secondLayer:GetChildren()) do
			if part:IsA("MeshPart") then
				local imageClone = skin:Clone()
				imageClone.Parent = part
			end
		end
	end

	-- Apply to main body parts
	for _, part in pairs(Character:GetChildren()) do
		if part:IsA("MeshPart") then
			local imageClone = skin:Clone()
			imageClone.Parent = part
		end
	end
end)
