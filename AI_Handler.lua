--// Services
local PS = game:GetService("PathfindingService")

--// Module
local AI_Handler = {}
AI_Handler.__index = AI_Handler

--// Playstyle definitions
AI_Handler.Playstyles = {}
for _, playStyle in script:GetChildren() do
	if playStyle:IsA("ModuleScript") then
		AI_Handler.Playstyles[playStyle.Name] = require(playStyle)
	end
end

--// Default Navigation Costs
local Costs = {
	Climb = 1
}

--// Playstyle Type
export type Playstyle = {
	GetTarget: (AI: AI_Object) -> (nil),
	FollowTarget: (AI: AI_Object, target: mod) -> (nil),
	TryToAttack: (AI: AI_Object, target: Model) -> (nil)?,
}

--// AI_Object Type
export type AI_Object = { 
	--// Main attributes
	AI:Model, 
	PlayStyle: string?, 
	Target: Model?, 
	LastTargetPos: Vector3?, 

	--// Instance-derived attributes 
	Damage:number, 
	ChaseDistance: number, 
	AttackDistance: number, 
	MaxAttackIndex: number, 
	Cooldown: number, 
	WhoChases: string, 

	Humanoid: Humanoid, 
	Animator: Animator, 
	RootPart: BasePart, 

	ChaseFolder: Folder, 
	TargetV: ObjectValue, 
	DistanceV: NumberValue, 
	HealthV: NumberValue, 
	WaypointsV: ObjectValue,

	Sounds: { [string]: Sound }, 
	Animations: { [string]: Animation }, 

	_UseCombatHandler: boolean, 
	_InCooldown: boolean, 
	_Patrolling: boolean, 
	_Playstyle: Playstyle, 
	_KillEnabled: boolean, 
	_InfectTeamColor: BrickColor, 

	PathParams: { 
		AgentRadius: number, 
		AgentHeight: number, 
		AgentCanJump: boolean, 
		AgentCanClimb: boolean, 
		Costs: { [string]: number }
	},
}


--// Constructor
function AI_Handler.newAI(AI: Model, playStyle: string?)
	assert(AI, "Missing argument #1 (AI) or it is nil")

	local AI_Object: AI_Object = setmetatable({}, AI_Handler)

	--// Attributes
	local damage = AI:GetAttribute("Damage")
	local chaseDistance = AI:GetAttribute("ChaseDistance")
	local attackDistance = AI:GetAttribute("AttackDistance")
	local attackIndex = AI:GetAttribute("AttackIndex")
	local maxAttackIndex = AI:GetAttribute("MaxAttackIndex")
	local cooldown = AI:GetAttribute("AttackCooldown")
	local whoChases = AI:GetAttribute("WhoChases")
	local killInsteadOfInfect = AI:GetAttribute("Kill_InsteadOf_Infect")
	local infectTeamColor = AI:GetAttribute("InfectTeamColor")

	local AI_Playstyle = AI_Handler.Playstyles[playStyle] or AI_Handler.Playstyles.Agressive

	assert(damage ~= nil, "Missing attribute: Damage")
	assert(chaseDistance ~= nil, "Missing attribute: ChaseDistance")
	assert(attackDistance ~= nil, "Missing attribute: AttackDistance")
	assert(attackIndex ~= nil, "Missing attribute: AttackIndex")
	assert(maxAttackIndex ~= nil, "Missing attribute: MaxAttackIndex")
	assert(cooldown ~= nil, "Missing attribute: AttackCooldown")
	assert(whoChases ~= nil, "Missing attribute: WhoChases")
	assert(killInsteadOfInfect ~= nil, "Missing attribute: Kill_InsteadOf_Infect")
	assert(infectTeamColor ~= nil, "Missing attribute: InfectTeamColor")

	local Hum = AI:FindFirstChildWhichIsA("Humanoid")
	local Anima = Hum:FindFirstChild("Animator")
	local RootPart: BasePart = AI:FindFirstChild("HumanoidRootPart")

	assert(Hum, "Missing: Humanoid")
	assert(Anima, "Missing: Animator")
	assert(RootPart, "Missing part: HumanoidRootPart")

	--// Required Chase values
	local chaseFolder = AI:FindFirstChild("Chase")
	assert(chaseFolder, "Missing folder: Chase")

	local animsFolder = AI:FindFirstChild("Animations")
	assert(animsFolder, "Missing folder: Animations")

	local targetVal = chaseFolder:FindFirstChild("Target")
	local distanceVal = chaseFolder:FindFirstChild("Distance")
	local healthVal = chaseFolder:FindFirstChild("Health")
	local waypointsVal = chaseFolder:FindFirstChild("Waypoints")

	assert(targetVal, "Missing ValueBase: Target")
	assert(distanceVal, "Missing ValueBase: Distance")
	assert(healthVal, "Missing ValueBase: Health")
	assert(waypointsVal, "Missing ValueBase: Waypoints")

	local sounds, animations = {}, {}

	for _, v in RootPart:GetChildren() do
		if v:IsA("Sound") then
			sounds[v.Name] = v
		end
	end
	for _, v in animsFolder:GetChildren() do
		if v:IsA("Animation") then
			animations[v.Name] = v
		end
	end

	if RootPart:GetNetworkOwner() then
		warn(`AI RootPart has an NetworkOwner ({RootPart:GetNetworkOwner()}), it'll be removed for the script to run correctly`)
		RootPart.Anchored = false
		RootPart:SetNetworkOwner(nil)
	end

	--// Store values
	AI_Object.AI = AI
	AI_Object.Damage = damage
	AI_Object.ChaseDistance = chaseDistance
	AI_Object.AttackDistance = attackDistance
	AI_Object.MaxAttackIndex = maxAttackIndex
	AI_Object.Cooldown = cooldown
	AI_Object.WhoChases = whoChases

	AI_Object.Humanoid = Hum
	AI_Object.Animator = Anima
	AI_Object.RootPart = RootPart

	AI_Object.ChaseFolder = chaseFolder
	AI_Object.TargetV = targetVal
	AI_Object.DistanceV = distanceVal
	AI_Object.HealthV = healthVal
	AI_Object.WaypointsV = waypointsVal

	AI_Object.Sounds = sounds
	AI_Object.Animations = animations

	AI_Object._UseCombatHandler = false
	AI_Object._InCooldown = false
	AI_Object._Patrolling = false
	AI_Object._Playstyle = AI_Playstyle
	AI_Object._KillEnabled = killInsteadOfInfect
	AI_Object._InfectTeamColor = infectTeamColor

	AI_Object.PathParams = {
		AgentRadius = 2 * AI:GetScale(),
		AgentHeight = 5 * AI:GetScale(),
		AgentCanJump = true,
		AgentCanClimb = true,
		Costs = { table.unpack(Costs) }
	}

	return AI_Object
end

--// Function that follows the waypoints, if it has
function AI_Handler:FollowWaypoints()
	local waypointsFolder = self.WaypointsV.Value
	if not waypointsFolder then return end

	local sortedWaypoints = {}
	for _, part in ipairs(waypointsFolder:GetChildren()) do
		if part:IsA("BasePart") then
			table.insert(sortedWaypoints, part)
		end
	end
	table.sort(sortedWaypoints, function(a, b)
		return tonumber(a.Name) < tonumber(b.Name)
	end)

	self._Patrolling = true

	for _, targetWaypoint in ipairs(sortedWaypoints) do
		if not self._Patrolling then break end

		-- Gerar o caminho
		local path = PS:CreatePath(self.PathParams)
		local success, result = pcall(path.ComputeAsync, path, self.RootPart.Position, targetWaypoint.Position)

		if path.Status == Enum.PathStatus.Success and success then
			local waypoints = path:GetWaypoints()
			for _, waypoint in ipairs(waypoints) do
				if not self._Patrolling then break end

				self.Humanoid:MoveTo(waypoint.Position)

				local reached = false
				local conn
				conn = self.Humanoid.MoveToFinished:Connect(function()
					reached = true
					conn:Disconnect()
				end)

				local timeout = 5
				local timer = 0
				while not reached and timer < timeout do
					-- Interrompe se detectar alvo durante o patrulhamento
					local target = self._Playstyle:FindTarget(self)
					if target then
						self._Patrolling = false
						conn:Disconnect()
						self._Playstyle:FollowTarget(self, target)
						return
					end
					task.wait(0.025)
					timer += 0.025
				end
			end
		else
			warn("Failed to calculate the waypoint path", targetWaypoint.Name, result)
		end
	end

	self._Patrolling = false
end

--// Function that patrols and for exemple: try to find a target
function AI_Handler:Patrol()
	if self._Playstyle.GetTarget then
		local target = self._Playstyle:GetTarget(self)
		if target then
			self._Playstyle:FollowTarget(self, target)
		else
			self:FollowWaypoints()
		end
	else
		self:FollowWaypoints()
	end
end

--// Change AI behavior dynamically
function AI_Handler:ChangePlayStyle(newPlayStyle: string)
	assert(AI_Handler.Playstyles[newPlayStyle], "Invalid playstyle name")
	self._Playstyle = AI_Handler.Playstyles[newPlayStyle]
end

return AI_Handler
