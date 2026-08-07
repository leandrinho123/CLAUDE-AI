--!strict
--[[
	BossClient — feedback visual do Guardião de Pedra no cliente.

	Onde vive: StarterPlayer > StarterPlayerScripts > BossClient (LocalScript)

	O cliente é SÓ apresentação — ele NUNCA decide dano:
	  • desenha os telegraphs (anéis vermelhos no chão) que o servidor manda;
	  • mantém a healthbar/HUD do boss a partir do snapshot do servidor;
	  • toca VFX pontuais (impacto, onda, enrage, morte);
	  • envia RequestHit quando o jogador ataca — e o SERVIDOR valida.

	Trocar o input de ataque: aqui usamos clique como demo. No jogo real, dispare
	RequestHit a partir do seu sistema de armas/combate.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BossPkg = ReplicatedStorage:WaitForChild("ArkhaeonBoss")
local BossConfig = require(BossPkg:WaitForChild("BossConfig"))
local Remotes = require(BossPkg:WaitForChild("Remotes"))

local player = Players.LocalPlayer

local TelegraphRemote = Remotes.get("Telegraph")
local BossStateRemote = Remotes.get("BossState")
local VfxRemote = Remotes.get("BossVfx")
local RequestHit = Remotes.get("RequestHit")

-- ---------------------------------------------------------------------------
-- Telegraphs (anel vermelho que preenche até o golpe conectar)
-- ---------------------------------------------------------------------------

local TELEGRAPH_COLOR = Color3.fromRGB(220, 40, 40)

local function drawTelegraph(payload: any)
	local pos: Vector3 = payload.position
	local radius: number = payload.radius
	local duration: number = math.max(0.05, payload.duration or 1)

	-- Disco achatado no chão (cilindro deitado).
	local disc = Instance.new("Part")
	disc.Shape = Enum.PartType.Cylinder
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CanTouch = false
	disc.Material = Enum.Material.Neon
	disc.Color = TELEGRAPH_COLOR
	disc.Transparency = 0.75
	disc.Size = Vector3.new(0.2, radius * 2, radius * 2)
	disc.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	disc.Parent = workspace

	-- "Preenche" ao longo do telegraph: fica menos transparente até o baque.
	local fill = TweenService:Create(
		disc,
		TweenInfo.new(duration, Enum.EasingStyle.Linear),
		{ Transparency = 0.35 }
	)
	fill:Play()

	task.delay(duration, function()
		-- flash e some
		disc.Transparency = 0.1
		local fade = TweenService:Create(
			disc,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad),
			{ Transparency = 1 }
		)
		fade:Play()
		fade.Completed:Once(function()
			disc:Destroy()
		end)
	end)
end

TelegraphRemote.OnClientEvent:Connect(drawTelegraph)

-- ---------------------------------------------------------------------------
-- VFX pontuais
-- ---------------------------------------------------------------------------

local function quickBurst(pos: Vector3, radius: number, color: Color3)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.2
	p.Size = Vector3.new(2, 2, 2)
	p.CFrame = CFrame.new(pos)
	p.Parent = workspace
	local grow = TweenService:Create(
		p,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(radius, radius, radius) * 1.5, Transparency = 1 }
	)
	grow:Play()
	grow.Completed:Once(function() p:Destroy() end)
end

VfxRemote.OnClientEvent:Connect(function(kind: string, pos: Vector3, radius: number)
	if kind == "Impact" then
		quickBurst(pos, math.max(6, radius), Color3.fromRGB(150, 130, 90))
	elseif kind == "Shockwave" then
		quickBurst(pos, radius, Color3.fromRGB(200, 180, 120))
	elseif kind == "SeismicSlam" then
		quickBurst(pos, radius, Color3.fromRGB(210, 90, 40))
	elseif kind == "Enrage" then
		quickBurst(pos, 24, Color3.fromRGB(200, 40, 40))
	elseif kind == "Awaken" or kind == "Stagger" then
		quickBurst(pos, 20, Color3.fromRGB(120, 60, 200))
	elseif kind == "Death" then
		quickBurst(pos, 40, Color3.fromRGB(90, 80, 70))
	end
end)

-- ---------------------------------------------------------------------------
-- HUD / Healthbar
-- ---------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "BossHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0.5, 0, 0, 54)
frame.Position = UDim2.new(0.25, 0, 0, 24)
frame.BackgroundColor3 = Color3.fromRGB(20, 18, 16)
frame.BackgroundTransparency = 0.25
frame.BorderSizePixel = 0
frame.Parent = gui

local nameLabel = Instance.new("TextLabel")
nameLabel.Size = UDim2.new(1, 0, 0, 20)
nameLabel.BackgroundTransparency = 1
nameLabel.Font = Enum.Font.GothamBold
nameLabel.TextColor3 = Color3.fromRGB(235, 225, 210)
nameLabel.TextScaled = false
nameLabel.TextSize = 16
nameLabel.Text = BossConfig.Name
nameLabel.Parent = frame

local barBg = Instance.new("Frame")
barBg.Size = UDim2.new(1, -12, 0, 20)
barBg.Position = UDim2.new(0, 6, 0, 26)
barBg.BackgroundColor3 = Color3.fromRGB(45, 40, 36)
barBg.BorderSizePixel = 0
barBg.Parent = frame

local barFill = Instance.new("Frame")
barFill.Size = UDim2.new(1, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(160, 60, 60)
barFill.BorderSizePixel = 0
barFill.Parent = barBg

local phaseLabel = Instance.new("TextLabel")
phaseLabel.Size = UDim2.new(1, 0, 1, 0)
phaseLabel.BackgroundTransparency = 1
phaseLabel.Font = Enum.Font.GothamMedium
phaseLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
phaseLabel.TextSize = 13
phaseLabel.Text = ""
phaseLabel.Parent = barBg

BossStateRemote.OnClientEvent:Connect(function(snap: any)
	if snap.phase == "Dormant" then
		gui.Enabled = false
		return
	end
	gui.Enabled = snap.phase ~= "Dead"

	local frac = if snap.maxHealth > 0 then snap.health / snap.maxHealth else 0
	TweenService:Create(
		barFill,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad),
		{ Size = UDim2.new(math.clamp(frac, 0, 1), 0, 1, 0) }
	):Play()

	-- Núcleo exposto pinta a barra de roxo (sinaliza a janela de burst).
	barFill.BackgroundColor3 = if snap.coreExposed
		then Color3.fromRGB(150, 70, 210)
		else Color3.fromRGB(160, 60, 60)

	local label = snap.phase
	if snap.coreExposed then
		label = "NÚCLEO EXPOSTO — ataquem!"
	elseif snap.phase == "Phase2" then
		label = "ENFURECIDO"
	elseif snap.phase == "Staggered" then
		label = "cambaleando…"
	end
	phaseLabel.Text = label
end)

-- ---------------------------------------------------------------------------
-- Input de ataque (DEMO) — troque pelo seu sistema de armas.
-- ---------------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.KeyCode == Enum.KeyCode.ButtonR2 then
		RequestHit:FireServer()
	end
end)
