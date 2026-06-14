-- Receives MC server events relayed by EventRelay.Script and renders them as
-- vanilla-Minecraft-style UI: titles, subtitles, actionbar, and a health bar.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player   = Players.LocalPlayer
local gui      = player:WaitForChild("PlayerGui")
local gameEvent = ReplicatedStorage:WaitForChild("GameEvent")

-- ── Build ScreenGui ────────────────────────────────────────────────────────

local screen = Instance.new("ScreenGui")
screen.Name            = "MCEventUI"
screen.ResetOnSpawn    = false
screen.IgnoreGuiInset  = true
screen.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
screen.Parent          = gui

local function makeLabel(name, size, anchorPoint, position, textSize)
	local lbl = Instance.new("TextLabel")
	lbl.Name                   = name
	lbl.Size                   = size
	lbl.AnchorPoint            = anchorPoint
	lbl.Position               = position
	lbl.BackgroundTransparency = 1
	lbl.TextColor3             = Color3.new(1, 1, 1)
	lbl.TextStrokeTransparency = 0.5
	lbl.TextStrokeColor3       = Color3.new(0, 0, 0)
	lbl.TextScaled             = true
	lbl.Font                   = Enum.Font.GothamBold
	lbl.TextTransparency       = 1  -- start hidden
	lbl.Text                   = ""
	lbl.Parent                 = screen
	return lbl
end

-- Title: large text centered at ~40% height
local titleLabel    = makeLabel("Title",
	UDim2.new(0.8, 0, 0.1, 0),
	Vector2.new(0.5, 0.5),
	UDim2.new(0.5, 0, 0.38, 0),
	48)

-- Subtitle: smaller text just below title
local subtitleLabel = makeLabel("Subtitle",
	UDim2.new(0.6, 0, 0.06, 0),
	Vector2.new(0.5, 0.5),
	UDim2.new(0.5, 0, 0.48, 0),
	28)

-- Actionbar: anchored near bottom center (above hotbar)
local actionbarLabel = makeLabel("Actionbar",
	UDim2.new(0.5, 0, 0.04, 0),
	Vector2.new(0.5, 0.5),
	UDim2.new(0.5, 0, 0.88, 0),
	22)

-- Health bar (bottom-left corner, 10 hearts = 20 HP)
local healthFrame = Instance.new("Frame")
healthFrame.Name                = "HealthBar"
healthFrame.Size                = UDim2.new(0, 202, 0, 14)
healthFrame.Position            = UDim2.new(0, 10, 1, -50)
healthFrame.AnchorPoint         = Vector2.new(0, 1)
healthFrame.BackgroundColor3    = Color3.fromRGB(30, 30, 30)
healthFrame.BorderSizePixel     = 0
healthFrame.Parent              = screen

local healthFill = Instance.new("Frame")
healthFill.Name             = "Fill"
healthFill.Size             = UDim2.new(1, 0, 1, 0)
healthFill.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
healthFill.BorderSizePixel  = 0
healthFill.Parent           = healthFrame

local healthText = Instance.new("TextLabel")
healthText.Size                   = UDim2.new(1, 0, 1, 0)
healthText.BackgroundTransparency = 1
healthText.TextColor3             = Color3.new(1, 1, 1)
healthText.TextStrokeTransparency = 0.4
healthText.TextStrokeColor3       = Color3.new(0, 0, 0)
healthText.Text                   = ""
healthText.Font                   = Enum.Font.GothamBold
healthText.TextScaled             = true
healthText.Parent                 = healthFrame

-- ── Tween helpers ─────────────────────────────────────────────────────────

local FADE_IN  = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function fadeIn(lbl)
	TweenService:Create(lbl, FADE_IN, { TextTransparency = 0 }):Play()
end

local function fadeOut(lbl)
	TweenService:Create(lbl, FADE_OUT, { TextTransparency = 1 }):Play()
end

-- ── Title / subtitle display ───────────────────────────────────────────────

local titleThread    = nil
local subtitleThread = nil
local TITLE_STAY     = 3.5  -- seconds visible before fade-out

local function showLabel(lbl, text, threadRef)
	lbl.Text = text
	fadeIn(lbl)
	if threadRef[1] then task.cancel(threadRef[1]) end
	threadRef[1] = task.delay(TITLE_STAY, function()
		fadeOut(lbl)
	end)
end

local titleThreadRef    = { nil }
local subtitleThreadRef = { nil }

-- ── Actionbar display ─────────────────────────────────────────────────────

local actionbarThread = { nil }
local ACTIONBAR_STAY  = 3.0

local function showActionbar(text)
	actionbarLabel.Text = text
	fadeIn(actionbarLabel)
	if actionbarThread[1] then task.cancel(actionbarThread[1]) end
	actionbarThread[1] = task.delay(ACTIONBAR_STAY, function()
		fadeOut(actionbarLabel)
	end)
end

-- ── Health display ────────────────────────────────────────────────────────

local function updateHealth(healthStr)
	local hp = tonumber(healthStr)
	if not hp then return end
	local ratio = math.clamp(hp / 20, 0, 1)
	healthFill.Size = UDim2.new(ratio, 0, 1, 0)
	healthText.Text = string.format("%.1f / 20", hp)
	-- Color shifts red → orange → yellow as health gets low
	if ratio < 0.25 then
		healthFill.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
	elseif ratio < 0.5 then
		healthFill.BackgroundColor3 = Color3.fromRGB(220, 140, 40)
	else
		healthFill.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
	end
end

-- ── Death screen ──────────────────────────────────────────────────────────

local deathScreen = Instance.new("Frame")
deathScreen.Name                 = "DeathScreen"
deathScreen.Size                 = UDim2.new(1, 0, 1, 0)
deathScreen.BackgroundColor3     = Color3.fromRGB(80, 0, 0)
deathScreen.BackgroundTransparency = 0.35
deathScreen.ZIndex               = 10
deathScreen.Visible              = false
deathScreen.Parent               = screen

local deathTitle = Instance.new("TextLabel")
deathTitle.Size                   = UDim2.new(1, 0, 0.15, 0)
deathTitle.Position               = UDim2.new(0, 0, 0.33, 0)
deathTitle.BackgroundTransparency = 1
deathTitle.Text                   = "You Died!"
deathTitle.TextColor3             = Color3.new(1, 1, 1)
deathTitle.TextStrokeTransparency = 0.4
deathTitle.TextStrokeColor3       = Color3.new(0, 0, 0)
deathTitle.Font                   = Enum.Font.GothamBold
deathTitle.TextScaled             = true
deathTitle.ZIndex                 = 11
deathTitle.Parent                 = deathScreen

local respawnBtn = Instance.new("TextButton")
respawnBtn.Size                   = UDim2.new(0.25, 0, 0.07, 0)
respawnBtn.AnchorPoint            = Vector2.new(0.5, 0.5)
respawnBtn.Position               = UDim2.new(0.5, 0, 0.54, 0)
respawnBtn.BackgroundColor3       = Color3.fromRGB(60, 60, 60)
respawnBtn.BackgroundTransparency = 0.2
respawnBtn.Text                   = "Respawn"
respawnBtn.TextColor3             = Color3.new(1, 1, 1)
respawnBtn.TextStrokeTransparency = 0.5
respawnBtn.Font                   = Enum.Font.GothamBold
respawnBtn.TextScaled             = true
respawnBtn.ZIndex                 = 11
respawnBtn.Parent                 = deathScreen

-- Wire up the button in a separate thread so WaitForChild can't block
-- the rest of the event handler (titles, health) if the server script loads slowly.
task.spawn(function()
	local respawnEvent = ReplicatedStorage:WaitForChild("RespawnEvent")
	respawnBtn.MouseButton1Click:Connect(function()
		deathScreen.Visible = false
		respawnEvent:FireServer()
	end)
end)

-- ── Event dispatcher ───────────────────────────────────────────────────────

gameEvent.OnClientEvent:Connect(function(evtType, evtData)
	if evtType == "title" then
		showLabel(titleLabel, evtData, titleThreadRef)
	elseif evtType == "subtitle" then
		showLabel(subtitleLabel, evtData, subtitleThreadRef)
	elseif evtType == "actionbar" then
		showActionbar(evtData)
	elseif evtType == "health" then
		updateHealth(evtData)
	elseif evtType == "death" then
		deathScreen.Visible = true
	end
end)
