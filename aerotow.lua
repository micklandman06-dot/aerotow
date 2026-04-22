return function()
	print("[Aerotow] Core gestart.")
    
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")


local ROPE_LENGTH = 220
local BREAK_DISTANCE = 300

local SPRING_K = 2200
local DAMPING = 260
local MAX_FORCE = 65000
local MIN_START_DISTANCE = 8

local CABLE_THICKNESS = 0.09
local CABLE_COLOR = ColorSequence.new(
	Color3.fromRGB(30, 30, 30),
	Color3.fromRGB(18, 18, 18)
)

local MIDPOINT_BASE_SAG = 2.5
local MIDPOINT_SLACK_MULT = 0.18
local MIDPOINT_TENSION_SAG = 0.8


local actionEvent = ReplicatedStorage:FindFirstChild("AerotowAction")
if not actionEvent then
	actionEvent = Instance.new("RemoteEvent")
	actionEvent.Name = "AerotowAction"
	actionEvent.Parent = ReplicatedStorage
end


local visualsFolder = Workspace:FindFirstChild("AerotowVisuals")
if not visualsFolder then
	visualsFolder = Instance.new("Folder")
	visualsFolder.Name = "AerotowVisuals"
	visualsFolder.Parent = Workspace
end


local pendingConnections = {}         
local activeTowsByGlider = {}         
local activeTowsByTug = {}            



local function findAircraftModel(part)
	local current = part
	while current and current ~= Workspace do
		if current:IsA("Model") and current.PrimaryPart then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function getAircraftPilot(aircraft)
	if not aircraft then
		return nil
	end

	local pilotSeat = aircraft:FindFirstChild("PilotSeat", true)
	if pilotSeat and (pilotSeat:IsA("Seat") or pilotSeat:IsA("VehicleSeat")) then
		local occupant = pilotSeat.Occupant
		if occupant and occupant.Parent then
			local player = Players:GetPlayerFromCharacter(occupant.Parent)
			if player then
				return player
			end
		end
	end

	for _, descendant in ipairs(aircraft:GetDescendants()) do
		if descendant:IsA("Seat") or descendant:IsA("VehicleSeat") then
			local occupant = descendant.Occupant
			if occupant and occupant.Parent then
				local player = Players:GetPlayerFromCharacter(occupant.Parent)
				if player then
					return player
				end
			end
		end
	end

	return nil
end

local function getOrCreateAttachment(part, attachmentName)
	local att = part:FindFirstChild(attachmentName)
	if att and att:IsA("Attachment") then
		return att
	end

	att = Instance.new("Attachment")
	att.Name = attachmentName
	att.Parent = part
	return att
end

local function getPrimaryAttachment(model)
	local primary = model.PrimaryPart
	if not primary then
		return nil
	end

	local att = primary:FindFirstChild("AerotowForceAttachment")
	if att and att:IsA("Attachment") then
		return att
	end

	att = Instance.new("Attachment")
	att.Name = "AerotowForceAttachment"
	att.Position = Vector3.new(0, 0, 0)
	att.Parent = primary
	return att
end

local function createBeam(attachment0, attachment1, name)
	local beam = Instance.new("Beam")
	beam.Name = name or "AerotowBeam"
	beam.Attachment0 = attachment0
	beam.Attachment1 = attachment1
	beam.FaceCamera = true
	beam.Segments = 24
	beam.Width0 = CABLE_THICKNESS
	beam.Width1 = CABLE_THICKNESS
	beam.Color = CABLE_COLOR
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.03),
		NumberSequenceKeypoint.new(0.5, 0.0),
		NumberSequenceKeypoint.new(1, 0.03),
	})
	beam.LightEmission = 0
	beam.LightInfluence = 1
	beam.TextureSpeed = 0
	beam.Parent = visualsFolder
	return beam
end

local function createCableVisual(tugAttachment, gliderAttachment, keyName)
	local midPart = Instance.new("Part")
	midPart.Name = keyName .. "_Midpoint"
	midPart.Size = Vector3.new(0.2, 0.2, 0.2)
	midPart.Anchored = true
	midPart.CanCollide = false
	midPart.CanQuery = false
	midPart.CanTouch = false
	midPart.Transparency = 1
	midPart.Massless = true
	midPart.Parent = visualsFolder

	local midAttachment = Instance.new("Attachment")
	midAttachment.Name = keyName .. "_MidAttachment"
	midAttachment.Parent = midPart

	local beam1 = createBeam(tugAttachment, midAttachment, keyName .. "_BeamA")
	local beam2 = createBeam(midAttachment, gliderAttachment, keyName .. "_BeamB")

	return {
		midPart = midPart,
		midAttachment = midAttachment,
		beam1 = beam1,
		beam2 = beam2,
	}
end

local function createGliderForce(gliderModel)
	local primary = gliderModel.PrimaryPart
	if not primary then
		return nil
	end

	local attachment = getPrimaryAttachment(gliderModel)
	if not attachment then
		return nil
	end

	local vf = primary:FindFirstChild("AerotowForce")
	if vf and vf:IsA("VectorForce") then
		return vf
	end

	vf = Instance.new("VectorForce")
	vf.Name = "AerotowForce"
	vf.Attachment0 = attachment
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.ApplyAtCenterOfMass = true
	vf.Force = Vector3.zero
	vf.Parent = primary

	return vf
end

local function setNetworkOwner(model, player)
	if not model or not model.PrimaryPart then
		return
	end

	pcall(function()
		model.PrimaryPart:SetNetworkOwner(player)
	end)
end

local function setBoolFlag(model, flagName, value)
	if not model then
		return
	end

	local found = model:FindFirstChild(flagName, true)
	if found and found:IsA("BoolValue") then
		found.Value = value
	end
end

local function getEngineState(tugModel)
	if not tugModel then
		return false
	end

	local attr = tugModel:GetAttribute("EngineOn")
	if typeof(attr) == "boolean" then
		return attr
	end

	local boolValue = tugModel:FindFirstChild("EngineOn", true)
	if boolValue and boolValue:IsA("BoolValue") then
		return boolValue.Value
	end

	return false
end

local function setEngineState(tugModel, on)
	if not tugModel then
		return
	end

	tugModel:SetAttribute("EngineOn", on)

	local boolValue = tugModel:FindFirstChild("EngineOn", true)
	if boolValue and boolValue:IsA("BoolValue") then
		boolValue.Value = on
	end
end

local function findSound(model, possibleNames)
	if not model then
		return nil
	end

	for _, name in ipairs(possibleNames) do
		local s = model:FindFirstChild(name, true)
		if s and s:IsA("Sound") then
			return s
		end
	end

	return nil
end

local function playOneShot(sound)
	if not sound then
		return
	end

	pcall(function()
		sound.TimePosition = 0
		sound:Play()
	end)
end

local function ensureRunningSound(tugModel, on)
	local runningSound = findSound(tugModel, {
		"EngineRunning",
		"EngineLoop",
		"Engine",
		"RunSound",
	})

	if runningSound then
		runningSound.Looped = true
		if on then
			if not runningSound.IsPlaying then
				runningSound:Play()
			end
		else
			if runningSound.IsPlaying then
				runningSound:Stop()
			end
		end
	end
end

local function startTugEngine(tugModel, towData)
	if not tugModel then
		return
	end

	if towData.engineWasOnBeforeTow then
		setEngineState(tugModel, true)
		ensureRunningSound(tugModel, true)
		return
	end

	local startSound = findSound(tugModel, {
		"EngineStart",
		"StartSound",
		"Ignition",
		"EngineIgnition",
	})

	setEngineState(tugModel, true)
	playOneShot(startSound)
	ensureRunningSound(tugModel, true)
end

local function restoreTugEngine(tugModel, towData)
	if not tugModel then
		return
	end

	if towData.engineWasOnBeforeTow then
		setEngineState(tugModel, true)
		ensureRunningSound(tugModel, true)
		return
	end

	local stopSound = findSound(tugModel, {
		"EngineStop",
		"StopSound",
		"Shutdown",
	})

	playOneShot(stopSound)
	setEngineState(tugModel, false)
	ensureRunningSound(tugModel, false)
end

local function clearTowByGlider(gliderModel, reason)
	local towData = activeTowsByGlider[gliderModel]
	if not towData then
		return
	end

	if towData.beam1 then
		towData.beam1:Destroy()
	end
	if towData.beam2 then
		towData.beam2:Destroy()
	end
	if towData.midPart then
		towData.midPart:Destroy()
	end
	if towData.force then
		towData.force:Destroy()
	end

	if towData.gliderModel and towData.gliderModel.Parent then
		setBoolFlag(towData.gliderModel, "Active", false)
		towData.gliderModel:SetAttribute("AerotowActive", false)
		towData.gliderModel:SetAttribute("AerotowTowPlane", nil)
	end

	if towData.tugModel and towData.tugModel.Parent then
		setBoolFlag(towData.tugModel, "On", false)
		towData.tugModel:SetAttribute("AerotowActive", false)
		towData.tugModel:SetAttribute("AerotowGlider", nil)
		restoreTugEngine(towData.tugModel, towData)
	end

	activeTowsByGlider[gliderModel] = nil
	if towData.tugModel then
		activeTowsByTug[towData.tugModel] = nil
	end

	print(("Aerotow gestopt: %s (%s)"):format(gliderModel.Name, reason or "unknown"))
end

local function canRelease(player, gliderModel)
	local towData = activeTowsByGlider[gliderModel]
	if not towData then
		return false
	end
	return player == towData.gliderPilot
end

local function canCut(player, gliderModel)
	local towData = activeTowsByGlider[gliderModel]
	if not towData then
		return false
	end
	return player == towData.tugPilot
end

local function getCurrentAircraftFromPlayer(player)
	local character = player.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	local seat = humanoid.SeatPart
	if not seat then
		return nil
	end

	return findAircraftModel(seat)
end

local function startTow(tugHook, gliderHook, initiatorPlayer)
	local tugModel = findAircraftModel(tugHook)
	local gliderModel = findAircraftModel(gliderHook)

	if not tugModel or not gliderModel then
		warn("Aircraft model not found")
		return
	end

	if tugModel == gliderModel then
		warn("Tug and glider cant be the same model")
		return
	end

	if activeTowsByGlider[gliderModel] then
		warn("This glider is already being towed")
		return
	end

	if activeTowsByTug[tugModel] then
		warn("This tug id already used")
		return
	end

	local tugPilot = getAircraftPilot(tugModel)
	local gliderPilot = getAircraftPilot(gliderModel)

	print("Tug model:", tugModel:GetFullName())
	print("Tug pilot:", tugPilot and tugPilot.Name or "nil")
	print("Glider model:", gliderModel:GetFullName())
	print("Glider pilot:", gliderPilot and gliderPilot.Name or "nil")
	print("Initiator:", initiatorPlayer and initiatorPlayer.Name or "nil")

	if not gliderPilot then
		warn("No glider pilot found in pilot seat")
		return
	end

	local tugAttachment = getOrCreateAttachment(tugHook, "TowAttachment")
	local gliderAttachment = getOrCreateAttachment(gliderHook, "GliderAttachment")

	local initialDistance = (tugAttachment.WorldPosition - gliderAttachment.WorldPosition).Magnitude
	if initialDistance < MIN_START_DISTANCE then
		warn("Planes are to close to connect")
		return
	end

	local force = createGliderForce(gliderModel)
	if not force then
		warn("Could not create glider force")
		return
	end

	local cableVisual = createCableVisual(tugAttachment, gliderAttachment, tugModel.Name .. "_to_" .. gliderModel.Name)

	local engineWasOnBeforeTow = getEngineState(tugModel)
	startTugEngine(tugModel, { engineWasOnBeforeTow = engineWasOnBeforeTow })

	local towData = {
		tugModel = tugModel,
		gliderModel = gliderModel,
		tugPilot = tugPilot,
		gliderPilot = gliderPilot,
		tugHook = tugHook,
		gliderHook = gliderHook,
		tugAttachment = tugAttachment,
		gliderAttachment = gliderAttachment,
		force = force,

		midPart = cableVisual.midPart,
		midAttachment = cableVisual.midAttachment,
		beam1 = cableVisual.beam1,
		beam2 = cableVisual.beam2,

		engineWasOnBeforeTow = engineWasOnBeforeTow,
	}

	activeTowsByGlider[gliderModel] = towData
	activeTowsByTug[tugModel] = towData

	tugModel:SetAttribute("AerotowActive", true)
	tugModel:SetAttribute("AerotowGlider", gliderModel.Name)
	gliderModel:SetAttribute("AerotowActive", true)
	gliderModel:SetAttribute("AerotowTowPlane", tugModel.Name)

	setBoolFlag(tugModel, "On", true)
	setBoolFlag(gliderModel, "Active", true)

	if tugPilot then
		setNetworkOwner(tugModel, tugPilot)
	end
	if gliderPilot then
		setNetworkOwner(gliderModel, gliderPilot)
	end

	print(("Aerotow started: %s -> %s"):format(tugModel.Name, gliderModel.Name))
end

local function onTowHookClick(tugHook, player)
	local tugModel = findAircraftModel(tugHook)
	if not tugModel then
		return
	end

	pendingConnections[player] = {
		tugHook = tugHook,
		tugModel = tugModel,
		tugPilot = getAircraftPilot(tugModel),
	}

	print(player.Name .. " clicked the towhook. click now on the gliderhook.")
end

local function onGliderHookClick(gliderHook, player)
	local pending = pendingConnections[player]
	if not pending then
		warn("First click on the tow hook")
		return
	end

	local gliderModel = findAircraftModel(gliderHook)
	if not gliderModel then
		return
	end

	local gliderPilot = getAircraftPilot(gliderModel)
	if not gliderPilot then
		warn("No glider pilot found in pilot seat")
		return
	end

	startTow(pending.tugHook, gliderHook, player)
	pendingConnections[player] = nil
end

local function connectHook(part)
	if not part:IsA("BasePart") then
		return
	end

	if part.Name == "TowHook" then
		local cd = part:FindFirstChildOfClass("ClickDetector")
		if cd then
			cd.MouseClick:Connect(function(player)
				onTowHookClick(part, player)
			end)
		end
	elseif part.Name == "GliderHook" then
		local cd = part:FindFirstChildOfClass("ClickDetector")
		if cd then
			cd.MouseClick:Connect(function(player)
				onGliderHookClick(part, player)
			end)
		end
	end
end


for _, descendant in ipairs(Workspace:GetDescendants()) do
	connectHook(descendant)
end


Workspace.DescendantAdded:Connect(function(descendant)
	task.wait(0.05)
	connectHook(descendant)
end)


actionEvent.OnServerEvent:Connect(function(player, action)
	if typeof(action) ~= "string" then
		return
	end

	local aircraft = getCurrentAircraftFromPlayer(player)
	if not aircraft then
		return
	end

	local towData = activeTowsByGlider[aircraft]
	if not towData then
		return
	end

	if action == "Release" then
		if canRelease(player, aircraft) then
			clearTowByGlider(aircraft, "Release door gliderpilot")
		end
	elseif action == "Cut" then
		if canCut(player, aircraft) then
			clearTowByGlider(aircraft, "Cut door tugpilot")
		end
	end
end)


RunService.Heartbeat:Connect(function()
	for gliderModel, towData in pairs(activeTowsByGlider) do
		if not gliderModel.Parent or not towData.tugModel.Parent then
			clearTowByGlider(gliderModel, "Aircraft verwijderd")
			continue
		end

		local tugPrimary = towData.tugModel.PrimaryPart
		local gliderPrimary = gliderModel.PrimaryPart

		if not tugPrimary or not gliderPrimary then
			clearTowByGlider(gliderModel, "Geen PrimaryPart")
			continue
		end

		if not towData.tugAttachment.Parent or not towData.gliderAttachment.Parent then
			clearTowByGlider(gliderModel, "Attachment verwijderd")
			continue
		end

		local tugPos = towData.tugAttachment.WorldPosition
		local gliderPos = towData.gliderAttachment.WorldPosition
		local offset = tugPos - gliderPos
		local distance = offset.Magnitude

		if distance > BREAK_DISTANCE then
			clearTowByGlider(gliderModel, "Kabel gebroken")
			continue
		end

		if distance < 0.05 then
			towData.force.Force = Vector3.zero
			continue
		end

		local direction = offset / distance
		local stretch = math.max(0, distance - ROPE_LENGTH)

		local gliderVel = gliderPrimary.AssemblyLinearVelocity
		local tugVel = tugPrimary.AssemblyLinearVelocity
		local relVel = (gliderVel - tugVel):Dot(direction)

		local forceMag = (stretch * SPRING_K) - (relVel * DAMPING)
		forceMag = math.clamp(forceMag, 0, MAX_FORCE)

		if stretch <= 0 then
			towData.force.Force = Vector3.zero
		else
			towData.force.Force = direction * forceMag
		end

		-- mooiere slack / spanning visual
		local midPos = (tugPos + gliderPos) * 0.5
		local slack = math.max(0, ROPE_LENGTH - distance)
		local tension = math.clamp((distance - ROPE_LENGTH) / ROPE_LENGTH, 0, 1)

		local sag = MIDPOINT_BASE_SAG
			+ (slack * MIDPOINT_SLACK_MULT)
		- (tension * MIDPOINT_TENSION_SAG)

		if sag < 0.15 then
			sag = 0.15
		end

		local visualMid = midPos - Vector3.new(0, sag, 0)
		towData.midPart.CFrame = CFrame.new(visualMid)

		setBoolFlag(towData.gliderModel, "Active", true)
		setBoolFlag(towData.tugModel, "On", true)
	end
end)

print("Aerotow Server gestart")

end