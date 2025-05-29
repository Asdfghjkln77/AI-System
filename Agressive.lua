--// Services
local PS = game:GetService("PathfindingService")
local Plrs = game:GetService("Players")

--// Module
local Agressive = {}

--// Function that try to get a target
function Agressive:GetTarget(AI: {any}): Model?
	for _, plr in Plrs:GetPlayers() do
		local char = plr.Character
		local hum = char and char:FindFirstChildWhichIsA("Humanoid")
		local root: BasePart? = char and char:FindFirstChild("HumanoidRootPart")
		if not root or not hum or hum.Health <= 0 then continue end
		
		local whoChasesTb = AI.WhoChases:gsub(" ", ""):split(",")
		local canChaseTeam = false
		
		for _, v in whoChasesTb do if v == plr.Team.Name then canChaseTeam = true break end end

		local dist = (root.Position - AI.RootPart.Position).Magnitude
		local canChase = (AI.WhoChases == "Everyone") or canChaseTeam
		local distAllowed = dist <= AI.ChaseDistance

		if canChase and distAllowed then
			AI.TargetV.Value, AI.DistanceV.Value, AI.HealthV.Value = char, dist, hum.Health
			return char
		else
			AI.TargetV.Value, AI.DistanceV.Value, AI.HealthV.Value = nil, 0, 0
			return nil
		end
	end
	return nil
end

--// Function that follows a target
function Agressive:FollowTarget(AI: {any}, target: Model)
	local humanoidRoot = target:FindFirstChild("HumanoidRootPart")
	local targetHum = target:FindFirstChildWhichIsA("Humanoid")
	if not humanoidRoot or not targetHum then return end

	while targetHum.Health > 0 and (AI.RootPart.Position - humanoidRoot.Position).Magnitude <= AI.ChaseDistance do
		local dist = (AI.RootPart.Position - humanoidRoot.Position).Magnitude

		if dist <= AI.AttackDistance then
			Agressive:TryToAttack(AI, target)
			break
		end

		local path = PS:CreatePath(AI.PathParams)
		path:ComputeAsync(AI.RootPart.Position, humanoidRoot.Position)

		if path.Status == Enum.PathStatus.Success then
			local waypoints = path:GetWaypoints()
			for _, waypoint in ipairs(waypoints) do
				if (AI.RootPart.Position - humanoidRoot.Position).Magnitude <= AI.AttackDistance then
					break
				end
				AI.Humanoid:MoveTo(waypoint.Position)
			end
		end

		task.wait()
	end
end

--// Function that try to attack a target
function Agressive:TryToAttack(AI: {any}, target: Model)
	if AI._InCooldown then return end -- 🛑
	
	local plr = Plrs:GetPlayerFromCharacter(target)
	local hum = target:FindFirstChildWhichIsA("Humanoid")
	local root = target:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health <= 0 then return end

	if (AI.RootPart.Position - root.Position).Magnitude <= AI.AttackDistance then
		AI._InCooldown = true -- ✅

		local index = AI.AI:GetAttribute("AttackIndex") or 1
		local anim = AI.Animations[`Attack{index}`]
		local sound = AI.Sounds[`Attack{index}`]

		if anim then
			local track = AI.Animator:LoadAnimation(anim)
			track:Play()
		end
		if sound then
			sound:Play()
		end

		AI.AI:SetAttribute("AttackIndex", (index % AI.MaxAttackIndex) + 1)
		if hum.Health <= AI.Damage and not AI._KillEnabled then
			if plr then
				plr.TeamColor = AI._InfectTeamColor
			end
		else
			hum:TakeDamage(AI.Damage)
		end

		task.delay(AI.Cooldown or 1, function()
			AI._InCooldown = false
		end)
	end
end

return Agressive
