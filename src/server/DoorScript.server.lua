--[[
	DoorScript — porta interativa que libera o Guardião de Pedra (Arkhaeon).

	O que faz:
	  • Mostra um aviso "[E] Abrir" quando o jogador chega perto (ProximityPrompt).
	  • Cada E ALTERNA: abre a porta; o próximo E fecha; e assim por diante.
	  • Na PRIMEIRA vez que abre, liga o atributo no workspace que faz o
	    BossBootstrap soltar o boss. É o gatilho do spawn.

	Onde vive (duas opções — funciona nas duas):
	  A) ServerScriptService, via Rojo (recomendado, versionado). Ele acha a
	     porta em workspace pelo nome DOOR_NAME.
	  B) Dentro da própria porta: coloque este Script dentro da Part da porta
	     (ex.: Workspace > Door > Door > Script). Ele usa script.Parent.
	  Escolha UMA — não deixe as duas rodando (senão cria prompt/gatilho dobrado).

	Server-authoritative: a porta abre/fecha e o gatilho do boss são decididos
	no SERVIDOR. O ProximityPrompt já entrega o "aproximar + apertar E" nativo.
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfig = require(ReplicatedStorage:WaitForChild("ArkhaeonBoss"):WaitForChild("BossConfig"))

-- ------------------------------------------------------------------ CONFIG
local DOOR_NAME = "Door"          -- nome do Model da porta em workspace (opção A)
local SWING_ANGLE = 90            -- graus que a porta abre
local OPEN_TIME = 0.6             -- duração da animação (s)
local HINGE_ON_LEFT = true        -- dobradiça na borda esquerda (-X). Se abrir
                                  -- pro lado errado, troque para false.
local PROMPT_DISTANCE = 10        -- a que distância (studs) aparece o "[E] Abrir"

-- ---------------------------------------------------------------------------

-- Descobre qual BasePart é a folha da porta.
local function resolveDoorPart(): BasePart?
	-- Opção B: o script está dentro da própria Part.
	if script.Parent and script.Parent:IsA("BasePart") then
		return script.Parent
	end
	-- Opção A: acha o Model em workspace e pega a folha (a Part de mesmo nome,
	-- para não confundir com a Doorbell ou outras partes).
	local model = workspace:WaitForChild(DOOR_NAME, 30)
	if not model then
		return nil
	end
	local part = model:FindFirstChild(DOOR_NAME)
	if part and part:IsA("BasePart") then
		return part
	end
	return model:FindFirstChildWhichIsA("BasePart")
end

local doorPart = resolveDoorPart()
if not doorPart then
	warn("[Arkhaeon] DoorScript: não encontrei a Part da porta ('" .. DOOR_NAME .. "').")
	return
end

-- A folha precisa estar ancorada para animar por CFrame de forma estável.
-- (Peças soldadas a ela, como a Doorbell, acompanham o movimento.)
doorPart.Anchored = true

-- Poses fechada e aberta. A aberta gira SWING_ANGLE em torno de uma borda
-- vertical (a "dobradiça"), não do centro — assim ela abre como porta de verdade.
-- A dobradiça vai na borda do eixo horizontal MAIS LARGO (X ou Z), pra funcionar
-- não importa como a Part foi orientada.
local closedCF = doorPart.CFrame
local size = doorPart.Size
local sign = if HINGE_ON_LEFT then -1 else 1
local edge = if size.X >= size.Z
	then Vector3.new(sign * size.X / 2, 0, 0)
	else Vector3.new(0, 0, sign * size.Z / 2)
local pivot = closedCF * CFrame.new(edge)
local openCF = pivot * CFrame.Angles(0, math.rad(sign * SWING_ANGLE), 0) * pivot:Inverse() * closedCF

-- ProximityPrompt (aproximar + E). Reaproveita um existente, se houver.
local prompt = doorPart:FindFirstChildWhichIsA("ProximityPrompt")
if not prompt then
	prompt = Instance.new("ProximityPrompt")
	prompt.Parent = doorPart
end
prompt.ActionText = "Abrir"
prompt.ObjectText = "Porta"
prompt.KeyboardKeyCode = Enum.KeyCode.E
prompt.HoldDuration = 0
prompt.RequiresLineOfSight = false
prompt.MaxActivationDistance = PROMPT_DISTANCE

-- Estado + toggle.
local isOpen = false
local busy = false

prompt.Triggered:Connect(function(_player: Player)
	if busy then return end
	busy = true

	isOpen = not isOpen
	prompt.ActionText = if isOpen then "Fechar" else "Abrir"

	local goal = if isOpen then openCF else closedCF
	local tween = TweenService:Create(
		doorPart,
		TweenInfo.new(OPEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = goal }
	)
	tween:Play()

	-- Gatilho do boss: na primeira abertura, liga o atributo (latch). Fica
	-- ligado mesmo se a porta fechar depois — o boss já foi liberado.
	if isOpen and not workspace:GetAttribute(BossConfig.DoorReleaseAttribute) then
		workspace:SetAttribute(BossConfig.DoorReleaseAttribute, true)
	end

	tween.Completed:Wait()
	busy = false
end)

print("[Arkhaeon] Porta pronta. Aproxime-se e aperte E para abrir.")
