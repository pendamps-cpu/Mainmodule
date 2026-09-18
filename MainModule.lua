local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local soundService = game:GetService("SoundService")
local TeamService = game:GetService("Teams")

local badgeService = game:GetService("BadgeService")

local seekerChanceTable = {}
local seekerChance =  {}

local teams = {
	["Hider"] = TeamService.Hiders,
	["Robbers"] = TeamService.Robbers,
	["Seeker"] = TeamService.Seeker,
	["Police"] = TeamService.Police,
	["Lobby"] = TeamService.Lobby,
	["Team1"] = TeamService.Team1,
	["Team2"] = TeamService.Team2,
}

print(teams)

local limbs = {
	"RightArm",
	"LeftArm",
	"Torso",
	"Head",
	"RightLeg",
	"LeftLeg",
}

local controllerFolder = script.Parent
local mapDataModule = require(controllerFolder.MapData)
local globalData = require(controllerFolder.GlobalData)

local Spawners = workspace:WaitForChild("MapSpawns")

local Guns = ServerStorage:WaitForChild("Weapons")
local Items = ServerStorage:WaitForChild("Items")
local Lighting = game:GetService("Lighting")

local currentState = "WAITING"

local currentMap = nil
local currentMapData = nil

local guarenteedMap = nil
local guarenteedJugg = nil

local currentRoundMusic = nil
local currentPoliceMusic = nil
local currentLobbyMusic = nil

local policeTimerTask = nil
local seekerTimerTask = nil

local currentSeekerPlayer = nil

local lastMap = nil
local lastSeeker = nil

local lobbyMusics = {soundService.LobbyTheme}

local currentEndResult = ""
local seekerSlain = false
local currentCasualities = {}

local helperModule = {}

-- Forward declaration so Initialize() can call loadJuggernautWins()
-- (the actual implementation is defined later in this file).
local loadJuggernautWins


-- Search gun folders for a specified string.
function helperModule.SearchGunsForString(gunName)
	local toSearch = {Guns, ServerStorage, Items, ServerStorage.Melees}
	
	for i, tableToCheck in ipairs(toSearch) do
		if tableToCheck:FindFirstChild(gunName) then return tableToCheck:FindFirstChild(gunName) end
	end
end

function helperModule.SetGuarenteedMap(mapName)
	guarenteedMap = mapName
end

function helperModule.SetGuarenteedJugg(jugg)
	guarenteedJugg = jugg
end

function helperModule.GetMapAndData()
	return currentMap, currentMapData
end

function helperModule.KillTasks()
	if seekerTimerTask then
		pcall(function()-- pcall everything dammit
			task.cancel(seekerTimerTask)
		end)
	end
	
	if policeTimerTask then
		pcall(function()
			task.cancel(policeTimerTask)
		end)
	end
	
	seekerTimerTask = nil policeTimerTask = nil
end

-- Set the status. Does it fade afterwards aswell?
function helperModule.SetPlayerRoleAndStatus(plr, status, role, doesFade)
	pcall(function()
		local playerGui = plr:WaitForChild("PlayerGui")
		local statusGui = playerGui:WaitForChild("StatusGUI")
		local statusLbl = statusGui:WaitForChild("StatusLabel")
		local roleLbl = statusGui:WaitForChild("ROLE") :: TextLabel

		statusLbl.Visible = true
		roleLbl.Visible = true

		if role == "CIVILIAN" then
			roleLbl.TextColor3 = Color3.new(0.490196, 1, 0.490196)
		elseif role == "POLICE" then
			roleLbl.TextColor3 = Color3.new(0.282353, 0.321569, 0.678431)
		elseif role == "SEEKER" then
			roleLbl.TextColor3 = Color3.new(0.678431, 0.247059, 0.254902)
		end

		if status then
			statusLbl.Text = status
		end

		if role then
			roleLbl.Text = role
		end

		if doesFade then
			task.delay(2, function()
				pcall(function()
					statusLbl.Visible = false
					roleLbl.Visible = false
				end)
			end)
		end
	end)
end

function helperModule.BroadcastMessage(status, role, doesFade)
	for i, plr in ipairs(helperModule.GetActivePlayers()) do
		helperModule.SetPlayerRoleAndStatus(plr, status, role, doesFade)
	end
end

-- Give players a random gun. Requires a table.
function helperModule.SpawnGuns(plr:Player, guns, grantAll)
	if not plr then return end
	
	if #guns == 0 then return end
	
	local playerBackpack = plr.Backpack :: Backpack
	
	if grantAll then
		for index, gunName in ipairs(guns) do
			local gunInStorage = helperModule.SearchGunsForString(gunName)

			if not gunInStorage then warn("Gun not found in storage: ".. gunName) continue end

			gunInStorage:Clone().Parent = playerBackpack
		end
		
		return
	end
	
	local randomGun = guns[math.random(1, #guns)]
	local gunInStorage = helperModule.SearchGunsForString(randomGun)
	
	if not gunInStorage then warn("Gun not found in storage: ".. randomGun) return end
	
	gunInStorage:Clone().Parent = playerBackpack
end


local savedLighting = {}
local savedInstances = {}

function helperModule.GetActivePlayers()
	local availablePlayers = {}
	
	for i, plrs in ipairs(game.Players:GetPlayers()) do
		if plrs:FindFirstChild("AFK") then
			if plrs.AFK.Value == false then
				table.insert(availablePlayers, plrs)
			end
		end
	end
	
	return availablePlayers
end

local function saveLightingState()
	savedLighting = {
		Ambient = Lighting.Ambient,
		Brightness = Lighting.Brightness,
		ColorShift_Bottom = Lighting.ColorShift_Bottom,
		ColorShift_Top = Lighting.ColorShift_Top,
		EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
		EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
		GlobalShadows = Lighting.GlobalShadows,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		ShadowSoftness = Lighting.ShadowSoftness,
		ClockTime = Lighting.ClockTime,
		GeographicLatitude = Lighting.GeographicLatitude,
		ExposureCompensation = Lighting.ExposureCompensation,
	}

	savedInstances = {}
	for _, obj in ipairs(Lighting:GetChildren()) do
		if obj:IsA("Sky")
			or obj:IsA("Atmosphere")
			or obj:IsA("Clouds")
			or obj:IsA("ColorCorrectionEffect") then
			table.insert(savedInstances, obj:Clone())
		end
	end
end

local function restoreLightingState()
	for _, obj in ipairs(Lighting:GetChildren()) do
		if obj:IsA("Sky")
			or obj:IsA("Atmosphere")
			or obj:IsA("Clouds")
			or obj:IsA("ColorCorrectionEffect") then
			obj:Destroy()
		end
	end

	for prop, value in pairs(savedLighting) do
		Lighting[prop] = value
	end

	for _, clone in ipairs(savedInstances) do
		clone.Parent = Lighting
	end
end

local function applyMapLighting(mapModel)
	local module = mapModel:FindFirstChild("LightingPreferences")
	if not module then return end

	local ok, data = pcall(require, module)
	if not ok then
		return
	end

	for prop, value in pairs(data.Lighting or {}) do
		if Lighting[prop] ~= nil then
			Lighting[prop] = value
		end
	end

	for _, obj in ipairs(Lighting:GetChildren()) do
		if obj:IsA("Sky")
			or obj:IsA("Atmosphere")
			or obj:IsA("Clouds")
			or obj:IsA("ColorCorrectionEffect") then
			obj:Destroy()
		end
	end

	if data.Sky then
		local sky = Instance.new("Sky")
		for p, v in pairs(data.Sky) do sky[p] = v end
		sky.Parent = Lighting
	end

	if data.ColorCorrection then
		local cc = Instance.new("ColorCorrectionEffect")
		for p, v in pairs(data.ColorCorrection) do cc[p] = v end
		cc.Parent = Lighting
	end

	if data.Atmosphere then
		local atm = Instance.new("Atmosphere")
		for p, v in pairs(data.Atmosphere) do atm[p] = v end
		atm.Parent = Lighting
	end

	if data.Clouds then
		local clouds = Instance.new("Clouds")
		for p, v in pairs(data.Clouds) do clouds[p] = v end
		clouds.Parent = Lighting
	end
end

-- Clears all tools in the player's backpack.
function helperModule.ClearTools(plr:Player)
	if not plr or plr.Character == nil then return end
	
	for i, tool in ipairs(plr.Backpack:GetChildren()) do
		tool:Destroy()
	end
	
	for i, toolInCharacter in ipairs(plr.Character:GetChildren()) do
		if toolInCharacter:IsA("Tool") then
			toolInCharacter:Destroy()
		end
	end
end

-- Get a random spawn from a folder.
function helperModule.GetRandomSpawn(spawnFolder)
	local spawns = spawnFolder:GetChildren()
	return spawns[math.random(1, #spawns)]
end

-- Check if a players humanoid is alive.
function helperModule.IsPlayerAlive(plr:Player)
	local plrCharacter = plr.Character :: Model
	
	if not plrCharacter then return false end
	
	local humanoid = plrCharacter:FindFirstChild("Humanoid") :: Humanoid
	
	if not humanoid then return false end
	
	if humanoid.Health <= 0 then return false end
	
	return true
end

-- Teleport the player to the lobby. Also sets team and removes all tools.
function helperModule.SetPlayerToLobby(plr:Player)
	--if plr.Team == teams.Lobby then return end
	
	helperModule.ClearTools(plr)
	
	plr:LoadCharacterAsync()
	
	plr.CameraMinZoomDistance = 0.5
	plr.CameraMaxZoomDistance = 16
	
	plr.Team = teams.Lobby
	
	local plrCharacter = plr.Character :: Model
	local humanoidRootPart = plrCharacter:FindFirstChild("HumanoidRootPart") :: BasePart
	
	if not humanoidRootPart then return end
	
	local spawnLocation = workspace:WaitForChild("lobbySpawn")
	
	pcall(function()
		humanoidRootPart.CFrame = spawnLocation.CFrame + Vector3.new(0, math.random(3, 6), 0)
	end)
end

-- Remove clothing from a character.
function helperModule.RemoveClothing(character) -- heh
	if not character then return end
	
	for i, clothing in ipairs(character:GetChildren()) do
		if clothing:IsA("Shirt") or clothing:IsA("Pants") then
			clothing:Destroy()
		end
	end
end

-- Apply clothing from a template to a character.
function helperModule.ApplyClothing(template, character)
	--print(template, character)
	
	if not template or not character then return end
	
	for i, clothes in ipairs(template:GetChildren()) do
		--print(clothes.ClassName)
		
		if clothes:IsA("Shirt") or clothes:IsA("Pants") then
			clothes:Clone().Parent = character
		end
	end
end

-- Apply head decals to a new head.
function helperModule.ApplyHeadDecals(headTemplate, newHead)
	print("ran")
	
	if not headTemplate or not newHead or not newHead:FindFirstChild("face") or not headTemplate:FindFirstChild("face") then return end
	
	local newFace = newHead.face.water -- why is it called water..?
	local templateFace = headTemplate.face.water
	
	if not newFace or not templateFace then return end
	
	print(newFace:GetChildren(), templateFace:GetChildren())
	
	for i, oldDecal in ipairs(newFace:GetChildren()) do
		if oldDecal:IsA("Decal") then
			oldDecal:Destroy()
		end
	end
	
	for i, newDecal in ipairs(templateFace:GetChildren()) do
		if newDecal:IsA("Decal") then
			newDecal:Clone().Parent = newFace
		end
	end
end

-- Apply a skin color to a character. Accepts Color3.
function helperModule.ApplySkinColor(character, skinColor)
	if not character or not skinColor then return end
	
	local limbsToPaint = {}
	
	local bodyColors = character:FindFirstChild("BodyColors") or Instance.new("BodyColors")
	bodyColors.HeadColor3 = skinColor
	bodyColors.LeftArmColor3 = skinColor
	bodyColors.RightArmColor3 = skinColor
	bodyColors.LeftLegColor3 = skinColor
	bodyColors.RightLegColor3 = skinColor
	bodyColors.TorsoColor3 = skinColor
	
	bodyColors.Parent = character
	
	for i, potentialLimb in ipairs(character:GetChildren()) do
		if table.find(limbs, potentialLimb.Name) then
			table.insert(limbsToPaint, potentialLimb)
		end
	end
	
	for i, limb in ipairs(limbsToPaint) do
		limb.Color = skinColor
	end
end

-- Clears all accessories from a character.
function helperModule.ClearAccessories(character)
	if not character then return end
	
	for i, oldAccessory in ipairs(character:GetChildren()) do
		if oldAccessory:IsA("Accessory") then
			oldAccessory:Destroy()
		end
	end
end

-- Copy accessories from one character to another.
function helperModule.ApplyAccessories(template, character)
	if not template or not character then return end
	
	for i, accesory in ipairs(template:GetChildren()) do
		if accesory:IsA("Accessory") then
			accesory:Clone().Parent = character
		end
	end
end

-- Returns all team player amounts
function helperModule.TeamAmounts()
	local teamAmounts = {}
	
	for i, plr in ipairs(helperModule.GetActivePlayers()) do
		if plr.Team then
			if not teamAmounts[plr.Team.Name] then
				teamAmounts[plr.Team.Name] = 1
			else
				teamAmounts[plr.Team.Name] += 1
			end
		end
	end
	
	for i, team in ipairs(teams) do
		if not teamAmounts[team.Name] then
			teamAmounts[team.Name] = 0
		end
	end
	
	return teamAmounts
end

function helperModule.GetCurrentState()
	return currentState
end

-- Returns all alive players for teams.
function helperModule.GetAllAlivePlayersForTeams()
	local teamAmounts = {}

	for i, team in pairs(teams) do
		for i, plr in ipairs(helperModule.GetActivePlayers()) do
			if plr.Team == team then
				if helperModule.IsPlayerAlive(plr) then
					if not teamAmounts[team.Name] then
						teamAmounts[team.Name] = 1
					else
						teamAmounts[team.Name] += 1
					end
				end
			end
		end
	end
	
	for i, team in pairs(teams) do
		if not teamAmounts[team.Name] then
			teamAmounts[team.Name] = 0
		end
	end
	
	--print(teamAmounts)

	return teamAmounts
end

-- Morph a character into another character.
function helperModule.MorphPlayer(template, character)
	pcall(function()
		if not character or not template then return end

		local templateHumanoid = template:FindFirstChild("Humanoid") :: Humanoid
		local characterHumanoid = character:FindFirstChild("Humanoid") :: Humanoid

		if not templateHumanoid or not characterHumanoid then return end

		task.delay(1.5, function()
			characterHumanoid.DisplayName = template.Name

			characterHumanoid.MaxHealth = templateHumanoid.MaxHealth
			characterHumanoid.Health = templateHumanoid.MaxHealth

			characterHumanoid.WalkSpeed = templateHumanoid.WalkSpeed
		end)

		local mesh = template:FindFirstChild("CharacterMesh", true)

		if mesh then
			local existing = character:FindFirstChild(mesh.Name)
			if existing then existing:Destroy() end
			mesh:Clone().Parent = character
		end

		helperModule.ClearAccessories(character)
		helperModule.ApplyAccessories(template, character)

		helperModule.ApplySkinColor(character, template:FindFirstChild("Head").Color)
		helperModule.ApplyHeadDecals(template:FindFirstChild("Head"), character:FindFirstChild("Head"))

		helperModule.RemoveClothing(character)
		helperModule.ApplyClothing(template, character)
		
		
		if template.Name == "Unknown Creature" then
			template.Head.EyeAttachment:Clone().Parent = character.Head
			template.Head.EyeAttachment2:Clone().Parent = character.Head
			template.Head.Redlight:Clone().Parent = character.Head
		end
	end)
end

-- Send all players to the lobby.
function helperModule.SendAllPlayersToLobby()
	for i, plr in ipairs(helperModule.GetActivePlayers()) do
		helperModule.SetPlayerToLobby(plr)
	end
end

function helperModule.StartWaiting()
	repeat
		currentState = "WAITING"
		
		helperModule.BroadcastMessage("Waiting for more players...", "", false)
		
		task.wait(0.05)
	until #helperModule.GetActivePlayers() >= globalData.MIN_PLAYERS_TO_START
	
	--helperModule.Intermission()
end

function helperModule.GetPreparedClockTime(seconds)
	local minutes = math.floor(seconds / 60)
	local remainingSeconds = seconds % 60

	return string.format("%d:%02d", minutes, remainingSeconds)
end

-- Start a timer. Returns true when done.
function helperModule.EngageTimer(length, broadcast, timerName, cooldown)
	for i = 1, length do
		if currentState == "GAME_OVER" or currentState == "INTERMISSION" then
			return false -- cancelled
		end

		if broadcast then
			pcall(function()
				helperModule.BroadcastMessage("Timer: " .. helperModule.GetPreparedClockTime(length - i), "", false)
			end)
		end

		helperModule.checkIfGameCanEnd()
		task.wait(cooldown)
	end

	return true -- finished normally
end

function helperModule.slowDownAndStop(sound, duration)
	if not sound or not sound.IsPlaying then return end
	local startSpeed = sound.PlaybackSpeed
	local endSpeed = 0.5
	local steps = 30
	local stepTime = duration / steps
	local speedDelta = (startSpeed - endSpeed) / steps

	for i = 1, steps do
		if sound.IsPlaying then
			sound.PlaybackSpeed = sound.PlaybackSpeed - speedDelta
			task.wait(stepTime)
		else
			break
		end
	end

	if sound.IsPlaying then
		sound:Stop()
	end
	sound.PlaybackSpeed = 1
end

local TweenService = game:GetService("TweenService")

function helperModule.DisplayEndScreen()
	for i, plrs in ipairs(helperModule.GetActivePlayers()) do
		pcall(function()
			local endScreenForPlayer = plrs.PlayerGui:FindFirstChild("EndRoundSeeker")

			local printedCasualities = "Casualties: ".. table.concat(currentCasualities, ", ")

			print(currentMapData, printedCasualities)

			if endScreenForPlayer and currentMapData.EndScreen then
				local someFrame = endScreenForPlayer:WaitForChild("StuffFrame")
				local seekerImage = someFrame:FindFirstChild("SeekerImage")

				someFrame.Casualties.Text = printedCasualities
				someFrame.Description.Text = currentMapData.EndScreen.SeekerDescription
				someFrame.MatchResultIs.Text = currentEndResult

				seekerImage.Image = "rbxassetid://".. currentMapData.EndScreen.Icon
				someFrame.GunUsed.Text = currentMapData.EndScreen.GunUsed

				if not currentMapData.Teams then
					someFrame.CharacterName.Text = currentMapData.Seeker.Name
					--seekerImage.Player.Text = currentSeekerPlayer.Name.. " | ".. currentSeekerPlayer.UserId
				else
					someFrame.CharacterName.Text = ""
				end

				if seekerSlain then
					seekerImage.Defeat.Visible = true
				else
					seekerImage.Defeat.Visible = false
				end

				someFrame.Position = UDim2.new(0, -500, 0.57, 0)
				endScreenForPlayer.Enabled = true

				local showTween = TweenService:Create(
					someFrame,
					TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{Position = UDim2.new(0.499, 0, 0.57, 0)}
				)

				showTween:Play()

				local closeButton = someFrame.Close :: TextButton

				closeButton.MouseButton1Click:Connect(function()
					endScreenForPlayer.Enabled = false
				end)

				task.delay(8, function()
					if endScreenForPlayer then
						local hideTween = TweenService:Create(
							someFrame,
							TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
							{Position = UDim2.new(0, -500, 0.57, 0)}
						)

						hideTween:Play()
						hideTween.Completed:Wait()

						endScreenForPlayer.Enabled = false
					end
				end)
			end
		end)
	end
end


function helperModule.stopAllMusic()
	-- Fade round music
	if currentRoundMusic and currentRoundMusic.IsPlaying then
		task.spawn(function()
			helperModule.slowDownAndStop(currentRoundMusic, 1.2)
		end)
	end

	-- Fade police music
	if currentPoliceMusic and currentPoliceMusic.IsPlaying then
		task.spawn(function()
			helperModule.slowDownAndStop(currentPoliceMusic, 1.2)
		end)
	end

	-- Immediately stop lobby music (like the original)
	if currentLobbyMusic and currentLobbyMusic.IsPlaying then
		pcall(function() currentLobbyMusic:Stop() end)
	end

	-- Clear all references so intermission music can start fresh
	currentLobbyMusic, currentRoundMusic, currentPoliceMusic = nil, nil, nil
end

function helperModule.endGame(condition)
	if currentState == "GAME_OVER" then return end
	
	helperModule.KillTasks()
	helperModule.stopAllMusic()
	
	local teamAmounts = helperModule.GetAllAlivePlayersForTeams()
	
	local endStatus = nil
	local willEndGame = true
	local arrivePolice = false
	
	local isTeamWar = currentMapData.Teams ~= nil
	
	if condition == "TEAM1_WIN" then
		local theirTeamCondition = currentMapData.Teams.Team2.WinMessage
		
		if theirTeamCondition then
			endStatus = theirTeamCondition
			
		--	soundService.SeekerSTOPPED:Play()
			
			currentMapData.EndScreen.Icon = currentMapData.Teams.Team2.Icon
			currentMapData.EndScreen.SeekerDescription = currentMapData.Teams.Team2.Description
			
			soundService.EndTeamWar:Play()
		end
	elseif condition == "TEAM2_WIN" then
		local theirTeamCondition = currentMapData.Teams.Team1.WinMessage

		if theirTeamCondition then
			endStatus = theirTeamCondition

			--soundService.SeekerSTOPPED:Play()
			
			currentMapData.EndScreen.Icon = currentMapData.Teams.Team1.Icon
			currentMapData.EndScreen.SeekerDescription = currentMapData.Teams.Team1.Description
			
			soundService.EndTeamWar:Play()
		end
	end
	
	if currentState ~= "POLICE_ARRIVAL" then
		if condition == "ROBBERS_DEAD" then
			endStatus = "The robbers have died!"
			
			arrivePolice = true
			willEndGame = false
		elseif condition == "HOMEOWNER_DEAD" then
			endStatus = "The homeowner has died!"

			arrivePolice = true
			willEndGame = false
		end
	end
	
	if condition == "POLICE_WINS" then
		endStatus = "The Police have secured the cottage! Police wins!"
		
		--soundService.SeekerSUPERwins:Play()
	elseif condition == "ROBBERS_WIN" then
		endStatus = "The Police have failed to secure the cottage! Robbers win!"
		
		--soundService.SeekerWINS:Play()
	end
	
	if condition == "SEEKER_DEAD" then
		local survivors = teamAmounts.Hiders + teamAmounts.Police
		
		if currentState == "POLICE_ARRIVAL" then
			for i, plrs in ipairs(helperModule.GetActivePlayers()) do
				if plrs.Team == teams.Hider then
					badgeService:AwardBadgeAsync(plrs.UserId, 1946450229090700)
				end
			end
		end
		
		if teamAmounts.Hiders == 1 then
			for i, plrs in ipairs(helperModule.GetActivePlayers()) do
				if plrs.Team == teams.Hider then
					badgeService:AwardBadgeAsync(plrs.UserId, 1387549752901770)
				end
			end
		end

		-- Award civilian survivor badge to all alive hiders who didn't die
		for i, plrs in ipairs(helperModule.GetActivePlayers()) do
			if plrs.Team == teams.Hider then
				pcall(function()
					badgeService:AwardBadgeAsync(plrs.UserId, 2914227262190303)
				end)
			end
		end

		if currentMapData.SeekerDeadMessage then
			endStatus = currentMapData.SeekerDeadMessage
			soundService.Hiders:Play()
		else
			if survivors == 1 then
				endStatus = "The seeker has been stopped, at a catastrophic price."
				soundService.Hiders:Play()

			elseif survivors > 1 and survivors < 3 then
				endStatus = "The seeker has been stopped, with strong penalties."
				soundService.Hiders:Play()

			elseif survivors > 3 and survivors < 6 then
				endStatus = "The seeker fell, but their tracks left scars behind."
				soundService.Hiders:Play()

			else
				endStatus = "The seeker has been stopped dead in their tracks."
				soundService.Hiders:Play()
			end
		end


	elseif condition == "SEEKER_WIN_SUPER" then
		endStatus = currentMapData.SeekerWinMessageSuper
		
		soundService.Juggernaut:Play()
		
		helperModule.RecordJuggernautWin()
		
		local badge = currentMapData.WinBadge
		
		if badge then
			for i, seeker in ipairs(helperModule.GetActivePlayers()) do
				if seeker.Team == teams.Seeker then
					badgeService:AwardBadgeAsync(seeker.UserId, badge)
				end
			end
		end
	elseif condition == "SEEKER_WIN_REGULAR" then
		endStatus = currentMapData.SeekerWinMessageRegular
		
		soundService.Juggernaut:Play()
		
		helperModule.RecordJuggernautWin()
	elseif condition == "NOBODY_WON" then
		if teamAmounts.Hiders == 1 then
			for i, plrs in ipairs(helperModule.GetActivePlayers()) do
				if plrs.Team == teams.Hider then
					badgeService:AwardBadgeAsync(plrs.UserId, 1387549752901770)
				end
			end
		end

		-- Award civilian survivor badge to all alive hiders who didn't die
		for i, plrs in ipairs(helperModule.GetActivePlayers()) do
			if plrs.Team == teams.Hider then
				pcall(function()
					badgeService:AwardBadgeAsync(plrs.UserId, 2914227262190303)
				end)
			end
		end
		
		if currentMap.Name == "Private Cottage" then
			endStatus = "wow none of you killed eachother in time?"
			
		--	soundService.ClownLol:Play()
		else
			endStatus = "The Hiders win by not becoming victims."

			soundService.Hiders:Play()
		end
	end
	
	if endStatus then
		if willEndGame then
			currentState = "GAME_OVER"
			
			currentEndResult = endStatus
			
			helperModule.BroadcastMessage(endStatus, "", false)
			
			task.wait(14.5)
			
			for i, plr in ipairs(helperModule.GetActivePlayers()) do
				if plr.Team == teams.Seeker then
					if plr.Character.Humanoid.Health > 0 then
						helperModule.GrantSeekerShopItems()
					end
				end
				
				helperModule.ClearTools(plr)
			end
			
			task.wait(1)

			--currentMapData = nil

			helperModule.Intermission()
		else
			helperModule.BroadcastMessage(endStatus, "", true)
			
			if arrivePolice then
				helperModule.stopAllMusic()
				
				task.wait(6)
				
				helperModule.PoliceArrival()
			end
		end
	end
end

function helperModule.detectEndConditions()
	local isCottage = currentMap.Name == "Private Cottage"
	local isNUWinterOffensive = currentMap.Name == "NUWinterOffensive"
	local isMapTeamWar = currentMapData.Teams ~= nil
	
	if currentState == "GAME_OVER" then
		return nil
	end

	local teamAmounts = helperModule.GetAllAlivePlayersForTeams()
	
	if isMapTeamWar then
		if teamAmounts.Team1 <= 0 then
			return "TEAM1_WIN"
		elseif teamAmounts.Team2 <= 0 then
			return "TEAM2_WIN"
		end
	end

	if not isMapTeamWar then
		if teamAmounts.Seeker <= 0 then
			if isCottage then
				if currentState == "ROUND_ACTIVE" then
					seekerSlain = true

					return "HOMEOWNER_DEAD"
				end

				if teamAmounts.Police <= 0 and teamAmounts.Robbers > 0 then
					return "ROBBERS_WIN"
				elseif teamAmounts.Police > 0 and teamAmounts.Robbers <= 0 then
					return "POLICE_WINS"
				end
			else
				seekerSlain = true

				return "SEEKER_DEAD"
			end
		end

		if currentState == "ROUND_ACTIVE" then
			if isCottage then
				if teamAmounts.Robbers <= 0 then
					return "ROBBERS_DEAD"
				end
			else
				if teamAmounts.Hiders <= 0 then
					return "SEEKER_WIN_REGULAR"
				end
			end
		elseif currentState == "POLICE_ARRIVAL" then
			if (teamAmounts.Hiders + teamAmounts.Police + teamAmounts.Robbers) <= 0 then
				return "SEEKER_WIN_SUPER"
			end
		end
	end

	return nil
end

function helperModule.checkIfGameCanEnd()
	if currentState == "GAME_OVER" or currentState == "INTERMISSION" then
		return true
	end

	local endCondition = helperModule.detectEndConditions()
	if endCondition then
		helperModule.endGame(endCondition)
		return true
	end

	return false
end

function helperModule.HookCasualtyMeter(plr:Player)
	local char = plr.Character

	if char then
		local humanoid = char:FindFirstChild("Humanoid") :: Humanoid
		local delayTick = 0
		
		local conn

		if humanoid then
			conn = game:GetService("RunService").Heartbeat:Connect(function(delta)
				delayTick += delta
				
				if delayTick >= 1 then
					delayTick = 0
					
					if humanoid and plr then
						if humanoid.Health <= 0 and plr.Team ~= teams.Lobby then
							plr.Team = teams.Lobby
							
							if conn then
								conn:Disconnect()
								return
							end
						end
					else
						if conn then
							conn:Disconnect()
							return
						end
					end
				end
			end)
			
			humanoid.Died:Connect(function()
				if plr.Team == teams.Lobby then return end

				task.delay(2, function()
					plr.Team = teams.Lobby
				end)

				--table.insert(currentCasualities, humanoid.DisplayName)
			end)

			humanoid.Died:Once(function()
				if plr.Team == teams.Lobby then return end

				table.insert(currentCasualities, humanoid.DisplayName)
			end)
		end
	end
end

function helperModule.PoliceArrival()
	if currentState == "POLICE_ARRIVAL" or currentState == "GAME_OVER" then return end
	
	local isNUWinterOffensive = currentMap.Name == "NUWinterOffensive"
	
	currentState = "POLICE_ARRIVAL"
	
	local overtimeValue = ReplicatedStorage:WaitForChild("OvertimeActive")
	overtimeValue.Value = true

	if not currentMap then return end

	if currentMap.Name == "AlexeiTarasovRevamp" then
		local target = currentMap:FindFirstChild("ELEVATORDOORS", true)
		if target then
			target:Destroy()
		end
    end 

	if currentMap.Name == "Private Cottage" then
		local target = currentMap:FindFirstChild("ELEVATORDOORS", true)
		if target then
			local scriptToEnable = target:FindFirstChild("DestroyScript", true)

			if not scriptToEnable then
				for _, obj in ipairs(target:GetDescendants()) do
					if obj:IsA("Script") then
						scriptToEnable = obj
						break
					end
				end
			end

			if scriptToEnable then
				scriptToEnable.Enabled = true
			end
		end
	end
	
	if not currentMapData.SingleMusic then
		helperModule.stopAllMusic()

		local PoliceMusic = currentMapData.PoliceMusic[math.random(1, #currentMapData.PoliceMusic)]

		PoliceMusic:Play()

		currentPoliceMusic = PoliceMusic
	end
	
	helperModule.BroadcastMessage(currentMapData.PoliceArrivalMessage, "", false)
	
	task.spawn(function()
		if currentMapData.FunctionOnPoliceArrival then
			currentMapData.FunctionOnPoliceArrival(currentMap)
		end
	end)
	
	for i, plr in ipairs(helperModule.GetActivePlayers()) do
		pcall(function()
			--[[
			if plr.Team == teams.Hiders or plr.Team == teams.Robbers then
				helperModule.SpawnGuns(plr, currentMapData.HiderWeaponry, false)
			end
			]]
			
			print(plr.Team == teams.Lobby, currentMap)

			if plr.Team == teams.Lobby and currentMap then
				local spawnPart = currentMapData.Spawns.Police:GetChildren()[math.random(1, #currentMapData.Spawns.Police:GetChildren())]
				local randomModel = currentMapData.PoliceModels:GetChildren()[math.random(1, #currentMapData.PoliceModels:GetChildren())]

				if plr and plr.Character then
					plr.Character:PivotTo(spawnPart.CFrame)
				end

				plr.Team = teams.Police

				helperModule.ClearTools(plr)

				helperModule.MorphPlayer(randomModel, plr.Character)

				helperModule.SpawnGuns(plr, currentMapData.PoliceWeaponry)
				
				helperModule.HookCasualtyMeter(plr)

				if currentMapData.PoliceUtilities then
					helperModule.SpawnGuns(plr, currentMapData.PoliceUtilities, true)
				end
			end
		end)
	end
	
	task.wait(5)
end

-- too much work to integrate it into the other round handler
function helperModule.BeginRoundTeamWar(chosenMap)

	local mapData = mapDataModule[chosenMap]
	local mapName = chosenMap
	
	currentMapData = mapData

	lastMap = mapName

	local mapModel = mapData.MapModel:Clone()
	mapModel.Parent = workspace

	currentMap = mapModel

	saveLightingState()
	applyMapLighting(mapModel)
	
	helperModule.BroadcastMessage("Map : ".. mapName..", TEAM WAR Mode.", "", false)
	
	local onTeam1 = {}
	local onTeam2 = {}
	
	local team1Data = currentMapData.Teams["Team1"]
	local team2Data = currentMapData.Teams["Team2"]
	
	print(team1Data, team1Data)
	
	local players = helperModule.GetActivePlayers()

	-- shuffle players so teams are random
	for i = #players, 2, -1 do
		local j = math.random(i)
		players[i], players[j] = players[j], players[i]
	end

	local onTeam1 = {}
	local onTeam2 = {}

	local half = math.ceil(#players / 2)

	for i, player in ipairs(players) do
		if i <= half then
			table.insert(onTeam1, player)
		else
			table.insert(onTeam2, player)
		end
	end
	
	task.wait(globalData.MAP_LOAD_TIME + globalData.SPAWN_DELAY)
	
	helperModule.BroadcastMessage("Prepare.", "", false)
	
	for i, plr:Player in ipairs(onTeam1) do
		pcall(function()
			local spawnPart = nil

			spawnPart = helperModule.GetRandomSpawn(team1Data.Spawns)

			if plr and plr.Character then
				plr.Character:PivotTo(spawnPart.CFrame)
			end


			if plr then
				print(team1Data.TeamTeam)
				
				plr.Team = team1Data.TeamTeam

				helperModule.ClearTools(plr)
				
				if team1Data.Equipment then
					local ui = plr.PlayerGui.TeamWarSelector
					
					for i, thing in ipairs(ui.MainFrame.List:GetChildren()) do
						if thing:IsA("Frame") then
							thing:Destroy()
						end
					end
					
					for i, gun in ipairs(team1Data.Equipment) do
						local newTemplate = script.ItemTemplate:Clone()
						newTemplate.BBText.Text = gun
						newTemplate.Parent = ui.MainFrame.List
						
						newTemplate.Button.MouseButton1Click:Connect(function()
							helperModule.SpawnGuns(plr, {gun}, true)
							
							ui.Enabled = false

							for i, thing in ipairs(ui.MainFrame.List:GetChildren()) do
								if thing:IsA("Frame") then
									thing:Destroy()
								end
							end
						end)
					end
					
					ui.Enabled = true
				end
			end
		end)
	end

	for i, plr in ipairs(onTeam2) do
		pcall(function()
			local spawnPart = nil

			spawnPart = helperModule.GetRandomSpawn(team2Data.Spawns)

			if plr and plr.Character then
				plr.Character:PivotTo(spawnPart.CFrame)
			end


			if plr then
				plr.Team = team2Data.TeamTeam

				helperModule.ClearTools(plr)
				
				if team2Data.Equipment then
					local ui = plr.PlayerGui.TeamWarSelector

					for i, thing in ipairs(ui.MainFrame.List:GetChildren()) do
						if thing:IsA("Frame") then
							thing:Destroy()
						end
					end

					for i, gun in ipairs(team2Data.Equipment) do
						local newTemplate = script.ItemTemplate:Clone()
						newTemplate.BBText.Text = gun
						newTemplate.Parent = ui.MainFrame.List

						newTemplate.Button.MouseButton1Click:Connect(function()
							helperModule.SpawnGuns(plr, {gun}, true)

							ui.Enabled = false

							for i, thing in ipairs(ui.MainFrame.List:GetChildren()) do
								if thing:IsA("Frame") then
									thing:Destroy()
								end
							end
						end)
					end

					ui.Enabled = true
				end
			end
		end)
	end
	
	for i, plr in ipairs(players) do
		helperModule.SpawnGuns(plr, currentMapData.Secondaries)
	end
	
	local t1models = team1Data.Model:GetChildren()

	for i = #t1models, 2, -1 do
		local j = math.random(1, i)
		t1models[i], t1models[j] = t1models[j], t1models[i]
	end

	local idx = 1

	for i, plr in ipairs(onTeam1) do
		pcall(function()
			if plr.Character and idx <= #t1models then
				local chosen = t1models[idx]

				if chosen then
					helperModule.MorphPlayer(chosen, plr.Character)

					helperModule.HookCasualtyMeter(plr)

					idx = idx + 1
				end
			end
		end)
	end
	
	local t2models = team2Data.Model:GetChildren()

	for i = #t2models, 2, -1 do
		local j = math.random(1, i)
		t2models[i], t2models[j] = t2models[j], t2models[i]
	end

	local idx = 1

	for i, plr in ipairs(onTeam2) do
		pcall(function()
			if plr.Character and idx <= #t2models then
				local chosen = t2models[idx]

				if chosen then
					helperModule.MorphPlayer(chosen, plr.Character)

					helperModule.HookCasualtyMeter(plr)

					idx = idx + 1
				end
			end
		end)
	end
	
	local barriers = currentMap:FindFirstChild("Barriers")
	
	if barriers then
		task.wait(18)
		
		barriers:Destroy()
	end

	pcall(function()
		helperModule.stopAllMusic()

		if currentLobbyMusic and currentLobbyMusic.IsPlaying then
			currentLobbyMusic:Stop()
		end

		local mapSong = currentMapData.Song[math.random(1, #currentMapData.Song)]

		mapSong:Play()

		currentRoundMusic = mapSong
	end)

	seekerTimerTask = task.spawn(function()
		if currentState == "GAME_OVER" then return end
		
		ReplicatedStorage:WaitForChild("OvertimeActive").Value = false

		local policeTimerFinished =
			helperModule.EngageTimer(currentMapData.Time, true, "", 1)

		if not policeTimerFinished or currentState == "GAME_OVER" then
			return
		end
		
		helperModule.endGame("NOBODY_WON")
	end)
end

function helperModule.GrantSeekerShopItems()
	local shopModule = require(ReplicatedStorage.Modules.ShopEntries)
	
	pcall(function()
		if currentSeekerPlayer then
			for i, thing in ipairs(currentSeekerPlayer.Backpack:GetChildren()) do
				if shopModule[thing.Name] then
					local inv = currentSeekerPlayer:WaitForChild("Inventory")

					inv:FindFirstChild(thing.Name).Value += 1
				end
			end

			for i, thing in ipairs(currentSeekerPlayer.Character:GetChildren()) do
				if shopModule[thing.Name] then
					local inv = currentSeekerPlayer:WaitForChild("Inventory")

					inv:FindFirstChild(thing.Name).Value += 1
				end
			end
		end
	end)
end

function helperModule.BeginRound()
	
	currentState = "ROUND_LAUNCHING"
	
	--helperModule.BroadcastMessage("Beginning...", "", true)
	
	-- VOTING RESULT
	local votes, voteOptions = _G.VotingSystem.GetVotes()

	local voteCount = {}
	local totalVotes = 0

	for _, mapName in pairs(votes) do
		voteCount[mapName] = (voteCount[mapName] or 0) + 1
		totalVotes += 1
	end

	local chosenMap = nil
	local highestCount = -1

	-- Find winner
	for mapName, count in pairs(voteCount) do
		if count > highestCount then
			highestCount = count
			chosenMap = mapName
		end
	end

	-- If nobody voted → pick random (but still avoid lastMap)
	if not chosenMap then
		local pool = {}
		for mapName,MDATA in pairs(mapDataModule) do
			if mapName ~= lastMap and not MDATA.Admin then
				table.insert(pool, mapName)
			end
		end
		if #pool == 0 then
			for mapName,NDATA in pairs(mapDataModule) do if not NDATA.Admin then
					table.insert(pool, mapName)
				end
			end
		end

		chosenMap = pool[math.random(1, #pool)]
	end
	
	if guarenteedMap then
		chosenMap = guarenteedMap
	end

	local mapData = mapDataModule[chosenMap]
	local mapName = chosenMap
	
	if mapData.Teams then
		helperModule.BeginRoundTeamWar(chosenMap)
		
		return
	end
	
	
	print(mapData, mapName)
	
	currentMapData = mapData
	
	--if mapName == "Private Cottage" then
		--currentMapData.HiderWeaponryOnSpawn = {currentMapData.HiderWeaponryOnSpawn[math.random(1,#currentMapData.HiderWeaponryOnSpawn)]}
	--end

	lastMap = mapName
	
	local mapModel = mapData.MapModel:Clone()
	mapModel.Parent = workspace
	
	saveLightingState()
	applyMapLighting(mapModel)
	
	currentMap = mapModel
	
	if currentMapData.Seekers then
		local totalWeight = 0
		local cumalativeWeight = 0
		
		for i, availableSeeker in pairs(currentMapData.Seekers) do
			totalWeight += availableSeeker.Chance
		end
		
		local roll = math.random(1, totalWeight)
		
		for i, availableSeeker in pairs(currentMapData.Seekers) do
			cumalativeWeight += availableSeeker.Chance
			
			if roll <= cumalativeWeight then
				currentMapData.SeekerWeaponry = availableSeeker.Weaponry
				currentMapData.Seeker = availableSeeker.Model
				
				currentMapData.EndScreen.Icon = availableSeeker.Icon
				currentMapData.EndScreen.GunUsed = availableSeeker.GunUsed
				currentMapData.EndScreen.SeekerDescription = availableSeeker.SeekerDescription
				
				currentMapData.Song = availableSeeker.OST
				
				break
			end
		end
	end
	
	if mapName == "Private Cottage" then
		helperModule.BroadcastMessage("Map : ".. mapName..", Home Defense Mode.", "", false)
	elseif mapName == "NUWinterOffensive" then
		helperModule.BroadcastMessage("Map : ".. mapName..", Homeland Defense Mode.", "", false)
	else
		helperModule.BroadcastMessage("Map : ".. mapName..", Juggernaut Mode.", "", false)
	end
	
	--[[
	if not currentLobbyMusic or not currentLobbyMusic.IsPlaying then
		currentLobbyMusic = lobbyMusics[math.random(1, #lobbyMusics)]
		if currentLobbyMusic then
			pcall(function() currentLobbyMusic:Play() end)
		end
	end
	]]
	
	task.wait(globalData.MAP_LOAD_TIME)
	
	local players = helperModule.GetActivePlayers()
	if #players == 0 then helperModule.Restart() return end
	
	--- UPDATE PERCENTAGES
	for _, plr in ipairs(players) do
		if plr ~= lastSeeker then
			seekerChance[plr] = (seekerChance[plr] or 1) + 1
		end
	end

	-- FORCE last seeker to have low chance
	if lastSeeker then
		seekerChance[lastSeeker] = 1
	end

	-- DETERMINE HIGHEST % PLAYER
	local highestPlr = nil
	local highestVal = -1

	for _, plr in ipairs(players) do
		local val = seekerChance[plr] or 1
		if val > highestVal then
			highestVal = val
			highestPlr = plr
		end
	end
	
	local randomSeeker = highestPlr

	if not guarenteedJugg and not currentMapData.Teams then
		-- RESET THE SEEKER'S PERCENTAGE
		seekerChance[randomSeeker] = 1
	else
		randomSeeker = guarenteedJugg
	end

	lastSeeker = randomSeeker
	currentSeekerPlayer = randomSeeker
	
	task.wait(globalData.SPAWN_DELAY)
	
	if not randomSeeker then helperModule.BroadcastMessage("The seeker has left or died.", "", true) helperModule.Restart() end
	
	for i, plr in ipairs(players) do
		pcall(function()
			local spawnPart = nil

			if plr == randomSeeker then
				spawnPart = helperModule.GetRandomSpawn(currentMapData.Spawns.Seeker)
			else
				spawnPart = helperModule.GetRandomSpawn(currentMapData.Spawns.Hiders)
			end
			
			if plr and plr.Character then
				plr.Character:PivotTo(spawnPart.CFrame)
			end

			local selectedTeam = "Hiders"

			if plr == randomSeeker then selectedTeam = "Seeker" end

			if selectedTeam == "Hiders" then
				selectedTeam = currentMapData.HiderTeam
			elseif selectedTeam == "Seeker" then
				selectedTeam = teams.Seeker
			end

			if plr then
				plr.Team = selectedTeam

				helperModule.ClearTools(plr)
			end
		end)
	end
	
	pcall(function()
		helperModule.stopAllMusic()

		if currentLobbyMusic and currentLobbyMusic.IsPlaying then
			currentLobbyMusic:Stop()
		end

		if currentMapData.SingleMusic then
			local mapSong = currentMapData.SingleMusic[math.random(1, #currentMapData.SingleMusic)]

			mapSong:Play()

			currentRoundMusic = mapSong
		else
			local mapSong = currentMapData.Song[math.random(1, #currentMapData.Song)]

			mapSong:Play()

			currentRoundMusic = mapSong
		end
	end)
	
	if randomSeeker then
		helperModule.MorphPlayer(currentMapData.Seeker, randomSeeker.Character)
		
		helperModule.HookCasualtyMeter(randomSeeker)
		
		for i, loadout in ipairs(randomSeeker.Loadout:GetChildren()) do
			if loadout.Value > 0 then
				local shopEntry = require(ReplicatedStorage.Modules.ShopEntries)[loadout.Name]

				if not shopEntry.Accessory then
					for i=1, loadout.Value do
						helperModule.SpawnGuns(randomSeeker, {loadout.Name}, true)
					end
				else
					--local newAccessory = ServerStorage.Accessories:FindFirstChild(loadout.Name):Clone()
					local hum = randomSeeker.Character:FindFirstChild("Humanoid")::Humanoid

					--hum:AddAccessory(newAccessory)

					if shopEntry.Health then
						hum.MaxHealth += shopEntry.Health
						
						hum.Health = hum.MaxHealth
					end
				end

				loadout.Value = 0
			end
		end
		
		if mapName == "NUWinterOffensive" then
			ReplicatedStorage.Events.ClearAtmosphereEffect:FireClient(randomSeeker, 0)
		elseif mapName == "2002RuralForest" then
			ReplicatedStorage.Events.ClearAtmosphereEffect:FireClient(randomSeeker, 0)
		end
	else
		helperModule.Restart()
	end
	
	local models = currentMapData.HiderModels:GetChildren()

	for i = #models, 2, -1 do
		local j = math.random(1, i)
		models[i], models[j] = models[j], models[i]
	end

	local idx = 1
	
	for i, plr in ipairs(players) do
		pcall(function()
			if plr.Team == currentMapData.HiderTeam and plr.Character and idx <= #models then
				local chosen = models[idx]

				if chosen then
					helperModule.MorphPlayer(chosen, plr.Character)

					helperModule.SpawnGuns(plr, currentMapData.HiderWeaponryOnSpawn, false)

					helperModule.HookCasualtyMeter(plr)
					
					local characterName = chosen.Name
					
					if mapData.HidersWithTools then
						if mapData.HidersWithTools[characterName] then
							helperModule.SpawnGuns(plr, mapData.HidersWithTools[characterName], false)
						end
					end

					idx = idx + 1
				end
			end
		end)
	end
	
	if randomSeeker then
		helperModule.SpawnGuns(randomSeeker, currentMapData.SeekerWeaponry, true)
	else
		helperModule.Restart() 
	end
	
	currentState = "ROUND_ACTIVE"
	
	if mapData.OnMapSpawn then
		task.spawn(function()
			mapData.OnMapSpawn(currentMap)
		end)
	end
	
	task.wait(4)
	
	if not randomSeeker then
		helperModule.Restart() 
	end
	
	seekerTimerTask = task.spawn(function()
		if currentState == "GAME_OVER" then return end
		
		local policeTimerFinished =
			helperModule.EngageTimer(currentMapData.SeekerTime, true, "", 1)

		if not policeTimerFinished or currentState == "GAME_OVER" then
			return
		end

		helperModule.PoliceArrival()

		local gameEndTimerFinished =
			helperModule.EngageTimer(currentMapData.PoliceTime, true, "", 1)

		if not gameEndTimerFinished or currentState == "GAME_OVER" then
			return
		end

		helperModule.endGame("NOBODY_WON")
	end)
end

function helperModule.ClearEndScreenThings()
	currentEndResult = ""
	seekerSlain = false
	
	currentSeekerPlayer = nil
	
	table.clear(currentCasualities)
end

function helperModule.Intermission()
	
	
	
	print(currentMapData)
	--print("Intermissioned")
	
	helperModule.Restart()
	helperModule.stopAllMusic()
	
	if currentEndResult ~= "" then
		helperModule.DisplayEndScreen()
	end
	
	helperModule.ClearEndScreenThings()
	
	currentState = "INTERMISSION"
	
	_G.VotingSystem.Reset()
	_G.VotingSystem.Assign()
	
	helperModule.BroadcastMessage("Intermission will begin shortly.", "", false)
	
	if currentMap then currentMap:Destroy() end
	
	currentMap = nil
	
	local lobbySong = lobbyMusics[math.random(1, #lobbyMusics)]
	
	currentLobbyMusic = lobbySong
	
	lobbySong:Play()
	
	guarenteedMap = nil
	guarenteedJugg = nil
	
	task.delay(3, function()
		for i=1, globalData.INTERMISSION_TIME, 1 do
			if currentState ~= "INTERMISSION" then break end
			
			helperModule.BroadcastMessage("Starting in " .. tostring(globalData.INTERMISSION_TIME - i).. " seconds", "", false)
			task.wait(1)
		end
		
		if currentState == "INTERMISSION" then
			helperModule.BeginRound()
		else
			helperModule.Intermission()
		end
	end)
end

function helperModule.Restart()
	helperModule.SendAllPlayersToLobby()
	restoreLightingState()
	
	local cleanEvent = ReplicatedStorage:FindFirstChild("CleanCorpses")
	if cleanEvent then
		cleanEvent:FireAllClients()
	end
	
	local overtimeValue = ReplicatedStorage:FindFirstChild("OvertimeActive")
	if overtimeValue then overtimeValue.Value = false end
	
	if currentMap and currentMapData and currentMapData.OnMapCleanup then
		currentMapData.OnMapCleanup(currentMap)
	end

	local bodyFolder = workspace:FindFirstChild("DeadBodies")
	local bloodFolder = workspace:FindFirstChild("BloodFolder")
	local toolsFolder = workspace:FindFirstChild("Drops")

	if bodyFolder then
		for _, body in ipairs(bodyFolder:GetChildren()) do body:Destroy() end
	end
	if bloodFolder then
		for _, bloodPart in ipairs(bloodFolder:GetChildren()) do bloodPart:Destroy() end
	end
	if toolsFolder then
		for _, tool in ipairs(toolsFolder:GetChildren()) do tool:Destroy() end
	end

	helperModule.StartWaiting()
end

function helperModule.Initialize()
	helperModule.StartWaiting()
	
	loadJuggernautWins()
	
	helperModule.UpdateJuggernautLeaderboard()
	
	-- Keep the leaderboard in sync as players join or leave
	local Players = game:GetService("Players")
	Players.PlayerAdded:Connect(function()
		helperModule.UpdateJuggernautLeaderboard()
	end)
	Players.PlayerRemoving:Connect(function()
		helperModule.UpdateJuggernautLeaderboard()
	end)
	
	helperModule.Intermission()
end

-- ============================================================
-- Juggernaut Win Tracking & Leaderboard
-- ============================================================
local DataStoreService = game:GetService("DataStoreService")

-- Keyed by UserId (string) -> { name = string, wins = number }
local juggernautWins = {}
local juggernautStore = nil

pcall(function()
	juggernautStore = DataStoreService:GetDataStore("JuggernautWins")
end)

loadJuggernautWins = function()
	if not juggernautStore then return end

	local ok, data = pcall(function()
		return juggernautStore:GetAsync("JuggernautWins")
	end)

	if ok and type(data) == "table" then
		juggernautWins = data
	end
end

local function saveJuggernautWins()
	if not juggernautStore then return end

	pcall(function()
		juggernautStore:SetAsync("JuggernautWins", juggernautWins)
	end)
end

function helperModule.RecordJuggernautWin()
	if currentSeekerPlayer then
		local userId = tostring(currentSeekerPlayer.UserId)
		local entry = juggernautWins[userId]

		if entry then
			entry.wins += 1
			entry.name = currentSeekerPlayer.Name
		else
			juggernautWins[userId] = { name = currentSeekerPlayer.Name, wins = 1 }
		end

		saveJuggernautWins()
		helperModule.UpdateJuggernautLeaderboard()
	end
end

function helperModule.UpdateJuggernautLeaderboard()
	pcall(function()
		local leaderboardModel = workspace:FindFirstChild("TimePlayedLeaderboard")
		if not leaderboardModel then return end

		local scoreBlock = leaderboardModel:FindFirstChild("ScoreBlock")
		if not scoreBlock then return end

		local leaderboardGui = scoreBlock:FindFirstChild("Leaderboard")
		if not leaderboardGui then return end

		local scoreFolder = leaderboardGui:FindFirstChild("Score")
		local namesFolder = leaderboardGui:FindFirstChild("Names")
		if not scoreFolder or not namesFolder then return end

		local sorted = {}
		for userId, entry in pairs(juggernautWins) do
			table.insert(sorted, { name = entry.name or "Unknown", wins = entry.wins or 0 })
		end
		-- Also include current players in the game so the leaderboard
		-- always shows names and scores when the server starts.
		local Players = game:GetService("Players")
		for _, plr in ipairs(Players:GetPlayers()) do
			local alreadyIncluded = false
			for _, e in ipairs(sorted) do
				if e.name == plr.Name then
					alreadyIncluded = true
					break
				end
			end
			if not alreadyIncluded then
				local userId = tostring(plr.UserId)
				local entry = juggernautWins[userId]
				table.insert(sorted, { name = plr.Name, wins = entry and entry.wins or 0 })
			end
		end

		table.sort(sorted, function(a, b)
			if a.wins == b.wins then
				return a.name < b.name
			end
			return a.wins > b.wins
		end)

		for i = 1, 10 do
			local scoreLabel = scoreFolder:FindFirstChild("Score" .. i)
			local nameLabel = namesFolder:FindFirstChild("Name" .. i)

			if scoreLabel and nameLabel then
				local entry = sorted[i]

				if entry then
					nameLabel.Text = entry.name
					scoreLabel.Text = tostring(entry.wins)
				else
					nameLabel.Text = ""
					scoreLabel.Text = ""
				end
			end
		end
		-- Populate the "Name" folder with the top 10 player names
		local nameFolder = leaderboardModel:FindFirstChild("Name")
		if nameFolder then
			for _, child in ipairs(nameFolder:GetChildren()) do
				child:Destroy()
			end
			for i = 1, 10 do
				local entry = sorted[i]
				if entry then
					local nameValue = Instance.new("StringValue")
					nameValue.Name = "Name" .. i
					nameValue.Value = entry.name
					nameValue.Parent = nameFolder
				end
			end
		end
	end)
end

return helperModule
