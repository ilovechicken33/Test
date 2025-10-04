Hastebin

local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Teams = game:GetService("Teams")

local Remotes = ReplicatedStorage.Remotes
local Modules = ServerScriptService.Modules
local RepModules = ReplicatedStorage.Modules

local UnlockableItems = ServerStorage.UnlockableItems
local TycoonTemplate = ServerStorage.TycoonTemplate

local PlayerManager = require(Modules.PlayerManager)
local Submarines = workspace.Submarines

local ButtonModule = require(Modules.Button)
local ConveyorModule = require(Modules.Conveyor)
local UpgraderModule = require(Modules.Upgrader)
local CollectorModule = require(Modules.Collector)
local GamepassObjModule = require(Modules.Gamepass)
local TeleporterModule = require(Modules.Teleporter)

local ButtonInfo = require(Modules.ButtonInfo)
local FormatNumber = require(Modules.FormatNumber.Simple)

local ZoneModule = require(RepModules.Zone)

local Tycoons = workspace.Tycoons
local Drops = workspace.Drops

local Tycoon = {}
Tycoon.__index = Tycoon

Tycoon.ClaimedTycoons = {} -- Stores all the tycoons that have been claimed

local function setup(tycoon: Model)
	--Creating a new tycoon folder 
	local tycoonFolder = Instance.new("Folder")
	tycoonFolder.Name = tycoon.Name
	tycoonFolder.Parent = UnlockableItems

	--Storing all of the buttons that unlock droppers, walls, etc
	local buttonFolder = Instance.new('Folder')
	buttonFolder.Name = "Buttons"
	buttonFolder.Parent = tycoonFolder
	
	tycoon.Door.Parent = tycoonFolder

	for _, button in tycoon.Buttons:GetChildren() do
		--Hides all of the buttons except for the first one
		if button.Name ~= "1" then
			button.Parent = buttonFolder
		end
	end
	
	--Hides all of the unlockables from player view by storing them in a folder
	for _, unlockableType in tycoon.Unlockables:GetChildren() do
		local unlockableTypeFolder = Instance.new("Folder")
		unlockableTypeFolder.Name = unlockableType.Name

		for _, child in unlockableType:GetChildren() do
			child.Parent = unlockableTypeFolder
		end

		unlockableTypeFolder.Parent = tycoonFolder
	end
	
	tycoon.Building.DOORFRAME.DOOR.Touched:Connect(function(hit: BasePart)
		--Checks when a player first goes through the door model--
		if hit.Parent:FindFirstChild("Humanoid") then
			local player = Players:GetPlayerFromCharacter(hit.Parent)
			local newTycoon = Tycoon.new(player, tycoon)

			if newTycoon ~= nil then
				newTycoon:Init() -- Calling the init method, which sets everything up internally
			end
		end
	end)
end

for _, tycoon in Tycoons:GetChildren() do
	--This calls the setup() function for all of the tycoons preput into the game
	setup(tycoon)
end

local function playerOwnsTycoon(player: Player)
	--This function checks if a player already owns a tycoon, which means they cant claim another one
	for _, plr in Tycoon.ClaimedTycoons do
		if plr.UserId == player.UserId then
			return true
		end
	end
	return false
end

local function displayButtonAffordability(player: Player, tycoonName: string, buttonName: string)
	--This function turns a button green or red depending on if the player can afford it
	local currentButtonInfo = ButtonInfo.GetButtonInfo(buttonName)
	if currentButtonInfo.ID ~= nil then return end
	
	local canAfford = player.leaderstats.Cash.Value >= currentButtonInfo.Price
	Remotes.UpdateButtonAffordability:FireClient(player, tycoonName, buttonName, canAfford)
end

local function findAvailableTycoon(player: Player)
	--This gives a player an available tycoon when they join the game. Gives them a little arrow leading toward the tycoon
	for _, tycoon in workspace.Tycoons:GetChildren() do
		if not Tycoon.ClaimedTycoons[tycoon] then
			return tycoon.Name
		end
	end
	return nil
end

function Tycoon:End()
	--Destroys the tycoon completely from the map and wipes all data associated with it
	Tycoon.ClaimedTycoons[self.Tycoon] = nil

	if UnlockableItems:FindFirstChild(self.Owner.Name) then
		UnlockableItems:FindFirstChild(self.Owner.Name):Destroy()
	end
	
	if Submarines:FindFirstChild(self.Owner.Name) then
		Submarines:FindFirstChild(self.Owner.Name):Destroy()
	end
	
	if Drops:FindFirstChild(self.Owner.Name) then
		Drops:FindFirstChild(self.Owner.Name):Destroy()
	end
	
	
	if TycoonTemplate:FindFirstChild("Template") then
		--This reverses everything that was done to the tycoon by the player--
		local backup = TycoonTemplate.Template:Clone()
		local backupName = self.Tycoon.Name
		local backupCFrame = self.Tycoon:GetPivot()
		local backupDropType = self.Tycoon:GetAttribute("DropType")
		
		backup:SetAttribute("DropType", backupDropType)
		backup.Name = backupDropType.."Tycoon"
		backup:PivotTo(backupCFrame)
		
		self.Tycoon.Parent = ServerStorage.Purgatory
		
		backup.Parent = Tycoons
		setup(backup)
	end
	
	self.Tycoon:Destroy()
	
	--Idk what exactly these do, I think it protects against memory leaks or something
	setmetatable(self, nil)
	table.clear(self)
	table.freeze(self)
end

function Tycoon:Init()
	--Initialising all the buttons--
	
	local buttons = self.Tycoon.Buttons
	for _, button in buttons:GetChildren() do
		local buttonObj = ButtonModule.new(self.Owner, self.Tycoon, button)
	end
	
	--Initialising conveyors--
	
	local conveyors = self.Tycoon.Conveyors
	for _, conveyor in conveyors:GetChildren() do
		local conveyorObj = ConveyorModule.new(self.Tycoon, conveyor, self.Owner)
	end
	
	--Initialising collector--
	local collectors = self.Tycoon.Collectors
	local unlockableCollectors = self.Tycoon.Unlockables.Collector
	
	for _, collector in collectors:GetChildren() do
		local collectorObj = CollectorModule.new(self.Tycoon, collector, self.Owner)
	end
	
	--Initialising gamepasses--
	local gamepasses = self.Tycoon.Gamepasses
	for _, gamepass in gamepasses:GetChildren() do
		local gamepassObj = GamepassObjModule.new(self.Tycoon, gamepass, self.Owner)
	end
	
	--Initialising teleporters-
	
	local teleporters = self.Tycoon.Teleporters
	for _, teleporter in teleporters:GetChildren() do
		local teleportObj = TeleporterModule.new(self.Tycoon, teleporter, self.Owner)
	end
	
	--Initialising upgraders--
	
	local upgraders = self.Tycoon.Unlockables.Upgrader
	
	for _, upgrader in upgraders:GetChildren() do
		local upgraderObj = UpgraderModule.new(self.Tycoon, upgrader)
	end
	
	self.Tycoon.Stats.MoneyCollected.Changed:Connect(function(newValue: number)
		--Every time the player collects money, it updates the collectors to show the new value--
		for _, collector in collectors:GetChildren() do
			collector.Sensor.BillboardGui.TextLabel.Text = "COLLECT: $"..FormatNumber.Format(newValue)
		end
		
		for _, collector in unlockableCollectors:GetChildren() do
			collector.Sensor.BillboardGui.TextLabel.Text = "COLLECT: $"..FormatNumber.Format(newValue)
		end
	end)
end

function Tycoon.new(player: Player, tycoon: Model)
	--If the player already has a tycoon, then return--
	if Tycoon.ClaimedTycoons[tycoon] then return nil end
	--If the current tycoon is already owned by the player then return
	if playerOwnsTycoon(player) then return nil end
	
	local self = {}
	setmetatable(self, Tycoon)
	
	self.Owner = player
	self.Tycoon = tycoon
	
	player.PrivateStats.ClaimedTycoon.Value = true
	Tycoon.ClaimedTycoons[tycoon] = player
	
	player.Team = Teams[tycoon:GetAttribute("DropType")] --This sets the type of the tycoon, which affects the type of drops

	local playerItems = Instance.new('Folder')
	playerItems.Name = player.Name
	playerItems.Parent = UnlockableItems
	
	local playerDrops = Instance.new('Folder')
	playerDrops.Name = player.Name
	playerDrops.Parent = Drops
	
	--Transferring all the stuff to the player's folder--
	local tycoonFolder = UnlockableItems:FindFirstChild(tycoon.Name)
	
	for _, child in tycoonFolder:GetChildren() do
		child.Parent = playerItems
	end
	
	tycoonFolder:Destroy()
	
	--Door--
	
	playerItems.Door.Parent = tycoon
	local door = tycoon.Door
	
	for _, part in door:GetChildren() do
		if part:FindFirstChildOfClass("ClickDetector") then continue end
		
		--This is for when another player goes through the tycoon door (owner only door?)
		part.Touched:Connect(function(hit: BasePart)
			if hit.Parent:FindFirstChild("Humanoid") then
				local plrWhoHit = Players:GetPlayerFromCharacter(hit.Parent)
				
				if (plrWhoHit ~= player) and (part.Transparency == 0) then
					plrWhoHit.Character.Humanoid.Health = 0
				end
			end
		end)
	end
	
	--This is triggering the owner only door functionality--
	door.Button.ClickDetector.MouseClick:Connect(function(playerWhoClicked: Player)
		if playerWhoClicked == player then
			for _, part in door:GetChildren() do
				if part:FindFirstChildOfClass("ClickDetector") then continue end
				
				part.Transparency = if part.Transparency == 0 then 1 else 0
			end
		end
	end)
	
	tycoon.Name = player.Name
	
	--loading in the player's previous data--
	PlayerManager.GamepassFunctions[935563288](player, 935563288, true)
	
	local currentButtonValue = player.PrivateStats.CurrentButton.Value --Gets the value of the current button the player is on
	
	if currentButtonValue > 1 then --Hopefully saves myself a cheeky headache--
		for _, unlockableType in playerItems:GetChildren() do
			for _, child in unlockableType:GetChildren() do
				local currentNum = tonumber(child.Name)
				if not currentNum then continue end
				
				local currentButtonInfo = ButtonInfo.GetButtonInfo(child.Name)

				if unlockableType.Name == "Buttons" then
					if currentNum == currentButtonValue + 1 then
						
						if currentButtonInfo.ID ~= nil then
							if not player.PrivateStats.Gamepasses:FindFirstChild(currentButtonInfo.Display) then
								child.Parent = tycoon.Buttons
								local nextButton = unlockableType:FindFirstChild(currentNum + 1)
								
								if nextButton then
									nextButton.Parent = tycoon.Buttons
								end
							end
						else
							child.Parent = tycoon.Buttons
						end
					end
				else
					if currentNum <= currentButtonValue then
						if currentButtonInfo.ID ~= nil then
							if not player.PrivateStats.Gamepasses:FindFirstChild(currentButtonInfo.Display) then
								continue
							else
								PlayerManager.GamepassFunctions[currentButtonInfo.ID](player, currentButtonInfo.ID, true)
							end
						end
						
						child.Parent = tycoon.Unlockables:FindFirstChild(unlockableType.Name)
					end
				end
			end
		end
		
		if tycoon.Buttons:FindFirstChild("1") then
			tycoon.Buttons:FindFirstChild("1"):Destroy()
		end
	end
	
	--Loading in all the droppers and stuff you know--
	for _, unlockableType in tycoon.Unlockables:GetChildren() do
		if Modules:FindFirstChild(unlockableType.Name) then
			local module = require(Modules:FindFirstChild(unlockableType.Name))
			for _, child in unlockableType:GetChildren() do
				local newObj = module.new(tycoon, child, player)
			end
		end
	end
	
	--All the affordability things yk--
	for _, button in tycoon.Buttons:GetChildren() do
		displayButtonAffordability(player, tycoon.Name, button.Name)
	end
	
	--Whole bunch of connections and sh
	
	local cashConnection --Checks every second to see if the player's cash has gone up, then updates the affordability of a button
	cashConnection = player.leaderstats.Cash.Changed:Connect(function()
		task.wait(1)
		if not tycoon.Buttons then return end
		if #tycoon.Buttons:GetChildren() >= 1 then --Otherwise nothings in there
			for _, button in tycoon.Buttons:GetChildren() do
				displayButtonAffordability(player, tycoon.Name, button.Name)
			end
		end
	end)
	
	tycoon.Buttons.ChildAdded:Connect(function(child: Model)
		for _, button in tycoon.Buttons:GetChildren() do
			displayButtonAffordability(player, tycoon.Name, button.Name)
		end
	end)
	
	local playerRemovingConnection --Checks to see if the player is removing, and if so, ends everything
	playerRemovingConnection = Players.PlayerRemoving:Connect(function(plrWhoLeft: Player)
		if plrWhoLeft == player then
			
			--prevents memory leaks (I think)
			cashConnection:Disconnect()
			cashConnection = nil
			
			self:End()

			--prevents memory leaks (i think)
			playerRemovingConnection:Disconnect()
			playerRemovingConnection = nil
		end
	end)
	
	return self
end

--This remote function returns an available tycoon to the client
Remotes.FindAvailableTycoon.OnServerInvoke = findAvailableTycoon

return Tycoon

For immediate assistance, please email our customer support: support@toptal.com

