--!strict
--[[
	StoneGuardian — classe do boss Guardião de Pedra (Arkhaeon).

	Onde vive: ServerScriptService > StoneGuardian (ModuleScript com filhos
	           BossModelBuilder, Attacks). O bootstrap dá require e :new().

	Responsabilidades (TUDO no servidor — autoridade):
	  • spawn do modelo e vida
	  • máquina de estados (Dormant → Awakening → Phase1 → Phase2 → Staggered → Dead)
	  • seleção de alvo, locomoção, seleção e execução de ataques
	  • recepção de dano com armadura, poise e stagger (núcleo exposto)
	  • transições de fase e morte + recompensa

	Segurança/limpeza: todo dano de/para o boss é resolvido aqui; conexões e
	loops são registrados e desligados em :Destroy() pra não vazar memória.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BossPkg = ReplicatedStorage:WaitForChild("ArkhaeonBoss")
local BossConfig = require(BossPkg:WaitForChild("BossConfig"))
local BossTypes = require(BossPkg:WaitForChild("BossTypes"))
local Remotes = require(BossPkg:WaitForChild("Remotes"))

local script = script :: ModuleScript
local BossModelBuilder = require(script:WaitForChild("BossModelBuilder"))
local Attacks = require(script:WaitForChild("Attacks"))

local BossStateRemote = Remotes.get("BossState")
local VfxRemote = Remotes.get("BossVfx")

type Phase = BossTypes.Phase
type AttackName = BossTypes.AttackName

local StoneGuardian = {}
StoneGuardian.__index = StoneGuardian

export type StoneGuardian = typeof(setmetatable(
	{} :: {
		model: Model,
		root: BasePart,
		humanoid: Humanoid,
		core: BasePart?,
		phase: Phase,
		alive: boolean,
		busy: boolean,          -- executando um ataque (não anda nem escolhe outro)
		coreExposed: boolean,
		canStagger: boolean,
		poise: number,
		poiseResetAt: number,
		cooldowns: { [string]: number }, -- os.clock() em que cada ataque libera
		connections: { RBXScriptConnection },
		aiThread: thread?,
		onDefeated: ((StoneGuardian) -> ())?,
	},
	StoneGuardian
))

-- ---------------------------------------------------------------------------
-- Construção
-- ---------------------------------------------------------------------------

function StoneGuardian.new(spawnCFrame: CFrame): StoneGuardian
	local model = BossModelBuilder.spawn(spawnCFrame)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model.PrimaryPart :: BasePart

	humanoid.MaxHealth = BossConfig.MaxHealth
	humanoid.Health = BossConfig.MaxHealth
	humanoid.WalkSpeed = 0 -- começa dormente

	local self = setmetatable({
		model = model,
		root = root,
		humanoid = humanoid,
		core = model:FindFirstChild("Core") :: BasePart?,
		phase = "Dormant" :: Phase,
		alive = true,
		busy = false,
		coreExposed = false,
		canStagger = true,
		poise = 0,
		poiseResetAt = 0,
		cooldowns = {},
		connections = {},
		aiThread = nil,
		onDefeated = nil,
	}, StoneGuardian) :: StoneGuardian

	-- Núcleo apagado no início.
	self:_setCoreGlow(false)

	-- Morte via Humanoid (rede de segurança caso algo zere a vida direto).
	table.insert(self.connections, humanoid.Died:Connect(function()
		self:_die()
	end))

	self:_broadcast()
	self:_startAI()
	return self
end

-- ---------------------------------------------------------------------------
-- Estado / broadcast
-- ---------------------------------------------------------------------------

function StoneGuardian._broadcast(self: StoneGuardian)
	local snapshot: BossTypes.BossSnapshot = {
		name = BossConfig.Name,
		health = math.max(0, self.humanoid.Health),
		maxHealth = self.humanoid.MaxHealth,
		phase = self.phase,
		coreExposed = self.coreExposed,
	}
	BossStateRemote:FireAllClients(snapshot)
end

function StoneGuardian._setCoreGlow(self: StoneGuardian, on: boolean)
	local core = self.core
	if not core then return end
	core.Transparency = if on then 0 else 0.35
	local light = core:FindFirstChildOfClass("PointLight")
	if light then
		light.Brightness = if on then 4 else 0
	end
end

-- Multiplicador de dano de saída (Fase 2 pega o enrage). Passado aos Attacks.
function StoneGuardian._damageMult(self: StoneGuardian): number
	return if self.phase == "Phase2" then BossConfig.EnrageDamageMult else 1
end

-- ---------------------------------------------------------------------------
-- Alvo / locomoção
-- ---------------------------------------------------------------------------

-- Alvo = jogador vivo mais próximo dentro do leash. Retorna char + distância.
function StoneGuardian._pickTarget(self: StoneGuardian): (Model?, number)
	local bestChar: Model? = nil
	local bestDist = math.huge
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if not char then continue end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hum or not hrp or hum.Health <= 0 then continue end
		local dist = (hrp.Position - self.root.Position).Magnitude
		if dist < bestDist then
			bestDist = dist
			bestChar = char
		end
	end
	if bestDist > BossConfig.LeashRange then
		return nil, bestDist
	end
	return bestChar, bestDist
end

-- ---------------------------------------------------------------------------
-- Seleção de ataque
-- ---------------------------------------------------------------------------

function StoneGuardian._ready(self: StoneGuardian, name: string): boolean
	local at = self.cooldowns[name]
	return at == nil or os.clock() >= at
end

function StoneGuardian._setCooldown(self: StoneGuardian, name: string, base: number)
	local mult = if self.phase == "Phase2" then BossConfig.EnrageCooldownMult else 1
	self.cooldowns[name] = os.clock() + base * mult
end

-- Escolhe um ataque válido dada a fase e a distância do alvo. Retorna nil se
-- nada estiver pronto (aí o boss só persegue).
function StoneGuardian._chooseAttack(self: StoneGuardian, dist: number): AttackName?
	local A = BossConfig.Attacks
	local pool: { AttackName } = {}

	-- Fase 1 e 2: básicos.
	if self:_ready("GroundSlam") and dist <= A.GroundSlam.Range then
		table.insert(pool, "GroundSlam")
	end
	if self:_ready("RockThrow") and dist >= A.RockThrow.MinRange then
		table.insert(pool, "RockThrow")
	end

	-- Só na Fase 2: kit de enrage.
	if self.phase == "Phase2" then
		if self:_ready("Shockwave") then table.insert(pool, "Shockwave") end
		if self:_ready("BoulderBarrage") then table.insert(pool, "BoulderBarrage") end
		if self:_ready("SeismicSlam") then table.insert(pool, "SeismicSlam") end
	end

	if #pool == 0 then return nil end
	return pool[math.random(1, #pool)]
end

function StoneGuardian._execute(self: StoneGuardian, name: AttackName, target: Model)
	self.busy = true
	self.humanoid:MoveTo(self.root.Position) -- trava no lugar durante o golpe
	self:_setCooldown(name, BossConfig.Attacks[name].Cooldown)

	local ctx = {
		model = self.model,
		root = self.root,
		damageMult = function() return self:_damageMult() end,
		isAlive = function() return self.alive end,
	}

	-- pcall pra um golpe que falhe não travar a IA em busy=true pra sempre.
	local ok, err = pcall(function()
		(Attacks :: any)[name](ctx, target)
	end)
	if not ok then
		warn("[StoneGuardian] ataque", name, "falhou:", err)
	end
	self.busy = false
end

-- ---------------------------------------------------------------------------
-- Loop de IA
-- ---------------------------------------------------------------------------

function StoneGuardian._startAI(self: StoneGuardian)
	self.aiThread = task.spawn(function()
		while self.alive do
			task.wait(0.15)
			if self.busy then continue end

			local target, dist = self:_pickTarget()

			if self.phase == "Dormant" then
				if target and dist <= BossConfig.AggroRange then
					self:_awaken()
				end
				continue
			end

			if self.phase == "Staggered" then
				continue -- travado; o timer de stagger religa a fase
			end

			if not target then
				-- Sem alvo no leash: para. (Poderia voltar a dormir; mantemos
				-- simples e só aguardamos.)
				self.humanoid:MoveTo(self.root.Position)
				continue
			end

			local tRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not tRoot then continue end

			local attack = self:_chooseAttack(dist)
			if attack then
				self:_execute(attack, target)
			else
				-- Nada pronto: persegue o alvo.
				self.humanoid:MoveTo(tRoot.Position)
			end
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Transições de fase
-- ---------------------------------------------------------------------------

function StoneGuardian._awaken(self: StoneGuardian)
	self.phase = "Awakening"
	self:_broadcast()
	VfxRemote:FireAllClients("Awaken", self.root.Position, 0)
	self.busy = true
	task.wait(1.5) -- animação de "acordar" (rugido, poeira)
	self.busy = false
	self.humanoid.WalkSpeed = BossConfig.WalkSpeed
	self.phase = "Phase1"
	self:_broadcast()
end

function StoneGuardian._maybePhase2(self: StoneGuardian)
	if self.phase ~= "Phase1" then return end
	local frac = self.humanoid.Health / self.humanoid.MaxHealth
	if frac <= BossConfig.Phase2Threshold then
		self.phase = "Phase2"
		self.humanoid.WalkSpeed = BossConfig.WalkSpeed * BossConfig.EnrageSpeedMult
		VfxRemote:FireAllClients("Enrage", self.root.Position, 0)
		self:_broadcast()
	end
end

-- ---------------------------------------------------------------------------
-- Recepção de dano (armadura + poise + stagger)
-- ---------------------------------------------------------------------------

-- API pública: o sistema de combate do jogo chama isto pra ferir o boss.
-- `raw` = dano bruto do golpe do jogador; `_source` = quem causou (p/ agro/loot).
function StoneGuardian.TakeDamage(self: StoneGuardian, raw: number, _source: Player?)
	if not self.alive or self.phase == "Dormant" then return end
	if raw <= 0 then return end

	local applied: number
	if self.coreExposed then
		-- Núcleo à mostra: dano cheio + bônus. É a janela de burst do time.
		applied = raw * BossConfig.CoreDamageBonus
	else
		-- Armadura fechada: dano reduzido, mas acumula poise pra quebrar.
		applied = raw * (1 - BossConfig.ArmorReduction)
		self:_addPoise(raw)
	end

	self.humanoid:TakeDamage(applied)
	self:_maybePhase2()
	self:_broadcast()
end

function StoneGuardian._addPoise(self: StoneGuardian, amount: number)
	if not self.canStagger then return end

	local now = os.clock()
	if now >= self.poiseResetAt then
		self.poise = 0 -- passou da janela sem quebrar: zera o acúmulo
	end
	self.poise += amount
	self.poiseResetAt = now + BossConfig.PoiseWindow

	if self.poise >= BossConfig.PoiseMax then
		self:_stagger()
	end
end

function StoneGuardian._stagger(self: StoneGuardian)
	self.poise = 0
	self.canStagger = false
	self.coreExposed = true
	self.phase = "Staggered"
	self.humanoid:MoveTo(self.root.Position)
	self:_setCoreGlow(true)
	VfxRemote:FireAllClients("Stagger", self.root.Position, 0)
	self:_broadcast()

	-- Timers independentes: stun curto vs. janela de núcleo exposto.
	task.spawn(function()
		task.wait(BossConfig.StaggerStunTime)
		if not self.alive then return end
		-- Sai do stun: religa a fase certa (Fase 2 se já passou do limiar).
		self.phase = "Phase1"
		self:_maybePhase2()
		self:_broadcast()
	end)

	task.spawn(function()
		task.wait(BossConfig.CoreExposeDuration)
		if not self.alive then return end
		self.coreExposed = false
		self:_setCoreGlow(false)
		self:_broadcast()
	end)

	task.spawn(function()
		task.wait(BossConfig.StaggerRecoverTime)
		self.canStagger = true
	end)
end

-- ---------------------------------------------------------------------------
-- Morte / limpeza
-- ---------------------------------------------------------------------------

function StoneGuardian._die(self: StoneGuardian)
	if not self.alive then return end
	self.alive = false
	self.phase = "Dead"
	self.coreExposed = false
	self:_setCoreGlow(false)
	self.humanoid.WalkSpeed = 0
	self:_broadcast()
	VfxRemote:FireAllClients("Death", self.root.Position, 0)

	-- Gancho de recompensa: a economia/quest do jogo assina onDefeated.
	if self.onDefeated then
		task.spawn(self.onDefeated, self)
	end

	-- Deixa o "cadáver" um tempo pra o VFX de desmoronar rodar, depois limpa.
	task.delay(5, function()
		self:Destroy()
	end)
end

function StoneGuardian.Destroy(self: StoneGuardian)
	self.alive = false
	for _, conn in self.connections do
		conn:Disconnect()
	end
	table.clear(self.connections)
	if self.model and self.model.Parent then
		self.model:Destroy()
	end
end

return StoneGuardian
