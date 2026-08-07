--!strict
--[[
	BossTypes — tipos compartilhados do Guardião de Pedra.
	Onde vive: ReplicatedStorage > ArkhaeonBoss > BossTypes
	Centraliza os tipos pra servidor e cliente falarem a mesma língua.
]]

export type Phase = "Dormant" | "Awakening" | "Phase1" | "Phase2" | "Staggered" | "Dead"

export type AttackName =
	"GroundSlam" | "RockThrow" | "Shockwave" | "BoulderBarrage" | "SeismicSlam"

-- Snapshot enviado ao cliente para HUD/healthbar (sem lógica sensível).
export type BossSnapshot = {
	name: string,
	health: number,
	maxHealth: number,
	phase: Phase,
	coreExposed: boolean,
}

-- Payload de um telegraph que o servidor manda o cliente desenhar.
-- O cliente NÃO decide dano; só renderiza o aviso na posição indicada.
export type TelegraphPayload = {
	attack: AttackName,
	position: Vector3,
	radius: number,
	duration: number,        -- quanto tempo até o golpe conectar
	extra: { [string]: any }?,
}

return {}
