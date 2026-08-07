--!strict
--[[
	Remotes — cria/pega os RemoteEvents do boss de forma idempotente.
	Onde vive: ReplicatedStorage > ArkhaeonBoss > Remotes

	Pode ser exigido tanto do servidor quanto do cliente. O SERVIDOR cria os
	objetos (get-or-create); o CLIENTE apenas espera por eles (WaitForChild).

	Fluxo:
	  Server -> Client  : Telegraph  (desenhe o aviso do ataque aqui)
	  Server -> Client  : BossState  (atualize a HUD/healthbar)
	  Server -> Client  : BossVfx    (efeito pontual: impacto, quebra de armadura…)
	  Client -> Server  : RequestHit (jogador afirma que acertou; SERVIDOR valida)
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local FOLDER_NAME = "ArkhaeonBossRemotes"
local EVENT_NAMES = { "Telegraph", "BossState", "BossVfx", "RequestHit" }

local function getFolder(): Folder
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
		for _, name in EVENT_NAMES do
			if not folder:FindFirstChild(name) then
				local ev = Instance.new("RemoteEvent")
				ev.Name = name
				ev.Parent = folder
			end
		end
		return folder :: Folder
	else
		-- Cliente: os remotes já foram criados pelo servidor no boot.
		return ReplicatedStorage:WaitForChild(FOLDER_NAME, 30) :: Folder
	end
end

function Remotes.get(name: string): RemoteEvent
	local folder = getFolder()
	if RunService:IsServer() then
		return folder:FindFirstChild(name) :: RemoteEvent
	end
	return folder:WaitForChild(name, 30) :: RemoteEvent
end

return Remotes
