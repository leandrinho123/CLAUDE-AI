--!strict
--[[
	BossModelBuilder — garante que existe um Model jogável do Guardião.

	Onde vive: ServerScriptService > StoneGuardian > BossModelBuilder

	Prioridade:
	  1) Se existir um modelo pronto (do Clay) em ServerStorage/ReplicatedStorage
	     chamado "StoneGuardian", clona ELE. É o caminho de produção.
	  2) Senão, CONSTRÓI um golem de pedras arredondadas (arenito) procedural
	     pra o sistema rodar out-of-the-box, sem depender de arte. Protótipo.

	Contrato do modelo (o resto do código depende disto):
	  Model
	   ├─ Humanoid            (vida e locomoção)
	   ├─ HumanoidRootPart    (PrimaryPart, raiz de física)
	   └─ Core                (BasePart marcada com atributo "WeakPoint"=true;
	                           é o ponto fraco que brilha no stagger)
]]

local BossModelBuilder = {}

local MODEL_NAME = "StoneGuardian"
-- Paleta arenito (referência: golem de pedras arredondadas claras com fendas).
local SAND = Color3.fromRGB(203, 191, 169)      -- pedra clara
local SAND_MID = Color3.fromRGB(176, 162, 139)  -- meio-tom
local SAND_DARK = Color3.fromRGB(146, 132, 111) -- fendas / sombra
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

local function weld(a: BasePart, b: BasePart, offset: CFrame)
	-- Motor6D permite animar depois; Weld puro bastaria se for estático.
	local m = Instance.new("Motor6D")
	m.Part0 = a
	m.Part1 = b
	m.C0 = offset
	m.Parent = a
	b.CFrame = a.CFrame * offset
end

--[[
	Constrói um GOLEM de pedras arredondadas (referência: colosso de arenito,
	baixote e possante — ombros enormes, cabeça pequena afundada, braços grossos
	com punhos perto do chão, pernas curtas).

	Estratégia de rig robusto para NPC de rig próprio:
	  • HumanoidRootPart é o ÚNICO corpo de colisão (invisível). O resto é
	    cosmético: CanCollide=false + Massless=true, pra a física não brigar
	    com dezenas de esferas nem desequilibrar o Humanoid.
	  • "Front" do personagem é -Z (convenção do Roblox p/ virar ao andar):
	    cabeça, punhos, pés e o núcleo apontam pra -Z.
	  • Esferas (PartType.Ball) com Size não-uniforme viram elipsoides — é o
	    que dá o aspecto de "pedra" sem precisar de mesh.
]]
local function buildProcedural(): Model
	local model = Instance.new("Model")
	model.Name = MODEL_NAME

	-- Raiz de colisão invisível: PrimaryPart + HumanoidRootPart.
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(4, 5, 3)
	root.Transparency = 1
	root.CanCollide = true
	root.Parent = model
	model.PrimaryPart = root

	-- Torso: massa central. É o "pai" das demais pedras (hierarquia
	-- root → torso → membros ajuda uma animação futura).
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Shape = Enum.PartType.Ball
	torso.Size = Vector3.new(9, 8.5, 7.5)
	torso.Color = SAND
	torso.Material = Enum.Material.Sandstone
	torso.CanCollide = false
	torso.Massless = true
	torso.Parent = model
	weld(root, torso, CFrame.new(0, 0.5, 0))

	-- Helper: adiciona uma "pedra" (elipsoide) colada no torso, numa posição
	-- relativa. `rotate` dá uma leve rotação aleatória p/ variedade orgânica.
	local function rock(name: string, size: Vector3, color: Color3, pos: Vector3, rotate: boolean?): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = Enum.PartType.Ball
		p.Size = size
		p.Color = color
		p.Material = Enum.Material.Sandstone
		p.CanCollide = false
		p.Massless = true
		p.Parent = model
		local rot = if rotate
			then CFrame.Angles(
				math.rad(math.random(-18, 18)),
				math.rad(math.random(-30, 30)),
				math.rad(math.random(-18, 18))
			)
			else CFrame.new()
		weld(torso, p, CFrame.new(pos) * rot)
		return p
	end

	-- Massa do corpo (barriga pesada + peito).
	rock("Belly", Vector3.new(8.5, 7, 7.5), SAND_MID, Vector3.new(0, -3.5, -0.3))
	rock("Chest", Vector3.new(8, 6, 6.5), SAND, Vector3.new(0, 2.6, -0.4))

	-- Ombros enormes (assinatura da referência).
	rock("LeftShoulder", Vector3.new(6.2, 6, 6), SAND, Vector3.new(-6, 3, 0))
	rock("RightShoulder", Vector3.new(6.2, 6, 6), SAND, Vector3.new(6, 3, 0))

	-- Cabeça pequena, afundada entre os ombros e levemente à frente (-Z).
	rock("Head", Vector3.new(3.6, 3.6, 3.6), SAND_MID, Vector3.new(0, 4.2, -0.9))
	rock("Brow", Vector3.new(3, 1.6, 2.4), SAND_DARK, Vector3.new(0, 5.5, -0.9), true)

	-- Braços grossos que descem; punhos grandes perto do chão (cavador).
	rock("LeftUpperArm", Vector3.new(4.2, 5.5, 4.2), SAND_MID, Vector3.new(-7, -1.4, -0.4))
	rock("RightUpperArm", Vector3.new(4.2, 5.5, 4.2), SAND_MID, Vector3.new(7, -1.4, -0.4))
	rock("LeftFist", Vector3.new(5, 5, 5), SAND, Vector3.new(-7.3, -6.6, -1.2))
	rock("RightFist", Vector3.new(5, 5, 5), SAND, Vector3.new(7.3, -6.6, -1.2))

	-- Pernas curtas e grossas + pés achatados apontando à frente.
	rock("LeftLeg", Vector3.new(4.6, 4.6, 4.6), SAND_MID, Vector3.new(-3, -7.4, 0))
	rock("RightLeg", Vector3.new(4.6, 4.6, 4.6), SAND_MID, Vector3.new(3, -7.4, 0))
	rock("LeftFoot", Vector3.new(4.6, 3, 5.6), SAND_DARK, Vector3.new(-3, -9.8, -1))
	rock("RightFoot", Vector3.new(4.6, 3, 5.6), SAND_DARK, Vector3.new(3, -9.8, -1))

	-- Pedras de detalhe (variam a silhueta, dão o look "empilhado").
	rock("Rock1", Vector3.new(2.6, 2.4, 2.6), SAND_DARK, Vector3.new(-4.5, 5.4, 1.5), true)
	rock("Rock2", Vector3.new(2.4, 2.2, 2.4), SAND_DARK, Vector3.new(4.5, 5.2, 1.6), true)
	rock("Rock3", Vector3.new(3, 2.6, 3), SAND_MID, Vector3.new(0, 0, 3.6), true)   -- costas
	rock("Rock4", Vector3.new(2.2, 2, 2.2), SAND_DARK, Vector3.new(-2.6, -1, 3.4), true)
	rock("Rock5", Vector3.new(2.2, 2, 2.2), SAND_DARK, Vector3.new(2.6, -1, 3.4), true)

	-- Núcleo (ponto fraco) encravado no peito, na frente (-Z). Começa apagado.
	local core = Instance.new("Part")
	core.Name = "Core"
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(2.8, 2.8, 1.6)
	core.Color = CORE_COLOR
	core.Material = Enum.Material.Neon
	core.CanCollide = false
	core.Massless = true
	core.Transparency = 0.35
	core:SetAttribute("WeakPoint", true)
	core.Parent = model
	weld(torso, core, CFrame.new(0, 0.6, -3.7))
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

	-- Distância da raiz ao chão. Os pés vão a ~-11 studs da raiz; se ele
	-- flutuar ou afundar no playtest, ajuste este valor.
	humanoid.HipHeight = 11

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
