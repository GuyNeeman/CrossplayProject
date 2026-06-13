-- Sends a BREAK request to /post when the Roblox player left-clicks a block while
-- breaking mode is enabled. Walks up the model tree to find the block root so nested
-- model structures (multi-part blocks) work correctly.
local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player      = Players.LocalPlayer
local remoteEvent = ReplicatedStorage:WaitForChild("BlockBrokenEvent")

local modifyModeGui = player:WaitForChild("PlayerGui"):WaitForChild("ModifyMode")
local breakButton   = modifyModeGui:WaitForChild("Frame"):WaitForChild("Break")

local isBreakingEnabled = false

breakButton.MouseButton1Click:Connect(function()
	isBreakingEnabled = not isBreakingEnabled
	breakButton.Text = isBreakingEnabled and "Breaking Enabled" or "Breaking Disabled"
	breakButton.BackgroundColor3 = isBreakingEnabled
		and Color3.fromRGB(80, 160, 80)
		or  Color3.fromRGB(80, 80, 80)
end)

-- Walk up the instance tree to find the direct child of workspace.Blocks.
-- This handles multi-part block models where the clicked part is a descendant,
-- not a direct child, of the model root.
local function getBlockModel(part)
	local blocksFolder = Workspace:FindFirstChild("Blocks")
	if not blocksFolder then return nil end
	local current = part
	while current and current.Parent ~= blocksFolder do
		current = current.Parent
		if current == Workspace or current == nil then return nil end
	end
	return (current and current.Parent == blocksFolder) and current or nil
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if not isBreakingEnabled then return end

	local target = player:GetMouse().Target
	if not target then return end

	local block = getBlockModel(target)
	if not block then return end

	local primary = block.PrimaryPart
	if not primary then return end

	remoteEvent:FireServer(primary.Position)
end)
