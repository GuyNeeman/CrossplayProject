local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local updateInterval = 60 / 100

if not Workspace:FindFirstChild("Mobs") then
	local folder = Instance.new("Folder")
	folder.Name = "Mobs"
	folder.Parent = Workspace
end

local mobsFolder = Workspace.Mobs
local mobModels = {}

-- Colors per mob type
local MOB_COLORS = {
	ZOMBIE         = { body = Color3.fromRGB(50,120,50),    skin = Color3.fromRGB(100,180,100) },
	SKELETON       = { body = Color3.fromRGB(220,220,220),  skin = Color3.fromRGB(240,240,240) },
	CREEPER        = { body = Color3.fromRGB(50,180,50),    skin = Color3.fromRGB(50,180,50)   },
	SPIDER         = { body = Color3.fromRGB(60,20,20),     skin = Color3.fromRGB(80,30,30)    },
	ENDERMAN       = { body = Color3.fromRGB(20,0,40),      skin = Color3.fromRGB(20,0,40)     },
	PIG            = { body = Color3.fromRGB(255,182,193),  skin = Color3.fromRGB(240,150,160) },
	COW            = { body = Color3.fromRGB(90,60,30),     skin = Color3.fromRGB(60,40,20)    },
	SHEEP          = { body = Color3.fromRGB(230,230,230),  skin = Color3.fromRGB(200,200,200) },
	CHICKEN        = { body = Color3.fromRGB(255,240,200),  skin = Color3.fromRGB(240,200,150) },
	HORSE          = { body = Color3.fromRGB(140,100,60),   skin = Color3.fromRGB(120,80,40)   },
	WOLF           = { body = Color3.fromRGB(150,140,130),  skin = Color3.fromRGB(130,120,110) },
	VILLAGER       = { body = Color3.fromRGB(200,160,110),  skin = Color3.fromRGB(255,200,150) },
	IRON_GOLEM     = { body = Color3.fromRGB(170,170,160),  skin = Color3.fromRGB(190,190,180) },
	WITCH          = { body = Color3.fromRGB(80,0,120),     skin = Color3.fromRGB(90,0,140)    },
	BLAZE          = { body = Color3.fromRGB(255,180,0),    skin = Color3.fromRGB(255,200,50)  },
}
local DEFAULT_COLOR = { body = Color3.fromRGB(160,80,40), skin = Color3.fromRGB(140,60,20) }

-- Mob shape categories
local ANIMAL_MOBS    = { COW=true, PIG=true, SHEEP=true, HORSE=true, WOLF=true, CHICKEN=true }
local HUMANOID_MOBS  = { ZOMBIE=true, SKELETON=true, VILLAGER=true, IRON_GOLEM=true, WITCH=true, BLAZE=true }

local function makePart(parent, name, size, color, offset)
	local p = Instance.new("Part")
	p.Name       = name
	p.Size       = size
	p.Anchored   = true
	p.CanCollide = false
	p.CastShadow = false
	p.Color      = color
	p.Material   = Enum.Material.SmoothPlastic
	p.CFrame     = CFrame.new(offset)
	p.Parent     = parent
	return p
end

-- Build a 4-legged animal model (cow, pig, sheep…)
-- MC animal box: body ~0.9w × 0.9h × 1.8d blocks → ×3 studs
local function buildAnimalModel(uuid, mobType)
	local colors  = MOB_COLORS[mobType] or DEFAULT_COLOR
	local model   = Instance.new("Model")
	model.Name    = uuid

	local bw, bh, bd = 2.7, 2.7, 5.4   -- body (studs)
	local lw, lh, ld = 0.8, 2.4, 0.8   -- leg
	local hw, hh, hd = 1.8, 1.8, 1.8   -- head

	-- Body sits with bottom at y=lh, centre of body at y = lh + bh/2
	local bodyY  = lh + bh / 2   -- 2.4 + 1.35 = 3.75
	local body   = makePart(model, "Body", Vector3.new(bw, bh, bd), colors.body, Vector3.new(0, bodyY, 0))
	model.PrimaryPart = body

	-- Head at front of body, slightly raised
	makePart(model, "Head", Vector3.new(hw, hh, hd), colors.skin, Vector3.new(0, bodyY + bh/2, bd/2 + hd/2))

	-- 4 legs below body
	local lx, lz = (bw/2 - lw/2), (bd/2 - ld/2)
	for _, off in ipairs({ {lx,lz}, {-lx,lz}, {lx,-lz}, {-lx,-lz} }) do
		makePart(model, "Leg", Vector3.new(lw, lh, ld), colors.body, Vector3.new(off[1], lh/2, off[2]))
	end

	-- Name label
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0,120,0,24); bb.StudsOffset = Vector3.new(0,2,0)
	bb.AlwaysOnTop = false; bb.MaxDistance = 80; bb.Adornee = body; bb.Parent = model
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1,0,1,0); lbl.Text = mobType:gsub("_"," ")
	lbl.TextColor3 = Color3.new(1,1,1); lbl.BackgroundTransparency = 0.5
	lbl.BackgroundColor3 = Color3.fromRGB(30,30,30); lbl.BorderSizePixel = 0
	lbl.TextScaled = true; lbl.Parent = bb

	model.Parent = mobsFolder
	return model
end

-- Build a humanoid-shaped mob (zombie, skeleton, villager…)
-- MC player body: 0.6w × 1.8h total
local function buildHumanoidModel(uuid, mobType)
	local colors = MOB_COLORS[mobType] or DEFAULT_COLOR
	local model  = Instance.new("Model")
	model.Name   = uuid

	-- Dimensions in studs (MC × 3)
	local tw, th, td = 1.8, 2.4, 0.9  -- torso
	local hw, hh, hd = 1.5, 1.5, 1.5  -- head
	local aw, ah, ad = 0.8, 2.1, 0.8  -- arm
	local lw, lh, ld = 0.8, 2.1, 0.8  -- leg

	local legBase  = lh / 2
	local torsoY   = lh + th / 2
	local headY    = lh + th + hh / 2
	local armY     = lh + th - ah / 2

	local torso = makePart(model, "Torso", Vector3.new(tw, th, td), colors.body, Vector3.new(0, torsoY, 0))
	model.PrimaryPart = torso
	makePart(model, "Head",     Vector3.new(hw, hh, hd), colors.skin, Vector3.new(0, headY, 0))
	makePart(model, "RightArm", Vector3.new(aw, ah, ad), colors.body, Vector3.new((tw+aw)/2, armY, 0))
	makePart(model, "LeftArm",  Vector3.new(aw, ah, ad), colors.body, Vector3.new(-(tw+aw)/2, armY, 0))
	makePart(model, "RightLeg", Vector3.new(lw, lh, ld), colors.body, Vector3.new(lw/2,  legBase, 0))
	makePart(model, "LeftLeg",  Vector3.new(lw, lh, ld), colors.body, Vector3.new(-lw/2, legBase, 0))

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0,120,0,24); bb.StudsOffset = Vector3.new(0,1.2,0)
	bb.AlwaysOnTop = false; bb.MaxDistance = 80; bb.Adornee = torso; bb.Parent = model
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1,0,1,0); lbl.Text = mobType:gsub("_"," ")
	lbl.TextColor3 = Color3.new(1,1,1); lbl.BackgroundTransparency = 0.5
	lbl.BackgroundColor3 = Color3.fromRGB(30,30,30); lbl.BorderSizePixel = 0
	lbl.TextScaled = true; lbl.Parent = bb

	model.Parent = mobsFolder
	return model
end

-- Simple box fallback for uncommon mobs
local function buildSimpleModel(uuid, mobType)
	local colors = MOB_COLORS[mobType] or DEFAULT_COLOR
	local model  = Instance.new("Model")
	model.Name   = uuid
	local body   = makePart(model, "Body", Vector3.new(1.5, 2.1, 1.5), colors.body, Vector3.new(0, 1.05, 0))
	model.PrimaryPart = body

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0,120,0,24); bb.StudsOffset = Vector3.new(0,1.5,0)
	bb.AlwaysOnTop = false; bb.MaxDistance = 80; bb.Adornee = body; bb.Parent = model
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1,0,1,0); lbl.Text = mobType:gsub("_"," ")
	lbl.TextColor3 = Color3.new(1,1,1); lbl.BackgroundTransparency = 0.5
	lbl.BackgroundColor3 = Color3.fromRGB(30,30,30); lbl.BorderSizePixel = 0
	lbl.TextScaled = true; lbl.Parent = bb

	model.Parent = mobsFolder
	return model
end

local function getOrCreateMobModel(uuid, mobType)
	if mobModels[uuid] then return mobModels[uuid] end
	local model
	if ANIMAL_MOBS[mobType] then
		model = buildAnimalModel(uuid, mobType)
	elseif HUMANOID_MOBS[mobType] then
		model = buildHumanoidModel(uuid, mobType)
	else
		model = buildSimpleModel(uuid, mobType)
	end
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
			-- Position: feet at y*3, model origin is at ground level
			local pos = Vector3.new(mob.x * 3, mob.y * 3, mob.z * 3)
			local yaw = CFrame.Angles(0, math.rad(mob.yaw or 0), 0)
			TweenService:Create(model.PrimaryPart, tweenInfo, {
				CFrame = CFrame.new(pos + Vector3.new(0, model.PrimaryPart.Size.Y / 2, 0)) * yaw
			}):Play()
		end

		for uuid, model in pairs(mobModels) do
			if not seen[uuid] then
				model:Destroy()
				mobModels[uuid] = nil
			end
		end
	end

	task.wait(updateInterval)
end
