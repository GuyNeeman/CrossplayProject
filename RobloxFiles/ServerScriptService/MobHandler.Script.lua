local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local updateInterval = 60 / 100

-- Auto-create Mobs folder
if not Workspace:FindFirstChild("Mobs") then
	local folder = Instance.new("Folder")
	folder.Name = "Mobs"
	folder.Parent = Workspace
end

local mobsFolder = Workspace.Mobs
local mobModels = {}  -- uuid → Model

-- Mob type → color mapping for placeholder boxes
local MOB_COLORS = {
	ZOMBIE         = Color3.fromRGB(50, 120, 50),
	SKELETON       = Color3.fromRGB(220, 220, 220),
	CREEPER        = Color3.fromRGB(50, 180, 50),
	SPIDER         = Color3.fromRGB(80, 30, 30),
	ENDERMAN       = Color3.fromRGB(20, 0, 40),
	WITCH          = Color3.fromRGB(90, 0, 140),
	BLAZE          = Color3.fromRGB(255, 180, 0),
	GHAST          = Color3.fromRGB(240, 240, 240),
	SLIME          = Color3.fromRGB(100, 200, 100),
	MAGMA_CUBE     = Color3.fromRGB(200, 50, 0),
	PIG            = Color3.fromRGB(255, 182, 193),
	COW            = Color3.fromRGB(90, 60, 30),
	SHEEP          = Color3.fromRGB(230, 230, 230),
	CHICKEN        = Color3.fromRGB(255, 240, 200),
	HORSE          = Color3.fromRGB(140, 100, 60),
	WOLF           = Color3.fromRGB(150, 140, 130),
	CAT            = Color3.fromRGB(240, 200, 140),
	VILLAGER       = Color3.fromRGB(200, 160, 110),
	IRON_GOLEM     = Color3.fromRGB(170, 170, 160),
	PRIMED_TNT     = Color3.fromRGB(255, 50, 50),
}
local DEFAULT_MOB_COLOR = Color3.fromRGB(160, 80, 40)

-- Returns or creates the 3D placeholder box model for a mob
local function getOrCreateMobModel(uuid, mobType)
	if mobModels[uuid] then return mobModels[uuid] end

	local model = Instance.new("Model")
	model.Name = uuid

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(1.5, 2, 0.75)
	body.Anchored = true
	body.CanCollide = false
	body.CastShadow = false
	body.Color = MOB_COLORS[mobType] or DEFAULT_MOB_COLOR
	body.Material = Enum.Material.SmoothPlastic
	body.Parent = model
	model.PrimaryPart = body

	-- Billboard with mob type name
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 120, 0, 24)
	billboard.StudsOffset = Vector3.new(0, 1.8, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 80
	billboard.Adornee = body
	billboard.Parent = model

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Text = mobType:gsub("_", " ")
	label.TextColor3 = Color3.new(1, 1, 1)
	label.BackgroundTransparency = 0.5
	label.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	label.BorderSizePixel = 0
	label.TextScaled = true
	label.Parent = billboard

	model.Parent = mobsFolder
	mobModels[uuid] = model
	return model
end

local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Linear)

while true do
	local ok, body = pcall(function()
		return HttpService:GetAsync("http://" .. ReplicatedStorage.IP.Value .. "/mobs")
	end)

	if ok and body then
		local data = HttpService:JSONDecode(body)
		local seen = {}

		for _, mob in ipairs(data) do
			local uuid = mob.uuid
			if not uuid then continue end
			seen[uuid] = true

			local model = getOrCreateMobModel(uuid, mob.mobType or "UNKNOWN")
			local pos = Vector3.new(mob.x * 3, mob.y * 3 + 1, mob.z * 3)
			TweenService:Create(model.PrimaryPart, tweenInfo, {CFrame = CFrame.new(pos)}):Play()
		end

		-- Remove mobs that left the loaded area
		for uuid, model in pairs(mobModels) do
			if not seen[uuid] then
				model:Destroy()
				mobModels[uuid] = nil
			end
		end
	end

	task.wait(updateInterval)
end
