-- Shows the Roblox player's Minecraft inventory in a hotbar/grid GUI.
-- Polls /inventory/:username on the Java server and renders slots.
-- Items are picked up automatically in Minecraft when the Roblox player breaks blocks.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService") -- not available in LocalScript; uses RemoteFunction
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- We can't call HttpService from a LocalScript, so we use a RemoteFunction
-- that the server evaluates and returns the result.
local inventoryFetch = ReplicatedStorage:WaitForChild("InventoryFetch", 10)
if not inventoryFetch then
	warn("InventoryUI: InventoryFetch RemoteFunction not found — inventory will not display.")
	return
end

-- ── Build the GUI ─────────────────────────────────────────────────────────────

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "InventoryUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- Hotbar: 9 slots across the bottom of the screen
local SLOT_SIZE = 60
local SLOT_PAD  = 6
local SLOTS     = 9
local hotbarWidth = SLOTS * (SLOT_SIZE + SLOT_PAD) - SLOT_PAD

local hotbarFrame = Instance.new("Frame")
hotbarFrame.Name = "Hotbar"
hotbarFrame.Size = UDim2.new(0, hotbarWidth, 0, SLOT_SIZE + SLOT_PAD * 2)
hotbarFrame.Position = UDim2.new(0.5, -hotbarWidth / 2, 1, -(SLOT_SIZE + SLOT_PAD * 3))
hotbarFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
hotbarFrame.BackgroundTransparency = 0.25
hotbarFrame.BorderSizePixel = 0
hotbarFrame.Parent = screenGui

-- Full inventory toggle button
local toggleBtn = Instance.new("TextButton")
toggleBtn.Name = "ToggleInventory"
toggleBtn.Size = UDim2.new(0, 120, 0, 32)
toggleBtn.Position = UDim2.new(0.5, -60, 1, -(SLOT_SIZE + SLOT_PAD * 3) - 40)
toggleBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
toggleBtn.BackgroundTransparency = 0.2
toggleBtn.TextColor3 = Color3.new(1, 1, 1)
toggleBtn.Text = "Inventory [E]"
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 14
toggleBtn.BorderSizePixel = 0
toggleBtn.Parent = screenGui

-- Full inventory grid (3 rows × 9 columns, slots 9-35)
local ROWS = 3
local invWidth = SLOTS * (SLOT_SIZE + SLOT_PAD) - SLOT_PAD
local invHeight = ROWS * (SLOT_SIZE + SLOT_PAD) - SLOT_PAD
local invFrame = Instance.new("Frame")
invFrame.Name = "FullInventory"
invFrame.Size = UDim2.new(0, invWidth + SLOT_PAD * 2, 0, invHeight + SLOT_PAD * 2)
invFrame.Position = UDim2.new(0.5, -(invWidth / 2 + SLOT_PAD), 1,
	-(SLOT_SIZE + SLOT_PAD * 3) - invHeight - SLOT_PAD * 4 - 44)
invFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
invFrame.BackgroundTransparency = 0.25
invFrame.BorderSizePixel = 0
invFrame.Visible = false
invFrame.Parent = screenGui

-- Create slot frames
local slotFrames = {}  -- slot index → Frame

local function makeSlot(parent, slotIndex, col, row, yBase)
	local frame = Instance.new("Frame")
	frame.Name = "Slot_" .. slotIndex
	frame.Size = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE)
	frame.Position = UDim2.new(0, SLOT_PAD + col * (SLOT_SIZE + SLOT_PAD),
		0, yBase + row * (SLOT_SIZE + SLOT_PAD))
	frame.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	frame.BackgroundTransparency = 0.3
	frame.BorderSizePixel = 0
	frame.Parent = parent

	local label = Instance.new("TextLabel")
	label.Name = "ItemLabel"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Text = ""
	label.Font = Enum.Font.GothamBold
	label.TextWrapped = true
	label.Parent = frame

	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "CountLabel"
	countLabel.Size = UDim2.new(0.5, 0, 0.3, 0)
	countLabel.Position = UDim2.new(0.5, 0, 0.7, 0)
	countLabel.BackgroundTransparency = 1
	countLabel.TextColor3 = Color3.new(1, 1, 0)
	countLabel.TextScaled = true
	countLabel.Text = ""
	countLabel.Font = Enum.Font.GothamBold
	countLabel.Parent = frame

	slotFrames[slotIndex] = frame
	return frame
end

-- Hotbar slots (indices 0-8)
for i = 0, 8 do
	makeSlot(hotbarFrame, i, i, 0, SLOT_PAD)
end

-- Main inventory slots (indices 9-35)
for slot = 9, 35 do
	local col = (slot - 9) % 9
	local row = math.floor((slot - 9) / 9)
	makeSlot(invFrame, slot, col, row, SLOT_PAD)
end

-- ── Toggle inventory ──────────────────────────────────────────────────────────

local invOpen = false
toggleBtn.MouseButton1Click:Connect(function()
	invOpen = not invOpen
	invFrame.Visible = invOpen
end)

-- ── Poll inventory and update slots ──────────────────────────────────────────

local function clearSlot(slotIndex)
	local frame = slotFrames[slotIndex]
	if not frame then return end
	frame.ItemLabel.Text = ""
	frame.CountLabel.Text = ""
	frame.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
end

local function updateSlot(slotIndex, itemName, count)
	local frame = slotFrames[slotIndex]
	if not frame then return end
	-- Shorten item name (strip MINECRAFT_ prefix-style names, underscore→space)
	local display = itemName:gsub("_", " "):lower():gsub("^%l", string.upper)
	if #display > 12 then display = display:sub(1, 12) .. "…" end
	frame.ItemLabel.Text = display
	frame.CountLabel.Text = count > 1 and tostring(count) or ""
	frame.BackgroundColor3 = Color3.fromRGB(80, 100, 80)
end

-- Clear all slots
local function clearAllSlots()
	for i = 0, 35 do clearSlot(i) end
end

-- Poll every second (inventory changes infrequently)
local username = player.Name
while task.wait(1) do
	local ok, result = pcall(function()
		return inventoryFetch:InvokeServer(username)
	end)

	if ok and result then
		clearAllSlots()
		for _, entry in ipairs(result) do
			updateSlot(entry.slot, entry.item, entry.count)
		end
	end
end
