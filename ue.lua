--[[
=====================================================================
   RIVALS  |  CLEAN RAGE / SILENT AIM / ESP HUB
   Works on: Delta / Solara / Madium / Wave / Arceus / Xeno / Fluxus
   PvP + Zombie Tower (PvE) support - keyless - no UI library
=====================================================================
]]

if _G.RIVALS_HUB and _G.RIVALS_HUB.Unload then
	pcall(_G.RIVALS_HUB.Unload)
end

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace        = game:GetService("Workspace")
local Lighting         = game:GetService("Lighting")
local VirtualUser      = game:GetService("VirtualUser")

local LP    = Players.LocalPlayer
local MOUSE = LP:GetMouse()

local Config = {
	Aimbot      = false,
	AutoFire    = false,
	Hitbox      = "Head",
	AimFOV      = 30,
	Smoothness  = 4,
	Prediction  = 0.15,
	FireDelay   = 0.08,
	VisibleOnly = false,

	SilentAim    = false,
	SilentHitbox = "Head",
	SilentFOV    = 90,

	TargetNPCs = true,
	TeamCheck  = true,
	Priority   = "Distance",

	ESP         = false,
	ESPBox      = true,
	ESPName     = true,
	ESPDistance = true,
	ESPHealth   = true,
	ESPTracer   = true,
	ESPNPC      = true,
	ESPMaxDist  = 500,

	FOVCircle = true,
	CameraFOV = 0,
	Fullbright = false,
}

local Hub = {
	Running = true,
	Current = nil,
	AimPos  = nil,
	ESP     = {},
	OldIndex = nil,
	OldNamecall = nil,
	Gui = nil,
}
_G.RIVALS_HUB = Hub

local HITBOXES  = {"Head", "Body", "Nearest"}
local PRIORITIES = {"Distance", "Health", "Crosshair"}
local SKINS = {
	{name = "Default",  color = nil},
	{name = "Gold",     color = Color3.fromRGB(255, 200, 60)},
	{name = "Cyan",     color = Color3.fromRGB(60, 230, 255)},
	{name = "Magenta",  color = Color3.fromRGB(255, 60, 220)},
	{name = "Lime",     color = Color3.fromRGB(120, 255, 80)},
	{name = "Blood",    color = Color3.fromRGB(200, 25, 25)},
	{name = "Void",     color = Color3.fromRGB(25, 25, 35)},
	{name = "Ice",      color = Color3.fromRGB(220, 240, 255)},
}
local skinIndex = 1
local skinOriginals = {}

--=============================================================
--  UTILITIES
--=============================================================
local function getChar()
	local char = LP.Character
	if not char then return nil end
	local root = char:FindFirstChild("HumanoidRootPart")
	local hum  = char:FindFirstChildOfClass("Humanoid")
	if root and hum and hum.Health > 0 then return char, root, hum end
	return nil
end

local function clamp(v, a, b)
	return math.max(a, math.min(b, v))
end

local function isSameTeam(plr)
	if not Config.TeamCheck then return false end
	local mine = LP.Team
	local theirs = plr.Team
	if mine and theirs then return mine == theirs end
	return false
end

--=============================================================
--  TARGETING
--=============================================================
local function collectNPCs()
	local out = {}
	local myChar = LP.Character

	local function scan(container)
		for _, m in ipairs(container:GetChildren()) do
			if m:IsA("Model") and m ~= myChar and not Players:GetPlayerFromCharacter(m) then
				local hum  = m:FindFirstChildOfClass("Humanoid")
				local root = m:FindFirstChild("HumanoidRootPart")
				if hum and root and hum.Health > 0 then
					table.insert(out, {model = m, humanoid = hum, root = root, isNPC = true})
				elseif (m:IsA("Folder") or m:IsA("Model")) and not hum then
					for _, c in ipairs(m:GetChildren()) do
						if c:IsA("Model") and c ~= myChar
							and not Players:GetPlayerFromCharacter(c) then
							local h2 = c:FindFirst
