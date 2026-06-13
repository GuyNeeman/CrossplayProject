local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "CoordinatesGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 160, 0, 58)
frame.Position = UDim2.new(0, 8, 1, -66)
frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
frame.BackgroundTransparency = 0.4
frame.BorderSizePixel = 0
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 4)
corner.Parent = frame

local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, -8, 1, -8)
label.Position = UDim2.new(0, 4, 0, 4)
label.BackgroundTransparency = 1
label.TextColor3 = Color3.new(1, 1, 1)
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextYAlignment = Enum.TextYAlignment.Top
label.Font = Enum.Font.Code
label.TextSize = 13
label.RichText = true
label.Parent = frame

RunService.RenderStepped:Connect(function()
	local character = player.Character
	if not character then
		label.Text = "<font color='#ff4444'>No character</font>"
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local mcX = math.floor(hrp.Position.X / 3)
	local mcY = math.floor(hrp.Position.Y / 3)
	local mcZ = math.floor(hrp.Position.Z / 3)

	label.Text = string.format(
		"<font color='#ff6666'>X</font> %d  <font color='#66ff66'>Y</font> %d  <font color='#6666ff'>Z</font> %d",
		mcX, mcY, mcZ
	)
end)
