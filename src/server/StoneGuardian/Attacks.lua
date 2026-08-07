--!strict
--[[
	Attacks — biblioteca de ataques do Guardião de Pedra.

	Onde vive: ServerScriptService > StoneGuardian > Attacks

	Cada ataque é uma função (boss, targetChar) que:
	  1) manda um TELEGRAPH ao cliente (aviso visual, o jogador reage/desvia);
	  2) espera o tempo de telegraph;
	  3) resolve DANO no servidor (autoridade), aplicando multiplicador de fase.

	As funções RENDEM (task.wait). O StateMachine as roda com controle de "busy".
	Todo dano a jogador acontece aqui, no servidor — o cliente nunca decide dano.
]]

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BossPkg = ReplicatedStorage:WaitForChild("ArkhaeonBoss")
local BossConfig = require(BossPkg:WaitForChild("BossConfig"))
local Remotes = require(BossPkg:WaitForChild("Remotes"))

local TelegraphRemote = Remotes.get("Telegraph")
local VfxRemote = Remotes.get("BossVfx")

local Attacks = {}

-- Tipo mínimo do contexto do boss que os ataques consomem (evita dependência
-- circular com a classe StoneGuardian, que passa `self`).
type BossCtx = {
	model: Model,
	root: BasePart,
	damageMult: () -> number, -- retorna 1 na Fase 1, EnrageDamageMult na Fase 2
	isAlive: () -> boolean,
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

type Victim = { player: Player, char: Model, humanoid: Humanoid, root: BasePart, dist: number }

local function collectVictims(position: Vector3, radius: number): { Victim }
	local out = {}
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if not char then continue end
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not humanoid or not hrp or humanoid.Health <= 0 then continue end
		local dist = (hrp.Position - position).Magnitude
		if dist <= radius then
			table.insert(out, { player = player, char = char, humanoid = humanoid, root = hrp, dist = dist })
		end
	end
	return out
end

local function applyKnockback(root: BasePart, fromPos: Vector3, power: number)
	if power <= 0 then return end
	local dir = (root.Position - fromPos)
	dir = if dir.Magnitude > 0.01 then dir.Unit else Vector3.new(0, 1, 0)
	-- Empurra pra fora e um pouco pra cima. AssemblyLinearVelocity é a via atual
	-- (BodyVelocity está depreciado).
	root.AssemblyLinearVelocity = dir * power + Vector3.new(0, power * 0.5, 0)
end

-- Aplica dano a todos os alvos num raio. `opts.requireGrounded`: só acerta quem
-- NÃO está no ar (usado pelo SeismicSlam, onde pular salva).
local function damageArea(boss: BossCtx, position: Vector3, radius: number, baseDamage: number, opts: {
	knockback: number?,
	requireGrounded: boolean?,
}?)
	opts = opts or {}
	local dmg = baseDamage * boss.damageMult()
	for _, v in collectVictims(position, radius) do
		if opts.requireGrounded then
			local state = v.humanoid:GetState()
			if state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping then
				continue -- pulou no momento do baque: escapou
			end
		end
		v.humanoid:TakeDamage(dmg)
		if opts.knockback then
			applyKnockback(v.root, position, opts.knockback)
		end
	end
end

local function telegraph(attack: string, position: Vector3, radius: number, duration: number, extra: any?)
	TelegraphRemote:FireAllClients({
		attack = attack,
		position = position,
		radius = radius,
		duration = duration,
		extra = extra,
	})
end

local function targetRoot(targetChar: Model): BasePart?
	return targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- ---------------------------------------------------------------------------
-- Ataques
-- ---------------------------------------------------------------------------

-- Baque no chão: AoE circular na posição do alvo no início do telegraph.
function Attacks.GroundSlam(boss: BossCtx, targetChar: Model)
	local cfg = BossConfig.Attacks.GroundSlam
	local tRoot = targetRoot(targetChar)
	if not tRoot then return end

	local pos = tRoot.Position
	telegraph("GroundSlam", pos, cfg.Radius, cfg.Telegraph)
	task.wait(cfg.Telegraph)
	if not boss.isAlive() then return end

	VfxRemote:FireAllClients("Impact", pos, cfg.Radius)
	damageArea(boss, pos, cfg.Radius, cfg.Damage, { knockback = cfg.Knockback })
end

-- Arremesso de pedregulho: telegrafa o ponto de queda, tween do projétil, AoE.
function Attacks.RockThrow(boss: BossCtx, targetChar: Model)
	local cfg = BossConfig.Attacks.RockThrow
	local tRoot = targetRoot(targetChar)
	if not tRoot then return end

	-- Mira num ponto à frente do alvo (leve "lead" pra recompensar movimento).
	local aim = tRoot.Position + tRoot.AssemblyLinearVelocity * 0.4
	telegraph("RockThrow", aim, cfg.Radius, cfg.Telegraph)

	-- Cria o pedregulho e o lança do "ombro" do boss até o ponto mirado.
	local rock = Instance.new("Part")
	rock.Shape = Enum.PartType.Ball
	rock.Size = Vector3.new(4, 4, 4)
	rock.Material = Enum.Material.Slate
	rock.Color = Color3.fromRGB(70, 66, 60)
	rock.CanCollide = false
	rock.Anchored = true
	rock.CFrame = boss.root.CFrame * CFrame.new(0, 8, -4)
	rock.Parent = workspace
	Debris:AddItem(rock, cfg.Telegraph + 1)

	local origin = rock.Position
	local flightTime = math.max(0.15, cfg.Telegraph)
	local t0 = os.clock()
	while os.clock() - t0 < flightTime do
		if not boss.isAlive() then rock:Destroy(); return end
		local alpha = (os.clock() - t0) / flightTime
		-- Arco parabólico simples: interpola em linha e soma altura senoidal.
		local flat = origin:Lerp(aim, alpha)
		local height = math.sin(alpha * math.pi) * 18
		rock.CFrame = CFrame.new(flat + Vector3.new(0, height, 0))
		task.wait()
	end
	rock:Destroy()
	if not boss.isAlive() then return end

	VfxRemote:FireAllClients("Impact", aim, cfg.Radius)
	damageArea(boss, aim, cfg.Radius, cfg.Damage)
end

-- Onda de choque radial (Fase 2): anel que expande do boss; acerta quem o anel
-- cruza. Recompensa timing — dá pra ficar colado ou correr junto com a onda.
function Attacks.Shockwave(boss: BossCtx, _targetChar: Model)
	local cfg = BossConfig.Attacks.Shockwave
	local center = boss.root.Position
	telegraph("Shockwave", center, cfg.MaxRadius, cfg.Telegraph, { startRadius = cfg.StartRadius })
	task.wait(cfg.Telegraph)
	if not boss.isAlive() then return end

	VfxRemote:FireAllClients("Shockwave", center, cfg.MaxRadius)

	-- O anel avança de StartRadius até MaxRadius. Cada jogador só pode ser
	-- atingido UMA vez (quando o anel passa por ele).
	local hit: { [Player]: boolean } = {}
	local radius = cfg.StartRadius
	while radius < cfg.MaxRadius and boss.isAlive() do
		local inner = radius - cfg.Width * 0.5
		local outer = radius + cfg.Width * 0.5
		for _, v in collectVictims(center, outer) do
			if not hit[v.player] and v.dist >= inner then
				hit[v.player] = true
				v.humanoid:TakeDamage(cfg.Damage * boss.damageMult())
				applyKnockback(v.root, center, cfg.Knockback)
			end
		end
		radius += cfg.ExpandSpeed * task.wait()
	end
end

-- Barragem de pedregulhos (Fase 2): vários pontos de impacto telegrafados numa
-- área ao redor da arena/alvo, caindo quase juntos.
function Attacks.BoulderBarrage(boss: BossCtx, targetChar: Model)
	local cfg = BossConfig.Attacks.BoulderBarrage
	local tRoot = targetRoot(targetChar)
	local center = if tRoot then tRoot.Position else boss.root.Position

	local points = {}
	for i = 1, cfg.Count do
		local angle = math.rad((360 / cfg.Count) * i + math.random(-20, 20))
		local dist = math.random() * cfg.Spread
		local p = center + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
		table.insert(points, p)
		telegraph("BoulderBarrage", p, cfg.Radius, cfg.Telegraph)
	end

	task.wait(cfg.Telegraph)
	if not boss.isAlive() then return end

	for _, p in points do
		VfxRemote:FireAllClients("Impact", p, cfg.Radius)
		damageArea(boss, p, cfg.Radius, cfg.Damage)
	end
end

-- Baque sísmico arena-wide (Fase 2): telegraph longo; quem estiver no ar (pulou)
-- no momento da resolução não toma dano. Ataque-assinatura, o mais punitivo.
function Attacks.SeismicSlam(boss: BossCtx, _targetChar: Model)
	local cfg = BossConfig.Attacks.SeismicSlam
	local center = boss.root.Position
	telegraph("SeismicSlam", center, cfg.Radius, cfg.Telegraph)
	task.wait(cfg.Telegraph)
	if not boss.isAlive() then return end

	VfxRemote:FireAllClients("SeismicSlam", center, cfg.Radius)
	damageArea(boss, center, cfg.Radius, cfg.Damage, { requireGrounded = cfg.SafeIfAirborne })
end

return Attacks
