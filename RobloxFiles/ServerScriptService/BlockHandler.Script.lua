local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local BlockStateManager = require(ReplicatedStorage:WaitForChild("BlockStateManager"))
local currentBlocks = require(ReplicatedStorage:WaitForChild("CurrentBlocks"))

-- Wait for models folder with a clear error if missing
local modelsFolder = ReplicatedStorage:WaitForChild("models", 10)
if not modelsFolder then
	error("BlockHandler: 'models' folder not found in ReplicatedStorage after 10s. Import models.rbxm into ReplicatedStorage first!")
end

local blockSize = 3
local updateInterval = 60 / 100 -- 100 requests per minute

-- Auto-create Blocks folder if missing
if not Workspace:FindFirstChild("Blocks") then
	local folder = Instance.new("Folder")
	folder.Name = "Blocks"
	folder.Parent = Workspace
end

-- Biome color table
local biomeColors = {
	PLAINS = Color3.fromRGB(145, 189, 89)
}

-- Always show 12 blocks below the surface regardless of player height.
-- Y_SURFACE_BELOW anchors underground relative to the surface (mcSpawnY or player Y,
-- whichever is lower), so caves and underground blocks stay visible even when
-- the player is flying or standing on a tall structure.
local Y_SURFACE_BELOW = 12
-- How many blocks to show above the player's current position.
local Y_ABOVE = 20

-- Fetch the actual MC world spawn so we can seed both the Y range and chunk center
-- before the player has been teleported (they start at Roblox 0,5,0 = MC 0,~1,0).
local mcSpawnX = 0
local mcSpawnY = 64
local mcSpawnZ = 0
do
	local ok, resp = pcall(function()
		return HttpService:GetAsync("http://" .. ReplicatedStorage.IP.Value .. "/spawn")
	end)
	if ok then
		local data = HttpService:JSONDecode(resp)
		if data then
			mcSpawnX = math.floor(data.x or 0)
			mcSpawnY = math.floor(data.y or 64)
			mcSpawnZ = math.floor(data.z or 0)
		end
	else
		warn("BlockHandler: could not fetch spawn, defaulting to 0,64,0 –", resp)
	end
end

-- Returns the average player Y position in Minecraft coordinates.
-- Falls back to mcSpawnY (fetched from server) so the first load is at surface level.
local function getAveragePlayerY()
	local allPlayers = Players:GetPlayers()
	if #allPlayers == 0 then return mcSpawnY end

	local totalY, count = 0, 0
	for _, player in ipairs(allPlayers) do
		if player.Character then
			local hrp = player.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				-- Only count players who have been teleported (Y > 10 in Roblox = Y > ~3 in MC)
				-- Ignore players still at default spawn height (Y ≈ 5) before teleport fires
				if hrp.Position.Y > 10 then
					totalY = totalY + (hrp.Position.Y / 3)
					count = count + 1
				end
			end
		end
	end
	return count > 0 and math.floor(totalY / count) or mcSpawnY
end

-- Request blocks using cord1/cord2 with Y bounds to avoid fetching all 383 Y levels
local function getChunkBlocks(minChunkX, maxChunkX, minChunkZ, maxChunkZ)
	local playerY = getAveragePlayerY()
	-- Anchor underground 12 blocks below whichever is lower: player or world surface.
	-- This keeps the underground layer visible even when flying or in tall structures.
	local surfaceRef = math.min(playerY, mcSpawnY)
	local minY = surfaceRef - Y_SURFACE_BELOW
	local maxY = playerY + Y_ABOVE

	local minX = minChunkX * 16
	local maxX = maxChunkX * 16 + 15
	local minZ = minChunkZ * 16
	local maxZ = maxChunkZ * 16 + 15

	local url = string.format(
		"http://%s/blocks?cord1=%d,%d,%d&cord2=%d,%d,%d",
		ReplicatedStorage.IP.Value,
		minX, minY, minZ,
		maxX, maxY, maxZ
	)
	local success, response = pcall(function() return HttpService:GetAsync(url) end)
	if success then
		return HttpService:JSONDecode(response)
	else
		warn("BlockHandler: Failed to fetch blocks:", response)
		return nil
	end
end

local function placeBlock(blockData)
	local key = string.format("%d,%d,%d", blockData.x, blockData.y, blockData.z)
	local existingBlock = currentBlocks[key]

	if existingBlock then
		if existingBlock.Name ~= blockData.t then
			existingBlock:Destroy()
			currentBlocks[key] = nil
		else
			BlockStateManager.applyState(existingBlock, blockData)
			return existingBlock
		end
	end

	local blockType = blockData.t
	local modelTemplate = modelsFolder:FindFirstChild(blockType)

	if not modelTemplate then
		-- Warn once per block type so the developer knows which models are missing
		if not BlockHandler_WarnedTypes then BlockHandler_WarnedTypes = {} end
		if not BlockHandler_WarnedTypes[blockType] then
			BlockHandler_WarnedTypes[blockType] = true
			warn("BlockHandler: no model for block type '" .. blockType .. "' — import models.rbxm or add the missing model to ReplicatedStorage.models")
		end
		return nil
	end

	if modelTemplate then
		local modelClone = modelTemplate:Clone()
		modelClone:SetPrimaryPartCFrame(CFrame.new(blockData.x * blockSize, blockData.y * blockSize, blockData.z * blockSize))
		modelClone.Parent = Workspace.Blocks

		BlockStateManager.applyState(modelClone, blockData)

		if blockData.b then
			local biome = blockData.b
			local color = biomeColors[biome]
			if color then
				for _, descendant in ipairs(modelClone:GetDescendants()) do
					if blockType == "GRASS_BLOCK" then
						if descendant:IsA("Texture") or descendant:IsA("Decal") then
							if string.match(descendant.Name, "_Overlay$") then
								descendant.Color3 = color
							end
						end
					else
						if descendant:IsA("BasePart") then
							descendant.Color = color
						elseif descendant:IsA("Texture") or descendant:IsA("Decal") then
							descendant.Color3 = color
						end
					end
				end
			end
		end

		currentBlocks[key] = modelClone
		return modelClone
	else
		-- Only warn once per block type to avoid log spam
		return nil
	end
end

local function updateBlocks(chunkData)
	local newBlocks = {}

	for _, blockData in ipairs(chunkData) do
		local key = string.format("%d,%d,%d", blockData.x, blockData.y, blockData.z)
		newBlocks[key] = placeBlock(blockData)
	end

	for key, block in pairs(currentBlocks) do
		if not newBlocks[key] then
			block:Destroy()
			currentBlocks[key] = nil
		end
	end
end

-- Returns the chunk coords of the average player position.
-- Only counts players who have been teleported to the MC spawn (Roblox Y > 10).
-- Falls back to the actual MC world spawn chunk instead of (0, 0).
local function getCenterChunk()
	local allPlayers = Players:GetPlayers()

	local totalX, totalZ, count = 0, 0, 0
	for _, player in ipairs(allPlayers) do
		if player.Character then
			local hrp = player.Character:FindFirstChild("HumanoidRootPart")
			if hrp and hrp.Position.Y > 10 then
				totalX = totalX + hrp.Position.X / 3
				totalZ = totalZ + hrp.Position.Z / 3
				count = count + 1
			end
		end
	end

	if count == 0 then
		-- Fall back to the actual MC world spawn chunk
		return math.floor(mcSpawnX / 16), math.floor(mcSpawnZ / 16)
	end
	return math.floor((totalX / count) / 16), math.floor((totalZ / count) / 16)
end

local function loadChunks(chunkGridSize)
	local centerChunkX, centerChunkZ = getCenterChunk()
	local halfGridSize = math.floor(chunkGridSize / 2)
	local minChunkX = centerChunkX - halfGridSize
	local maxChunkX = centerChunkX + halfGridSize
	local minChunkZ = centerChunkZ - halfGridSize
	local maxChunkZ = centerChunkZ + halfGridSize

	local chunkData = getChunkBlocks(minChunkX, maxChunkX, minChunkZ, maxChunkZ)
	if chunkData then
		updateBlocks(chunkData)
	end
end

-- First load: 7x7 grid (49 chunks) to fill in a wide area before the player unanchors.
-- Ongoing:    5x5 grid (25 chunks) for the increased render distance.
-- Each chunk is 16×16 blocks. 5x5 = 80×80 block view; 7x7 = 112×112 on first join.
local firstLoad = true
while true do
	if firstLoad then
		loadChunks(7)
		firstLoad = false
	else
		loadChunks(5)
	end
	task.wait(updateInterval)
end
