local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Build the HUD
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ConnectionStatus"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 10
screenGui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Name = "StatusFrame"
frame.Size = UDim2.new(0, 220, 0, 90)
frame.Position = UDim2.new(0, 8, 0, 8)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
frame.BackgroundTransparency = 0.35
frame.BorderSizePixel = 0
frame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 6)
corner.Parent = frame

local function makeLabel(yPos, text)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -10, 0, 20)
	lbl.Position = UDim2.new(0, 6, 0, yPos)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = Color3.new(1, 1, 1)
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Font = Enum.Font.Code
	lbl.TextSize = 13
	lbl.Text = text
	lbl.RichText = true
	lbl.Parent = frame
	return lbl
end

local connLabel    = makeLabel(4,  "<font color='#aaaaaa'>Server:</font> waiting…")
local blocksLabel  = makeLabel(26, "<font color='#aaaaaa'>Blocks:</font> 0")
local playersLabel = makeLabel(48, "<font color='#aaaaaa'>MC Players:</font> 0")
local pingLabel    = makeLabel(68, "<font color='#aaaaaa'>Ping:</font> —")

-- Count blocks in workspace
local function countBlocks()
	local blocksFolder = workspace:FindFirstChild("Blocks")
	if not blocksFolder then return 0 end
	local count = 0
	for _ in pairs(blocksFolder:GetChildren()) do count = count + 1 end
	return count
end

-- Count Minecraft player models in workspace.Players
local function countMCPlayers()
	local playersFolder = workspace:FindFirstChild("Players")
	if not playersFolder then return 0 end
	local count = 0
	for _ in pairs(playersFolder:GetChildren()) do count = count + 1 end
	return count
end

-- Listen for status from the server-side ConnectionChecker script
-- (LocalScripts cannot use HttpService, so the server pings and fires this event)
local statusEvent = ReplicatedStorage:WaitForChild("ServerStatusEvent", 10)
if statusEvent then
	statusEvent.OnClientEvent:Connect(function(ok, ms)
		if ok then
			connLabel.Text = "<font color='#aaaaaa'>Server:</font> <font color='#00ff88'>Online</font>"
			pingLabel.Text = "<font color='#aaaaaa'>Ping:</font> " .. ms .. " ms"
		else
			connLabel.Text = "<font color='#aaaaaa'>Server:</font> <font color='#ff4444'>Offline</font>"
			pingLabel.Text = "<font color='#aaaaaa'>Ping:</font> <font color='#ff4444'>—</font>"
		end
	end)
else
	connLabel.Text = "<font color='#aaaaaa'>Server:</font> <font color='#ffaa00'>No checker</font>"
end

-- Update block and player counts every frame
RunService.Heartbeat:Connect(function()
	blocksLabel.Text  = "<font color='#aaaaaa'>Blocks:</font> " .. countBlocks()
	playersLabel.Text = "<font color='#aaaaaa'>MC Players:</font> " .. countMCPlayers()
end)
