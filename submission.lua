--[[ Services ]]
local Players = game:GetService("Players")  
local ReplicatedStorage = game:GetService("ReplicatedStorage") 
local TweenService = game:GetService("TweenService") 
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer  -- Reference to the local player.

--[[ GUI Setup ]]
local playerGui = player:WaitForChild("PlayerGui")
local MainGui: ScreenGui = playerGui:WaitForChild("MainGui")
local BottomFrame: Frame = MainGui:WaitForChild("Bottom") 

--[[ Shared Assets ]]
local Remotes = ReplicatedStorage.Remotes
local Sounds = ReplicatedStorage.Sounds
local Modules = ReplicatedStorage.Modules
local PlayerItems = ReplicatedStorage.PlayerItems
local UI = ReplicatedStorage.UI
local CollectablesFolder = ReplicatedStorage.Collectables

--[[ Zones and Particles ]]
local Zones = workspace:WaitForChild("Zones")
local Particles = PlayerItems.Particles
local ParticlesFolder = workspace.Particles
local workspaceSounds = workspace.Sounds

--[[ Configuration Files ]]
local CollectablesConfig = require(Modules.CollectablesConfig)
local RewardConfig = require(Modules.RewardConfig)
local ZonesConfig = require(Modules.ZonesConfig)
local BoostsConfig = require(Modules.BoostConfig)
local TweenModule = require(Modules.Tween)
local Short = require(ReplicatedStorage.Short)

--[[ Popups ]]
local PopupsWorkspace = workspace.Popups

-- Constants for managing the radius and spawning logic of collectables.
local GENERATION_OFFSET = 1
local radiusSize = PlayerItems.CollectionRadius.Size
local radiusPowerupSize = radiusSize * 2
local tweenPlaying = false  -- Keeps track of whether a tween is currently in progress.

--[[ Functions ]]

-- Helper function to return information based on whether the object is a model or a mesh part.
local function returnServerInfo(isModel: boolean, hit: MeshPart)
	-- Collect the relevant collectable info based on whether the hit object is part of a model or a regular mesh part.
	if isModel then
		return CollectablesConfig.CollectableInfo[hit.Parent.Name], hit.Parent.Name, hit.Parent
	else
		return CollectablesConfig.CollectableInfo[hit.Name], hit.Name, hit
	end
end

-- Function to animate the collection radius using a tween, creating a visual effect when an item is collected.
local function tweenCollectionRadius(collectionRadius: MeshPart)
	if tweenPlaying then return end  -- Avoiding simultaneous tweens.
	tweenPlaying = true

	-- Creating an expanding and contracting effect for the collection radius.
	local size = collectionRadius.Size.X
	local tweenLength = 0.05

	local tween = TweenService:Create(collectionRadius, TweenInfo.new(tweenLength),
		{Size = Vector3.new(size*1.15, 0, size*1.15)}  -- Expands the radius slightly.
	)
	tween:Play()
	tween.Completed:Wait()

	tween = TweenService:Create(collectionRadius, TweenInfo.new(tweenLength),
		{Size = Vector3.new(size, 0, size)}  -- Restores the radius to its original size.
	)
	tween:Play()
	tween.Completed:Wait()
	tweenPlaying = false
end

-- Function to play the sound associated with the collection of a specific type of collectable.
local function playSound(collectableType: string)
	local shouldPlaySound = player:FindFirstChild("Settings").Sounds.Value
	if shouldPlaySound == true then
		local collectableSound = Sounds:FindFirstChild(collectableType.."CollectionSound")
		if collectableSound then
			-- Cloning and playing the sound.
			local collectableSoundClone: Sound = collectableSound:Clone()
			collectableSoundClone.Parent = workspaceSounds
			collectableSoundClone:Play()
			task.wait(collectableSoundClone.TimeLength)  -- Wait for the sound to finish before destroying.
			collectableSoundClone:Destroy()
		end
	end
end

-- Function to create and display a particle effect when a collectable is collected.
local function displayParticleEffect(collectable, collectableInfo, amount: number)
	if not collectable then return end  -- Return if collectable is nil.
	if collectable:IsA("Model") then
		if not collectable.PrimaryPart then return end  -- Ensure the collectable model has a primary part.
	end

	-- Creating a particle effect to show when a collectable is picked up.
	local PickUpPart = Particles.RuneCollect:Clone()
	PickUpPart.Anchored = true
	PickUpPart.CanCollide = false
	PickUpPart.Transparency = 1
	PickUpPart.Position = if collectable:IsA("Model") == true then collectable.PrimaryPart.Position else collectable.Position
	PickUpPart.PickupEffect.Color = collectableInfo.ParticleColor or PickUpPart.PickupEffect.Color
	PickUpPart.Parent = ParticlesFolder

	-- Handling popups for the collected items, showing an amount if applicable.
	local collectableType = collectableInfo.Type.."s"
	local popupPart
	local isPopupPart = CollectablesConfig.POPUP_IDS[collectableType] ~= nil

	-- If it's a popup part, create and show it.
	if isPopupPart and (amount ~= nil) then
		-- Creating the popup GUI.
		popupPart = Instance.new("Part")
		popupPart.Name = collectableType
		popupPart.Size = Vector3.new(1,1,1)
		popupPart.Anchored = true
		popupPart.Position = PickUpPart.Position
		popupPart.Transparency = 1
		popupPart.CanCollide = false

		-- Create the popup GUI and position it above the collectable.
		local popupGUI = UI.PopupGUI:Clone()
		local parentFrame = popupGUI.ParentFrame
		local popupImage = parentFrame.CollectableImage
		local popupAmount = parentFrame.Amount
		popupAmount.Text = Short.en(amount)  -- Shorten the amount for display.
		popupImage.Image = "rbxassetid://"..CollectablesConfig.POPUP_IDS[collectableType]
		popupGUI.Parent = popupPart
		popupPart.Parent = PopupsWorkspace
	end

	collectable:Destroy()  -- Remove the collectable from the game after it has been collected.
	PickUpPart.PickupEffect:Emit()  -- Trigger the particle effect.

	-- Destroy the particle effect after a delay.
	task.delay(CollectablesConfig.PARTICLE_DELAY, function()
		PickUpPart:Destroy()

		if isPopupPart and (popupPart ~= nil) then
			local char = player.Character
			if not char then popupPart:Destroy() end
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if not hrp then popupPart:Destroy() end

			-- Tween the popup towards the player's position.
			local tween = TweenService:Create(popupPart, TweenInfo.new(0.2), {Position = hrp.Position - Vector3.new(0,1,0)})
			tween:Play()
			tween.Completed:Wait()
			popupPart:Destroy()
		end
	end)
end

-- Function to change the transparency of a collectable while it is being collected or dropped.
local function setCollectableTransparency(collectable, isModel: Model, transparency: number)
	-- Iterate through each part of the model and change the transparency to simulate it being "dropped."
	if isModel then
		for _, part in collectable:GetChildren() do
			if part.Name == "Casing" then continue end  -- Skip the casing if it exists.
			if part:IsA("BasePart") then
				part.Transparency = transparency
			end
		end
	else
		collectable.Transparency = transparency
	end
end

local function setCollectablePosition(collectable, isModel: boolean, position: Vector3)
	-- Position the collectable based on whether it's a model or a MeshPart
	if isModel then
		-- If it's a model, slightly adjust the Y-axis to ensure it sits above the surface
		position = position + Vector3.new(0, 1, 0)
		local collectableCFrame = CFrame.new(position)
		collectable:PivotTo(collectableCFrame)  -- Move the model to the calculated position
	else
		-- If it's not a model, directly set the MeshPart's position
		collectable.Position = position
	end
end

local function tweenModel(model: Model, CF: CFrame)
	-- Smoothly tween the model to a target CFrame (using a CFrameValue)
	local cfValue = Instance.new("CFrameValue")
	cfValue.Value = model:GetPivot()  -- Store the current position of the model

	cfValue:GetPropertyChangedSignal("Value"):Connect(function()
		-- Update the model's position when the CFrame value changes
		model:PivotTo(cfValue.Value)
	end)

	-- Create and play the tween to move the model to the desired position (CF)
	local tween = TweenService:Create(cfValue, CollectablesConfig.DEFAULT_TWEEN_INFO, {Value = CF})
	tween:Play()

	-- Once the tween is completed, destroy the CFrameValue to clean up
	tween.Completed:Connect(function()
		cfValue:Destroy()
	end)
end

local function hitItemIsCollectable(hit: MeshPart)
	-- Check if the hit item is a valid collectable by matching its name to the collectables list
	if CollectablesConfig.CollectableInfo[hit.Name] then return true end
	-- Check if the parent of the hit object is a collectable
	if hit.Parent ~= nil then
		if CollectablesConfig.CollectableInfo[hit.Parent.Name] then return true end
	end
	return false
end

local function spawnCollectable(Surface: Part, zoneName: string, currentZoneCollectables: Folder, chooseRandom: boolean, collectableName: string?, collectableValue: number?)
	-- Generate a random position within the zone surface to spawn the collectable
	local randomXPos = math.random(-1 * (Surface.Size.X-GENERATION_OFFSET)/2, (Surface.Size.X-GENERATION_OFFSET)/2)
	local randomZPos = math.random(-1 * (Surface.Size.Z-GENERATION_OFFSET)/2, (Surface.Size.Z-GENERATION_OFFSET)/2)

	-- Determine the collectable's name either randomly or from the given name
	local collectableName = if chooseRandom then CollectablesConfig.ChooseRandomCollectable(zoneName) else collectableName
	local collectableInfo = CollectablesConfig.CollectableInfo[collectableName]
	local collectableType = collectableInfo.Type

	-- Check if the collectable exists in the collection folder
	local collectable: MeshPart = CollectablesFolder:FindFirstChild(collectableName)
	if not collectable then return end

	-- Clone the collectable to ensure multiple instances can exist
	collectable = collectable:Clone()
	collectable:SetAttribute("Value", collectableValue)

	-- Calculate the position for the collectable based on the surface position and random offsets
	local collectablePos = Surface.Position + Vector3.new(randomXPos, collectableInfo.yOffset or CollectablesConfig.DEFAULT_Y_OFFSET, randomZPos)

	-- Set the collectable's position and transparency
	setCollectablePosition(collectable, collectable:IsA("Model"), collectablePos)
	setCollectableTransparency(collectable, collectable:IsA("Model"), 1)

	-- Parent the collectable to the appropriate collection folder in the zone
	collectable.Parent = currentZoneCollectables[collectableType.."s"]

	-- If the collectable is not a model and has collisions with other objects, destroy it to avoid issues
	if not collectable:IsA("Model") then
		if #collectable:GetTouchingParts() > 0 then
			collectable:Destroy()
		end
	end
end

local function createCollectionRadius(collectionRadiusSize: Vector3)
	-- Create a collection radius around the player to detect collectables
	local char = player.Character or player.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart")

	local CollectionRadius = PlayerItems.CollectionRadius:Clone()

	-- Set the position of the collection radius relative to the player's position
	CollectionRadius.Position = hrp.Position + Vector3.new(0, -2.75, 0)
	CollectionRadius.Size = collectionRadiusSize
	CollectionRadius.Parent = char

	-- Attach the collection radius to the player's HumanoidRootPart using a weld constraint
	local CollectionWeld: WeldConstraint = Instance.new("WeldConstraint")
	CollectionWeld.Name = "CollectionWeld"
	CollectionWeld.Part0 = hrp
	CollectionWeld.Part1 = CollectionRadius
	CollectionWeld.Parent = hrp

	-- Make the power-up button visible
	BottomFrame.Power.Visible = true

	-- Setup for detecting when the collection radius touches a collectable
	local radiusTouched
	local pickupDelay = CollectablesConfig.scalePickupDelay(player.leaderstats.Power.Value)

	-- Connection for when the radius touches a collectable
	radiusTouched = CollectionRadius.Touched:Connect(function(hit)
		local isCollectable = hitItemIsCollectable(hit)

		if isCollectable then
			-- Prevent further touching of the collectable until the interaction is complete
			hit.CanTouch = false

			-- If the collectable is a boost, handle the boost collection logic
			if (hit.Parent ~= nil) and (BoostsConfig.BoostInfo[hit.Parent.Name] ~= nil) then
				local collectableInfo = CollectablesConfig.CollectableInfo[hit.Parent.Name]
				local collectableType = collectableInfo.Type

				-- Trigger a server-side boost collection event
				local Result = Remotes.CollectBoost:InvokeServer(hit.Parent.Name)

				-- Wait for the pickup delay before executing further actions
				if hit.Parent then
					task.wait(pickupDelay)
					tweenCollectionRadius(CollectionRadius)  -- Optionally apply a visual effect to the collection radius
					displayParticleEffect(hit.Parent, collectableInfo)  -- Show particle effects for the boost
				end
				playSound(collectableType)  -- Play a sound to indicate the boost has been collected
			else
				-- For normal collectables, proceed with the standard collection process
				task.wait(pickupDelay)
				tweenCollectionRadius(CollectionRadius)  -- Apply a visual effect to the collection radius

				-- Determine if the collectable is a model and gather its data for server communication
				local isModel = if not hit.Parent then false else hit.Parent:IsA("Model")

				local collectableInfo, toSend, collectable = returnServerInfo(isModel, hit)
				if not collectableInfo then return end
				local collectableType = collectableInfo.Type

				-- Communicate with the server to collect the item
				local Result = Remotes.IsServerEvent:InvokeServer(hit)

				if Result == true then
					displayParticleEffect(hit, collectableInfo)  -- Display the particle effect for successful collection
					playSound(collectableType)  -- Play sound on collectable collection

					Remotes.CollectServerEvent:FireServer(hit)  -- Server-side collection event fired
					return
				end

				-- If not a server event, invoke the collection on the server side
				local Result = Remotes.CollectCollectable:InvokeServer(collectableType, toSend, hit:GetAttribute("Value"))
				displayParticleEffect(collectable, collectableInfo, Result)  -- Display effects for the collection process
				playSound(collectableType)  -- Play the associated sound effect
			end
		end
	end)

	-- Ensure that the connection is properly disconnected when the collection radius is destroyed
	CollectionRadius.Destroying:Connect(function()
		radiusTouched:Disconnect()
		radiusTouched = nil
	end)
end

local function destroyCollectionRadius()
	-- Destroy the collection radius and cleanup associated elements when no longer needed
	local char = player.Character or player.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart")

	-- Find and destroy the collection radius if it exists
	local CollectionRadius = char:FindFirstChild("CollectionRadius")
	if CollectionRadius then
		CollectionRadius:Destroy()
	end

	-- Log for debugging purposes
	print('Collection radius destroyed')

	-- Hide the power-up button once the collection radius is removed
	BottomFrame.Power.Visible = false

	-- Find and remove the weld constraint used to attach the radius to the player
	local CollectionWeld = hrp:FindFirstChild("CollectionWeld") or hrp:FindFirstChildOfClass("WeldConstraint")
	if CollectionWeld then
		CollectionWeld:Destroy()
	end
end

Remotes.ZoneEvent.OnClientEvent:Connect(function(enteringZone: boolean, collectionRadiusSize: Vector3)
	-- Handle the event when the player enters or exits a zone
	if enteringZone == true then
		if not collectionRadiusSize then return end
		radiusSize = collectionRadiusSize
		radiusPowerupSize = radiusSize * 2

		-- Create a new collection radius when entering a zone
		createCollectionRadius(collectionRadiusSize)
	else
		-- Destroy the collection radius when leaving the zone
		destroyCollectionRadius()
	end
end)

-- Handle collectable spawning and boss rewards in specific zones
for _, zone in Zones:GetChildren() do
	local Surface = zone:WaitForChild("Surface")

	local currentZoneCollectables = zone:WaitForChild("Collectables")

	-- Listen for new collectables being added and position them with a random Y offset
	for _, collectableType: Folder in currentZoneCollectables:GetChildren() do
		collectableType.ChildAdded:Connect(function(collectable)
			local currentPosition = if collectable:IsA("Model") then collectable.PrimaryPart.Position else collectable.Position
			local startingTweenPosition = currentPosition + Vector3.new(0, math.random(10, 20), 0)

			-- Set initial transparency and position for collectables
			setCollectableTransparency(collectable, collectable:IsA("Model"), 0)
			setCollectablePosition(collectable, collectable:IsA("Model"), startingTweenPosition)

			-- Animate collectables into their starting positions
			if collectable:IsA("Model") then
				tweenModel(collectable, CFrame.new(currentPosition))
			else
				local tween = TweenService:Create(
					collectable,
					CollectablesConfig.DEFAULT_TWEEN_INFO,
					{Position = currentPosition}
				)
				tween:Play()
				tween.Completed:Wait()
			end
		end)
	end

	local CollectableCreationConnection

	-- Only spawn collectables if the zone allows it
	if not table.find(ZonesConfig.NonPickupZones, zone.Name) then
		CollectableCreationConnection = RunService.Heartbeat:Connect(function()    
			-- Spawn collectables if the number of collectables in the zone is below the max limit
			if #currentZoneCollectables:GetDescendants() < CollectablesConfig.MAX_COLLECTABLES then
				spawnCollectable(Surface, zone.Name, currentZoneCollectables, true)
			end

			-- Disconnect the connection if the zone is destroyed
			if zone == nil then
				CollectableCreationConnection:Disconnect()
				CollectableCreationConnection = nil
			end
		end)
	end
end

-- Handle boss reward collection
Remotes.BossReward.OnClientEvent:Connect(function(currentZone: zoneName, collectionRadiusSize: Vector3)
	local RewardsInfo = RewardConfig.RewardInfo[currentZone]
	local Zone = Zones:FindFirstChild(currentZone)
	local ZoneInfo = ZonesConfig.getCurrentZoneInfo(currentZone)
	local BossInfo = ZoneInfo.BossInfo
	if not Zone then return end

	-- Create the collection radius for the boss reward area
	local Surface = Zone.Surface
	local currentZoneCollectables = Zone.Collectables

	createCollectionRadius(collectionRadiusSize)

	local currentIndex = 1

	-- Iterate through the reward items and spawn them based on their amount and type
	for rewardName, rewardAmount in RewardsInfo do
		local CollectableInfo = CollectablesConfig.CollectableInfo[rewardName]
		local rewardValue = CollectableInfo.Value
		local Type = CollectableInfo.Type

		-- Adjust for multipliers and calculate total values for rewards
		local multipliers = Remotes.getPlayerMultipliers:InvokeServer(Type)
		local totalValue = rewardValue * multipliers
		local iterations = rewardAmount/totalValue

		-- If the reward amount requires fewer iterations than the available rewards, spawn one collectable
		if iterations < 1 then
			if currentIndex >= #RewardsInfo then
				spawnCollectable(Surface, currentZone, currentZoneCollectables, false, rewardName, rewardAmount)
			else
				spawnCollectable(Surface, currentZone, currentZoneCollectables, false, rewardName)
			end
			continue
		end

		-- For larger rewards, spawn multiple collectables
		for currentIteration = 1, iterations-1, 1 do
			spawnCollectable(Surface, currentZone, currentZoneCollectables, false, rewardName)
			task.wait(0.1)
		end

		-- Spawn the final collectable of the reward
		if currentIndex >= #RewardsInfo then
			spawnCollectable(Surface, currentZone, currentZoneCollectables, false, rewardName, 0)
		else
			spawnCollectable(Surface, currentZone, currentZoneCollectables, false, rewardName)
		end

		currentIndex += 1
	end

	-- Wait for the respawn duration before cleaning up
	task.wait(BossInfo.RESPAWN_DURATION)

	-- Destroy the collection radius after the boss event ends
	destroyCollectionRadius()
end)
