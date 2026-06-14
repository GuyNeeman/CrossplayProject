-- Renders Minecraft players as 3D models in Roblox.
-- HTTP polling (100 req/min) updates live state; RunService.Heartbeat drives
-- limb animation at ~60 fps so walking looks smooth between polls.
local HttpService       = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local TweenService      = game:GetService("TweenService")
local ChatService       = game:GetService("Chat")
local RunService        = game:GetService("RunService")

local playerModelTemplate = ReplicatedStorage:WaitForChild("Player")
local updateInterval      = 60 / 100
local dataUrl             = "http://" .. ReplicatedStorage.IP.Value .. "/players"

if not Workspace:FindFirstChild("Players") then
	local f = Instance.new("Folder"); f.Name = "Players"; f.Parent = Workspace
end

-- ── State ─────────────────────────────────────────────────────────────────────

local playerModels   = {}  -- uuid → Model
local usernameToUUID = {}
local uuidToUsername = {}

-- Live state written by the HTTP poll, read by Heartbeat.
local playerState = {}

-- ── Limb animation at ~60 fps ─────────────────────────────────────────────────

local LIMB_TWEEN = TweenInfo.new(0.08, Enum.EasingStyle.Linear)

local function animateLimbs(uuid, dt)
	local model = playerModels[uuid]
	local state = playerState[uuid]
	if not model or not state then return end

	if state.isMoving then
		state.walkTime = state.walkTime + dt * 8
	else
		state.walkTime = state.walkTime * 0.7  -- damp to rest
	end
	local t = state.walkTime

	local swing   = math.sin(t) * math.rad(35)
	local yawRad  = math.rad(-state.yaw)
	local bodyRot = CFrame.Angles(0, yawRad, 0)
	local tPos    = state.position + Vector3.new(0, 1, 0)

	local rightArm = model:FindFirstChild("Right Arm")
	if rightArm then
		local rs = state.isAttacking and math.rad(-75) or -swing
		TweenService:Create(rightArm, LIMB_TWEEN, {
			CFrame = CFrame.new(tPos + bodyRot * Vector3.new(1.25, 0.25, 0))
				* bodyRot * CFrame.Angles(rs, 0, 0) * CFrame.new(0, -0.75, 0)
		}):Play()
	end

	local leftArm = model:FindFirstChild("Left Arm")
	if leftArm then
		TweenService:Create(leftArm, LIMB_TWEEN, {
			CFrame = CFrame.new(tPos + bodyRot * Vector3.new(-1.25, 0.25, 0))
				* bodyRot * CFrame.Angles(swing, 0, 0) * CFrame.new(0, -0.75, 0)
		}):Play()
	end

	local rightLeg = model:FindFirstChild("Right Leg")
	if rightLeg then
		TweenService:Create(rightLeg, LIMB_TWEEN, {
			CFrame = CFrame.new(tPos + bodyRot * Vector3.new(0.45, -0.85, 0))
				* bodyRot * CFrame.Angles(swing, 0, 0) * CFrame.new(0, -0.75, 0)
		}):Play()
	end

	local leftLeg = model:FindFirstChild("Left Leg")
	if leftLeg then
		TweenService:Create(leftLeg, LIMB_TWEEN, {
			CFrame = CFrame.new(tPos + bodyRot * Vector3.new(-0.45, -0.85, 0))
				* bodyRot * CFrame.Angles(-swing, 0, 0) * CFrame.new(0, -0.75, 0)
		}):Play()
	end
end

RunService.Heartbeat:Connect(function(dt)
	for uuid in pairs(playerState) do
		animateLimbs(uuid, dt)
	end
end)

-- ── HTTP poll ─────────────────────────────────────────────────────────────────

local BODY_TWEEN = TweenInfo.new(0.5, Enum.EasingStyle.Linear)

local function handleRequest()
	local ok, raw = pcall(function() return HttpService:GetAsync(dataUrl) end)
	if not ok then warn("PlayerHandler: /players failed:", raw) return end

	local data = HttpService:JSONDecode(raw)
	local seen = {}

	for _, d in ipairs(data) do
		local uuid = d.uuid
		if not uuid or not d.name then continue end
		seen[uuid] = true

		if not playerModels[uuid] then
			local model    = playerModelTemplate:Clone()
			model.Name     = uuid
			model.Parent   = Workspace.Players
			local username = d.name
			usernameToUUID[username] = uuid
			uuidToUsername[uuid]     = username

			-- Scale body parts to match MC proportions (1 block = 3 studs)
			-- MC player: 0.6w × 1.8h total. Torso ≈ 0.6×0.75×0.375 blocks
			local function scalePart(name, size)
				local p = model:FindFirstChild(name, true)
				if p and p:IsA("BasePart") then p.Size = size end
			end
			scalePart("Head",      Vector3.new(1.8, 1.8, 1.8))
			scalePart("Torso",     Vector3.new(1.8, 2.25, 0.9))
			scalePart("HumanoidRootPart", Vector3.new(1.8, 2.25, 0.9))
			scalePart("Right Arm", Vector3.new(0.9, 2.25, 0.9))
			scalePart("Left Arm",  Vector3.new(0.9, 2.25, 0.9))
			scalePart("Right Leg", Vector3.new(0.9, 2.25, 0.9))
			scalePart("Left Leg",  Vector3.new(0.9, 2.25, 0.9))

			-- Use recursive search so head works even if nested inside a union
			local headPart = model:FindFirstChild("Head", true)

			local billboard = Instance.new("BillboardGui")
			billboard.Name          = "PlayerNameLabel"
			billboard.Size          = UDim2.new(0, 100, 0, 20)
			billboard.StudsOffset   = Vector3.new(0, 1.2, 0)
			billboard.Adornee       = headPart
			billboard.AlwaysOnTop   = false
			billboard.MaxDistance   = 50
			billboard.Parent        = model

			local nameText = Instance.new("TextLabel")
			nameText.Size                   = UDim2.new(1, 0, 1, 0)
			nameText.Text                   = username
			nameText.TextColor3             = Color3.new(1, 1, 1)
			nameText.BackgroundTransparency = 0.6
			nameText.BackgroundColor3       = Color3.fromRGB(128, 128, 128)
			nameText.BorderSizePixel        = 0
			nameText.FontFace               = Font.fromId(12187371840)
			nameText.TextScaled             = true
			nameText.Parent                 = billboard

			ReplicatedStorage.loadPlayerSkin:FireAllClients(uuid, username, model)

			playerModels[uuid] = model
			playerState[uuid]  = {
				position  = Vector3.new(0, 0, 0), yaw = 0, pitch = 0,
				isMoving  = false, isAttacking = false, isCrouching = false,
				walkTime  = 0,
			}
		end

		local isCrouching = d.crouch == true
		local position    = Vector3.new(
			(d.x * 3) - 1.5,
			(d.y * 3) + 0.3 + (isCrouching and -1.125 or 0),
			(d.z * 3) - 1.5
		)
		local yaw = (d.yaw or 0) + 180

		local state       = playerState[uuid]
		state.isMoving    = (position - state.position).Magnitude > 0.05
		state.position    = position
		state.yaw         = yaw
		state.pitch       = d.pitch or 0
		state.isAttacking = d.isAttacking == true
		state.isCrouching = isCrouching

		local model      = playerModels[uuid]
		local crouchTilt = isCrouching and math.rad(20) or 0
		local yawRad     = math.rad(-yaw)

		TweenService:Create(model.PrimaryPart, BODY_TWEEN, { CFrame = CFrame.new(position) }):Play()

		local head = model:FindFirstChild("Head", true)
		if head then
			TweenService:Create(head, BODY_TWEEN, {
				CFrame = CFrame.new(position + Vector3.new(0, 2.7, 0))
					* CFrame.Angles(0, yawRad, 0)
					* CFrame.Angles(math.rad(-(d.pitch or 0)) - crouchTilt, 0, 0)
			}):Play()
		end

		local torso = model:FindFirstChild("Torso")
		if torso then
			TweenService:Create(torso, BODY_TWEEN, {
				CFrame = CFrame.new(position + Vector3.new(0, 1, 0))
					* CFrame.Angles(0, yawRad, 0)
					* CFrame.Angles(crouchTilt, 0, 0)
			}):Play()
		end
	end

	-- Remove disconnected players
	local toRemove = {}
	for uuid in pairs(playerModels) do
		if not seen[uuid] then toRemove[#toRemove + 1] = uuid end
	end
	for _, uuid in ipairs(toRemove) do
		if playerModels[uuid] then playerModels[uuid]:Destroy() end
		playerModels[uuid] = nil
		playerState[uuid]  = nil
		local username = uuidToUsername[uuid]
		if username then usernameToUUID[username] = nil end
		uuidToUsername[uuid] = nil
	end
end

-- Chat bubbles from MC players
ReplicatedStorage.Chat.OnServerEvent:Connect(function(_, message, sender)
	local uuid = usernameToUUID[sender]
	if uuid and playerModels[uuid] then
		ChatService:Chat(playerModels[uuid].Head, message, Enum.ChatColor.White)
	end
end)

while true do
	handleRequest()
	task.wait(updateInterval)
end
