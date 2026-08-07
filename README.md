# Arkhaeon — Guardião de Pedra 🗿

Boss **Guardião de Pedra**: um coloso antigo, server-authoritative, com fases,
telegraphs e um ponto fraco (o núcleo) que abre janela de burst para o time.
Escrito em Luau tipado (`--!strict`), pronto para rodar no Studio.

> Feito pelo esquadrão: **John-Doe** (código). Design de combate embutido no
> `BossConfig`; a arte/modelo é papel do **Clay** (opcional — há um modelo
> procedural de fallback que roda sem asset nenhum).

---

## O que ele faz

- **Vida e dano 100% no servidor.** O cliente só renderiza telegraphs e HUD e
  *pede* acertos — quem valida e aplica dano é o servidor.
- **Máquina de estados:** `Dormant → Awakening → Phase1 → Phase2 → Staggered → Dead`.
  - Dorme até um jogador entrar no `AggroRange`.
  - **Fase 1:** Baque no Chão (AoE melee) e Arremesso de Pedregulho (ranged).
  - **Fase 2 (enrage, abaixo de 50%):** mais rápido e forte, ganha Onda de
    Choque radial, Barragem de Pedregulhos e o Baque Sísmico arena-wide
    (pule para desviar).
- **Armadura + poise + stagger:** blindado por padrão (dano reduzido). Acumule
  dano dentro da janela de poise para **quebrar a armadura** → o **núcleo fica
  exposto** por alguns segundos, tomando dano bônus. É o loop de "crie a
  abertura, depois despeje o dano".
- **Telegraphs:** todo ataque avisa antes (anel vermelho no chão) — o jogador
  tem tempo de reagir/desviar.
- **Gancho de recompensa:** `boss.onDefeated` para plugar economia/quest.

---

## Estrutura (mapeada por Rojo)

```
src/
├─ shared/ArkhaeonBoss/   → ReplicatedStorage.ArkhaeonBoss
│  ├─ BossConfig.lua      ← TODOS os números (balanceamento mexe só aqui)
│  ├─ BossTypes.lua       ← tipos compartilhados
│  └─ Remotes.lua         ← RemoteEvents (get-or-create idempotente)
├─ server/                → ServerScriptService
│  ├─ StoneGuardian/      ← ModuleScript (classe do boss)
│  │  ├─ init.lua         ← máquina de estados, dano, fases, morte
│  │  ├─ Attacks.lua      ← biblioteca de ataques (telegraph → dano)
│  │  └─ BossModelBuilder.lua ← usa o modelo do Clay ou constrói um procedural
│  └─ BossBootstrap.server.lua ← sobe o boss + valida hits + recompensa
└─ client/                → StarterPlayer.StarterPlayerScripts
   └─ BossClient.client.lua ← telegraphs, VFX, healthbar, input de ataque
```

---

## Como instalar

### Opção A — Rojo (recomendado)
```bash
rojo serve   # com o default.project.json na raiz
```
Conecte o plugin Rojo no Studio e dê *Sync In*.

### Opção B — manual no Studio
Recrie a hierarquia acima colando cada arquivo no lugar indicado no comentário
do topo de cada script. `StoneGuardian` é um **ModuleScript** cujo corpo é o
`init.lua`, com `Attacks` e `BossModelBuilder` como ModuleScripts filhos.

Depois: dê **Play**. Sem modelo do Clay presente, um guardião de blocos aparece
em `CFrame.new(0, 10, 0)`. Chegue perto para acordá-lo. **Clique** (demo) para
atacar — troque esse input pelo seu sistema de armas.

---

## Plugando no seu jogo

- **Ferir o boss pelo seu combate:** chame `boss:TakeDamage(dano, jogador)` a
  partir do servidor. O `BossBootstrap` já mostra a validação de um hit vindo do
  cliente (distância + cadência anti-spam). Substitua `PLAYER_HIT_DAMAGE` pela
  saída real da sua arma.
- **Modelo do Clay:** coloque um `Model` chamado `StoneGuardian` em
  `ServerStorage` ou `ReplicatedStorage` com um `Humanoid`, uma `PrimaryPart`
  (`HumanoidRootPart`) e uma parte `Core` (atributo `WeakPoint = true`). O
  builder clona ele em vez do procedural.
- **Recompensa:** preencha `boss.onDefeated` no `BossBootstrap` com sua economia.
- **Balanceamento:** tudo em `BossConfig.lua` (vida, limiar de fase, dano/raio/
  cooldown/telegraph por ataque, poise, armadura, duração do núcleo exposto).

---

## Notas de segurança / performance

- **Autoridade do servidor:** nenhum dano é decidido no cliente; hits do jogador
  passam por validação de distância e rate-limit (anti auto-clicker/exploit).
- **Sem vazamento:** conexões e o loop de IA são registrados e desligados em
  `boss:Destroy()`; o cadáver é limpo após o VFX de morte.
- **APIs atuais:** knockback via `AssemblyLinearVelocity` (não o depreciado
  `BodyVelocity`).

### Próximos passos sugeridos
- Passar o código pelo **Guest** (QA) antes de considerar "pronto".
- Trocar os VFX placeholder por partículas/animações do **Clay**.
- Pathfinding real (`PathfindingService`) se a arena tiver obstáculos — hoje o
  boss usa `Humanoid:MoveTo` direto.
