-- Sends a hit request to /attack when the Roblox player left-clicks on a MC player model.
-- Uses a filtered workspace:Raycast (only hits workspace.Players descendants) instead of
-- mouse.Target so the detection works reliably even when other UI is visible.
local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")

local player      = Players.LocalPlayer
local attackEvent = ReplicatedStorage:WaitForChild("AttackEvent")

local ATTACK_COOLDOWN = 0.5
local lastAttack      = 0

-- Raycast parameters: only consider parts inside workspace.Players
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local function getPlayersFolder()
	return Workspace:FindFirstChild("Players")
end

-- Returns the MC player username if the camera ray hits a player model, else nil.
local function getMCPlayerTarget()
	local folder = getPlayersFolder()
	if not folder or #folder:GetChildren() == 0 then return nil end

	rayParams.FilterDescendantsInstances = { folder }

	local camera  = Workspace.CurrentCamera
	local mouse   = player:GetMouse()
	local unitRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local result  = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 60, rayParams)
	if not result then return nil end

	-- Walk up to find the direct child of the Players folder
	local part = result.Instance
	local model = part.Parent
	while model and model.Parent ~= folder do
		model = model.Parent
	end
	if not model or model.Parent ~= folder then return nil end

	local gui   = model:FindFirstChildOfClass("BillboardGui")
	if not gui then return nil end
	local label = gui:FindFirstChildOfClass("TextLabel")
	return label and label.Text or nil
end

-- Visual crosshair: highlight cursor red when hovering over a MC player
local crosshairHighlight = false
RunService.RenderStepped:Connect(function()
	local hovering = getMCPlayerTarget() ~= nil
	if hovering ~= crosshairHighlight then
		crosshairHighlight = hovering
		-- Change mouse icon to signal a valid target (red dot = can attack)
		player:GetMouse().Icon = hovering and "rbxasset://textures/Cursors/CrossCursor.png" or ""
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

	local now = tick()
	if now - lastAttack < ATTACK_COOLDOWN then return end

	local targetName = getMCPlayerTarget()
	if targetName then
		lastAttack = now
		attackEvent:FireServer(targetName)
	end
end)
