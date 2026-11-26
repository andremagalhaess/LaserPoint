# LASERPOINT

FPS competitivo futurista para Roblox. **Aim. Adapt. Dominate.**

Status: **Fase 1, Combat Prototype.** Dois jogadores entram numa arena de teste e se enfrentam com a Pulse Rifle. Quem decide disparo, acerto, dano e eliminação é o servidor.

Plano da arquitetura: [LASERPOINT — Fase 1: Arquitetura do Combat Prototype](https://claude.ai/artifact/4UuZFCeSUpJAh2GM3x35Em)

## Como abrir no Roblox Studio

O código fica em arquivos `.luau` neste repositório, e o [Rojo](https://rojo.space) leva esses arquivos para dentro do Studio. Assim o GitHub guarda o histórico de cada mudança.

### Instalação (uma vez só)

1. Instale o [Rokit](https://github.com/rojo-rbx/rokit), que gerencia as ferramentas do projeto. No Windows, rode no PowerShell:
   ```powershell
   Invoke-RestMethod https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | Invoke-Expression
   ```
2. Feche e abra o terminal. Na pasta do repositório, rode:
   ```
   rokit install
   ```
   Isso instala o Rojo na versão fixada em `rokit.toml`.
3. Instale o plugin do Rojo no Studio:
   ```
   rojo plugin install
   ```

### Opção A: abrir um place pronto (mais simples)

```
rojo build default.project.json -o LaserPoint.rbxlx
```

Abra `LaserPoint.rbxlx` no Studio. Esse arquivo não vai para o Git (está no `.gitignore`). Gere de novo sempre que o código mudar.

### Opção B: sincronizar ao vivo (para desenvolver)

1. Na pasta do repositório, rode `rojo serve`.
2. No Studio, abra o `LaserPoint.rbxlx` da opção A, vá na aba **Plugins** e clique em **Rojo > Connect**.
3. Edite os arquivos `.luau` (no VS Code, por exemplo). O Studio atualiza sozinho.

Importante: com o Rojo conectado, os scripts que vêm de `src/` devem ser editados nos arquivos, não no Studio. O que você muda no Studio dentro desses scripts é sobrescrito.

## Onde cada coisa fica

| Arquivo | Vira no Studio | Tipo |
| --- | --- | --- |
| `src/shared/WeaponConfig.luau` | ReplicatedStorage > Modules > WeaponConfig | ModuleScript |
| `src/shared/WeaponState.luau` | ReplicatedStorage > Modules > WeaponState | ModuleScript |
| `src/server/Main.server.luau` | ServerScriptService > Main | Script |
| `src/server/Services/WeaponService.luau` | ServerScriptService > Services > WeaponService | ModuleScript |
| `src/server/Services/CombatService.luau` | ServerScriptService > Services > CombatService | ModuleScript |
| `src/client/ClientMain.client.luau` | StarterPlayer > StarterPlayerScripts > ClientMain | LocalScript |
| `src/client/Controllers/*.luau` | StarterPlayer > StarterPlayerScripts > Controllers | ModuleScripts |
| `src/character/Health.server.luau` | StarterPlayer > StarterCharacterScripts > Health | Script (vazio) |

O sufixo do arquivo define o tipo: `.server.luau` vira Script, `.client.luau` vira LocalScript e `.luau` vira ModuleScript.

Os objetos que não são código também estão em `default.project.json`:

- `ReplicatedStorage > Remotes`: os RemoteEvents `FireWeapon`, `ShotFired`, `HitConfirmed`, `WeaponStateSync` e `PlayerEliminated`.
- `StarterPlayer.CameraMode = LockFirstPerson`.
- `Workspace > Maps > TestArena`: chão, 5 coberturas, 2 pilares neon e 2 SpawnLocations com 2 s de proteção.

## Como os scripts se conectam

```
Servidor                                  Cliente
Main                                      ClientMain
├─ CombatService  (vida, dano, morte)     ├─ CameraController  (FOV, recuo)
└─ WeaponService  (valida tiros)          ├─ InputController   (mouse / botão de toque / R2)
     └─ usa CombatService.ApplyDamage     ├─ WeaponController  (tiro, laser, viewmodel)
                                          └─ UIController      (HUD)
Compartilhado: WeaponConfig, WeaponState
```

Caminho de um tiro:

1. O `WeaponController` consulta a cópia local do `WeaponState`, faz o Raycast e mostra o laser na hora.
2. Envia `FireWeapon(origem, direção, parte atingida, ponto)`. Nunca envia dano.
3. O `WeaponService` confere a cadência, a energia, o calor, a origem e, se houve acerto, se ele é plausível e se não tem parede no meio.
4. Se o tiro valeu, o `CombatService` aplica o dano da `WeaponConfig` do servidor. O servidor manda `ShotFired` aos outros jogadores e `HitConfirmed` ao atirador.
5. Se o tiro foi recusado, o servidor manda `WeaponStateSync` com o estado real da arma, e o HUD se corrige.

## Teste da Fase 1

Na aba **Test**, em *Clients and Servers*, escolha **2 jogadores** e clique em **Start**.

- [ ] Os dois nascem em primeira pessoa, com o mouse preso no centro.
- [ ] Segurar o botão esquerdo atira em ritmo automático e o laser aparece.
- [ ] A barra de calor sobe. Depois de uns 17 tiros seguidos aparece OVERHEAT e a arma trava por 1,5 s.
- [ ] A energia cai 2 por tiro e volta sozinha depois de 1 s sem atirar.
- [ ] Cada jogador vê o laser do outro saindo da arma dele.
- [ ] 6 acertos eliminam. O hitmarker fica vermelho no tiro que elimina e o aviso de eliminação aparece no topo.
- [ ] Atirar através de uma cobertura não causa dano (o Output do servidor mostra "parede no caminho").
- [ ] Quem morre volta em 3 s, com vida, energia e calor zerados.
- [ ] Logo depois de nascer, o jogador não leva dano por 2 s (escudo de proteção).
- [ ] No emulador de celular (aba **Test > Device**), aparece o botão FIRE e ele atira.
- [ ] Com lag simulado (**File > Studio Settings > Network > Incoming Replication Lag** = 0.1), acertos em alvos andando ainda contam.

Os tiros recusados aparecem em amarelo no Output do servidor. Para desligar esse log, mude `LOG_REJECTIONS` em `WeaponService`.

## Limites conhecidos da Fase 1

- **Tolerância a lag:** o servidor aceita um acerto até ~5 studs fora da posição atual do alvo. Um trapaceiro pode "puxar" acertos dentro dessa folga, mas não pode atravessar paredes, atirar mais rápido, ignorar o calor nem mudar o dano. Se os testes mostrarem acertos injustos, a melhoria seguinte é guardar o histórico de posições dos últimos 1 s.
- **Cadência em FPS baixo:** o cliente atira no frame em que o intervalo passou. A 30 FPS, a cadência real fica um pouco abaixo de 450 por minuto.
- **Previsão do cliente:** no limite do superaquecimento, o cliente pode disparar um tiro que o servidor recusa. O laser aparece, mas não dá dano, e o HUD se corrige em seguida.
- **Arena de teste:** a arena é definida em `default.project.json` só para a Fase 1. O mapa NEXUS (Fase 3) vai ser construído no Studio.
