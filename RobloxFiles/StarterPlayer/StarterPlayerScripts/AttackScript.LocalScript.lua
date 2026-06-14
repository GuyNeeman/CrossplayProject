-- Left-click to attack MC players (workspace.Players) or mobs (workspace.Mobs).
-- Players are identified by the BillboardGui TextLabel; mobs by model.Name (UUID).
local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")

local player      = Players.LocalPlayer
local attackEvent = ReplicatedStorage:WaitForChild("AttackEvent")

local ATTACK_COOLDOWN = 0.5
local lastAttack      = 0
local ATTACK_RANGE    = 10  -- studs (≈3.3 MC blocks, slightly more than vanilla 3)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

-- Returns { targetId = string, isMob = bool } or nil
local function getTarget()
	local playersFolder = Workspace:FindFirstChild("Players")
	local mobsFolder    = Workspace:FindFirstChild("Mobs")

	local targets = {}
	if playersFolder then targets[#targets+1] = playersFolder end
	if mobsFolder    then targets[#targets+1] = mobsFolder    end
	if #targets == 0 then return nil end

	rayParams.FilterDescendantsInstances = targets

	local camera  = Workspace.CurrentCamera
	local mouse   = player:GetMouse()
	local unitRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local result  = Workspace:Raycast(unitRay.Origin, unitRay.Direction * ATTACK_RANGE, rayParams)
	if not result then return nil end

	-- Walk up to the direct child of whichever folder was hit
	local part = result.Instance
	local model = part
	while model and model.Parent ~= playersFolder and model.Parent ~= mobsFolder do
		model = model.Parent
	end
	if not model then return nil end

	if model.Parent == mobsFolder then
		-- model.Name is the mob UUID
		return { targetId = model.Name, isMob = true }
	else
		-- MC player: read name from BillboardGui
		local gui   = model:FindFirstChildOfClass("BillboardGui")
		local label = gui and gui:FindFirstChildOfClass("TextLabel")
		local name  = label and label.Text
		if not name or name == "" then return nil end
		return { targetId = name, isMob = false }
	end
end

-- Crosshair highlight when hovering over a valid target
local highlighting = false
RunService.RenderStepped:Connect(function()
	local hit = getTarget() ~= nil
	if hit ~= highlighting then
		highlighting = hit
		player:GetMouse().Icon = hit and "rbxasset://textures/Cursors/CrossCursor.png" or ""
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

	local now = tick()
	if now - lastAttack < ATTACK_COOLDOWN then return end

	local hit = getTarget()
	if hit then
		lastAttack = now
		attackEvent:FireServer(hit.targetId)
	end
end)
