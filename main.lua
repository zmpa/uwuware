getgenv().uwuware = getgenv().uwuware or {}

local runService = game:GetService("RunService")
local textService = game:GetService("TextService")
local inputService = game:GetService("UserInputService")
local tweenService = game:GetService("TweenService")
local httpService = game:GetService("HttpService")
local playersService = game:GetService("Players")

local COMPAT = {
	hasFiles = typeof(writefile) == "function" and typeof(readfile) == "function" and typeof(isfolder) == "function" and typeof(listfiles) == "function",
	hasHook = typeof(hookmetamethod) == "function" and typeof(checkcaller) == "function",
	hasRawMeta = typeof(getrawmetatable) == "function" and typeof(setreadonly) == "function",
	isTouch = inputService.TouchEnabled and not inputService.KeyboardEnabled,
}

if getgenv().library and getgenv().library.Unload then
	pcall(function() getgenv().library:Unload() end)
end

local library = {
	Version = "2.0.0",
	design = getgenv().design == "kali" and "kali" or "uwuware",
	tabs = {}, draggable = true, flags = {}, flagListeners = {},
	title = "uwuware", open = false, rainbow = false,
	mousestate = inputService.MouseIconEnabled,
	popup = nil, instances = {}, connections = {}, namedConnections = {},
	options = {}, notifications = {}, tabSize = 0, theme = {},
	foldername = "uw_configs", fileext = ".uw",
	canSave = COMPAT.hasFiles,
	borderColor = Color3.fromRGB(60, 60, 60),
	keyBlacklist = {Enum.KeyCode.Unknown, Enum.KeyCode.Escape},
	flagprefix = nil,
}
getgenv().library = library
getgenv().uwuware.library = library
getgenv().uwuware.services = {runService = runService, textService = textService, inputService = inputService, tweenService = tweenService}

local dragging, dragInput, dragStart, startPos, dragObject
local whitelistedMouseinputs = {Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseButton2, Enum.UserInputType.MouseButton3}

local function wrap(fn)
	if typeof(newcclosure) == "function" then
		local ok, closure = pcall(newcclosure, fn)
		if ok and closure then return closure end
	end
	return fn
end

local function isPress(input)
	local t = input.UserInputType
	return t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
end

local function isMove(input)
	local t = input.UserInputType
	return t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch
end

local function measure(text, size)
	return textService:GetTextSize(tostring(text), size or 15, Enum.Font.Code, Vector2.new(9e9, 9e9)).X
end

local function viewport()
	local camera = workspace.CurrentCamera
	return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

local function themify(obj, prop)
	if not obj then return obj end
	library.theme[obj] = prop or (obj.ClassName == "TextLabel" and "TextColor3") or (obj.ClassName == "ImageLabel" and "ImageColor3") or (obj.ClassName == "UIStroke" and "Color") or "BackgroundColor3"
	return obj
end

local function attachEnabled(option, titleLabel)
	function option:SetEnabled(state)
		self.disabled = not state
		if titleLabel then titleLabel.TextTransparency = state and 0 or 0.45 end
		return state
	end
	function option:IsEnabled()
		return not self.disabled
	end
end

local function setTip(option)
	if not (option.tip and library.tooltip) then return end
	library.tooltip.Text = option.tip
	library.tooltip.Size = UDim2.new(0, measure(option.tip) + 14, 0, 20)
end

local function moveTip(option, input)
	if not (option.tip and library.tooltip) then return end
	local size = viewport()
	local width = library.tooltip.AbsoluteSize.X
	local x = input.Position.X + 26
	local y = input.Position.Y + 36
	if x + width > size.X then x = input.Position.X - width - 12 end
	if y + 24 > size.Y then y = input.Position.Y - 30 end
	library.tooltip.Position = UDim2.new(0, x, 0, y)
end

local function clearTip()
	if library.tooltip then library.tooltip.Position = UDim2.new(2) end
end

local function resolveFlag(option)
	local base = (library.flagprefix and library.flagprefix .. " " or "") .. (option.flag or option.text)
	local flag = base
	local n = 0
	while library.options[flag] do
		n = n + 1
		flag = base .. " " .. n
	end
	option.flag = flag
	return flag
end

library.round = function(num, bracket)
	if typeof(num) == "Vector2" then
		return Vector2.new(library.round(num.X), library.round(num.Y))
	elseif typeof(num) == "Vector3" then
		return Vector3.new(library.round(num.X), library.round(num.Y), library.round(num.Z))
	elseif typeof(num) == "Color3" then
		return library.round(num.r * 255), library.round(num.g * 255), library.round(num.b * 255)
	else
		return num - num % (bracket or 1)
	end
end

library.roundRGB = function(color)
	return library.round(color.r * 255), library.round(color.g * 255), library.round(color.b * 255)
end

function library:SetFlag(flag, value)
	self.flags[flag] = value
	local listeners = self.flagListeners[flag]
	if listeners then
		for _, fn in next, listeners do
			pcall(fn, value, flag)
		end
	end
	return value
end

function library:OnFlagChanged(flag, fn)
	self.flagListeners[flag] = self.flagListeners[flag] or {}
	table.insert(self.flagListeners[flag], fn)
	return fn
end

function library:ApplyAccent(color)
	if self.currentTab and self.currentTab.button then
		self.currentTab.button.TextColor3 = color
	end
	for obj, prop in next, self.theme do
		if obj.Parent == nil then
			self.theme[obj] = nil
		else
			obj[prop] = color
		end
	end
end

function library:SetRainbow(state)
	state = state == true
	self.rainbow = state
	if state and not self.chromaConnection then
		self.chromaConnection = runService.RenderStepped:Connect(function()
			local color = Color3.fromHSV((os.clock() / 4) % 1, 1, 1)
			library.flags["Menu Accent Color"] = color
			library:ApplyAccent(color)
		end)
	elseif not state and self.chromaConnection then
		self.chromaConnection:Disconnect()
		self.chromaConnection = nil
	end
end

local DRAWING_CLASSES = {Square = true, Line = true, Text = true, Quad = true, Circle = true, Triangle = true}

function library:Create(class, properties)
	properties = properties or {}
	if not class then return end
	local isDrawing = DRAWING_CLASSES[class] == true
	local inst = (isDrawing and Drawing or Instance).new(class)
	local parent = properties.Parent
	properties.Parent = nil
	for property, value in next, properties do
		inst[property] = value
	end
	if not isDrawing then inst.Parent = parent end
	table.insert(self.instances, {object = inst, method = isDrawing})
	return inst
end

function library:Outline(obj, radius, color)
	library:Create("UICorner", {CornerRadius = UDim.new(0, radius or 3), Parent = obj})
	return library:Create("UIStroke", {Color = color or self.borderColor, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = obj})
end

function library:AddConnection(connection, name, callback)
	callback = type(name) == "function" and name or callback
	local conn = connection:Connect(callback)
	table.insert(self.connections, conn)
	if type(name) == "string" then
		local previous = self.namedConnections[name]
		if previous then pcall(function() previous:Disconnect() end) end
		self.namedConnections[name] = conn
	end
	return conn
end

function library:Unload()
	if self.chromaConnection then
		self.chromaConnection:Disconnect()
		self.chromaConnection = nil
	end
	if self.restoreHooks then pcall(self.restoreHooks) end
	pcall(function() inputService.MouseIconEnabled = self.mousestate end)
	for _, conn in next, self.connections do
		pcall(function() conn:Disconnect() end)
	end
	for _, entry in next, self.instances do
		if entry.method then
			pcall(function() entry.object:Remove() end)
		else
			pcall(function() entry.object:Destroy() end)
		end
	end
	for _, option in next, self.options do
		if option.type == "toggle" then pcall(function() option:SetState(false) end) end
	end
	table.clear(self.connections)
	table.clear(self.namedConnections)
	table.clear(self.instances)
	table.clear(self.theme)
	table.clear(self.options)
	table.clear(self.flags)
	getgenv().uwuware.library = nil
	library = nil
	getgenv().library = nil
end

function library:GetConfigs()
	if not self.canSave then return {} end
	local ok, files = pcall(function()
		if not isfolder(self.foldername) then makefolder(self.foldername) end
		local out = {}
		for _, path in next, listfiles(self.foldername) do
			path = tostring(path)
			local name = path:match("[^/\\]+$") or path
			if #name > #self.fileext and name:sub(-#self.fileext) == self.fileext then
				table.insert(out, name:sub(1, #name - #self.fileext))
			end
		end
		return out
	end)
	return ok and files or {}
end

function library:LoadConfig(config)
	if not self.canSave then return end
	if not config or not table.find(self:GetConfigs(), config) then return end
	local ok, decoded = pcall(function()
		return httpService:JSONDecode(readfile(self.foldername .. "/" .. config .. self.fileext))
	end)
	local Config = (ok and typeof(decoded) == "table") and decoded or {}
	for _, option in next, self.options do
		if option.hasInit and option.type ~= "button" and option.flag and not option.skipflag then
			if option.type == "toggle" then
				task.spawn(function() option:SetState(Config[option.flag] == 1) end)
			elseif option.type == "color" then
				if Config[option.flag] then
					task.spawn(function() option:SetColor(Config[option.flag]) end)
					if option.trans then
						task.spawn(function() option:SetTrans(Config[option.flag .. " Transparency"]) end)
					end
				end
			elseif option.type == "bind" then
				task.spawn(function() option:SetKey(Config[option.flag]) end)
			else
				task.spawn(function() option:SetValue(Config[option.flag]) end)
			end
		end
	end
end

function library:SaveConfig(config)
	if not self.canSave or not config then return end
	local Config = {}
	if table.find(self:GetConfigs(), config) then
		local ok, decoded = pcall(function()
			return httpService:JSONDecode(readfile(self.foldername .. "/" .. config .. self.fileext))
		end)
		if ok and typeof(decoded) == "table" then Config = decoded end
	end
	for _, option in next, self.options do
		if option.type ~= "button" and option.flag and not option.skipflag then
			if option.type == "toggle" then
				Config[option.flag] = option.state and 1 or 0
			elseif option.type == "color" then
				Config[option.flag] = {option.color.r, option.color.g, option.color.b}
				if option.trans then
					Config[option.flag .. " Transparency"] = option.trans
				end
			elseif option.type == "bind" then
				if option.key ~= "none" then Config[option.flag] = option.key end
			else
				Config[option.flag] = option.value
			end
		end
	end
	pcall(function()
		writefile(self.foldername .. "/" .. config .. self.fileext, httpService:JSONEncode(Config))
	end)
end

library.createLabel = function(option, parent)
	option.main = library:Create("TextLabel", {
		LayoutOrder = option.position,
		Position = UDim2.new(0, 6, 0, 0),
		Size = UDim2.new(1, -12, 0, 24),
		BackgroundTransparency = 1,
		TextSize = 15,
		Font = Enum.Font.Code,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		RichText = true,
		Parent = parent
	})

	setmetatable(option, {__newindex = function(t, i, v)
		if i == "Text" then
			t.main.Text = tostring(v)
			t.main.Size = UDim2.new(1, -12, 0, textService:GetTextSize(t.main.Text, 15, Enum.Font.Code, Vector2.new(t.main.AbsoluteSize.X, 9e9)).Y + 6)
		else
			rawset(t, i, v)
		end
	end})
	option.Text = option.text
end

library.createDivider = function(option, parent)
	option.main = library:Create("Frame", {
		LayoutOrder = option.position,
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Parent = parent
	})

	library:Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, -24, 0, 1),
		BackgroundColor3 = library.borderColor,
		BorderSizePixel = 0,
		Parent = option.main
	})

	option.title = library:Create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		BackgroundColor3 = Color3.fromRGB(30, 30, 30),
		BorderSizePixel = 0,
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 15,
		Font = Enum.Font.Code,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = option.main
	})

	setmetatable(option, {__newindex = function(t, i, v)
		if i == "Text" then
			if v then
				t.title.Text = tostring(v)
				t.title.Size = UDim2.new(0, textService:GetTextSize(t.title.Text, 15, Enum.Font.Code, Vector2.new(9e9, 9e9)).X + 12, 0, 20)
				t.main.Size = UDim2.new(1, 0, 0, 18)
			else
				t.title.Text = ""
				t.title.Size = UDim2.new()
				t.main.Size = UDim2.new(1, 0, 0, 6)
			end
		else
			rawset(t, i, v)
		end
	end})
	option.Text = option.text
end

library.createToggle = function(option, parent)
	option.hasInit = true

	option.main = library:Create("Frame", {
		LayoutOrder = option.position,
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Parent = parent
	})

	local tickbox, tickboxOverlay, tickboxStroke
	if option.style then
		tickbox = library:Create("ImageLabel", {
			Position = UDim2.new(0, 6, 0, 4),
			Size = UDim2.new(0, 12, 0, 12),
			BackgroundTransparency = 1,
			Image = "rbxassetid://3570695787",
			ImageColor3 = library.borderColor,
			Parent = option.main
		})

		tickboxOverlay = library:Create("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(1, -6, 1, -6),
			BackgroundTransparency = 1,
			Image = "rbxassetid://3570695787",
			ImageColor3 = library.flags["Menu Accent Color"],
			Visible = option.state,
			Parent = tickbox
		})

		library:Create("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Image = "rbxassetid://5941353943",
			ImageTransparency = 0.6,
			Parent = tickbox
		})

		themify(tickboxOverlay)
	else
		tickbox = library:Create("Frame", {
			Position = UDim2.new(0, 6, 0, 4),
			Size = UDim2.new(0, 12, 0, 12),
			BackgroundColor3 = library.flags["Menu Accent Color"],
			BorderSizePixel = 0,
			Parent = option.main
		})
		tickboxStroke = library:Outline(tickbox, 3, library.flags["Menu Accent Color"])
		themify(tickboxStroke)

		tickboxOverlay = library:Create("ImageLabel", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = option.state and 1 or 0,
			BackgroundColor3 = Color3.fromRGB(50, 50, 50),
			BorderSizePixel = 0,
			Image = "rbxassetid://4155801252",
			ImageTransparency = 0.6,
			ImageColor3 = Color3.new(),
			Parent = tickbox
		})
	end

	option.interest = library:Create("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Parent = option.main
	})

	option.title = library:Create("TextLabel", {
		Position = UDim2.new(0, 24, 0, 0),
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = option.text,
		TextColor3 = option.state and Color3.fromRGB(210, 210, 210) or Color3.fromRGB(180, 180, 180),
		TextSize = 15,
		Font = Enum.Font.Code,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = option.interest
	})

	local function hover(state)
		if not option.style or library.warning or library.slider then return end
		tweenService:Create(tickbox, TweenInfo.new(0.15), {ImageColor3 = state and library.flags["Menu Accent Color"] or library.borderColor}):Play()
	end

	option.interest.InputBegan:Connect(function(input)
		if isPress(input) and not option.disabled then
			option:SetState(not option.state)
		end
		if isMove(input) then
			hover(true)
			setTip(option)
		end
	end)

	option.interest.InputChanged:Connect(function(input)
		if isMove(input) then moveTip(option, input) end
	end)

	option.interest.InputEnded:Connect(function(input)
		if isMove(input) then
			hover(false)
			clearTip()
		end
	end)

	function option:SetState(state, nocallback)
		state = not not state
		self.state = state
		library:SetFlag(self.flag, state)
		option.title.TextColor3 = state and Color3.fromRGB(210, 210, 210) or Color3.fromRGB(160, 160, 160)
		if option.style then
			tickboxOverlay.Visible = state
		else
			tickboxOverlay.BackgroundTransparency = state and 1 or 0
		end
		if not nocallback then self.callback(state) end
		return state
	end

	attachEnabled(option, option.title)

	if option.state ~= nil then
		task.delay(1, function()
			if library then option.callback(option.state) end
		end)
	end

	setmetatable(option, {__newindex = function(t, i, v)
		if i == "Text" then
			t.title.Text = tostring(v)
		else
			rawset(t, i, v)
		end
	end})
end

library.createButton = function(option, parent)
	option.hasInit = true

	option.main = library:Create("Frame", {
		LayoutOrder = option.position,
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		Parent = parent
	})

	option.title = library:Create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -5),
		Size = UDim2.new(1, -12, 0, 20),
		BackgroundColor3 = Color3.fromRGB(50, 50, 50),
		BorderSizePixel = 0,
		Text = option.text,
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 15,
		Font = Enum.Font.Code,
		Parent = option.main
	})
	local stroke = library:Outline(option.title, 3)

	library:Create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 180, 180)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(253, 253, 253)),
		}),
		Rotation = -90,
		Parent = option.title
	})

	option.title.InputBegan:Connect(function(input)
		if isPress(input) and not option.disabled then
			option.callback()
			if library then library.flags[option.flag] = true end
		end
		if isMove(input) then
			if not library.warning and not library.slider then stroke.Color = library.flags["Menu Accent Color"] end
			setTip(option)
		end
	end)

	option.title.InputChanged:Connect(function(input)
		if isMove(input) then moveTip(option, input) end
	end)

	option.title.InputEnded:Connect(function(input)
		if isMove(input) then
			stroke.Color = library.borderColor
			clearTip()
		end
	end)

	attachEnabled(option, option.title)
end

library.createBind = function(option, parent)
	option.hasInit = true

	local binding
	local Loop

	if option.sub then
		option.main = option:getMain()
	else
		option.main = option.main or library:Create("Frame", {
			LayoutOrder = option.position,
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Parent = parent
		})

		library:Create("TextLabel", {
			Position = UDim2.new(0, 6, 0, 0),
			Size = UDim2.new(1, -12, 1, 0),
			BackgroundTransparency = 1,
			Text = option.text,
			TextSize = 15,
			Font = Enum.Font.Code,
			TextColor3 = Color3.fromRGB(210, 210, 210),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = option.main
		})
	end

	local bindinput = library:Create(option.sub and "TextButton" or "TextLabel", {
		Position = UDim2.new(1, -6 - (option.subpos or 0), 0, option.sub and 2 or 3),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundColor3 = Color3.fromRGB(30, 30, 30),
		BorderSizePixel = 0,
		TextSize = 15,
		Font = Enum.Font.Code,
		TextColor3 = Color3.fromRGB(160, 160, 160),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = option.main
	})

	if option.sub then bindinput.AutoButtonColor = false end

	local interest = option.sub and bindinput or option.main

	interest.InputEnded:Connect(function(input)
		if not isPress(input) or option.disabled then return end
		binding = true
		bindinput.Text = "[...]"
		bindinput.TextColor3 = library.flags["Menu Accent Color"]
		bindinput.Size = UDim2.new(0, -textService:GetTextSize(bindinput.Text, 16, Enum.Font.Code, Vector2.new(9e9, 9e9)).X, 0, 16)
	end)

	library:AddConnection(inputService.InputBegan, function(input)
		if inputService:GetFocusedTextBox() then return end
		if binding then
			local key = (table.find(whitelistedMouseinputs, input.UserInputType) and not option.nomouse) and input.UserInputType
			option:SetKey(key or ((not table.find(library.keyBlacklist, input.KeyCode)) and input.KeyCode))
		elseif input.KeyCode.Name == option.key or input.UserInputType.Name == option.key then
			if option.mode == "toggle" then
				local state = not library.flags[option.flag]
				library:SetFlag(option.flag, state)
				option.callback(state, 0)
			else
				library:SetFlag(option.flag, true)
				if Loop then Loop:Disconnect() end
				option.callback(true, 0)
				Loop = library:AddConnection(runService.RenderStepped, function(step)
					if not inputService:GetFocusedTextBox() then option.callback(nil, step) end
				end)
			end
		end
	end)

	library:AddConnection(inputService.InputEnded, function(input)
		if option.key == "none" then return end
		if input.KeyCode.Name == option.key or input.UserInputType.Name == option.key then
			if Loop then
				Loop:Disconnect()
				Loop = nil
				library:SetFlag(option.flag, false)
				option.callback(true, 0)
			end
		end
	end)

	function option:SetKey(key)
		binding = false
		bindinput.TextColor3 = Color3.fromRGB(160, 160, 160)
		if Loop then
			Loop:Disconnect()
			Loop = nil
			library:SetFlag(option.flag, false)
			option.callback(true, 0)
		end
		self.key = (key and key.Name) or key or self.key or "none"
		if self.key == "Backspace" then
			self.key = "none"
			bindinput.Text = "[NONE]"
		else
			local label = self.key
			if self.key:match("Mouse") then
				label = self.key:gsub("Button", ""):gsub("Mouse", "M")
			elseif self.key:match("Shift") or self.key:match("Alt") or self.key:match("Control") then
				label = self.key:gsub("Left", "L"):gsub("Right", "R")
			end
			bindinput.Text = "[" .. label:gsub("Control", "CTRL"):upper() .. "]"
		end
		bindinput.Size = UDim2.new(0, -textService:GetTextSize(bindinput.Text, 16, Enum.Font.Code, Vector2.new(9e9, 9e9)).X, 0, 16)
		return self.key
	end
	option:SetKey()
end

library.createSlider = function(option, parent)
	option.hasInit = true

	if option.sub then
		option.main = option:getMain()
		option.main.Size = UDim2.new(1, 0, 0, 42)
	else
		option.main = library:Create("Frame", {
			LayoutOrder = option.position,
			Size = UDim2.new(1, 0, 0, option.textpos and 24 or 40),
			BackgroundTransparency = 1,
			Parent = parent
		})
	end

	option.slider = library:Create("Frame", {
		Position = UDim2.new(0, 6, 0, (option.sub and 22 or option.textpos and 4 or 20)),
		Size = UDim2.new(1, -12, 0, 16),
		BackgroundColor3 = Color3.fromRGB(50, 50, 50),
		BorderSizePixel = 0,
		Parent = option.main
	})
	local sliderStroke = library:Outline(option.slider, 3)

	option.fill = library:Create("Frame", {
		BackgroundColor3 = library.flags["Menu Accent Color"],
		BorderSizePixel = 0,
		Parent = option.slider
	})
	library:Create("UICorner", {CornerRadius = UDim.new(0, 3), Parent = option.fill})
	themify(option.fill)

	library:Create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(115, 115, 115)),
			ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
		}),
		Rotation = -90,
		Parent = option.fill
	})

	option.prefix = option.text == "nil" and "" or option.text .. ": "

	option.title = library:Create("TextBox", {
		Position = UDim2.new((option.sub or option.textpos) and 0.5 or 0, (option.sub or option.textpos) and 0 or 6, 0, 0),
		Size = UDim2.new(0, 0, 0, (option.sub or option.textpos) and 14 or 18),
		BackgroundTransparency = 1,
		Text = option.prefix .. option.value .. option.suffix,
		TextSize = (option.sub or option.textpos) and 14 or 15,
		Font = Enum.Font.Code,
		TextColor3 = Color3.fromRGB(210, 210, 210),
		TextXAlignment = Enum.TextXAlignment[(option.sub or option.textpos) and "Center" or "Left"],
		Parent = (option.sub or option.textpos) and option.slider or option.main
	})

	if option.min >= 0 then
		option.fill.Size = UDim2.new((option.value - option.min) / (option.max - option.min), 0, 1, 0)
	else
		option.fill.Position = UDim2.new((0 - option.min) / (option.max - option.min), 0, 0, 0)
		option.fill.Size = UDim2.new(option.value / (option.max - option.min), 0, 1, 0)
	end

	local manualInput

	option.title.Focused:Connect(function()
		if not manualInput then
			option.title:ReleaseFocus()
			option.title.Text = option.prefix .. option.value .. option.suffix
		end
	end)

	option.title.FocusLost:Connect(function()
		sliderStroke.Color = library.borderColor
		if manualInput then
			local parsed = tonumber(tostring(option.title.Text):match("-?%d+%.?%d*"))
			if parsed then
				option:SetValue(parsed)
			else
				option.title.Text = option.prefix .. option.value .. option.suffix
			end
		end
		manualInput = false
	end)

	local interest = (option.sub or option.textpos) and option.slider or option.main

	interest.InputBegan:Connect(function(input)
		if isPress(input) and not option.disabled then
			if inputService:IsKeyDown(Enum.KeyCode.LeftControl) or inputService:IsKeyDown(Enum.KeyCode.RightControl) then
				manualInput = true
				option.title:CaptureFocus()
			else
				library.slider = option
				sliderStroke.Color = library.flags["Menu Accent Color"]
				option:SetValue(option.min + ((input.Position.X - option.slider.AbsolutePosition.X) / option.slider.AbsoluteSize.X) * (option.max - option.min))
			end
		end
		if isMove(input) then
			if not library.warning and not library.slider then sliderStroke.Color = library.flags["Menu Accent Color"] end
			setTip(option)
		end
	end)

	interest.InputChanged:Connect(function(input)
		if isMove(input) then moveTip(option, input) end
	end)

	interest.InputEnded:Connect(function(input)
		if isMove(input) then
			clearTip()
			if option ~= library.slider then sliderStroke.Color = library.borderColor end
		end
	end)

	function option:SetValue(value, nocallback)
		if typeof(value) ~= "number" then value = self.min end
		value = library.round(value, self.float)
		value = math.clamp(value, self.min, self.max)
		local dragging = library.slider == self
		if self.min >= 0 then
			local target = UDim2.new((value - self.min) / (self.max - self.min), 0, 1, 0)
			if dragging then option.fill.Size = target else option.fill:TweenSize(target, "Out", "Quad", 0.05, true) end
		else
			option.fill.Position = UDim2.new((0 - self.min) / (self.max - self.min), 0, 0, 0)
			local target = UDim2.new(value / (self.max - self.min), 0, 1, 0)
			if dragging then option.fill.Size = target else option.fill:TweenSize(target, "Out", "Quad", 0.1, true) end
		end
		self.value = value
		library:SetFlag(self.flag, value)
		option.title.Text = self.prefix .. value .. self.suffix
		if not nocallback then self.callback(value) end
		return value
	end

	attachEnabled(option, option.title)

	task.delay(1, function()
		if library then option:SetValue(option.value) end
	end)
end

library.createList = function(option, parent)
	option.hasInit = true

	if option.sub then
		option.main = option:getMain()
		option.main.Size = UDim2.new(1, 0, 0, 48)
	else
		option.main = library:Create("Frame", {
			LayoutOrder = option.position,
			Size = UDim2.new(1, 0, 0, option.text == "nil" and 30 or 48),
			BackgroundTransparency = 1,
			Parent = parent
		})

		if option.text ~= "nil" then
			library:Create("TextLabel", {
				Position = UDim2.new(0, 6, 0, 0),
				Size = UDim2.new(1, -12, 0, 18),
				BackgroundTransparency = 1,
				Text = option.text,
				TextSize = 15,
				Font = Enum.Font.Code,
				TextColor3 = Color3.fromRGB(210, 210, 210),
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = option.main
			})
		end
	end

	local function getMultiText()
		local out = ""
		for _, value in next, option.values do
			out = out .. (option.value[value] and (tostring(value) .. ", ") or "")
		end
		return string.sub(out, 1, #out - 2)
	end

	option.listvalue = library:Create("TextLabel", {
		Position = UDim2.new(0, 6, 0, (option.text == "nil" and not option.sub) and 4 or 22),
		Size = UDim2.new(1, -12, 0, 22),
		BackgroundColor3 = Color3.fromRGB(50, 50, 50),
		BorderSizePixel = 0,
		Text = " " .. (typeof(option.value) == "string" and option.value or getMultiText()),
		TextSize = 15,
		Font = Enum.Font.Code,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = option.main
	})
	local listStroke = library:Outline(option.listvalue, 3)

	option.arrow = library:Create("ImageLabel", {
		Position = UDim2.new(1, -16, 0, 7),
		Size = UDim2.new(0, 8, 0, 8),
		Rotation = 90,
		BackgroundTransparency = 1,
		Image = "rbxassetid://4918373417",
		ImageColor3 = Color3.new(1, 1, 1),
		ScaleType = Enum.ScaleType.Fit,
		ImageTransparency = 0.4,
		Parent = option.listvalue
	})

	option.holder = library:Create("TextButton", {
		ZIndex = 4,
		BackgroundColor3 = Color3.fromRGB(40, 40, 40),
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		Parent = library.base
	})
	library:Outline(option.holder, 3)

	option.content = library:Create("ScrollingFrame", {
		ZIndex = 4,
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarImageColor3 = Color3.new(),
		ScrollBarThickness = 3,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		VerticalScrollBarInset = Enum.ScrollBarInset.Always,
		TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
		BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
		Parent = option.holder
	})

	local layout = library:Create("UIListLayout", {
		Padding = UDim.new(0, 2),
		Parent = option.content
	})

	library:Create("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 4),
		Parent = option.content
	})

	local valueCount = 0
	layout.Changed:Connect(function()
		option.holder.Size = UDim2.new(0, option.listvalue.AbsoluteSize.X, 0, 8 + (valueCount > option.max and (-2 + (option.max * 22)) or layout.AbsoluteContentSize.Y))
		option.content.CanvasSize = UDim2.new(0, 0, 0, 8 + layout.AbsoluteContentSize.Y)
	end)

	local interest = option.sub and option.listvalue or option.main

	option.listvalue.InputBegan:Connect(function(input)
		if isPress(input) and not option.disabled then
			if library.popup == option then
				option:Close()
				return
			end
			if library.popup then library.popup:Close() end
			option.arrow.Rotation = -90
			option.open = true
			option.holder.Visible = true
			local pos = option.main.AbsolutePosition
			option.holder.Position = UDim2.new(0, pos.X + 6, 0, pos.Y + ((option.text == "nil" and not option.sub) and 66 or 84))
			library.popup = option
			listStroke.Color = library.flags["Menu Accent Color"]
		end
		if isMove(input) then
			if not library.warning and not library.slider then listStroke.Color = library.flags["Menu Accent Color"] end
		end
	end)

	option.listvalue.InputEnded:Connect(function(input)
		if isMove(input) and not option.open then listStroke.Color = library.borderColor end
	end)

	interest.InputBegan:Connect(function(input)
		if isMove(input) then setTip(option) end
	end)

	interest.InputChanged:Connect(function(input)
		if isMove(input) then moveTip(option, input) end
	end)

	interest.InputEnded:Connect(function(input)
		if isMove(input) then clearTip() end
	end)

	local selected

	function option:AddValue(value, state)
		if self.labels[value] then return end
		valueCount = valueCount + 1

		if self.multiselect then
			self.values[value] = state
		elseif not table.find(self.values, value) then
			table.insert(self.values, value)
		end

		local label = library:Create("TextLabel", {
			ZIndex = 4,
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Text = value,
			TextSize = 15,
			Font = Enum.Font.Code,
			TextTransparency = self.multiselect and (self.value[value] and 1 or 0) or self.value == value and 1 or 0,
			TextColor3 = Color3.fromRGB(210, 210, 210),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = option.content
		})
		self.labels[value] = label

		local labelOverlay = library:Create("TextLabel", {
			ZIndex = 4,
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 0.8,
			Text = " " .. value,
			TextSize = 15,
			Font = Enum.Font.Code,
			TextColor3 = library.flags["Menu Accent Color"],
			TextXAlignment = Enum.TextXAlignment.Left,
			Visible = self.multiselect and self.value[value] or self.value == value,
			Parent = label
		})
		selected = selected or (self.value == value and labelOverlay)
		themify(labelOverlay)

		label.InputBegan:Connect(function(input)
			if not isPress(input) then return end
			if self.multiselect then
				self.value[value] = not self.value[value]
				self:SetValue(self.value)
			else
				self:SetValue(value)
				self:Close()
			end
		end)
	end

	for i, value in next, option.values do
		option:AddValue(tostring(typeof(i) == "number" and value or i))
	end

	function option:RemoveValue(value)
		local label = self.labels[value]
		if not label then return end
		label:Destroy()
		self.labels[value] = nil
		valueCount = valueCount - 1
		if self.multiselect then
			self.values[value] = nil
			self:SetValue(self.value)
		else
			table.remove(self.values, table.find(self.values, value))
			if self.value == value then
				selected = nil
				self:SetValue(self.values[1] or "")
			end
		end
	end

	function option:SetValue(value, nocallback)
		if self.multiselect and typeof(value) ~= "table" then
			value = {}
			for _, entry in next, self.values do
				value[entry] = false
			end
		end
		self.value = typeof(value) == "table" and value or tostring(table.find(self.values, value) and value or self.values[1])
		library:SetFlag(self.flag, self.value)
		option.listvalue.Text = " " .. (self.multiselect and getMultiText() or self.value)
		if self.multiselect then
			for name, label in next, self.labels do
				label.TextTransparency = self.value[name] and 1 or 0
				if label:FindFirstChild("TextLabel") then label.TextLabel.Visible = self.value[name] end
			end
		else
			if selected then
				selected.TextTransparency = 0
				if selected:FindFirstChild("TextLabel") then selected.TextLabel.Visible = false end
			end
			if self.labels[self.value] then
				selected = self.labels[self.value]
				selected.TextTransparency = 1
				if selected:FindFirstChild("TextLabel") then selected.TextLabel.Visible = true end
			end
		end
		if not nocallback then self.callback(self.value) end
		return self.value
	end

	task.delay(1, function()
		if library then option:SetValue(option.value) end
	end)

	function option:Close()
		if library.popup == self then library.popup = nil end
		option.arrow.Rotation = 90
		self.open = false
		option.holder.Visible = false
		listStroke.Color = library.borderColor
	end

	attachEnabled(option, option.listvalue)

	return option
end

library.createBox = function(option, parent)
	option.hasInit = true

	option.main = library:Create("Frame", {
		LayoutOrder = option.position,
		Size = UDim2.new(1, 0, 0, option.text == "nil" and 28 or 44),
		BackgroundTransparency = 1,
		Parent = parent
	})

	if option.text ~= "nil" then
		option.title = library:Create("TextLabel", {
			Position = UDim2.new(0, 6, 0, 0),
			Size = UDim2.new(1, -12, 0, 18),
			BackgroundTransparency = 1,
			Text = option.text,
			TextSize = 15,
			Font = Enum.Font.Code,
			TextColor3 = Color3.fromRGB(210, 210, 210),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = option.main
		})
	end

	option.holder = library:Create("Frame", {
		Position = UDim2.new(0, 6, 0, option.text == "nil" and 4 or 20),
		Size = UDim2.new(1, -12, 0, 20),
		BackgroundColor3 = Color3.fromRGB(50, 50, 50),
		BorderSizePixel = 0,
		Parent = option.main
	})
	local stroke = library:Outline(option.holder, 3)

	local inputvalue = library:Create("TextBox", {
		Position = UDim2.new(0, 4, 0, 0),
		Size = UDim2.new(1, -4, 1, 0),
		BackgroundTransparency = 1,
		Text = "  " .. option.value,
		TextSize = 15,
		Font = Enum.Font.Code,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		ClearTextOnFocus = false,
		Parent = option.holder
	})

	inputvalue.FocusLost:Connect(function(enter)
		stroke.Color = library.borderColor
		option:SetValue(inputvalue.Text, enter)
	end)

	inputvalue.Focused:Connect(function()
		stroke.Color = library.flags["Menu Accent Color"]
	end)

	inputvalue.InputBegan:Connect(function(input)
		if isPress(input) and not option.disabled then inputvalue.Text = "" end
		if isMove(input) then
			if not library.warning and not library.slider then stroke.Color = library.flags["Menu Accent Color"] end
			setTip(option)
		end
	end)

	inputvalue.InputChanged:Connect(function(input)
		if isMove(input) then moveTip(option, input) end
	end)

	inputvalue.InputEnded:Connect(function(input)
		if isMove(input) then
			if not inputvalue:IsFocused() then stroke.Color = library.borderColor end
			clearTip()
		end
	end)

	function option:SetValue(value, enter)
		if tostring(value) == "" then
			inputvalue.Text = self.value
		else
			self.value = tostring(value)
			inputvalue.Text = self.value
			library:SetFlag(self.flag, self.value)
			self.callback(value, enter)
		end
		return self.value
	end

	attachEnabled(option, option.title)

	task.delay(1, function()
		if library then option:SetValue(option.value) end
	end)
end

library.createColorPickerWindow = function(option)
	option.mainHolder = library:Create("TextButton", {
		ZIndex = 4,
		Size = UDim2.new(0, option.trans and 200 or 184, 0, 264),
		BackgroundColor3 = Color3.fromRGB(40, 40, 40),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Visible = false,
		Parent = library.base
	})
	library:Outline(option.mainHolder, 4)

	option.rgbBox = library:Create("Frame", {
		Position = UDim2.new(0, 6, 0, 214),
		Size = UDim2.new(0, (option.mainHolder.AbsoluteSize.X - 12), 0, 20),
		BackgroundColor3 = Color3.fromRGB(57, 57, 57),
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = option.mainHolder
	})
	library:Create("UICorner", {CornerRadius = UDim.new(0, 3), Parent = option.rgbBox})

	option.rgbInput = library:Create("TextBox", {
		Name = "TextBox",
		Position = UDim2.new(0, 4, 0, 0),
		Size = UDim2.new(1, -4, 1, 0),
		BackgroundTransparency = 1,
		Text = tostring(option.color),
		TextSize = 14,
		Font = Enum.Font.Code,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		ClearTextOnFocus = false,
		ZIndex = 6,
		Parent = option.rgbBox
	})

	option.hexBox = option.rgbBox:Clone()
	option.hexBox.Position = UDim2.new(0, 6, 0, 238)
	option.hexBox.Parent = option.mainHolder
	table.insert(library.instances, {object = option.hexBox, method = false})
	option.hexInput = option.hexBox.TextBox

	local hue, sat, val = Color3.toHSV(option.color)
	hue, sat, val = hue == 0 and 1 or hue, sat + 0.005, val - 0.005
	local editinghue, editingsatval, editingtrans
	local X, Y

	local transMain
	if option.trans then
		transMain = library:Create("ImageLabel", {
			ZIndex = 5,
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Image = "rbxassetid://2454009026",
			ImageColor3 = Color3.fromHSV(hue, 1, 1),
			Rotation = 180,
			Parent = library:Create("ImageLabel", {
				ZIndex = 4,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -6, 0, 6),
				Size = UDim2.new(0, 10, 1, -60),
				BorderSizePixel = 0,
				Image = "rbxassetid://4632082392",
				ScaleType = Enum.ScaleType.Tile,
				TileSize = UDim2.new(0, 5, 0, 5),
				Parent = option.mainHolder
			})
		})

		option.transSlider = library:Create("Frame", {
			ZIndex = 5,
			Position = UDim2.new(0, 0, option.trans, 0),
			Size = UDim2.new(1, 0, 0, 2),
			BackgroundColor3 = Color3.fromRGB(38, 41, 65),
			BorderSizePixel = 0,
			Parent = transMain
		})

		transMain.InputBegan:Connect(function(input)
			if not isPress(input) then return end
			editingtrans = true
			option:SetTrans(1 - ((input.Position.Y - transMain.AbsolutePosition.Y) / transMain.AbsoluteSize.Y))
		end)

		transMain.InputEnded:Connect(function(input)
			if isPress(input) then editingtrans = false end
		end)
	end

	local hueMain = library:Create("Frame", {
		ZIndex = 4,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 6, 1, -54),
		Size = UDim2.new(1, option.trans and -28 or -12, 0, 10),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = option.mainHolder
	})
	library:Create("UICorner", {CornerRadius = UDim.new(0, 3), Parent = hueMain})

	library:Create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
			ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 0, 255)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 0, 255)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 255, 255)),
			ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 255, 0)),
			ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 255, 0)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
		}),
		Parent = hueMain
	})

	local hueSlider = library:Create("Frame", {
		ZIndex = 4,
		Position = UDim2.new(1 - hue, 0, 0, 0),
		Size = UDim2.new(0, 2, 1, 0),
		BackgroundColor3 = Color3.fromRGB(38, 41, 65),
		BorderSizePixel = 0,
		Parent = hueMain
	})

	hueMain.InputBegan:Connect(function(input)
		if not isPress(input) then return end
		editinghue = true
		X = math.clamp((input.Position.X - hueMain.AbsolutePosition.X) / hueMain.AbsoluteSize.X, 0, 0.995)
		option:SetColor(Color3.fromHSV(1 - X, sat, val))
	end)

	hueMain.InputEnded:Connect(function(input)
		if isPress(input) then editinghue = false end
	end)

	local satval = library:Create("ImageLabel", {
		ZIndex = 4,
		Position = UDim2.new(0, 6, 0, 6),
		Size = UDim2.new(1, option.trans and -28 or -12, 1, -74),
		BackgroundColor3 = Color3.fromHSV(hue, 1, 1),
		BorderSizePixel = 0,
		Image = "rbxassetid://4155801252",
		ClipsDescendants = true,
		Parent = option.mainHolder
	})
	library:Create("UICorner", {CornerRadius = UDim.new(0, 3), Parent = satval})

	local satvalSlider = library:Create("Frame", {
		ZIndex = 4,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(sat, 0, 1 - val, 0),
		Size = UDim2.new(0, 4, 0, 4),
		Rotation = 45,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = satval
	})

	satval.InputBegan:Connect(function(input)
		if not isPress(input) then return end
		editingsatval = true
		X = math.clamp((input.Position.X - satval.AbsolutePosition.X) / satval.AbsoluteSize.X, 0.005, 1)
		Y = math.clamp((input.Position.Y - satval.AbsolutePosition.Y) / satval.AbsoluteSize.Y, 0, 0.995)
		option:SetColor(Color3.fromHSV(hue, X, 1 - Y))
	end)

	library:AddConnection(inputService.InputChanged, function(input)
		if not isMove(input) then return end
		if editingsatval then
			X = math.clamp((input.Position.X - satval.AbsolutePosition.X) / satval.AbsoluteSize.X, 0.005, 1)
			Y = math.clamp((input.Position.Y - satval.AbsolutePosition.Y) / satval.AbsoluteSize.Y, 0, 0.995)
			option:SetColor(Color3.fromHSV(hue, X, 1 - Y))
		elseif editinghue then
			X = math.clamp((input.Position.X - hueMain.AbsolutePosition.X) / hueMain.AbsoluteSize.X, 0, 0.995)
			option:SetColor(Color3.fromHSV(1 - X, sat, val))
		elseif editingtrans then
			option:SetTrans(1 - ((input.Position.Y - transMain.AbsolutePosition.Y) / transMain.AbsoluteSize.Y))
		end
	end)

	satval.InputEnded:Connect(function(input)
		if isPress(input) then editingsatval = false end
	end)

	local r, g, b = library.roundRGB(option.color)
	option.hexInput.Text = string.format("#%02x%02x%02x", r, g, b)
	option.rgbInput.Text = table.concat({r, g, b}, ",")

	option.rgbInput.FocusLost:Connect(function()
		local cr, cg, cb = option.rgbInput.Text:gsub("%s+", ""):match("(%d+),(%d+),(%d+)")
		if cr and cg and cb then
			return option:SetColor(Color3.fromRGB(tonumber(cr), tonumber(cg), tonumber(cb)))
		end
		local rr, gg, bb = library.roundRGB(option.color)
		option.rgbInput.Text = table.concat({rr, gg, bb}, ",")
	end)

	option.hexInput.FocusLost:Connect(function()
		local hr, hg, hb = option.hexInput.Text:match("#?(..)(..)(..)")
		if hr and hg and hb then
			return option:SetColor(Color3.fromRGB(tonumber("0x" .. hr), tonumber("0x" .. hg), tonumber("0x" .. hb)))
		end
		local rr, gg, bb = library.roundRGB(option.color)
		option.hexInput.Text = string.format("#%02x%02x%02x", rr, gg, bb)
	end)

	function option:updateVisuals(color)
		hue, sat, val = Color3.toHSV(color)
		hue = hue == 0 and 1 or hue
		satval.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
		if option.trans then transMain.ImageColor3 = Color3.fromHSV(hue, 1, 1) end
		hueSlider.Position = UDim2.new(1 - hue, 0, 0, 0)
		satvalSlider.Position = UDim2.new(sat, 0, 1 - val, 0)
		local rr, gg, bb = library.roundRGB(Color3.fromHSV(hue, sat, val))
		option.hexInput.Text = string.format("#%02x%02x%02x", rr, gg, bb)
		option.rgbInput.Text = table.concat({rr, gg, bb}, ",")
	end

	return option
end

library.createColor = function(option, parent)
	option.hasInit = true

	if option.sub then
		option.main = option:getMain()
	else
		option.main = library:Create("Frame", {
			LayoutOrder = option.position,
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Parent = parent
		})

		option.title = library:Create("TextLabel", {
			Position = UDim2.new(0, 6, 0, 0),
			Size = UDim2.new(1, -12, 1, 0),
			BackgroundTransparency = 1,
			Text = option.text,
			TextSize = 15,
			Font = Enum.Font.Code,
			TextColor3 = Color3.fromRGB(210, 210, 210),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = option.main
		})
	end

	option.visualize = library:Create(option.sub and "TextButton" or "Frame", {
		Position = UDim2.new(1, -(option.subpos or 0) - 24, 0, 4),
		Size = UDim2.new(0, 18, 0, 12),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundColor3 = option.color,
		BorderSizePixel = 0,
		Parent = option.main
	})
	local stroke = library:Outline(option.visualize, 3)

	local interest = option.sub and option.visualize or option.main

	if option.sub then
		option.visualize.Text = ""
		option.visualize.AutoButtonColor = false
	end

	interest.InputBegan:Connect(function(input)
		if isPress(input) and not option.disabled then
			if not option.mainHolder then library.createColorPickerWindow(option) end
			if library.popup == option then
				option:Close()
				return
			end
			if library.popup then library.popup:Close() end
			option.open = true
			local pos = option.main.AbsolutePosition
			option.mainHolder.Position = UDim2.new(0, pos.X + 36 + (option.trans and -16 or 0), 0, pos.Y + 56)
			option.mainHolder.Visible = true
			library.popup = option
			stroke.Color = library.flags["Menu Accent Color"]
		end
		if isMove(input) then
			if not library.warning and not library.slider then stroke.Color = library.flags["Menu Accent Color"] end
			setTip(option)
		end
	end)

	interest.InputChanged:Connect(function(input)
		if isMove(input) then moveTip(option, input) end
	end)

	interest.InputEnded:Connect(function(input)
		if isMove(input) then
			if not option.open then stroke.Color = library.borderColor end
			clearTip()
		end
	end)

	function option:SetColor(newColor, nocallback)
		if typeof(newColor) == "table" then
			newColor = Color3.new(newColor[1], newColor[2], newColor[3])
		end
		newColor = newColor or Color3.new(1, 1, 1)
		if self.mainHolder then self:updateVisuals(newColor) end
		option.visualize.BackgroundColor3 = newColor
		self.color = newColor
		library:SetFlag(self.flag, newColor)
		if not nocallback then self.callback(newColor) end
		return newColor
	end

	if option.trans then
		function option:SetTrans(value, manual)
			value = math.clamp(tonumber(value) or 0, 0, 1)
			if self.transSlider then self.transSlider.Position = UDim2.new(0, 0, value, 0) end
			self.trans = value
			library.flags[self.flag .. " Transparency"] = 1 - value
			self.calltrans(value)
			return value
		end
		option:SetTrans(option.trans)
	end

	task.delay(1, function()
		if library then option:SetColor(option.color) end
	end)

	function option:Close()
		if library.popup == self then library.popup = nil end
		self.open = false
		self.mainHolder.Visible = false
		stroke.Color = library.borderColor
	end

	attachEnabled(option, option.title)
end

function library:AddTab(title, pos)
	local tab = {canInit = true, columns = {}, title = tostring(title)}
	table.insert(self.tabs, pos or #self.tabs + 1, tab)

	function tab:AddColumn()
		local column = {sections = {}, position = #self.columns, canInit = true, tab = self}
		table.insert(self.columns, column)

		function column:AddSection(title)
			local section = {title = tostring(title), options = {}, canInit = true, column = self}
			table.insert(self.sections, section)

			function section:AddLabel(text)
				local option = {text = text, section = self, type = "label", position = #self.options, canInit = true}
				table.insert(self.options, option)
				if library.hasInit and self.hasInit then
					library.createLabel(option, self.content)
				else
					option.Init = library.createLabel
				end
				return option
			end

			function section:AddDivider(text)
				local option = {text = text, section = self, type = "divider", position = #self.options, canInit = true}
				table.insert(self.options, option)
				if library.hasInit and self.hasInit then
					library.createDivider(option, self.content)
				else
					option.Init = library.createDivider
				end
				return option
			end

			function section:AddToggle(option)
				option = typeof(option) == "table" and option or {}
				option.section = self
				option.text = tostring(option.text)
				option.state = option.state == nil and nil or (typeof(option.state) == "boolean" and option.state or false)
				option.callback = typeof(option.callback) == "function" and option.callback or function() end
				option.type = "toggle"
				option.position = #self.options
				option.subcount = 0
				option.canInit = (option.canInit ~= nil and option.canInit) or true
				option.tip = option.tip and tostring(option.tip)
				option.style = option.style == 2
				option.flag = resolveFlag(option)
				library.flags[option.flag] = option.state
				table.insert(self.options, option)
				library.options[option.flag] = option

				function option:AddColor(subOption)
					subOption = typeof(subOption) == "table" and subOption or {}
					subOption.sub = true
					subOption.subpos = self.subcount * 24
					function subOption:getMain() return option.main end
					self.subcount = self.subcount + 1
					return section:AddColor(subOption)
				end

				function option:AddBind(subOption)
					subOption = typeof(subOption) == "table" and subOption or {}
					subOption.sub = true
					subOption.subpos = self.subcount * 24
					function subOption:getMain() return option.main end
					self.subcount = self.subcount + 1
					return section:AddBind(subOption)
				end

				function option:AddList(subOption)
					subOption = typeof(subOption) == "table" and subOption or {}
					subOption.sub = true
					function subOption:getMain() return option.main end
					self.subcount = self.subcount + 1
					return section:AddList(subOption)
				end

				function option:AddSlider(subOption)
					subOption = typeof(subOption) == "table" and subOption or {}
					subOption.sub = true
					function subOption:getMain() return option.main end
					self.subcount = self.subcount + 1
					return section:AddSlider(subOption)
				end

				if library.hasInit and self.hasInit then
					library.createToggle(option, self.content)
				else
					option.Init = library.createToggle
				end
				return option
			end

			function section:AddButton(option)
				option = typeof(option) == "table" and option or {}
				option.section = self
				option.text = tostring(option.text)
				option.callback = typeof(option.callback) == "function" and option.callback or function() end
				option.type = "button"
				option.position = #self.options
				option.subcount = 0
				option.canInit = (option.canInit ~= nil and option.canInit) or true
				option.tip = option.tip and tostring(option.tip)
				option.flag = resolveFlag(option)
				table.insert(self.options, option)
				library.options[option.flag] = option

				function option:AddBind(subOption)
					subOption = typeof(subOption) == "table" and subOption or {}
					subOption.sub = true
					subOption.subpos = self.subcount * 24
					function subOption:getMain()
						option.main.Size = UDim2.new(1, 0, 0, 40)
						return option.main
					end
					self.subcount = self.subcount + 1
					return section:AddBind(subOption)
				end

				function option:AddColor(subOption)
					subOption = typeof(subOption) == "table" and subOption or {}
					subOption.sub = true
					subOption.subpos = self.subcount * 24
					function subOption:getMain()
						option.main.Size = UDim2.new(1, 0, 0, 40)
						return option.main
					end
					self.subcount = self.subcount + 1
					return section:AddColor(subOption)
				end

				if library.hasInit and self.hasInit then
					library.createButton(option, self.content)
				else
					option.Init = library.createButton
				end
				return option
			end

			function section:AddBind(option)
				option = typeof(option) == "table" and option or {}
				option.section = self
				option.text = tostring(option.text)
				option.key = (option.key and option.key.Name) or option.key or "none"
				option.nomouse = typeof(option.nomouse) == "boolean" and option.nomouse or false
				option.mode = typeof(option.mode) == "string" and (option.mode == "toggle" or option.mode == "hold" and option.mode) or "toggle"
				option.callback = typeof(option.callback) == "function" and option.callback or function() end
				option.type = "bind"
				option.position = #self.options
				option.canInit = (option.canInit ~= nil and option.canInit) or true
				option.tip = option.tip and tostring(option.tip)
				option.flag = resolveFlag(option)
				table.insert(self.options, option)
				library.options[option.flag] = option

				if library.hasInit and self.hasInit then
					library.createBind(option, self.content)
				else
					option.Init = library.createBind
				end
				return option
			end

			function section:AddSlider(option)
				option = typeof(option) == "table" and option or {}
				option.section = self
				option.text = tostring(option.text)
				option.min = typeof(option.min) == "number" and option.min or 0
				option.max = typeof(option.max) == "number" and option.max or 0
				if option.max <= option.min then option.max = option.min + 1 end
				option.value = option.min < 0 and 0 or math.clamp(typeof(option.value) == "number" and option.value or option.min, option.min, option.max)
				option.callback = typeof(option.callback) == "function" and option.callback or function() end
				option.float = typeof(option.float) == "number" and option.float or 1
				option.suffix = option.suffix and tostring(option.suffix) or ""
				option.textpos = option.textpos == 2
				option.type = "slider"
				option.position = #self.options
				option.subcount = 0
				option.canInit = (option.canInit ~= nil and option.canInit) or true
				option.tip = option.tip and tostring(option.tip)
				option.flag = resolveFlag(option)
				library.flags[option.flag] = option.value
				table.insert(self.options, option)
				library.options[option.flag] = option

				function option:AddColor(subOption)
					subOption = typeof(subOption) == "table" and subOption or {}
					subOption.sub = true
					subOption.subpos = self.subcount * 24
					function subOption:getMain() return option.main end
					self.subcount = self.subcount + 1
					return section:AddColor(subOption)
				end

				function option:AddBind(subOption)
					subOption = typeof(subOption) == "table" and subOption or {}
					subOption.sub = true
					subOption.subpos = self.subcount * 24
					function subOption:getMain() return option.main end
					self.subcount = self.subcount + 1
					return section:AddBind(subOption)
				end

				if library.hasInit and self.hasInit then
					library.createSlider(option, self.content)
				else
					option.Init = library.createSlider
				end
				return option
			end

			function section:AddList(option)
				option = typeof(option) == "table" and option or {}
				option.section = self
				option.text = tostring(option.text)
				option.values = typeof(option.values) == "table" and option.values or {}
				option.callback = typeof(option.callback) == "function" and option.callback or function() end
				option.multiselect = typeof(option.multiselect) == "boolean" and option.multiselect or false
				option.value = option.multiselect and (typeof(option.value) == "table" and option.value or {}) or tostring(option.value or option.values[1] or "")
				if option.multiselect then
					for _, entry in next, option.values do
						option.value[entry] = false
					end
				end
				option.max = option.max or 4
				option.open = false
				option.type = "list"
				option.position = #self.options
				option.labels = {}
				option.subcount = 0
				option.canInit = (option.canInit ~= nil and option.canInit) or true
				option.tip = option.tip and tostring(option.tip)
				option.flag = resolveFlag(option)
				library.flags[option.flag] = option.value
				table.insert(self.options, option)
				library.options[option.flag] = option

				function option:AddValue(value, state)
					if self.multiselect then
						self.values[value] = state
					elseif not table.find(self.values, value) then
						table.insert(self.values, value)
					end
				end

				function option:AddColor(subOption)
					subOption = typeof(subOption) == "table" and subOption or {}
					subOption.sub = true
					subOption.subpos = self.subcount * 24
					function subOption:getMain() return option.main end
					self.subcount = self.subcount + 1
					return section:AddColor(subOption)
				end

				function option:AddBind(subOption)
					subOption = typeof(subOption) == "table" and subOption or {}
					subOption.sub = true
					subOption.subpos = self.subcount * 24
					function subOption:getMain() return option.main end
					self.subcount = self.subcount + 1
					return section:AddBind(subOption)
				end

				if library.hasInit and self.hasInit then
					library.createList(option, self.content)
				else
					option.Init = library.createList
				end
				return option
			end

			function section:AddBox(option)
				option = typeof(option) == "table" and option or {}
				option.section = self
				option.text = tostring(option.text)
				option.value = tostring(option.value or "")
				option.callback = typeof(option.callback) == "function" and option.callback or function() end
				option.type = "box"
				option.position = #self.options
				option.canInit = (option.canInit ~= nil and option.canInit) or true
				option.tip = option.tip and tostring(option.tip)
				option.flag = resolveFlag(option)
				library.flags[option.flag] = option.value
				table.insert(self.options, option)
				library.options[option.flag] = option

				if library.hasInit and self.hasInit then
					library.createBox(option, self.content)
				else
					option.Init = library.createBox
				end
				return option
			end

			function section:AddColor(option)
				option = typeof(option) == "table" and option or {}
				option.section = self
				option.text = tostring(option.text)
				option.color = typeof(option.color) == "table" and Color3.new(option.color[1], option.color[2], option.color[3]) or option.color or Color3.new(1, 1, 1)
				option.callback = typeof(option.callback) == "function" and option.callback or function() end
				option.calltrans = typeof(option.calltrans) == "function" and option.calltrans or (option.calltrans == 1 and option.callback) or function() end
				option.open = false
				option.trans = tonumber(option.trans)
				option.subcount = 0
				option.type = "color"
				option.position = #self.options
				option.canInit = (option.canInit ~= nil and option.canInit) or true
				option.tip = option.tip and tostring(option.tip)
				option.flag = resolveFlag(option)
				library.flags[option.flag] = option.color
				table.insert(self.options, option)
				library.options[option.flag] = option

				function option:AddColor(subOption)
					subOption = typeof(subOption) == "table" and subOption or {}
					subOption.sub = true
					subOption.subpos = self.subcount * 24
					function subOption:getMain() return option.main end
					self.subcount = self.subcount + 1
					return section:AddColor(subOption)
				end

				if option.trans then
					library.flags[option.flag .. " Transparency"] = option.trans
				end

				if library.hasInit and self.hasInit then
					library.createColor(option, self.content)
				else
					option.Init = library.createColor
				end
				return option
			end

			function section:SetTitle(newTitle)
				self.title = tostring(newTitle)
				if self.titleText then self.titleText.Text = self.title end
			end

			function section:Init()
				if self.hasInit then return end
				self.hasInit = true

				self.main = library:Create("Frame", {
					BackgroundColor3 = Color3.fromRGB(30, 30, 30),
					BorderSizePixel = 0,
					Parent = column.main
				})
				library:Outline(self.main, 4)

				self.content = library:Create("Frame", {
					Size = UDim2.new(1, 0, 1, 0),
					BackgroundTransparency = 1,
					Parent = self.main
				})

				themify(library:Create("Frame", {
					Size = UDim2.new(1, 0, 0, 1),
					BackgroundColor3 = library.flags["Menu Accent Color"],
					BorderSizePixel = 0,
					Parent = self.main
				}))

				local layout = library:Create("UIListLayout", {
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 2),
					Parent = self.content
				})

				library:Create("UIPadding", {
					PaddingTop = UDim.new(0, 12),
					Parent = self.content
				})

				self.titleText = library:Create("TextLabel", {
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, 12, 0, 0),
					Size = UDim2.new(0, measure(self.title) + 10, 0, 3),
					BackgroundColor3 = Color3.fromRGB(30, 30, 30),
					BorderSizePixel = 0,
					Text = self.title,
					TextSize = 15,
					Font = Enum.Font.Code,
					TextColor3 = Color3.new(1, 1, 1),
					Parent = self.main
				})

				layout.Changed:Connect(function()
					self.main.Size = UDim2.new(1, 0, 0, layout.AbsoluteContentSize.Y + 16)
				end)

				for _, option in next, self.options do
					if option.canInit then option.Init(option, self.content) end
				end
			end

			if library.hasInit and self.hasInit then section:Init() end
			return section
		end

		function column:Init()
			if self.hasInit then return end
			self.hasInit = true

			self.main = library:Create("ScrollingFrame", {
				ZIndex = 2,
				Position = UDim2.new(0, 6 + (self.position * 239), 0, 2),
				Size = UDim2.new(0, 233, 1, -4),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarImageColor3 = Color3.new(),
				ScrollBarThickness = 4,
				VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
				ScrollingDirection = Enum.ScrollingDirection.Y,
				Visible = false,
				Parent = library.columnHolder
			})

			local layout = library:Create("UIListLayout", {
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 12),
				Parent = self.main
			})

			library:Create("UIPadding", {
				PaddingTop = UDim.new(0, 8),
				PaddingLeft = UDim.new(0, 2),
				PaddingRight = UDim.new(0, 2),
				Parent = self.main
			})

			layout.Changed:Connect(function()
				self.main.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 14)
			end)

			for _, section in next, self.sections do
				if section.canInit and #section.options > 0 then section:Init() end
			end
		end

		if library.hasInit and self.hasInit then column:Init() end
		return column
	end

	function tab:Init()
		if self.hasInit then return end
		self.hasInit = true
		local size = measure(self.title, 18) + 10

		self.button = library:Create("TextLabel", {
			Position = UDim2.new(0, library.tabSize, 0, 22),
			Size = UDim2.new(0, size, 0, 30),
			BackgroundTransparency = 1,
			Text = self.title,
			TextColor3 = Color3.new(1, 1, 1),
			TextSize = 15,
			Font = Enum.Font.Code,
			TextWrapped = true,
			ClipsDescendants = true,
			Parent = library.main
		})
		library.tabSize = library.tabSize + size

		self.button.InputBegan:Connect(function(input)
			if isPress(input) then library:selectTab(self) end
		end)

		for _, column in next, self.columns do
			if column.canInit then column:Init() end
		end
	end

	if self.hasInit then tab:Init() end
	return tab
end

function library:AddWarning(warning)
	warning = typeof(warning) == "table" and warning or {}
	warning.text = tostring(warning.text)
	warning.type = warning.type == "confirm" and "confirm" or ""

	local answer

	function warning:Show()
		library.warning = warning
		if warning.main and warning.type == "" then return end
		if library.popup then library.popup:Close() end

		if not warning.main then
			warning.main = library:Create("TextButton", {
				ZIndex = 2,
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundTransparency = 0.6,
				BackgroundColor3 = Color3.new(),
				BorderSizePixel = 0,
				Text = "",
				AutoButtonColor = false,
				Parent = library.main
			})

			warning.message = library:Create("TextLabel", {
				ZIndex = 2,
				Position = UDim2.new(0, 20, 0.5, -60),
				Size = UDim2.new(1, -40, 0, 40),
				BackgroundTransparency = 1,
				TextSize = 16,
				Font = Enum.Font.Code,
				TextColor3 = Color3.new(1, 1, 1),
				TextWrapped = true,
				RichText = true,
				Parent = warning.main
			})

			local function makeButton(text, x, useAccent)
				local button = library:Create("TextLabel", {
					ZIndex = 2,
					Position = UDim2.new(0.5, x, 0.5, -10),
					Size = UDim2.new(0, 100, 0, 20),
					BackgroundColor3 = Color3.fromRGB(40, 40, 40),
					BorderSizePixel = 0,
					Text = text,
					TextSize = 16,
					Font = Enum.Font.Code,
					TextColor3 = Color3.new(1, 1, 1),
					Parent = warning.main
				})
				library:Outline(button, 3, useAccent and library.flags["Menu Accent Color"] or library.borderColor)
				button.InputBegan:Connect(function(input)
					if isPress(input) then answer = useAccent end
				end)
				return button
			end

			if warning.type == "confirm" then
				makeButton("Yes", -105, true)
				makeButton("No", 5, false)
			else
				makeButton("OK", -50, true)
			end
		end

		warning.main.Visible = true
		warning.message.Text = warning.text

		repeat task.wait() until answer ~= nil
		local result = answer
		task.spawn(warning.Close)
		library.warning = nil
		return result
	end

	function warning:Close()
		answer = nil
		if warning.main then warning.main.Visible = false end
	end

	return warning
end

function library:Close()
	self.open = not self.open
	if self.open then
		inputService.MouseIconEnabled = false
	else
		inputService.MouseIconEnabled = self.mousestate
		clearTip()
	end
	if self.main then
		if self.popup then self.popup:Close() end
		self.main.Visible = self.open
		self.cursor.Visible = self.open
		self.cursor1.Visible = self.open
	end
	return self.open
end

function library:AddWatermark(text)
	local mark = library:Create("TextLabel", {
		ZIndex = 3,
		Position = UDim2.new(0, 8, 0, 8),
		Size = UDim2.new(0, measure(text, 14) + 20, 0, 24),
		BackgroundColor3 = Color3.fromRGB(25, 25, 25),
		BorderSizePixel = 0,
		Text = tostring(text),
		TextSize = 14,
		Font = Enum.Font.Code,
		TextColor3 = Color3.new(1, 1, 1),
		Parent = library.base
	})
	library:Outline(mark, 4, library.flags["Menu Accent Color"])

	function mark:SetText(newText)
		self.Text = tostring(newText)
		self.Size = UDim2.new(0, measure(newText, 14) + 20, 0, 24)
	end

	return mark
end

function library:Init()
	if self.hasInit then return end
	self.hasInit = true

	self.base = library:Create("ScreenGui", {
		Name = "uwuware",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Global
	})

	local function parentGui(gui)
		if runService:IsStudio() then
			gui.Parent = playersService.LocalPlayer:WaitForChild("PlayerGui")
			return
		end
		if typeof(gethui) == "function" then
			local ok = pcall(function() gui.Parent = gethui() end)
			if ok and gui.Parent then return end
		end
		if typeof(get_hidden_gui) == "function" then
			local ok = pcall(function() gui.Parent = get_hidden_gui() end)
			if ok and gui.Parent then return end
		end
		local ok = pcall(function() gui.Parent = game:GetService("CoreGui") end)
		if not ok or not gui.Parent then
			gui.Parent = playersService.LocalPlayer:WaitForChild("PlayerGui")
		end
	end
	parentGui(self.base)

	if COMPAT.isTouch then
		local scale = library:Create("UIScale", {Parent = self.base})
		local size = viewport()
		scale.Scale = math.clamp(math.min(size.X / 620, size.Y / 700), 0.45, 1)
	end

	self.main = self:Create("ImageButton", {
		AutoButtonColor = false,
		Position = UDim2.new(0, 100, 0, 46),
		Size = UDim2.new(0, 500, 0, 600),
		BackgroundColor3 = Color3.fromRGB(20, 20, 20),
		BorderSizePixel = 0,
		ScaleType = Enum.ScaleType.Tile,
		Modal = true,
		Visible = false,
		Parent = self.base
	})
	library:Outline(self.main, 5)

	self.top = self:Create("Frame", {
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundColor3 = Color3.fromRGB(30, 30, 30),
		BorderSizePixel = 0,
		Parent = self.main
	})

	self:Create("TextLabel", {
		Position = UDim2.new(0, 10, 0, 3),
		Size = UDim2.new(1, -20, 0, 20),
		BackgroundTransparency = 1,
		Text = tostring(self.title),
		Font = Enum.Font.Code,
		TextSize = 18,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = self.main
	})

	themify(self:Create("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 0, 26),
		BackgroundColor3 = library.flags["Menu Accent Color"],
		BorderSizePixel = 0,
		Parent = self.main
	}))

	self.tabHighlight = self:Create("Frame", {
		BackgroundColor3 = library.flags["Menu Accent Color"],
		BorderSizePixel = 0,
		Parent = self.main
	})
	themify(self.tabHighlight)

	self.columnHolder = self:Create("Frame", {
		Position = UDim2.new(0, 5, 0, 55),
		Size = UDim2.new(1, -10, 1, -60),
		BackgroundTransparency = 1,
		Parent = self.main
	})

	self.cursor = self:Create("Triangle", {Color = Color3.fromRGB(180, 180, 180), Transparency = 0.6})
	self.cursor1 = self:Create("Triangle", {Color = Color3.fromRGB(240, 240, 240), Transparency = 0.6})

	self.tooltip = self:Create("TextLabel", {
		ZIndex = 2,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		TextSize = 15,
		Font = Enum.Font.Code,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = self.base
	})
	self:Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(1, 14, 1, 0),
		Style = Enum.FrameStyle.RobloxRound,
		Parent = self.tooltip
	})

	self.top.InputBegan:Connect(function(input)
		if not isPress(input) then return end
		dragObject = self.main
		dragging = true
		dragStart = input.Position
		startPos = dragObject.Position
		if library.popup then library.popup:Close() end
	end)

	self.top.InputChanged:Connect(function(input)
		if dragging and isMove(input) then dragInput = input end
	end)

	self.top.InputEnded:Connect(function(input)
		if isPress(input) then dragging = false end
	end)

	function self:selectTab(tab)
		if self.currentTab == tab then return end
		if library.popup then library.popup:Close() end
		if self.currentTab then
			self.currentTab.button.TextColor3 = Color3.fromRGB(255, 255, 255)
			for _, column in next, self.currentTab.columns do
				column.main.Visible = false
			end
		end
		local width = #tab.columns < 2 and 2 or #tab.columns
		self.main.Size = UDim2.new(0, 16 + (width * 239), 0, 600)
		self.currentTab = tab
		tab.button.TextColor3 = library.flags["Menu Accent Color"]
		self.tabHighlight:TweenPosition(UDim2.new(0, tab.button.Position.X.Offset, 0, 50), "Out", "Quad", 0.2, true)
		self.tabHighlight:TweenSize(UDim2.new(0, tab.button.AbsoluteSize.X, 0, -1), "Out", "Quad", 0.1, true)
		for _, column in next, tab.columns do
			column.main.Visible = true
		end
	end

	if library.canSave then
		task.spawn(function()
			while library do
				task.wait(1)
				local configs = self:GetConfigs()
				local list = self.options["Config List"]
				if list then
					for _, config in next, configs do
						if not table.find(list.values, config) then list:AddValue(config) end
					end
					for _, config in next, list.values do
						if not table.find(configs, config) then list:RemoveValue(config) end
					end
				end
			end
		end)
	end

	for _, tab in next, self.tabs do
		if tab.canInit then tab:Init() end
	end
	if self.tabs[1] then self:selectTab(self.tabs[1]) end

	self:AddConnection(inputService.InputEnded, function(input)
		if isPress(input) and self.slider then
			self.slider.slider.BorderColor3 = library.borderColor
			self.slider = nil
		end
	end)

	self:AddConnection(inputService.InputChanged, function(input)
		if not self.open or not isMove(input) then return end
		local mouse = inputService:GetMouseLocation()
		local mousePos = Vector2.new(mouse.X, mouse.Y)
		self.cursor.PointA = mousePos
		self.cursor.PointB = mousePos + Vector2.new(12, 12)
		self.cursor.PointC = mousePos + Vector2.new(12, 12)
		self.cursor1.PointA = mousePos
		self.cursor1.PointB = mousePos + Vector2.new(11, 11)
		self.cursor1.PointC = mousePos + Vector2.new(11, 11)
		if self.slider then
			self.slider:SetValue(self.slider.min + ((input.Position.X - self.slider.slider.AbsolutePosition.X) / self.slider.slider.AbsoluteSize.X) * (self.slider.max - self.slider.min))
		end
		if input == dragInput and dragging and library.draggable then
			local size = viewport()
			local delta = input.Position - dragStart
			local newX = math.clamp(startPos.X.Offset + delta.X, -(dragObject.AbsoluteSize.X - 70), size.X - 70)
			local newY = math.clamp(startPos.Y.Offset + delta.Y, -40, size.Y - 40)
			dragObject:TweenPosition(UDim2.new(0, newX, 0, newY), "Out", "Quint", 0.1, true)
		end
	end)

	if COMPAT.hasRawMeta then
		local mt = getrawmetatable(game)
		local oldIndex, oldNewIndex = mt.__index, mt.__newindex
		local wasReadonly = not mt.__newindex
		if wasReadonly then setreadonly(mt, false) end
		mt.__index = wrap(function(t, i)
			if checkcaller() then return oldIndex(t, i) end
			if library and i == "MouseIconEnabled" then return library.mousestate end
			return oldIndex(t, i)
		end)
		mt.__newindex = wrap(function(t, i, v)
			if checkcaller() then return oldNewIndex(t, i, v) end
			if library and i == "MouseIconEnabled" then
				library.mousestate = v
				if library.open then return end
			end
			return oldNewIndex(t, i, v)
		end)
		if wasReadonly then setreadonly(mt, true) end
		self.restoreHooks = function()
			if wasReadonly then setreadonly(mt, false) end
			mt.__index = oldIndex
			mt.__newindex = oldNewIndex
			if wasReadonly then setreadonly(mt, true) end
		end
	elseif COMPAT.hasHook then
		local oldIndex
		oldIndex = hookmetamethod(game, "__index", function(t, i)
			if checkcaller() then return oldIndex(t, i) end
			if library and i == "MouseIconEnabled" then return library.mousestate end
			return oldIndex(t, i)
		end)
		local oldNewIndex
		oldNewIndex = hookmetamethod(game, "__newindex", function(t, i, v)
			if checkcaller() then return oldNewIndex(t, i, v) end
			if library and i == "MouseIconEnabled" then
				library.mousestate = v
				if library.open then return end
			end
			return oldNewIndex(t, i, v)
		end)
		self.restoreHooks = function()
			if typeof(restorefunction) == "function" then
				pcall(restorefunction, oldIndex)
				pcall(restorefunction, oldNewIndex)
			end
		end
	end

	if not getgenv().silent then
		task.delay(1, function()
			if library then self:Close() end
		end)
	end
end

library.SettingsTab = library:AddTab("Settings", 100)
library.SettingsColumn = library.SettingsTab:AddColumn()
library.SettingsColumn1 = library.SettingsTab:AddColumn()

library.SettingsMain = library.SettingsColumn:AddSection("Main")
library.SettingsMain:AddButton({text = "Unload Cheat", nomouse = true, callback = function()
	library:Unload()
end})
library.SettingsMain:AddBind({text = "Panic Key", callback = library.options["Unload Cheat"].callback})

library.SettingsMenu = library.SettingsColumn:AddSection("Menu")
library.SettingsMenu:AddBind({text = "Open / Close", flag = "UI Toggle", nomouse = true, key = "Insert", callback = function() library:Close() end})
library.SettingsMenu:AddColor({text = "Accent Color", flag = "Menu Accent Color", color = Color3.fromRGB(255, 65, 65), callback = function(Color)
	library:SetRainbow(false)
	library:ApplyAccent(Color)
end})
library.SettingsMenu:AddToggle({text = "Rainbow Accent", flag = "Rainbow Accent", callback = function(state)
	library:SetRainbow(state)
end})

local Backgrounds = {
	["Floral"] = 5553946656,
	["Flowers"] = 6071575925,
	["Circles"] = 6071579801,
	["Hearts"] = 6073763717,
	["Polka dots"] = 6214418014,
	["Mountains"] = 6214412460,
	["Zigzag"] = 6214416834,
	["Zigzag 2"] = 6214375242,
	["Tartan"] = 6214404863,
	["Roses"] = 6214374619,
	["Hexagons"] = 6214320051,
	["Leopard print"] = 6214318622
}

library.SettingsMenu:AddList({text = "Background", flag = "UI Background", max = 6, values = {"Floral", "Flowers", "Circles", "Hearts", "Polka dots", "Mountains", "Zigzag", "Zigzag 2", "Tartan", "Roses", "Hexagons", "Leopard print"}, callback = function(Value)
	if Backgrounds[Value] then library.main.Image = "rbxassetid://" .. Backgrounds[Value] end
end}):AddColor({flag = "Menu Background Color", color = Color3.new(), callback = function(Color)
	library.main.ImageColor3 = Color
end, trans = 1, calltrans = function(Value)
	library.main.ImageTransparency = 1 - Value
end})

library.SettingsMenu:AddSlider({text = "Tile Size", value = 90, min = 50, max = 500, callback = function(Value)
	library.main.TileSize = UDim2.new(0, Value, 0, Value)
end})

if library.canSave then
	library.ConfigSection = library.SettingsColumn1:AddSection("Configs")
	library.ConfigSection:AddBox({text = "Config Name", skipflag = true})
	library.ConfigSection:AddButton({text = "Create", callback = function()
		local name = library.flags["Config Name"]
		if name == "" then return end
		pcall(function() writefile(library.foldername .. "/" .. name .. library.fileext, "{}") end)
		library.options["Config List"]:AddValue(name)
	end})
	library.ConfigWarning = library:AddWarning({type = "confirm"})
	library.ConfigSection:AddList({text = "Configs", skipflag = true, value = "", flag = "Config List", values = library:GetConfigs()})
	library.ConfigSection:AddButton({text = "Save", callback = function()
		local r, g, b = library.roundRGB(library.flags["Menu Accent Color"])
		library.ConfigWarning.text = "Are you sure you want to save the current settings to config <font color='rgb(" .. r .. "," .. g .. "," .. b .. ")'>" .. library.flags["Config List"] .. "</font>?"
		if library.ConfigWarning:Show() then library:SaveConfig(library.flags["Config List"]) end
	end})
	library.ConfigSection:AddButton({text = "Load", callback = function()
		local r, g, b = library.roundRGB(library.flags["Menu Accent Color"])
		library.ConfigWarning.text = "Are you sure you want to load config <font color='rgb(" .. r .. "," .. g .. "," .. b .. ")'>" .. library.flags["Config List"] .. "</font>?"
		if library.ConfigWarning:Show() then library:LoadConfig(library.flags["Config List"]) end
	end})
	library.ConfigSection:AddButton({text = "Delete", callback = function()
		local r, g, b = library.roundRGB(library.flags["Menu Accent Color"])
		library.ConfigWarning.text = "Are you sure you want to delete config <font color='rgb(" .. r .. "," .. g .. "," .. b .. ")'>" .. library.flags["Config List"] .. "</font>?"
		if library.ConfigWarning:Show() then
			local config = library.flags["Config List"]
			if table.find(library:GetConfigs(), config) then
				library.options["Config List"]:RemoveValue(config)
				pcall(function() delfile(library.foldername .. "/" .. config .. library.fileext) end)
			end
		end
	end})
else
	library.SettingsColumn1:AddSection("Configs"):AddLabel("No filesystem available")
end

local lastNotification = 0

function library:SendNotification(duration, message)
	if not library.base then return end
	if os.clock() - lastNotification < 0.2 then return end
	lastNotification = os.clock()

	if duration then
		duration = tonumber(duration) or 2
		if duration < 2 then duration = 2 end
	else
		duration = message
	end
	message = message and tostring(message) or "Empty"

	local notification = library:Create("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		Size = UDim2.new(0, 0, 0, 80),
		Position = UDim2.new(1, -5, 1, -5),
		BackgroundTransparency = 1,
		BackgroundColor3 = Color3.fromRGB(30, 30, 30),
		BorderSizePixel = 0,
		Parent = library.base
	})
	library:Outline(notification, 4, Color3.fromRGB(20, 20, 20))
	tweenService:Create(notification, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(0, 240, 0, 80), BackgroundTransparency = 0}):Play()

	tweenService:Create(library:Create("TextLabel", {
		Position = UDim2.new(0, 8, 0, 24),
		Size = UDim2.new(1, -16, 0, 40),
		BackgroundTransparency = 1,
		Text = message,
		Font = Enum.Font.SourceSans,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 18,
		TextTransparency = 1,
		TextWrapped = true,
		Parent = notification
	}), TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.3), {TextTransparency = 0}):Play()

	for _, other in next, library.notifications do
		other:TweenPosition(UDim2.new(1, -5, 1, other.Position.Y.Offset - 85), "Out", "Quad", 0.2)
	end
	library.notifications[notification] = notification

	task.wait(0.4)

	library:Create("Frame", {
		Position = UDim2.new(0, 0, 0, 20),
		Size = UDim2.new(0, 0, 0, 1),
		BackgroundColor3 = library.flags["Menu Accent Color"],
		BorderSizePixel = 0,
		Parent = notification
	}):TweenSize(UDim2.new(1, 0, 0, 1), "Out", "Linear", duration)

	tweenService:Create(library:Create("TextLabel", {
		Position = UDim2.new(0, 8, 0, 0),
		Size = UDim2.new(0, 90, 0, 18),
		BackgroundTransparency = 1,
		Text = "uwuware",
		Font = Enum.Font.Gotham,
		TextColor3 = library.flags["Menu Accent Color"],
		TextSize = 16,
		TextTransparency = 1,
		Parent = notification
	}), TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency = 0}):Play()

	task.delay(duration, function()
		if not library then return end
		library.notifications[notification] = nil
		for _, other in next, library.notifications do
			if other.Position.Y.Offset < notification.Position.Y.Offset then
				other:TweenPosition(UDim2.new(1, -5, 1, other.Position.Y.Offset + 85), "Out", "Quad", 0.2)
			end
		end
		notification:Destroy()
	end)
end

function library:Notify(message, duration)
	return library:SendNotification(duration, message)
end

return library
