local h2 = c:FindFirstChildOfClass("Humanoid")
							local r2 = c:FindFirstChild("HumanoidRootPart")
							if h2 and r2 and h2.Health > 0 then
								table.insert(out, {model = c, humanoid = h2, root = r2, isNPC = true})
							end
						end
					end
				end
			end
		end
	end
	scan(Workspace)
	return out
end

local function getTargets()
	local list = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP and not isSameTeam(plr) then
			local char = plr.Character
			if char then
				local hum  = char:FindFirstChildOfClass("Humanoid")
				local root = char:FindFirstChild("HumanoidRootPart")
				if hum and root and hum.Health > 0 then
					table.insert(list, {model = char, humanoid = hum, root = root, isNPC = false, player = plr})
				end
			end
		end
	end
	if Config.TargetNPCs then
		for _, t in ipairs(collectNPCs()) do
			table.insert(list, t)
		end
	end
	return list
end

local function getAimPart(target, mode)
	local model = target.model
	if mode == "Head" then
		return model:FindFirstChild("Head") or target.root
	elseif mode == "Body" then
		return model:FindFirstChild("UpperTorso")
			or model:FindFirstChild("Torso")
			or target.root
	end
	local cam = Workspace.CurrentCamera
	if not cam then return target.root end
	local best, bestAng
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			local dir = p.Position - cam.CFrame.Position
			if dir.Magnitude > 0.01 then
				local ang = math.deg(math.acos(clamp(cam.CFrame.LookVector:Dot(dir.Unit), -1, 1)))
				if not best or ang < bestAng then
					best, bestAng = p, ang
				end
			end
		end
	end
	return best or target.root
end

local function isVisible(target)
	local cam = Workspace.CurrentCamera
	if not cam then return true end
	local origin = cam.CFrame.Position
	local pos    = target.root.Position
	local dir    = pos - origin
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {LP.Character, target.model}
	local hit = Workspace:Raycast(origin, dir, params)
	return hit == nil or (hit.Position - origin).Magnitude >= dir.Magnitude - 0.75
end

local function selectTarget(fov)
	local cam = Workspace.CurrentCamera
	if not cam then return nil end
	local origin = cam.CFrame.Position
	local look   = cam.CFrame.LookVector

	local best, bestScore
	for _, t in ipairs(getTargets()) do
		local pos = t.root.Position
		local dir = pos - origin
		if dir.Magnitude > 0.01 then
			local ang = math.deg(math.acos(clamp(look:Dot(dir.Unit), -1, 1)))
			if ang <= fov then
				local score
				if Config.Priority == "Health" then
					score = t.humanoid.Health
				elseif Config.Priority == "Crosshair" then
					score = ang
				else
					score = dir.Magnitude
				end
				if not best or score < bestScore then
					best, bestScore = t, score
				end
			end
		end
	end
	return best
end

--=============================================================
--  SILENT AIM HOOKS
--=============================================================
local function installHooks()
	local getmt = (type(getrawmetatable) == "function") and getrawmetatable or getmetatable
	local mt = getmt(game)
	if not mt then return end

	local guard = function(fn)
		if type(newcclosure) == "function" then
			local ok, c = pcall(newcclosure, fn)
			if ok then return c end
		end
		return fn
	end

	if type(setreadonly) == "function" then pcall(setreadonly, mt, false) end

	Hub.OldNamecall = mt.__namecall
	if type(mt.__namecall) == "function" then
		local old = mt.__namecall
		mt.__namecall = guard(function(self, ...)
			local method = (type(getnamecallmethod) == "function") and getnamecallmethod() or nil
			if method and Config.SilentAim and Hub.Current and Hub.AimPos then
				local cam = Workspace.CurrentCamera
				if method == "Raycast" and self == Workspace then
					local origin, direction, params = ...
					if type(origin) == "Vector3" and type(direction) == "Vector3" then
						local toTarget = Hub.AimPos - origin
						if toTarget.Magnitude > 0.01 then
							local len = math.max(direction.Magnitude, toTarget.Magnitude)
							return old(self, origin, toTarget.Unit * len, params)
						end
					end
				elseif (method == "ViewportPointToRay" or method == "ScreenPointToRay")
					and cam and self == cam then
					local dir = Hub.AimPos - cam.CFrame.Position
					if dir.Magnitude > 0.01 then
						return Ray.new(cam.CFrame.Position, dir.Unit)
					end
				end
			end
			return old(self, ...)
		end)
	end

	Hub.OldIndex = mt.__index
	if type(mt.__index) == "function" then
		local old = mt.__index
		mt.__index = guard(function(self, key)
			if Config.SilentAim and Hub.Current and Hub.AimPos and self == MOUSE then
				if key == "Hit" then
					return CFrame.new(Hub.AimPos)
				elseif key == "Target" then
					return Hub.Current.model
				elseif key == "UnitRay" then
					local dir = Hub.AimPos - Workspace.CurrentCamera.CFrame.Position
					return Ray.new(Workspace.CurrentCamera.CFrame.Position, dir.Unit)
				end
			end
			return old(self, key)
		end)
	end

	if type(setreadonly) == "function" then pcall(setreadonly, mt, true) end
end

local function removeHooks()
	local getmt = (type(getrawmetatable) == "function") and getrawmetatable or getmetatable
	local mt = getmt(game)
	if not mt then return end
	if type(setreadonly) == "function" then pcall(setreadonly, mt, false) end
	if Hub.OldNamecall then mt.__namecall = Hub.OldNamecall end
	if Hub.OldIndex then mt.__index = Hub.OldIndex end
	if type(setreadonly) == "function" then pcall(setreadonly, mt, true) end
end

--=============================================================
--  ESP
--=============================================================
local useDrawing = (type(Drawing) == "table" and type(Drawing.new) == "function")

local function newDrawing(class)
	if not useDrawing then return nil end
	local ok, obj = pcall(Drawing.new, class)
	if ok then return obj end
	return nil
end

local function createESP()
	local e = {}
	if useDrawing then
		e.box    = newDrawing("Square")
		e.name   = newDrawing("Text")
		e.dist   = newDrawing("Text")
		e.hpbg   = newDrawing("Square")
		e.hpfill = newDrawing("Square")
		e.tracer = newDrawing("Line")
		if e.box then
			e.box.Filled    = false
			e.box.Thickness = 1
		end
		if e.hpbg then
			e.hpbg.Filled = true
			e.hpbg.Color  = Color3.fromRGB(20, 20, 20)
		end
		if e.hpfill then e.hpfill.Filled = true end
		if e.name then
			e.name.Center  = true
			e.name.Outline = true
			e.name.Size    = 14
		end
		if e.dist then
			e.dist.Center  = true
			e.dist.Outline = true
			e.dist.Size    = 13
		end
		if e.tracer then e.tracer.Thickness = 1 end
	else
		local hl = Instance.new("Highlight")
		hl.Name = "RIVALS_ESP"
		hl.FillTransparency = 0.6
		hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		e.hl = hl
	end
	return e
end

local function removeESP(e)
	if not e then return end
	for _, key in ipairs({"box", "name", "dist", "hpbg", "hpfill", "tracer"}) do
		local obj = e[key]
		if obj then pcall(function() obj:Remove() end) end
	end
	if e.hl and e.hl.Parent then e.hl:Destroy() end
end

local function clearESP()
	for model, e in pairs(Hub.ESP) do
		removeESP(e)
	end
	Hub.ESP = {}
end

--=============================================================
--  SKIN CHANGER
--=============================================================
local function getWeapon()
	local char = LP.Character
	if char then
		local tool = char:FindFirstChildOfClass("Tool")
		if tool then return tool end
	end
	local cam = Workspace.CurrentCamera
	if cam then
		for _, d in ipairs(cam:GetChildren()) do
			if d:IsA("Model") then return d end
		end
	end
	return nil
end

local function applySkin()
	local weapon = getWeapon()
	if not weapon then return end
	local skin = SKINS[skinIndex]
	for _, d in ipairs(weapon:GetDescendants()) do
		if d:IsA("BasePart") then
			if skinOriginals[d] == nil then skinOriginals[d] = d.Color end
			d.Color = skin.color or skinOriginals[d]
		end
	end
end

--=============================================================
--  GUI
--=============================================================
local function buildGui()
	local gui = Instance.new("ScreenGui")
	gui.Name           = "Rivals_Hub"
	gui.ResetOnSpawn   = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local ok = pcall(function() gui.Parent = gethui() end)
	if not ok then gui.Parent = LP:WaitForChild("PlayerGui") end

	local main = Instance.new("Frame")
	main.Name             = "Main"
	main.Size             = UDim2.new(0, 262, 0, 430)
	main.Position         = UDim2.new(0, 24, 0.5, -215)
	main.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
	main.BorderSizePixel  = 0
	main.Active           = true
	main.Parent           = gui

	local mc = Instance.new("UICorner"); mc.CornerRadius = UDim.new(0, 10); mc.Parent = main
	local ms = Instance.new("UIStroke")
	ms.Color = Color3.fromRGB(255, 80, 80); ms.Thickness = 1; ms.Transparency = 0.35
	ms.Parent = main

	local bar = Instance.new("Frame")
	bar.Size             = UDim2.new(1, 0, 0, 34)
	bar.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
	bar.BorderSizePixel  = 0
	bar.Active           = true
	bar.Parent           = main
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 10); bc.Parent = bar

	local title = Instance.new("TextLabel")
	title.Size             = UDim2.new(1, -40, 1, 0)
	title.Position         = UDim2.new(0, 12, 0, 0)
	title.BackgroundTransparency = 1
	title.Text             = "RIVALS  |  RAGE HUB"
	title.Font             = Enum.Font.GothamBold
	title.TextSize         = 13
	title.TextColor3       = Color3.fromRGB(255, 90, 90)
	title.TextXAlignment   = Enum.TextXAlignment.Left
	title.Parent           = bar

	local minBtn = Instance.new("TextButton")
	minBtn.Size             = UDim2.new(0, 24, 0, 24)
	minBtn.Position         = UDim2.new(1, -30, 0, 5)
	minBtn.BackgroundColor3 = Color3.fromRGB(42, 42, 52)
	minBtn.Text             = "-"
	minBtn.Font             = Enum.Font.GothamBold
	minBtn.TextSize         = 16
	minBtn.TextColor3       = Color3.new(1, 1, 1)
	minBtn.BorderSizePixel  = 0
	minBtn.AutoButtonColor  = false
	minBtn.Parent           = bar
	local mc2 = Instance.new("UICorner"); mc2.CornerRadius = UDim.new(0, 6); mc2.Parent = minBtn

	local list = Instance.new("ScrollingFrame")
	list.Size                = UDim2.new(1, -16, 1, -44)
	list.Position            = UDim2.new(0, 8, 0, 38)
	list.BackgroundTransparency = 1
	list.BorderSizePixel     = 0
	list.ScrollBarThickness  = 4
	list.ScrollBarImageColor3 = Color3.fromRGB(255, 90, 90)
	list.CanvasSize          = UDim2.new(0, 0, 0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent              = main

	local layout = Instance.new("UIListLayout")
	layout.Padding   = UDim.new(0, 5)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent    = list

	local order = 0

	local function addSection(text)
		order += 1
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, -8, 0, 22)
		lbl.BackgroundTransparency = 1
		lbl.Text = text
		lbl.Font = Enum.Font.GothamBold
		lbl.TextSize = 12
		lbl.TextColor3 = Color3.fromRGB(255, 100, 100)
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.LayoutOrder = order
		lbl.Parent = list
	end

	local function addToggle(label, key)
		order += 1
		local btn = Instance.new("TextButton")
		btn.Size             = UDim2.new(1, -8, 0, 28)
		btn.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
		btn.Text             = label .. "   [ OFF ]"
		btn.Font             = Enum.Font.Gotham
		btn.TextSize         = 12
		btn.TextColor3       = Color3.fromRGB(220, 220, 230)
		btn.BorderSizePixel  = 0
		btn.AutoButtonColor  = false
		btn.LayoutOrder      = order
		btn.Parent           = list
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = btn

		local state = Config[key] == true
		local function render()
			btn.Text             = label .. (state and "   [ ON ]" or "   [ OFF ]")
			btn.BackgroundColor3 = state and Color3.fromRGB(140, 35, 45) or Color3.fromRGB(32, 32, 40)
		end
		render()
		btn.MouseButton1Click:Connect(function()
			state = not state
			Config[key] = state
			render()
		end)
		return btn
	end

	local function addCycle(label, key, options, onChange)
		order += 1
		local btn = Instance.new("TextButton")
		btn.Size             = UDim2.new(1, -8, 0, 28)
		btn.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
		btn.Text             = label .. ":  " .. tostring(Config[key])
		btn.Font             = Enum.Font.Gotham
		btn.TextSize         = 12
		btn.TextColor3       = Color3.fromRGB(220, 220, 230)
		btn.BorderSizePixel  = 0
		btn.AutoButtonColor  = false
		btn.LayoutOrder      = order
		btn.Parent           = list
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = btn

		btn.MouseButton1Click:Connect(function()
			local ix = 1
			for i, v in ipairs(options) do
				if v == Config[key] then ix = i break end
			end
			ix += 1
			if ix > #options then ix = 1 end
			Config[key] = options[ix]
			btn.Text = label .. ":  " .. tostring(options[ix])
			if onChange then pcall(onChange, options[ix]) end
		end)
		return btn
	end

	local function addSlider(label, key, min, max, fmt)
		order += 1
		local row = Instance.new("Frame")
		row.Size             = UDim2.new(1, -8, 0, 38)
		row.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
		row.BorderSizePixel  = 0
		row.LayoutOrder      = order
		row.Parent           = list
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = row

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, -16, 0, 18)
		lbl.Position = UDim2.new(0, 10, 0, 2)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.Gotham
		lbl.TextSize = 12
		lbl.TextColor3 = Color3.fromRGB(215, 215, 225)
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Parent = row

		local track = Instance.new("Frame")
		track.Size = UDim2.new(1, -20, 0, 8)
		track.Position = UDim2.new(0, 10, 1, -14)
		track.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
		track.BorderSizePixel = 0
		track.Parent = row
		local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(1, 0); tc.Parent = track

		local fill = Instance.new("Frame")
		fill.Size = UDim2.new(0, 0, 1, 0)
		fill.BackgroundColor3 = Color3.fromRGB(255, 90, 90)
		fill.BorderSizePixel = 0
		fill.Parent = track
		local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(1, 0); fc.Parent = fill

		local function setValue(v, write)
			v = clamp(v, min, max)
			if write ~= false then Config[key] = v end
			local ratio = (max > min) and ((v - min) / (max - min)) or 0
			fill.Size = UDim2.new(ratio, 0, 1, 0)
			lbl.Text = label .. ":  " .. string.format(fmt, v)
		end
		setValue(Config[key], false)

		local dragging = false
		local function fromInput(input)
			local rel = (input.Position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1)
			setValue(min + rel * (max - min))
		end
		track.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				fromInput(input)
				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then dragging = false end
				end)
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch) then
				fromInput(input)
			end
		end)
		return setValue
	end

	local function addButton(label, onClick)
		order += 1
		local btn = Instance.new("TextButton")
		btn.Size             = UDim2.new(1, -8, 0, 28)
		btn.BackgroundColor3 = Color3.fromRGB(45, 45, 56)
		btn.Text             = label
		btn.Font             = Enum.Font.GothamBold
		btn.TextSize         = 12
		btn.TextColor3       = Color3.fromRGB(255, 255, 255)
		btn.BorderSizePixel  = 0
		btn.AutoButtonColor  = false
		btn.LayoutOrder      = order
		btn.Parent           = list
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = btn
		btn.MouseButton1Click:Connect(function() pcall(onClick, btn) end)
		return btn
	end

	addSection("RAGE")
	addToggle("Aimbot", "Aimbot")
	addToggle("Auto Fire", "AutoFire")
	addCycle("Hitbox", "Hitbox", HITBOXES)
	addSlider("Aim FOV", "AimFOV", 1, 180, "%.0f deg")
	addSlider("Smoothness", "Smoothness", 1, 30, "%.1f")
	addSlider("Prediction", "Prediction", 0, 1, "%.2f")
	addSlider("Fire Delay", "FireDelay", 0.01, 0.5, "%.2fs")
	addToggle("Visible Only", "VisibleOnly")

	addSection("SILENT AIM")
	addToggle("Silent Aim", "SilentAim")
	addCycle("Silent Hitbox", "SilentHitbox", HITBOXES)
	addSlider("Silent FOV", "SilentFOV", 1, 180, "%.0f deg")

	addSection("TARGETING")
	addToggle("Target Zombies / NPCs", "TargetNPCs")
	addToggle("Team Check", "TeamCheck")
	addCycle("Priority", "Priority", PRIORITIES)

	addSection("ESP")
	addToggle("Player ESP", "ESP")
	addToggle("Boxes", "ESPBox")
	addToggle("Names", "ESPName")
	addToggle("Distance", "ESPDistance")
	addToggle("Health Bars", "ESPHealth")
	addToggle("Tracers", "ESPTracer")
	addToggle("Zombie ESP", "ESPNPC")
	addSlider("Max Distance", "ESPMaxDist", 50, 2000, "%.0f")

	addSection("VISUALS")
	addToggle("FOV Circle", "FOVCircle")
	addSlider("Camera FOV", "CameraFOV", 70, 120, "%.0f")
	addToggle("Fullbright", "Fullbright")
	addCycle("Weapon Skin", "Skin", (function()
		local names = {}
		for _, s in ipairs(SKINS) do table.insert(names, s.name) end
		return names
	end)(), function(name)
		for i, s in ipairs(SKINS) do
			if s.name == name then skinIndex = i break end
		end
		applySkin()
	end)

	addSection("MISC")
	addButton("RAGE MODE (all on)", function()
		Config.Aimbot     = true
		Config.SilentAim  = true
		Config.AutoFire   = true
		Config.TargetNPCs = true
	end)
	addButton("Unload", function() Hub.Unload() end)

	local dragging, dragStart, startPos
	bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, startPos = true, input.Position, main.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local d = input.Position - dragStart
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
				startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)

	local minimized = false
	minBtn.MouseButton1Click:Connect(function()
		minimized = not minimized
		list.Visible = not minimized
		main.Size = minimized and UDim2.new(0, 262, 0, 34) or UDim2.new(0, 262, 0, 430)
		minBtn.Text = minimized and "+" or "-"
	end)

	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.KeyCode == Enum.KeyCode.RightShift then
			main.Visible = not main.Visible
		end
	end)

	Hub.Gui = gui
end

--=============================================================
--  UNLOAD
--=============================================================
function Hub.Unload()
	Hub.Running = false
	pcall(function() RunService:UnbindFromRenderStep("RivalsHub_Render") end)
	pcall(removeHooks)
	clearESP()
	if Hub.Circle then
		pcall(function() Hub.Circle:Remove() end)
		Hub.Circle = nil
	end
	if Hub.Gui and Hub.Gui.Parent then Hub.Gui:Destroy() end
	if Workspace.CurrentCamera then Workspace.CurrentCamera.FieldOfView = 70 end
	if Hub.FBOld then
		Lighting.Brightness     = Hub.FBOld.b
		Lighting.Ambient        = Hub.FBOld.a
		Lighting.OutdoorAmbient = Hub.FBOld.o
	end
	_G.RIVALS_HUB = nil
end

--=============================================================
--  RENDER LOOP
--=============================================================
local lastFire = 0

local function onRender(dt)
	if not Hub.Running then return end

	local cam = Workspace.CurrentCamera
	local char = LP.Character
	if not cam or not char then
		Hub.Current, Hub.AimPos = nil, nil
		clearESP()
		return
	end

	local needsTarget = Config.Aimbot or Config.SilentAim or Config.AutoFire
	if needsTarget then
		local fov = math.max(Config.AimFOV, Config.SilentFOV)
		local t = selectTarget(fov)
		if t and (not Config.VisibleOnly or isVisible(t)) then
			Hub.Current = t
			local part = getAimPart(t, Config.SilentAim and Config.SilentHitbox or Config.Hitbox)
			local pos  = part and part.Position or t.root.Position
			if Config.Prediction > 0 and t.root then
				local vel = t.root.AssemblyLinearVelocity or t.root.Velocity
				local dist = (pos - cam.CFrame.Position).Magnitude
				pos = pos + vel * (dist / 1000) * Config.Prediction
			end
			Hub.AimPos = pos
		else
			Hub.Current, Hub.AimPos = nil, nil
		end
	else
		Hub.Current, Hub.AimPos = nil, nil
	end

	if Config.Aimbot and Hub.AimPos then
		local goal = CFrame.new(cam.CFrame.Position, Hub.AimPos)
		if Config.Smoothness <= 1 then
			cam.CFrame = goal
		else
			local a = clamp(1 - math.exp(-(60 / math.max(Config.Smoothness, 0.01)) * dt), 0, 1)
			cam.CFrame = cam.CFrame:Lerp(goal, a)
		end
	end

	if Config.AutoFire and Hub.Current and Hub.AimPos then
		local now = os.clock()
		if now - lastFire >= Config.FireDelay then
			lastFire = now
			if type(mouse1click) == "function" then
				pcall(mouse1click)
			else
				pcall(function()
					VirtualUser:Button1Down(Vector2.new(0, 0))
					VirtualUser:Button1Up(Vector2.new(0, 0))
				end)
			end
		end
	end

	if Config.FOVCircle and useDrawing then
		if not Hub.Circle then
			Hub.Circle = newDrawing("Circle")
			if Hub.Circle then
				Hub.Circle.Filled = false
				Hub.Circle.Thickness = 1
				Hub.Circle.NumSides = 64
				Hub.Circle.Color = Color3.fromRGB(255, 90, 90)
			end
		end
		if Hub.Circle then
			local vs = cam.ViewportSize
			local fov = Config.SilentAim and Config.SilentFOV or Config.AimFOV
			local radius = (vs.Y / 2) * math.tan(math.rad(fov)) / math.tan(math.rad(cam.FieldOfView / 2))
			Hub.Circle.Position = Vector2.new(vs.X / 2, vs.Y / 2)
			Hub.Circle.Radius = radius
			Hub.Circle.Visible = true
		end
	elseif Hub.Circle then
		Hub.Circle.Visible = false
	end

	if Config.CameraFOV > 0 then
		cam.FieldOfView = Config.CameraFOV
	end

	if Config.Fullbright then
		if not Hub.FB then
			Hub.FB = true
			Hub.FBOld = {
				b = Lighting.Brightness,
				a = Lighting.Ambient,
				o = Lighting.OutdoorAmbient,
			}
		end
		Lighting.Brightness     = 3
		Lighting.Ambient        = Color3.fromRGB(140, 140, 140)
		Lighting.OutdoorAmbient = Color3.fromRGB(140, 140, 140)
	elseif Hub.FB then
		Hub.FB = false
		local o = Hub.FBOld
		if o then
			Lighting.Brightness     = o.b
			Lighting.Ambient        = o.a
			Lighting.OutdoorAmbient = o.o
		end
	end

	if Config.ESP then
		local live = {}
		local vs = cam.ViewportSize
		for _, t in ipairs(getTargets()) do
			if (not t.isNPC) or Config.ESPNPC then
				local dist = (t.root.Position - cam.CFrame.Position).Magnitude
				if dist <= Config.ESPMaxDist then
					live[t.model] = true
					local e = Hub.ESP[t.model]
					if not e then
						e = createESP()
						Hub.ESP[t.model] = e
						if e.hl then
							e.hl.Adornee = t.model
							e.hl.Parent = t.model
						end
					end

					local col = t.isNPC and Color3.fromRGB(120, 255, 120) or Color3.fromRGB(255, 90, 90)

					local minX, minY, maxX, maxY
					local cf, size = t.model:GetBoundingBox()
					for x = -1, 1, 2 do
						for y = -1, 1, 2 do
							for z = -1, 1, 2 do
								local world = cf * Vector3.new(size.X / 2 * x, size.Y / 2 * y, size.Z / 2 * z)
								local sp, on = cam:WorldToViewportPoint(world)
								if on then
									minX = math.min(minX or sp.X, sp.X)
									maxX = math.max(maxX or sp.X, sp.X)
									minY = math.min(minY or sp.Y, sp.Y)
									maxY = math.max(maxY or sp.Y, sp.Y)
								end
							end
						end
					end

					if minX then
						local bw, bh = maxX - minX, maxY - minY

						if e.box then
							e.box.Visible  = Config.ESPBox
							e.box.Color    = col
							e.box.Position = Vector2.new(minX, minY)
							e.box.Size     = Vector2.new(bw, bh)
						end
						if e.name then
							e.name.Visible 
