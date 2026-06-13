-- Polls /blockdamage and overlays crack-stage models (stage 0-9) on blocks
-- being broken by Minecraft players, matching vanilla MC block-breaking visuals.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local updateInterval = 60 / 100
local blockSize = 3

-- Folder that holds temporary crack overlay parts
local crackFolder = Workspace:FindFirstChild("BlockCracks")
if not crackFolder then
	crackFolder = Instance.new("Folder")
	crackFolder.Name = "BlockCracks"
	crackFolder.Parent = Workspace
end

-- Active crack overlays: "x,y,z" → Part
local crackParts = {}

-- Crack transparency by stage (stage 0 = barely visible, 9 = almost broken)
local function stageToTransparency(stage)
	return 1 - (stage / 9) * 0.85  -- ranges from ~0.91 (stage 0) to 0.15 (stage 9)
end

-- Crack color shifts from white (not breaking) to orange/red (nearly broken)
local function stageToColor(stage)
	local t = stage / 9
	return Color3.fromRGB(255, math.floor(255 * (1 - t * 0.8)), math.floor(255 * (1 - t)))
end

while true do
	local ok, body = pcall(function()
		return HttpService:GetAsync("http://" .. ReplicatedStorage.IP.Value .. "/blockdamage")
	end)

	if ok and body then
		local data = HttpService:JSONDecode(body)
		local seen = {}

		for _, entry in ipairs(data) do
			local key = string.format("%d,%d,%d", entry.x, entry.y, entry.z)
			seen[key] = true

			local part = crackParts[key]
			if not part then
				part = Instance.new("Part")
				part.Name = "Crack_" .. key
				part.Size = Vector3.new(blockSize + 0.05, blockSize + 0.05, blockSize + 0.05)
				part.Anchored = true
				part.CanCollide = false
				part.CastShadow = false
				part.Material = Enum.Material.SmoothPlastic
				part.CFrame = CFrame.new(entry.x * blockSize, entry.y * blockSize, entry.z * blockSize)
				part.Parent = crackFolder
				crackParts[key] = part
			end

			local stage = math.clamp(entry.stage, 0, 9)
			part.Transparency = stageToTransparency(stage)
			part.Color = stageToColor(stage)
		end

		-- Remove overlays for blocks no longer being mined
		for key, part in pairs(crackParts) do
			if not seen[key] then
				part:Destroy()
				crackParts[key] = nil
			end
		end
	end

	task.wait(updateInterval)
end
