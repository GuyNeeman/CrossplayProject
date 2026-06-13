local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local attackEvent = ReplicatedStorage:WaitForChild("AttackEvent")
local breakEvent = ReplicatedStorage:WaitForChild("BlockBrokenEvent")

-- Returns the Minecraft player name if the mouse is over a MC player model,
-- or nil if it's pointing at something else.
local function getMCPlayerTarget()
	local mouse = player:GetMouse()
	local target = mouse.Target
	if not target then return nil end

	-- MC player models live in workspace.Players (folder named "Players")
	local model = target.Parent
	if not model then return nil end

	local playersFolder = workspace:FindFirstChild("Players")
	if model.Parent ~= playersFolder then return nil end

	-- Get the username from the BillboardGui name label
	local gui = model:FindFirstChildOfClass("BillboardGui")
	if not gui then return nil end
	local label = gui:FindFirstChildOfClass("TextLabel")
	return label and label.Text or nil
end

local ATTACK_COOLDOWN = 0.5
local lastAttack = 0

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
