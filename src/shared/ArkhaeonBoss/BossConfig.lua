--!strict
--[[
	BossConfig — Guardião de Pedra (Arkhaeon)
	--------------------------------------------------------------------------
	Fonte ÚNICA de valores ajustáveis (tunables) do boss. Design/balanceamento
	mexem só aqui; a lógica (StateMachine, Attacks) lê tudo daqui.

	Onde vive: ReplicatedStorage > ArkhaeonBoss > BossConfig
	(shared: servidor lê os números de gameplay; cliente lê os de telegraph/UI)
]]

local BossConfig = {}

-- Identidade -----------------------------------------------------------------
BossConfig.Name = "Guardião de Pedra"
BossConfig.Id = "stone_guardian"

-- Vida / fases ---------------------------------------------------------------
-- A vida é sempre autoridade do SERVIDOR. Fases disparam por % de vida.
BossConfig.MaxHealth = 12_000

-- Limiar (fração da vida) em que entra a Fase 2 (enrage). 0.5 = 50%.
BossConfig.Phase2Threshold = 0.50

-- Multiplicadores aplicados na Fase 2 (enrage).
BossConfig.EnrageDamageMult = 1.35
BossConfig.EnrageSpeedMult = 1.5   -- velocidade de andar
BossConfig.EnrageCooldownMult = 0.65 -- ataca mais rápido (cooldown menor)

-- Movimento ------------------------------------------------------------------
BossConfig.WalkSpeed = 8            -- lento e pesado, é um coloso de pedra
BossConfig.AggroRange = 120         -- distância pra "acordar" e começar a caçar
BossConfig.LeashRange = 260         -- se todo alvo passar disso, volta a dormir

-- Ponto fraco (núcleo) -------------------------------------------------------
-- O Guardião é blindado. Ele só toma dano CHEIO quando o núcleo está exposto.
-- Fora disso, o dano é reduzido por ArmorReduction.
BossConfig.ArmorReduction = 0.6     -- 60% do dano é bloqueado com a armadura fechada
BossConfig.CoreExposeDuration = 6   -- segundos que o núcleo fica exposto após stagger
BossConfig.CoreDamageBonus = 1.75   -- multiplicador de dano no núcleo exposto

-- Stagger (poise) — quebra a armadura quando toma dano suficiente numa janela.
BossConfig.PoiseMax = 2_500         -- dano acumulado necessário pra quebrar a armadura
BossConfig.PoiseWindow = 5          -- janela (s) em que o poise acumula antes de resetar
BossConfig.StaggerStunTime = 2.5    -- tempo que fica travado (sem agir) ao ser staggerado
BossConfig.StaggerRecoverTime = 12  -- cooldown antes de poder ser staggerado de novo

-- Ataques --------------------------------------------------------------------
-- Cada ataque tem: dano, alcance, cooldown, e tempo de telegraph (aviso visual
-- antes do golpe conectar — o jogador precisa de tempo pra reagir/desviar).
BossConfig.Attacks = {
	GroundSlam = {
		Damage = 45,
		Radius = 22,          -- AoE circular ao redor do impacto
		Cooldown = 5,
		Telegraph = 1.1,      -- s de aviso antes do baque
		Range = 26,           -- distância máx do alvo pra escolher esse ataque
		Knockback = 40,
	},
	RockThrow = {
		Damage = 60,
		Radius = 12,          -- AoE no ponto de impacto do pedregulho
		Cooldown = 6,
		Telegraph = 1.4,      -- pedra sobe, mira, cai
		ProjectileSpeed = 90,
		MinRange = 24,        -- só arremessa se o alvo estiver longe
	},
	Shockwave = {             -- Fase 2: onda radial que varre a arena
		Damage = 55,
		StartRadius = 6,
		MaxRadius = 70,
		ExpandSpeed = 55,     -- studs/s de expansão do anel
		Cooldown = 11,
		Telegraph = 1.6,
		Width = 8,            -- espessura visual do anel (cosmético; a resolução
		                     -- usa a frente da onda: pule quando ela te alcançar)
		Knockback = 55,
	},
	BoulderBarrage = {        -- Fase 2: chuva de pedregulhos telegrafados
		Damage = 40,
		Radius = 10,
		Count = 5,            -- quantos pontos de impacto
		Cooldown = 13,
		Telegraph = 1.5,
		Spread = 40,          -- raio da área onde os impactos caem
	},
	SeismicSlam = {           -- Fase 2: baque arena-wide, tem que pular pra desviar
		Damage = 70,
		Radius = 90,
		Cooldown = 18,
		Telegraph = 2.2,      -- telegraph longo — é o mais punitivo
		SafeIfAirborne = true,-- pulou no momento do baque? não toma dano
	},
}

-- Loot / recompensa (gancho — a economia do jogo consome isso na morte) ------
BossConfig.Rewards = {
	Currency = 500,
	XP = 1_200,
}

-- Respawn --------------------------------------------------------------------
-- Segundos após a morte até o Guardião renascer na arena. 3600 = 1 hora.
BossConfig.RespawnDelay = 3600

return BossConfig
