local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ChatService = game:GetService("Chat")
local RunService = game:GetService("RunService")

local playerModelTemplate = ReplicatedStorage:WaitForChild("Player")
local players = {}
local playerModels = {}
local usernameToUUID = {}
local uuidToUsername = {}
local playerPrevPos = {}   -- tracks last position for walk detection
local playerWalkTime = {}  -- per-player walk cycle time accumulator

-- Auto-create Players folder if missing
if not Workspace:FindFirstChild("Players") then
	local folder = Instance.new("Folder")
	folder.Name = "Players"
	folder.Parent = Workspace
end

local updateInterval = 60 / 100
local dataUrl = "http://" .. ReplicatedStorage.IP.Value .. "/players"

-- Animate a Minecraft player model's limbs.
-- Assumes standard Minecraft rig part names: Left Arm, Right Arm, Left Leg, Right Leg, Torso.
-- Offsets are based on blockSize=3; a Minecraft player is ~1.8 blocks tall = 5.4 studs.
local function animatePlayerLimbs(playerModel, position, yawDeg, isMoving, dt, isAttacking)
	local uuid = playerModel.Name
	playerWalkTime[uuid] = (playerWalkTime[uuid] or 0) + (isMoving and dt * 8 or 0)
	local t = playerWalkTime[uuid]

	-- When attacking, override the right-arm swing with a punch animation
	local attackSwing = isAttacking and math.rad(-75) or 0
	local swing = isMoving and math.sin(t) * math.rad(35) or 0
	local yawRad = math.rad(-yawDeg)
	local bodyRot = CFrame.Angles(0, yawRad, 0)

	local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Linear)

	local torsoPos = position + Vector3.new(0, 1, 0)

	-- Right Arm: punch forward when attacking, otherwise normal walk swing
	local rightArm = playerModel:FindFirstChild("Right Arm")
	if rightArm then
		local offset = bodyRot * Vector3.new(1.25, 0.25, 0)
		local armPos = torsoPos + offset
		local rightSwing = isAttacking and attackSwing or -swing
		local armCF = CFrame.new(armPos) * bodyRot * CFrame.Angles(rightSwing, 0, 0) * CFrame.new(0, -0.75, 0)
		TweenService:Create(rightArm, tweenInfo, {CFrame = armCF}):Play()
	end

	-- Left Arm: normal walk swing (unaffected by attack)
	local leftArm = playerModel:FindFirstChild("Left Arm")
	if leftArm then
		local offset = bodyRot * Vector3.new(-1.25, 0.25, 0)
		local armPos = torsoPos + offset
		local armCF = CFrame.new(armPos) * bodyRot * CFrame.Angles(swing, 0, 0) * CFrame.new(0, -0.75, 0)
		TweenService:Create(leftArm, tweenInfo, {CFrame = armCF}):Play()
	end

	-- Right Leg: offset right, opposite to right arm
	local rightLeg = playerModel:FindFirstChild("Right Leg")
	if rightLeg then
		local offset = bodyRot * Vector3.new(0.45, -0.85, 0)
		local legPos = torsoPos + offset
		local legCF = CFrame.new(legPos) * bodyRot * CFrame.Angles(swing, 0, 0) * CFrame.new(0, -0.75, 0)
		TweenService:Create(rightLeg, tweenInfo, {CFrame = legCF}):Play()
	end

	-- Left Leg: offset left, opposite to left arm
	local leftLeg = playerModel:FindFirstChild("Left Leg")
	if leftLeg then
		local offset = bodyRot * Vector3.new(-0.45, -0.85, 0)
		local legPos = torsoPos + offset
		local legCF = CFrame.new(legPos) * bodyRot * CFrame.Angles(-swing, 0, 0) * CFrame.new(0, -0.75, 0)
		TweenService:Create(leftLeg, tweenInfo, {CFrame = legCF}):Play()
	end
end

local lastUpdateTime = tick()

local function handleRequest()
	local now = tick()
	local dt = now - lastUpdateTime
	lastUpdateTime = now

	local success, pdata = pcall(function()
		return HttpService:GetAsync(dataUrl)
	end)

	if not success then
		warn("Failed to fetch player data:", pdata)
		return
	end

	local playerData = HttpService:JSONDecode(pdata)
	local currentPlayers = {}

	for _, data in ipairs(playerData) do
		local uuid = data["uuid"]
		if not uuid or not data.name then continue end
		currentPlayers[uuid] = true

		if not players[uuid] then
			local newPlayerModel = playerModelTemplate:Clone()
			newPlayerModel.Name = uuid
			newPlayerModel.Parent = Workspace:FindFirstChild("Players") or Workspace

			local username = data.name
			usernameToUUID[username] = uuid
			uuidToUsername[uuid] = username

			local nameLabel = Instance.new("BillboardGui")
			nameLabel.Name = "PlayerNameLabel"
			nameLabel.Size = UDim2.new(0, 100, 0, 20)
			nameLabel.StudsOffset = Vector3.new(0, 1.2, 0)
			nameLabel.Adornee = newPlayerModel:FindFirstChild("Head")
			nameLabel.AlwaysOnTop = false
			nameLabel.MaxDistance = 50

			local nameText = Instance.new("TextLabel")
			nameText.Parent = nameLabel
			nameText.Size = UDim2.new(1, 0, 1, 0)
			nameText.Text = username
			nameText.TextColor3 = Color3.new(1, 1, 1)
			nameText.BackgroundTransparency = 0.6
			nameText.BackgroundColor3 = Color3.fromRGB(128, 128, 128)
			nameText.BorderSizePixel = 0
			nameText.FontFace = Font.fromId(12187371840)
			nameText.TextScaled = true
			nameLabel.Parent = newPlayerModel

			game.ReplicatedStorage.loadPlayerSkin:FireAllClients(uuid, username, newPlayerModel)

			players[uuid] = true
			playerModels[uuid] = newPlayerModel
		end

		local playerModel = playerModels[uuid]
		local isCrouching = data.crouch == true

		-- When sneaking, Minecraft shifts the player down by 0.375 blocks (1.125 studs) and leans forward
		local crouchYOffset = isCrouching and -1.125 or 0
		local crouchForwardTilt = isCrouching and math.rad(20) or 0

		local position = Vector3.new((data.x * 3) - 1.5, (data.y * 3) + 0.3 + crouchYOffset, (data.z * 3) - 1.5)
		local yaw = data.yaw + 180
		local pitch = data.pitch

		-- Detect movement for walk animation
		local prevPos = playerPrevPos[uuid]
		local isMoving = prevPos ~= nil and (position - prevPos).Magnitude > 0.05
		playerPrevPos[uuid] = position

		local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)

		-- Move body root
		TweenService:Create(playerModel.PrimaryPart, tweenInfo, {CFrame = CFrame.new(position)}):Play()

		-- Head: looks in the direction the player is facing + pitch; counteract torso tilt when crouching
		local headPart = playerModel:FindFirstChild("Head")
		local neckPart = headPart and headPart:FindFirstChild("Neck")
		if headPart then
			local headPos = position + Vector3.new(0, 2, 0)
			local headCF = CFrame.new(headPos)
				* CFrame.Angles(0, math.rad(-yaw), 0)
				* CFrame.Angles(math.rad(-pitch) - crouchForwardTilt, 0, 0)
			TweenService:Create(headPart, tweenInfo, {CFrame = headCF}):Play()
			if neckPart then
				TweenService:Create(neckPart, tweenInfo, {CFrame = headCF}):Play()
			end
		end

		-- Torso: rotates with yaw and leans forward when crouching
		local torsoPart = playerModel:FindFirstChild("Torso")
		if torsoPart then
			local torsoCF = CFrame.new(position + Vector3.new(0, 1, 0))
				* CFrame.Angles(0, math.rad(-yaw), 0)
				* CFrame.Angles(crouchForwardTilt, 0, 0)
			TweenService:Create(torsoPart, tweenInfo, {CFrame = torsoCF}):Play()
		end

		-- Limb animations
		animatePlayerLimbs(playerModel, position, yaw, isMoving, dt, data.isAttacking == true)
	end

	-- Collect disconnected UUIDs first, then remove them.
	-- Modifying a table inside pairs() can cause Lua's next() to skip entries.
	local toRemove = {}
	for uuid in pairs(players) do
		if not currentPlayers[uuid] then
			toRemove[#toRemove + 1] = uuid
		end
	end
	for _, uuid in ipairs(toRemove) do
		local playerModel = playerModels[uuid]
		if playerModel then
			playerModel:Destroy()
			playerModels[uuid] = nil
		end
		players[uuid] = nil
		playerPrevPos[uuid] = nil
		playerWalkTime[uuid] = nil

		local username = uuidToUsername[uuid]
		if username then
			usernameToUUID[username] = nil
			uuidToUsername[uuid] = nil
		end
	end
end

local function CreateChatBubble(instance, message)
	ChatService:Chat(instance, message, Enum.ChatColor.White)
end

game.ReplicatedStorage.Chat.OnServerEvent:Connect(function(player, message, sender)
	local uuid = usernameToUUID[sender]
	if uuid then
		local playerModel = playerModels[uuid]
		if playerModel then
			CreateChatBubble(playerModel.Head, message)
		else
			warn("Player model not found for chat message:", sender)
		end
	else
		warn("UUID not found for username:", sender)
	end
end)

while true do
	handleRequest()
	task.wait(updateInterval)
end
