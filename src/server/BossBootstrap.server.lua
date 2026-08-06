--!strict
--[[
	BossBootstrap — sobe o Guardião de Pedra e liga o combate ao servidor.

	Onde vive: ServerScriptService > BossBootstrap (Script normal, roda no boot)
	           Tenha o ModuleScript "StoneGuardian" (com Attacks/BossModelBuilder)
	           ao lado, dentro de ServerScriptService.

	Faz:
	  • cria os RemoteEvents (idempotente)
	  • dá spawn do boss num ponto da arena
	  • valida os pedidos de acerto do cliente (RequestHit) — SERVIDOR é a
	    autoridade: distância, cadência (anti-spam) e existência do golpe
	  • concede recompensa quando o boss morre
]]

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossPkg = ReplicatedStorage:WaitForChild("ArkhaeonBoss")
local BossConfig = require(BossPkg:WaitForChild("BossConfig"))
local Remotes = require(BossPkg:WaitForChild("Remotes")) -- cria os remotes no servidor

local StoneGuardian = require(ServerScriptService:WaitForChild("StoneGuardian"))

-- Onde o boss nasce. Ajuste pra sua arena (ou leia de um marcador no workspace).
local SPAWN_CFRAME = CFrame.new(0, 10, 0)

-- Parâmetros de validação do golpe do jogador (autoridade do servidor).
local PLAYER_HIT_DAMAGE = 120   -- dano base por acerto validado (troque pelo seu
                                -- sistema de armas/dano real)
local PLAYER_HIT_RANGE = 30     -- alcance máx. permitido do jogador ao boss
local PLAYER_HIT_INTERVAL = 0.4 -- cadência mín. entre acertos do MESMO jogador

-- ---------------------------------------------------------------------------

local boss = StoneGuardian.new(SPAWN_CFRAME)

-- Recompensa na morte. Aqui só logamos; conecte à sua economia/quest de verdade.
boss.onDefeated = function(_b)
	print(string.format(
		"[Arkhaeon] %s derrotado! Recompensa: %d moedas, %d XP (por jogador).",
		BossConfig.Name, BossConfig.Rewards.Currency, BossConfig.Rewards.XP
	))
	-- Exemplo de gancho — descomente e ligue ao seu backend:
	-- for _, player in Players:GetPlayers() do
	--     Economy.grant(player, BossConfig.Rewards.Currency, BossConfig.Rewards.XP)
	-- end
end

-- Combate: o cliente PEDE um acerto; o servidor DECIDE se vale.
local lastHit: { [Player]: number } = {}

local RequestHit = Remotes.get("RequestHit")
RequestHit.OnServerEvent:Connect(function(player: Player)
	-- 1) rate-limit por jogador (anti-spam / anti auto-clicker exploit)
	local now = os.clock()
	local prev = lastHit[player]
	if prev and now - prev < PLAYER_HIT_INTERVAL then
		return
	end

	-- 2) o jogador existe, está vivo e o boss também
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then return end
	if not boss.alive or not boss.model.Parent then return end

	-- 3) distância plausível: o servidor confere, não confia no cliente
	local dist = (hrp.Position - boss.root.Position).Magnitude
	if dist > PLAYER_HIT_RANGE then return end

	lastHit[player] = now
	boss:TakeDamage(PLAYER_HIT_DAMAGE, player)
end)

Players.PlayerRemoving:Connect(function(player)
	lastHit[player] = nil
end)

print("[Arkhaeon] Guardião de Pedra ativo. Aproxime-se para despertá-lo.")
