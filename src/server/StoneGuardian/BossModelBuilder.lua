--!strict
--[[
	BossModelBuilder — garante que existe um Model jogável do Guardião.

	Onde vive: ServerScriptService > StoneGuardian > BossModelBuilder

	Prioridade:
	  1) Se existir um modelo pronto (do Clay) em ServerStorage/ReplicatedStorage
	     chamado "StoneGuardian", clona ELE. É o caminho de produção.
	  2) Senão, CONSTRÓI um coloso de pedra procedural (blocos) pra o sistema
	     rodar out-of-the-box, sem depender de arte. É o caminho de protótipo.

	Contrato do modelo (o resto do código depende disto):
	  Model
	   ├─ Humanoid            (vida e locomoção)
	   ├─ HumanoidRootPart    (PrimaryPart, raiz de física)
	   └─ Core                (BasePart marcada com atributo "WeakPoint"=true;
	                           é o ponto fraco que brilha no stagger)
]]

local BossModelBuilder = {}

local MODEL_NAME = "StoneGuardian"
local STONE = Color3.fromRGB(96, 92, 86)
local STONE_DARK = Color3.fromRGB(64, 60, 55)
local CORE_COLOR = Color3.fromRGB(120, 60, 200) -- roxo de energia arcana

local function findTemplate(): Model?
	for _, container in { game:GetService("ServerStorage"), game:GetService("ReplicatedStorage") } do
		local found = container:FindFirstChild(MODEL_NAME)
		if found and found:IsA("Model") then
			return found
		end
	end
	return nil
end

local function makePart(name: string, size: Vector3, color: Color3, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Slate
	p.Anchored = false
	p.CanCollide = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function weld(a: BasePart, b: BasePart, offset: CFrame)
	-- Motor6D permite animar depois; Weld puro bastaria se for estático.
	local m = Instance.new("Motor6D")
	m.Part0 = a
	m.Part1 = b
	m.C0 = offset
	m.Parent = a
	b.CFrame = a.CFrame * offset
end

-- Constrói um guardião blocky com raiz, torso, cabeça, braços, pernas e núcleo.
local function buildProcedural(): Model
	local model = Instance.new("Model")
	model.Name = MODEL_NAME

	-- Raiz invisível: é a PrimaryPart e o HumanoidRootPart.
	local root = makePart("HumanoidRootPart", Vector3.new(6, 8, 4), STONE, model)
	root.Transparency = 1
	root.CanCollide = false
	model.PrimaryPart = root

	local torso = makePart("Torso", Vector3.new(8, 9, 5), STONE, model)
	weld(root, torso, CFrame.new(0, 0.5, 0))

	local head = makePart("Head", Vector3.new(4, 4, 4), STONE_DARK, model)
	weld(torso, head, CFrame.new(0, 6.5, 0))

	local lArm = makePart("LeftArm", Vector3.new(3, 9, 3), STONE, model)
	weld(torso, lArm, CFrame.new(-6, 0, 0))
	local rArm = makePart("RightArm", Vector3.new(3, 9, 3), STONE, model)
	weld(torso, rArm, CFrame.new(6, 0, 0))

	local lLeg = makePart("LeftLeg", Vector3.new(3.5, 8, 3.5), STONE_DARK, model)
	weld(torso, lLeg, CFrame.new(-2.2, -8.5, 0))
	local rLeg = makePart("RightLeg", Vector3.new(3.5, 8, 3.5), STONE_DARK, model)
	weld(torso, rLeg, CFrame.new(2.2, -8.5, 0))

	-- Núcleo (ponto fraco) encravado no peito. Começa apagado.
	local core = makePart("Core", Vector3.new(2.5, 2.5, 1.5), CORE_COLOR, model)
	core.Material = Enum.Material.Neon
	core.CanCollide = false
	core.Transparency = 0.35
	core:SetAttribute("WeakPoint", true)
	weld(torso, core, CFrame.new(0, 1, -2.7))
	local light = Instance.new("PointLight")
	light.Color = CORE_COLOR
	light.Range = 14
	light.Brightness = 0
	light.Parent = core

	-- Humanoid: usa vida como recurso próprio; MaxHealth é setado pela classe.
	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = 100 -- placeholder; a classe seta o valor real do config
	humanoid.Health = 100
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0
	humanoid.Parent = model

	-- HipHeight garante que ele fica em pé sobre as pernas.
	humanoid.HipHeight = 9

	return model
end

-- Retorna um Model pronto e parenteado no workspace, posicionado em `spawnCFrame`.
function BossModelBuilder.spawn(spawnCFrame: CFrame): Model
	local template = findTemplate()
	local model: Model = if template then template:Clone() else buildProcedural()

	-- Segurança: garante o contrato mesmo num modelo do Clay que veio incompleto.
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	assert(humanoid, "StoneGuardian precisa de um Humanoid")
	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			or model:FindFirstChildWhichIsA("BasePart")
	end
	assert(model.PrimaryPart, "StoneGuardian precisa de uma PrimaryPart")

	-- Rig customizado (colosso) NÃO tem junta "Neck" padrão. Com RequiresNeck
	-- ligado (default), o Humanoid pode morrer sozinho no spawn / se comportar
	-- mal. Desligar é o correto e seguro para NPC de rig próprio — vale tanto
	-- pro procedural quanto pro modelo do Clay.
	humanoid.RequiresNeck = false

	model.Parent = workspace
	model:PivotTo(spawnCFrame)
	return model
end

return BossModelBuilder
